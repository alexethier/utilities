#!/bin/bash
# Fork Manager - Synchronize branches between main repo and private fork
#
# Repos located at: $PRBOT_WORKDIR/$PRBOT_REPO_OWNER/$repo_name
# Uses two remotes: origin (main repo) and fork (your private fork)
#
# This file is sourced by other scripts or used standalone.

# ============================================================================
# Configuration - These must be set as environment variables:
#   PRBOT_REPO_OWNER  - GitHub org/user that owns the main repos (e.g., "your-org")
#   PRBOT_FORK_OWNER  - GitHub user that owns your forks (e.g., "your-username")
#   PRBOT_FORK_PREFIX - Prefix for fork repo names (e.g., "my-")
# ============================================================================

# ============================================================================
# Helpers
# ============================================================================

# Ensure repository is set up with origin and fork remotes
# Idempotent - only performs actions if necessary
# Usage: _ensure_repo <repo_name>
_ensure_repo() {
    local repo_name=$1
    local fork_repo="${PRBOT_FORK_PREFIX}${repo_name}"
    local repo_dir="$PRBOT_WORKDIR/$PRBOT_REPO_OWNER/$repo_name"

    # 1. Ensure repo directory exists
    if [ ! -d "$repo_dir" ]; then
        echo "📁 Creating directory $repo_dir..."
        mkdir -p "$repo_dir"
    fi

    cd "$repo_dir"

    # 2. Ensure it's a git repo (clone if not)
    if [ ! -d ".git" ]; then
        echo "📦 Cloning $PRBOT_REPO_OWNER/$repo_name..."
        git clone "https://github.com/$PRBOT_REPO_OWNER/$repo_name.git" .
    fi

    # 3. Ensure origin remote exists and works
    if ! git remote get-url origin &>/dev/null; then
        echo "🔗 Adding origin remote..."
        git remote add origin "https://github.com/$PRBOT_REPO_OWNER/$repo_name.git"
        echo "🔍 Verifying origin remote..."
        if ! git ls-remote --exit-code origin &>/dev/null; then
            echo "Error: Could not connect to origin remote"
            return 1
        fi
    fi

    # 4. Ensure fork remote exists and works
    if ! git remote get-url fork &>/dev/null; then
        echo "🔗 Adding fork remote ($PRBOT_FORK_OWNER/$fork_repo)..."
        git remote add fork "https://github.com/$PRBOT_FORK_OWNER/$fork_repo.git"
        echo "🔍 Verifying fork remote..."
        if ! git ls-remote --exit-code fork &>/dev/null; then
            echo "Error: Could not connect to fork remote"
            return 1
        fi
    fi

    echo "📂 Working in $repo_dir"
}

# ============================================================================
# Main -> Fork
# ============================================================================

# Push a branch from origin (main repo) to fork. Force push.
# Usage: push_to_fork <repo_name> <branch_name>
push_to_fork() {
    local repo_name=$1
    local branch_name=$2

    if [ -z "$repo_name" ] || [ -z "$branch_name" ]; then
        echo "Error: repo_name and branch_name required"
        echo "Usage: push_to_fork <repo_name> <branch_name>"
        return 1
    fi

    _ensure_repo "$repo_name" || return 1

    git fetch origin "$branch_name"
    git checkout -B "$branch_name" "origin/$branch_name"
    git push -u fork "$branch_name" --force

    echo "✅ Pushed $branch_name to ${PRBOT_FORK_PREFIX}${repo_name}"
}

# ============================================================================
# Fork -> Main
# ============================================================================

# Push a branch from fork back to origin (main repo).
# Runs git save first to backup, then uses --force-with-lease for safety.
# Usage: push_to_main <repo_name> <branch_name>
push_to_main() {
    local repo_name=$1
    local branch_name=$2

    if [ -z "$repo_name" ] || [ -z "$branch_name" ]; then
        echo "Error: repo_name and branch_name required"
        echo "Usage: push_to_main <repo_name> <branch_name>"
        return 1
    fi

    _ensure_repo "$repo_name" || return 1

    echo "💾 Backing up $branch_name with git save..."
    git save "$branch_name"

    git fetch fork "$branch_name"
    git checkout -B "$branch_name" "fork/$branch_name"
    git push origin "$branch_name:refs/heads/$branch_name" --force-with-lease

    echo "✅ Pushed $branch_name from ${PRBOT_FORK_PREFIX}${repo_name} to $repo_name"
}
