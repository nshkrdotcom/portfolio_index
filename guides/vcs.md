# Version Control (Git)

PortfolioIndex includes a Git adapter that implements the
`PortfolioCore.Ports.VCS` behaviour, providing programmatic access to Git
operations with telemetry instrumentation.

## Git Adapter

`PortfolioIndex.Adapters.VCS.Git` wraps the Git CLI with structured Elixir
functions.

### Status

```elixir
alias PortfolioIndex.Adapters.VCS.Git

{:ok, status} = Git.status("/path/to/repo")

# status includes:
# - branch: "main"
# - staged: [%{path: "file.ex", status: :modified}]
# - unstaged: [%{path: "other.ex", status: :modified}]
# - untracked: ["new_file.ex"]
```

Uses `git status --porcelain=v1 -b` for reliable parsing.

### Diff

```elixir
# Unstaged changes
{:ok, diff} = Git.diff("/path/to/repo")

# Staged changes
{:ok, diff} = Git.diff("/path/to/repo", staged: true)

# Between commits
{:ok, diff} = Git.diff("/path/to/repo", from: "abc123", to: "def456")
```

Returns both patch text and numstat statistics (files changed, insertions,
deletions).

### Staging

```elixir
# Stage specific files
:ok = Git.stage("/path/to/repo", ["file1.ex", "file2.ex"])

# Stage all changes
:ok = Git.stage_all("/path/to/repo")

# Unstage files
:ok = Git.unstage("/path/to/repo", ["file1.ex"])
```

### Commits

```elixir
{:ok, commit_sha} = Git.commit("/path/to/repo", "Fix authentication bug")

# With options
{:ok, commit_sha} = Git.commit("/path/to/repo", "Initial commit",
  allow_empty: true,
  no_verify: true
)

# Amend
{:ok, commit_sha} = Git.commit("/path/to/repo", "Updated message",
  amend: true
)
```

### Log

```elixir
{:ok, commits} = Git.log("/path/to/repo", limit: 10)

# Each commit:
# %{sha: "abc123", message: "Fix bug", author: "Name", date: ~U[...]}
```

### Branch Operations

```elixir
# Create branch
:ok = Git.create_branch("/path/to/repo", "feature/new-thing")

# Checkout
:ok = Git.checkout("/path/to/repo", "feature/new-thing")

# Delete branch
:ok = Git.delete_branch("/path/to/repo", "feature/old-thing")
```

### Push and Pull

```elixir
:ok = Git.push("/path/to/repo", remote: "origin", branch: "main")
:ok = Git.pull("/path/to/repo", remote: "origin", branch: "main")
```

## Error Handling

The Git adapter maps Git exit codes to semantic error atoms:

| Exit Code | Error | Meaning |
|-----------|-------|---------|
| 1 | `:command_failed` | General failure |
| 128 | `:not_a_repo` | Not a Git repository |
| 128 | `:merge_conflict` | Merge conflict detected |

```elixir
case Git.commit("/path/to/repo", "message") do
  {:ok, sha} -> IO.puts("Committed: #{sha}")
  {:error, :not_a_repo} -> IO.puts("Not a Git repository")
  {:error, reason} -> IO.puts("Failed: #{inspect(reason)}")
end
```

## Telemetry

The Git adapter emits telemetry for key operations:

```elixir
[:portfolio_index, :vcs, :status, :start | :stop | :exception]
[:portfolio_index, :vcs, :commit, :start | :stop | :exception]
[:portfolio_index, :vcs, :diff, :start | :stop | :exception]
[:portfolio_index, :vcs, :push, :start | :stop | :exception]
[:portfolio_index, :vcs, :pull, :start | :stop | :exception]
```
