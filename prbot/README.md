# prbot

PR management bot with AI-powered code changes via Cursor.

## Quickstart

### 1. Install

```bash
cd prbot
poetry install
```

### 2. Configure

```bash
export PRBOT_WORKDIR=~/prbot-work              # Where repos get cloned
export PRBOT_REPO_OWNER=your-org               # GitHub org that owns your fork
export PRBOT_GITHUB_TOKEN=$(gh auth token)      # GitHub token with repo access
export PRBOT_FORK_PREFIX=yourname-              # Optional prefix for fork repos
```

### 3. Run

```bash
# Sync a branch from source repo to your fork
prbot sync_branch -o source-org -n source-repo -b my-branch

# Sync all your open PRs from source to fork (with PR creation + comments)
prbot sync_prs -o source-org -n source-repo

# Run builds on a PR and auto-fix errors with AI
prbot test -o your-org -n your-repo -b my-branch

# Process PR review comments with AI
prbot review -o your-org -n your-repo -b my-branch

# Fix merge conflicts with AI
prbot fix_conflict -o your-org -n your-repo -b my-branch

# Implement a Jira ticket with AI
prbot jira -o source-org -n source-repo -j TICKET-123
```

## Commands

| Command | Description |
|---|---|
| `sync_branch` | Sync a single branch from source repo to your fork |
| `sync_prs` | Sync all your open PRs from source to fork (branches + PRs + comments) |
| `test` | Run builds in stages (compile, test, build) and fix errors with AI |
| `review` | Process PR comments (laugh-reacted) and implement changes with AI |
| `fix_conflict` | Cherry-pick PR commits and resolve conflicts with AI |
| `jira` | Fetch Jira issue, implement with AI, open PR on fork |

## Repo Arguments

Two ways to specify repos:

```bash
# Preferred: separate flags
prbot test -o my-org -n my-repo -b my-branch

# Also works: combined
prbot test -r my-org/my-repo -b my-branch
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `PRBOT_WORKDIR` | Yes | Directory where repos are cloned |
| `PRBOT_REPO_OWNER` | Yes | GitHub org/owner for your fork |
| `PRBOT_GITHUB_TOKEN` | Yes | GitHub PAT with `repo` scope |
| `PRBOT_FORK_PREFIX` | No | Prefix for fork repo names (e.g., `yourname-`) |
| `PRBOT_CURSOR_MODEL` | No | Cursor model for default tasks (default: `claude-4.6-opus-high`) |
| `PRBOT_CURSOR_THINKING_MODEL` | No | Cursor model for complex tasks (default: `claude-4.6-opus-high-thinking`) |

## Options

```bash
prbot --loop <command>     # Run continuously every 15 minutes
prbot --verbose <command>  # Enable verbose output
```

## AI Branch Strategy

AI changes are pushed to separate branches, not the original:

```
PR branch: feature-x
    ├── AI review changes   → feature-x_ai_review (PR into feature-x)
    └── AI conflict fixes   → feature-x_ai_fix_conflicts (PR into feature-x)
```
