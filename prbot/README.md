# prbot

Tools for managing PRs, branches, and forks.

## Configuration

Set these environment variables before using prbot:

```bash
export PRBOT_WORKDIR=/path/to/workdir       # Directory for cloned repos
export PRBOT_REPO_OWNER=your-org            # GitHub org/user that owns main repos
export PRBOT_FORK_OWNER=your-github-user    # Your GitHub username
export PRBOT_FORK_PREFIX=yourprefix-        # Prefix for fork repo names
```

Repos are cloned to: `$PRBOT_WORKDIR/$PRBOT_REPO_OWNER/<repo_name>`

## Fork Manager

Sync branches between a main repo and a private fork for confidential development.

Remotes: `origin` (main repo), `fork` (your fork)

Setup is automatic and idempotent - the script creates the directory, clones the repo, and adds both remotes as needed.

### Usage

Source the script:

```bash
source prbot/util/fork_manager.sh
```

#### Copy branch from main to fork

```bash
push_to_fork <repo_name> <branch_name>
# Example:
push_to_fork myrepo my-feature-branch
```

Fetches from main repo, force pushes to fork.

#### Copy branch from fork to main

```bash
push_to_main <repo_name> <branch_name>
# Example:
push_to_main myrepo my-feature-branch
```

This:
1. Runs `git save` to backup the branch in main repo
2. Fetches from fork
3. Pushes to main with `--force-with-lease`

## Conflict Fixer

The conflict fixer (`prbot fix_conflict`) fixes merge conflicts by cherry-picking PR commits onto main with explicit conflict/fix commit pairs.

### Usage

```bash
prbot fix_conflict -b <pr_branch>
```

### Workflow

1. Starts from `origin/main`
2. Cherry-picks each PR commit (oldest to newest)
3. On conflict, creates two commits:
   - `[CONFLICT] <msg>` - files with conflict markers + `conflicts.txt`
   - `[FIX] <msg>` - the AI resolution
4. Pushes result to fork as `<pr_branch>_ai_fix_conflicts`
5. Creates a draft PR for viewing changes

### Result Branch

```
main → PR commit 1 → [CONFLICT] PR commit 2 → [FIX] PR commit 2 → PR commit 3 → ...
```

Each conflict generates two commits:
- The `[CONFLICT]` commit shows the raw conflict markers and a `conflicts.txt` listing affected files
- The `[FIX]` commit shows exactly what changed to resolve the conflicts

### Applying Fixes

The draft PR contains instructions. To apply the fixes to your PR branch:

```bash
git fetch fork <pr_branch>_ai_fix_conflicts
git push origin fork/<pr_branch>_ai_fix_conflicts:<pr_branch> --force
```

**Warning:** This force pushes and replaces your PR branch.

### Notes

- The original PR branch is never modified by this script
- The `[CONFLICT]` + `[FIX]` pairs show explicit conflict resolution
- The draft PR is for viewing only - do not merge it
- Re-running starts fresh from main (idempotent)

## Other Tools

- `prbot` - Main entry point for PR operations
- `util/common.sh` - Shared utilities
- `commenter/comment_handler.sh` - PR comment handling

