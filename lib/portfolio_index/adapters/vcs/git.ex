defmodule PortfolioIndex.Adapters.VCS.Git do
  @moduledoc """
  Git adapter implementing the VCS port behaviour via Git CLI.

  This adapter uses `System.cmd/3` to execute Git commands and parses
  the output to provide structured VCS operations.

  ## Error Handling

  Git exit codes are mapped to semantic error tuples:
  - Exit 0: Success
  - Exit 1: General error / Nothing to commit (context-dependent)
  - Exit 128: Not a git repository → `{:repository_not_found, repo}`
  - Exit 1 + "conflict": Merge conflict → `{:merge_conflict, files}`

  ## Implementation Notes

  - Uses `git status --porcelain=v1 -b` for reliable status parsing
  - Uses `git diff --stat` for diff statistics
  - Validates repository existence before operations
  - Captures stderr with `stderr_to_stdout: true`
  """

  @behaviour PortfolioCore.Ports.VCS

  ## Required Callbacks

  @impl true
  def is_repo?(repo) do
    case System.cmd("git", ["rev-parse", "--git-dir"],
           cd: repo,
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  @impl true
  def status(repo) do
    :telemetry.span(
      [:portfolio, :vcs, :status],
      %{repo: repo},
      fn ->
        result =
          if is_repo?(repo) do
            do_status(repo)
          else
            {:error, {:repository_not_found, repo}}
          end

        measurements =
          case result do
            {:ok, status} ->
              %{files_changed: length(status.changed_files) + length(status.untracked_files)}

            _ ->
              %{}
          end

        {result, measurements}
      end
    )
  end

  @impl true
  def current_branch(repo) do
    if is_repo?(repo) do
      case git_cmd(repo, ["rev-parse", "--abbrev-ref", "HEAD"]) do
        {:ok, output} ->
          branch = String.trim(output)
          # "HEAD" means detached HEAD state
          {:ok, if(branch == "HEAD", do: nil, else: branch)}

        {:error, _} = error ->
          error
      end
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  @impl true
  def diff(repo, from, to) do
    :telemetry.span(
      [:portfolio, :vcs, :diff],
      %{repo: repo, from: from, to: to},
      fn ->
        result =
          if is_repo?(repo) do
            do_diff(repo, from, to)
          else
            {:error, {:repository_not_found, repo}}
          end

        measurements =
          case result do
            {:ok, diff} ->
              %{
                additions: diff.stats.additions,
                deletions: diff.stats.deletions,
                files_changed: diff.stats.files_changed
              }

            _ ->
              %{}
          end

        {result, measurements}
      end
    )
  end

  @impl true
  def diff_uncommitted(repo) do
    :telemetry.span(
      [:portfolio, :vcs, :diff],
      %{repo: repo, from: "HEAD", to: "working_tree"},
      fn ->
        result =
          if is_repo?(repo) do
            do_diff_uncommitted(repo)
          else
            {:error, {:repository_not_found, repo}}
          end

        measurements =
          case result do
            {:ok, diff} ->
              %{
                additions: diff.stats.additions,
                deletions: diff.stats.deletions,
                files_changed: diff.stats.files_changed
              }

            _ ->
              %{}
          end

        {result, measurements}
      end
    )
  end

  @impl true
  def stage(repo, files) do
    if is_repo?(repo) do
      case git_cmd(repo, ["add" | files]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  @impl true
  def stage_all(repo) do
    if is_repo?(repo) do
      case git_cmd(repo, ["add", "-A"]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  @impl true
  def unstage(repo, files) do
    if is_repo?(repo) do
      case git_cmd(repo, ["reset", "HEAD" | files]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  @impl true
  def commit(repo, message, opts) do
    :telemetry.span(
      [:portfolio, :vcs, :commit],
      %{repo: repo},
      fn ->
        result =
          if is_repo?(repo) do
            do_commit(repo, message, opts)
          else
            {:error, {:repository_not_found, repo}}
          end

        {result, %{}}
      end
    )
  end

  @impl true
  def log(repo, opts) do
    if is_repo?(repo) do
      do_log(repo, opts)
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  @impl true
  def show(repo, ref) do
    if is_repo?(repo) do
      do_show(repo, ref)
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  ## Optional Callbacks

  @impl true
  def push(repo, opts) do
    :telemetry.span(
      [:portfolio, :vcs, :push],
      %{repo: repo},
      fn ->
        result =
          if is_repo?(repo) do
            do_push(repo, opts)
          else
            {:error, {:repository_not_found, repo}}
          end

        {result, %{}}
      end
    )
  end

  @impl true
  def pull(repo, opts) do
    :telemetry.span(
      [:portfolio, :vcs, :pull],
      %{repo: repo},
      fn ->
        result =
          if is_repo?(repo) do
            do_pull(repo, opts)
          else
            {:error, {:repository_not_found, repo}}
          end

        {result, %{}}
      end
    )
  end

  @impl true
  def branch_create(repo, name, opts) do
    if is_repo?(repo) do
      do_branch_create(repo, name, opts)
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  @impl true
  def branch_delete(repo, name, opts) do
    if is_repo?(repo) do
      do_branch_delete(repo, name, opts)
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  @impl true
  def checkout(repo, ref) do
    if is_repo?(repo) do
      do_checkout(repo, ref)
    else
      {:error, {:repository_not_found, repo}}
    end
  end

  ## Private Implementation Functions

  defp do_status(repo) do
    case git_cmd(repo, ["status", "--porcelain=v1", "-b"]) do
      {:ok, output} ->
        {:ok, parse_status(output)}

      {:error, _} = error ->
        error
    end
  end

  defp parse_status(output) do
    lines = String.split(output, "\n", trim: true)

    {branch_line, file_lines} =
      case lines do
        ["## " <> _ = branch | files] -> {branch, files}
        files -> {nil, files}
      end

    # Parse branch info
    branch_info = if branch_line, do: parse_branch_line(branch_line), else: %{}

    # Parse file status
    file_info = parse_file_lines(file_lines)

    Map.merge(branch_info, file_info)
  end

  defp parse_branch_line("## " <> rest) do
    # Format: "main...origin/main [ahead 2, behind 1]"
    # or just: "main"
    case String.split(rest, "...") do
      [branch, tracking_info] ->
        {upstream, ahead, behind} = parse_tracking_info(tracking_info)

        %{
          current_branch: branch,
          upstream_branch: upstream,
          ahead_count: ahead,
          behind_count: behind
        }

      [branch] ->
        %{
          current_branch: branch,
          upstream_branch: nil,
          ahead_count: 0,
          behind_count: 0
        }
    end
  end

  defp parse_tracking_info(info) do
    # Extract upstream branch and tracking counts
    case Regex.run(~r/^([^\s\[]+)(?: \[(.+)\])?/, info) do
      [_, upstream, counts_str] when counts_str != "" ->
        {ahead, behind} = parse_tracking_counts(counts_str)
        {upstream, ahead, behind}

      [_, upstream] ->
        {upstream, 0, 0}

      _ ->
        {nil, 0, 0}
    end
  end

  defp parse_tracking_counts(counts_str) do
    ahead =
      case Regex.run(~r/ahead (\d+)/, counts_str) do
        [_, num] -> String.to_integer(num)
        _ -> 0
      end

    behind =
      case Regex.run(~r/behind (\d+)/, counts_str) do
        [_, num] -> String.to_integer(num)
        _ -> 0
      end

    {ahead, behind}
  end

  defp parse_file_lines(lines) do
    initial = %{
      changed_files: [],
      staged_files: [],
      untracked_files: [],
      deleted_files: [],
      is_dirty: false
    }

    result =
      Enum.reduce(lines, initial, fn line, acc ->
        parse_file_status(line, acc)
      end)

    %{result | is_dirty: result != initial}
  end

  defp parse_file_status(line, acc) do
    # Porcelain format: XY filename
    # X = index status, Y = worktree status
    case line do
      <<x::binary-size(1), y::binary-size(1), " ", filename::binary>> ->
        acc
        |> update_for_index_status(x, filename)
        |> update_for_worktree_status(y, filename)

      _ ->
        acc
    end
  end

  defp update_for_index_status(acc, status, filename) do
    case status do
      "A" ->
        %{acc | staged_files: [filename | acc.staged_files]}

      "M" ->
        %{acc | staged_files: [filename | acc.staged_files]}

      "D" ->
        %{
          acc
          | staged_files: [filename | acc.staged_files],
            deleted_files: [filename | acc.deleted_files]
        }

      _ ->
        acc
    end
  end

  defp update_for_worktree_status(acc, status, filename) do
    case status do
      "M" ->
        %{acc | changed_files: [filename | acc.changed_files]}

      "D" ->
        %{
          acc
          | changed_files: [filename | acc.changed_files],
            deleted_files: [filename | acc.deleted_files]
        }

      "?" ->
        %{acc | untracked_files: [filename | acc.untracked_files]}

      _ ->
        acc
    end
  end

  defp do_diff(repo, from, to) do
    with {:ok, patch} <- git_cmd(repo, ["diff", from, to]),
         {:ok, stats} <- get_diff_stats(repo, from, to) do
      {:ok, %{patch: patch, stats: stats}}
    else
      {:error, {:command_failed, 128, output}} ->
        if output =~ "unknown revision" or output =~ "bad revision" do
          # Determine which ref is invalid
          invalid_ref = if ref_exists?(repo, from), do: to, else: from
          {:error, {:invalid_ref, invalid_ref}}
        else
          {:error, {:command_failed, 128, output}}
        end

      {:error, _} = error ->
        error
    end
  end

  defp do_diff_uncommitted(repo) do
    with {:ok, patch} <- git_cmd(repo, ["diff", "HEAD"]),
         {:ok, stats} <- get_diff_stats(repo, "HEAD", nil) do
      {:ok, %{patch: patch, stats: stats}}
    end
  end

  defp get_diff_stats(repo, from, to) do
    args = if to, do: ["diff", "--numstat", from, to], else: ["diff", "--numstat", from]

    case git_cmd(repo, args) do
      {:ok, output} ->
        {:ok, parse_diff_stats(output)}

      {:error, _} = error ->
        error
    end
  end

  defp parse_diff_stats(""), do: %{additions: 0, deletions: 0, files_changed: 0, files: []}

  defp parse_diff_stats(output) do
    lines = String.split(output, "\n", trim: true)

    files =
      Enum.map(lines, fn line ->
        case String.split(line, "\t") do
          [additions, deletions, path] ->
            %{
              path: path,
              additions: parse_stat_number(additions),
              deletions: parse_stat_number(deletions)
            }

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    total_additions = Enum.sum(Enum.map(files, & &1.additions))
    total_deletions = Enum.sum(Enum.map(files, & &1.deletions))

    %{
      additions: total_additions,
      deletions: total_deletions,
      files_changed: length(files),
      files: files
    }
  end

  defp parse_stat_number("-"), do: 0
  defp parse_stat_number(num), do: String.to_integer(num)

  defp ref_exists?(repo, ref) do
    case git_cmd(repo, ["rev-parse", "--verify", ref]) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp do_commit(repo, message, opts) do
    args = build_commit_args(message, opts)

    case git_cmd(repo, args) do
      {:ok, _output} ->
        # Get the full commit hash of HEAD
        case git_cmd(repo, ["rev-parse", "HEAD"]) do
          {:ok, hash} -> {:ok, String.trim(hash)}
          {:error, reason} -> {:error, reason}
        end

      {:error, {:command_failed, 1, output}} ->
        cond do
          output =~ "nothing to commit" ->
            {:error, :nothing_to_commit}

          output =~ "no changes added to commit" ->
            {:error, :nothing_to_commit}

          true ->
            {:error, {:command_failed, 1, output}}
        end

      {:error, _} = error ->
        error
    end
  end

  defp build_commit_args(message, opts) do
    base = ["commit", "-m", message]

    base
    |> maybe_add_flag(opts[:allow_empty], "--allow-empty")
    |> maybe_add_flag(opts[:amend], "--amend")
    |> maybe_add_flag(opts[:no_verify], "--no-verify")
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, _, _), do: args

  defp do_log(repo, opts) do
    limit = Keyword.get(opts, :limit)
    skip = Keyword.get(opts, :skip, 0)

    # Custom format for parsing
    # Format: hash|short_hash|author_name|author_email|timestamp|subject|body
    format = "%H|%h|%an|%ae|%aI|%s|%b"
    args = ["log", "--format=#{format}"]

    args = if limit, do: args ++ ["-#{limit}"], else: args
    args = if skip > 0, do: args ++ ["--skip=#{skip}"], else: args

    case git_cmd(repo, args) do
      {:ok, output} ->
        commits = parse_log_output(output)
        {:ok, commits}

      {:error, _} = error ->
        error
    end
  end

  defp parse_log_output(""), do: []

  defp parse_log_output(output) do
    # Split by commit (separated by newlines with format markers)
    commits =
      output
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_commit_line/1)
      |> Enum.reject(&is_nil/1)

    commits
  end

  defp parse_commit_line(line) do
    case String.split(line, "|", parts: 7) do
      [hash, short_hash, author, email, timestamp, subject, body] ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, dt, _} ->
            %{
              hash: hash,
              short_hash: short_hash,
              author: author,
              author_email: email,
              timestamp: dt,
              subject: subject,
              message: build_message(subject, body),
              parents: []
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp build_message(subject, ""), do: subject
  defp build_message(subject, body), do: subject <> "\n\n" <> String.trim(body)

  defp do_show(repo, ref) do
    format = "%H|%h|%an|%ae|%aI|%s|%b"

    case git_cmd(repo, ["show", "-s", "--format=#{format}", ref]) do
      {:ok, output} ->
        case parse_commit_line(String.trim(output)) do
          nil -> {:error, {:invalid_ref, ref}}
          commit -> {:ok, commit}
        end

      {:error, {:command_failed, 128, _output}} ->
        {:error, {:invalid_ref, ref}}

      {:error, _} = error ->
        error
    end
  end

  defp do_push(repo, opts) do
    remote = Keyword.get(opts, :remote, "origin")
    branch = Keyword.get(opts, :branch)
    force = Keyword.get(opts, :force, false)
    set_upstream = Keyword.get(opts, :set_upstream, false)

    args = ["push", remote]
    args = if branch, do: args ++ [branch], else: args
    args = if force, do: args ++ ["--force"], else: args
    args = if set_upstream, do: args ++ ["--set-upstream"], else: args

    case git_cmd(repo, args) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp do_pull(repo, opts) do
    remote = Keyword.get(opts, :remote, "origin")
    branch = Keyword.get(opts, :branch)
    rebase = Keyword.get(opts, :rebase, false)

    args = ["pull", remote]
    args = if branch, do: args ++ [branch], else: args
    args = if rebase, do: args ++ ["--rebase"], else: args

    case git_cmd(repo, args) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp do_branch_create(repo, name, opts) do
    from = Keyword.get(opts, :from, "HEAD")
    checkout = Keyword.get(opts, :checkout, false)

    args = ["branch", name, from]

    with :ok <- git_cmd_ok(repo, args),
         :ok <- if(checkout, do: do_checkout(repo, name), else: :ok) do
      :ok
    end
  end

  defp do_branch_delete(repo, name, opts) do
    force = Keyword.get(opts, :force, false)
    remote = Keyword.get(opts, :remote)

    if remote do
      # Delete remote branch
      git_cmd_ok(repo, ["push", remote, "--delete", name])
    else
      # Delete local branch
      flag = if force, do: "-D", else: "-d"
      git_cmd_ok(repo, ["branch", flag, name])
    end
  end

  defp do_checkout(repo, ref) do
    case git_cmd(repo, ["checkout", ref]) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  # Helper to execute git commands
  defp git_cmd(repo, args) do
    case System.cmd("git", args, cd: repo, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, 128} ->
        {:error, {:command_failed, 128, output}}

      {output, exit_code} ->
        {:error, {:command_failed, exit_code, output}}
    end
  end

  # Helper that returns :ok or error tuple
  defp git_cmd_ok(repo, args) do
    case git_cmd(repo, args) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end
end
