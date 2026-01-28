defmodule PortfolioIndex.Adapters.VCS.GitTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.VCS.Git

  setup do
    # Create temporary directory
    tmp_dir = System.tmp_dir!() |> Path.join("git_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    # Initialize git repo
    System.cmd("git", ["init", "-b", "main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)

    # Create initial commit
    initial_file = Path.join(tmp_dir, "README.md")
    File.write!(initial_file, "# Test Repository\n")
    System.cmd("git", ["add", "README.md"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "Initial commit"], cd: tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{repo: tmp_dir}
  end

  describe "is_repo?/1" do
    test "returns true for valid repository", %{repo: repo} do
      assert Git.is_repo?(repo) == true
    end

    test "returns false for non-repository path" do
      non_repo = System.tmp_dir!()
      assert Git.is_repo?(non_repo) == false
    end

    test "returns false for non-existent path" do
      assert Git.is_repo?("/nonexistent/path") == false
    end
  end

  describe "status/1" do
    test "returns clean status for clean repository", %{repo: repo} do
      assert {:ok, status} = Git.status(repo)

      assert status.is_dirty == false
      assert status.changed_files == []
      assert status.staged_files == []
      assert status.untracked_files == []
      assert status.deleted_files == []
      assert status.current_branch != nil
    end

    test "returns changed_files for modified file", %{repo: repo} do
      file = Path.join(repo, "README.md")
      File.write!(file, "Modified content\n")

      assert {:ok, status} = Git.status(repo)

      assert status.is_dirty == true
      assert "README.md" in status.changed_files
    end

    test "returns staged_files for staged file", %{repo: repo} do
      file = Path.join(repo, "new_file.txt")
      File.write!(file, "New content\n")
      System.cmd("git", ["add", "new_file.txt"], cd: repo)

      assert {:ok, status} = Git.status(repo)

      assert status.is_dirty == true
      assert "new_file.txt" in status.staged_files
    end

    test "returns untracked_files for untracked file", %{repo: repo} do
      file = Path.join(repo, "untracked.txt")
      File.write!(file, "Untracked content\n")

      assert {:ok, status} = Git.status(repo)

      assert status.is_dirty == true
      assert "untracked.txt" in status.untracked_files
    end

    test "returns deleted_files for deleted file", %{repo: repo} do
      file = Path.join(repo, "README.md")
      File.rm!(file)

      assert {:ok, status} = Git.status(repo)

      assert status.is_dirty == true
      assert "README.md" in status.deleted_files
    end

    test "returns error for non-repository path" do
      non_repo = System.tmp_dir!()
      assert {:error, {:repository_not_found, ^non_repo}} = Git.status(non_repo)
    end
  end

  describe "current_branch/1" do
    test "returns current branch name", %{repo: repo} do
      assert {:ok, branch} = Git.current_branch(repo)
      assert branch == "main"
    end

    test "returns error for non-repository" do
      non_repo = System.tmp_dir!()
      assert {:error, {:repository_not_found, ^non_repo}} = Git.current_branch(non_repo)
    end
  end

  describe "stage/2" do
    test "stages specific files", %{repo: repo} do
      file1 = Path.join(repo, "file1.txt")
      file2 = Path.join(repo, "file2.txt")
      File.write!(file1, "Content 1\n")
      File.write!(file2, "Content 2\n")

      assert :ok = Git.stage(repo, ["file1.txt"])

      {:ok, status} = Git.status(repo)
      assert "file1.txt" in status.staged_files
      assert "file2.txt" in status.untracked_files
    end

    test "returns error for non-existent file", %{repo: repo} do
      assert {:error, _} = Git.stage(repo, ["nonexistent.txt"])
    end
  end

  describe "stage_all/1" do
    test "stages all modified and untracked files", %{repo: repo} do
      # Modify existing file
      File.write!(Path.join(repo, "README.md"), "Modified\n")

      # Create new file
      File.write!(Path.join(repo, "new_file.txt"), "New\n")

      assert :ok = Git.stage_all(repo)

      {:ok, status} = Git.status(repo)
      assert status.is_dirty == true
      assert "README.md" in status.staged_files
      assert "new_file.txt" in status.staged_files
    end
  end

  describe "unstage/2" do
    test "removes files from staging area", %{repo: repo} do
      file = Path.join(repo, "new_file.txt")
      File.write!(file, "Content\n")
      System.cmd("git", ["add", "new_file.txt"], cd: repo)

      assert :ok = Git.unstage(repo, ["new_file.txt"])

      {:ok, status} = Git.status(repo)
      assert "new_file.txt" not in status.staged_files
      assert "new_file.txt" in status.untracked_files
    end
  end

  describe "commit/3" do
    test "creates commit and returns hash", %{repo: repo} do
      file = Path.join(repo, "test.txt")
      File.write!(file, "Test content\n")
      System.cmd("git", ["add", "test.txt"], cd: repo)

      assert {:ok, hash} = Git.commit(repo, "Test commit", [])

      assert is_binary(hash)
      assert String.length(hash) == 40
      assert hash =~ ~r/^[0-9a-f]{40}$/
    end

    test "creates empty commit with allow_empty option", %{repo: repo} do
      assert {:ok, hash} = Git.commit(repo, "Empty commit", allow_empty: true)
      assert is_binary(hash)
    end

    test "returns error when nothing to commit", %{repo: repo} do
      assert {:error, :nothing_to_commit} = Git.commit(repo, "Empty", [])
    end

    test "includes correct message in commit", %{repo: repo} do
      file = Path.join(repo, "test.txt")
      File.write!(file, "Content\n")
      System.cmd("git", ["add", "test.txt"], cd: repo)

      {:ok, hash} = Git.commit(repo, "Test message", [])

      # Verify commit message
      {output, 0} = System.cmd("git", ["log", "-1", "--format=%s", hash], cd: repo)
      assert String.trim(output) == "Test message"
    end
  end

  describe "diff_uncommitted/1" do
    test "returns empty patch for clean repo", %{repo: repo} do
      assert {:ok, diff} = Git.diff_uncommitted(repo)

      assert diff.patch == ""
      assert diff.stats.additions == 0
      assert diff.stats.deletions == 0
      assert diff.stats.files_changed == 0
    end

    test "returns patch content for modified files", %{repo: repo} do
      file = Path.join(repo, "README.md")
      File.write!(file, "# Test Repository\nNew line\n")

      assert {:ok, diff} = Git.diff_uncommitted(repo)

      assert diff.patch =~ "+New line"
      assert diff.stats.additions > 0
      assert diff.stats.files_changed == 1
    end

    test "includes stats with additions/deletions", %{repo: repo} do
      file = Path.join(repo, "README.md")
      File.write!(file, "Replaced content\n")

      assert {:ok, diff} = Git.diff_uncommitted(repo)

      assert diff.stats.files_changed == 1
      assert diff.stats.additions >= 1
      assert diff.stats.deletions >= 1
    end
  end

  describe "diff/3" do
    setup %{repo: repo} do
      # Create second commit
      file = Path.join(repo, "file.txt")
      File.write!(file, "First version\n")
      System.cmd("git", ["add", "file.txt"], cd: repo)
      System.cmd("git", ["commit", "-m", "Add file"], cd: repo)

      # Create third commit
      File.write!(file, "Second version\n")
      System.cmd("git", ["add", "file.txt"], cd: repo)
      System.cmd("git", ["commit", "-m", "Update file"], cd: repo)

      :ok
    end

    test "returns diff between two commits", %{repo: repo} do
      assert {:ok, diff} = Git.diff(repo, "HEAD~1", "HEAD")

      assert diff.patch =~ "+Second version"
      assert diff.patch =~ "-First version"
      assert diff.stats.files_changed == 1
    end

    test "returns error for invalid ref", %{repo: repo} do
      assert {:error, {:invalid_ref, "nonexistent"}} = Git.diff(repo, "nonexistent", "HEAD")
    end
  end

  describe "log/2" do
    setup %{repo: repo} do
      # Create additional commits
      for i <- 1..5 do
        file = Path.join(repo, "file#{i}.txt")
        File.write!(file, "Content #{i}\n")
        System.cmd("git", ["add", "file#{i}.txt"], cd: repo)
        System.cmd("git", ["commit", "-m", "Commit #{i}"], cd: repo)
      end

      :ok
    end

    test "returns list of commits", %{repo: repo} do
      assert {:ok, commits} = Git.log(repo, [])

      assert is_list(commits)
      # Initial + 5 setup commits
      assert length(commits) >= 6

      commit = List.first(commits)
      assert is_binary(commit.hash)
      assert String.length(commit.hash) == 40
      assert is_binary(commit.short_hash)
      assert is_binary(commit.author)
      assert is_binary(commit.message)
      assert %DateTime{} = commit.timestamp
    end

    test "respects limit option", %{repo: repo} do
      assert {:ok, commits} = Git.log(repo, limit: 3)

      assert length(commits) == 3
    end

    test "commits are in reverse chronological order", %{repo: repo} do
      assert {:ok, commits} = Git.log(repo, limit: 2)

      [first, second | _] = commits
      assert DateTime.compare(first.timestamp, second.timestamp) in [:gt, :eq]
    end
  end

  describe "show/2" do
    test "returns commit details", %{repo: repo} do
      {:ok, commits} = Git.log(repo, limit: 1)
      [commit] = commits

      assert {:ok, shown} = Git.show(repo, commit.hash)

      assert shown.hash == commit.hash
      assert shown.author == commit.author
      assert shown.message == commit.message
    end

    test "works with HEAD ref", %{repo: repo} do
      assert {:ok, commit} = Git.show(repo, "HEAD")

      assert is_binary(commit.hash)
      assert is_binary(commit.author)
    end

    test "returns error for invalid ref", %{repo: repo} do
      assert {:error, {:invalid_ref, "nonexistent"}} = Git.show(repo, "nonexistent")
    end
  end

  describe "telemetry" do
    test "status emits start and stop events", %{repo: repo} do
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end

      handler_id = "test-status-#{:erlang.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:portfolio, :vcs, :status, :start],
          [:portfolio, :vcs, :status, :stop]
        ],
        handler,
        nil
      )

      {:ok, _status} = Git.status(repo)

      assert_received {:telemetry, [:portfolio, :vcs, :status, :start], _, %{repo: ^repo}}
      assert_received {:telemetry, [:portfolio, :vcs, :status, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert Map.has_key?(metadata, :files_changed)

      :telemetry.detach(handler_id)
    end

    test "commit emits start and stop events", %{repo: repo} do
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end

      handler_id = "test-commit-#{:erlang.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:portfolio, :vcs, :commit, :start],
          [:portfolio, :vcs, :commit, :stop]
        ],
        handler,
        nil
      )

      file = Path.join(repo, "telemetry_test.txt")
      File.write!(file, "Telemetry test content\n")
      System.cmd("git", ["add", "telemetry_test.txt"], cd: repo)

      {:ok, _hash} = Git.commit(repo, "Telemetry test commit", [])

      assert_received {:telemetry, [:portfolio, :vcs, :commit, :start], _, %{repo: ^repo}}
      assert_received {:telemetry, [:portfolio, :vcs, :commit, :stop], measurements, _}
      assert is_integer(measurements.duration)

      :telemetry.detach(handler_id)
    end

    test "diff emits start and stop events", %{repo: repo} do
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end

      handler_id = "test-diff-#{:erlang.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:portfolio, :vcs, :diff, :start],
          [:portfolio, :vcs, :diff, :stop]
        ],
        handler,
        nil
      )

      {:ok, _diff} = Git.diff_uncommitted(repo)

      assert_received {:telemetry, [:portfolio, :vcs, :diff, :start], _, %{repo: ^repo}}
      assert_received {:telemetry, [:portfolio, :vcs, :diff, :stop], measurements, _}
      assert is_integer(measurements.duration)

      :telemetry.detach(handler_id)
    end
  end
end
