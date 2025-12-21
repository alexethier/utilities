#!/bin/bash
# Common utility functions for prbot
# This file is sourced by handler scripts

# Get the AI review branch name for a PR
get_ai_review_branch_name() {
    local pr_branch_name=$1
    echo "${pr_branch_name}_ai_review"
}

# Get the PR branch name from PR number
# Usage: get_pr_branch <repo_name> <pr_number>
get_pr_branch() {
    local repo_name=$1
    local pr_number=$2
    gh api "repos/$PRBOT_REPO_OWNER/$repo_name/pulls/$pr_number" --jq '.head.ref'
}

# Get the current GitHub user
get_current_user() {
    CURRENT_USER=$(gh api user -q .login)
    if [ -z "$CURRENT_USER" ]; then
        echo "Error: Could not determine current GitHub user"
        exit 1
    fi
}

# Get the current repo's owner and name from git remote
get_repo_info() {
    local remote_url=$(git config --get remote.origin.url)
    
    # Handle both SSH and HTTPS URLs
    if [[ $remote_url =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
    else
        echo "Error: Could not parse GitHub repository from remote URL: $remote_url"
        exit 1
    fi
}

# Checkout AI review branch based on the PR's head branch
# AI review branches only exist in the fork repo
# Usage: checkout_ai_review_branch <repo_name> <pr_branch>
checkout_ai_review_branch() {
    local repo_name=$1
    local pr_branch=$2
    local fork_repo="${PRBOT_FORK_PREFIX}${repo_name}"
    
    # Ensure repo is set up with origin and fork remotes
    _ensure_repo "$repo_name" || return 1
    
    echo "🔍 PR branch: $pr_branch"
    
    # Fetch the PR branch from origin (main repo)
    echo "📥 Fetching $pr_branch from origin..."
    git fetch origin "$pr_branch"
    
    # If PR branch already ends with _ai_review, use it directly from fork
    if [[ "$pr_branch" == *"_ai_review" ]]; then
        echo "🌿 PR is already on an AI review branch, using $pr_branch directly"
        git fetch fork "$pr_branch"
        git checkout -B "$pr_branch" "fork/$pr_branch"
    else
        local branch_name=$(get_ai_review_branch_name "$pr_branch")
        
        if git ls-remote --exit-code fork "refs/heads/$branch_name" &>/dev/null; then
            # AI branch exists on fork - check if it's based on latest PR
            echo "🔍 Found existing branch $branch_name on fork, checking if up-to-date..."
            git fetch fork "$branch_name"
            git fetch origin "$pr_branch"
            
            if git merge-base --is-ancestor "origin/$pr_branch" "fork/$branch_name"; then
                # AI branch already contains latest PR commits - use as-is
                echo "✅ AI branch is up-to-date with PR, using existing branch"
                git checkout -B "$branch_name" "fork/$branch_name"
            else
                # PR has new commits - reset AI branch from PR branch
                echo "🔄 PR has new commits, resetting AI branch from origin/$pr_branch"
                git checkout -B "$branch_name" --no-track "origin/$pr_branch"
            fi
        else
            # Branch doesn't exist - create from PR branch
            echo "🌿 Creating new branch: $branch_name (based on origin/$pr_branch)"
            git checkout -B "$branch_name" --no-track "origin/$pr_branch"
        fi
    fi
}

_push_and_create_fork_pr() {
    local fork_repo=$1
    local pr_branch_name=$2
    local pr_body=$3
    
    # If PR branch already ends with _ai_review, just push to fork
    if [[ "$pr_branch_name" == *"_ai_review" ]]; then
        echo ""
        echo "📤 Pushing updates to $pr_branch_name on fork..."
        git push fork "$pr_branch_name"
        echo "✅ Updates pushed to existing AI review branch on fork"
        return
    fi
    
    local ai_branch_name=$(get_ai_review_branch_name "$pr_branch_name")
    
    # Push AI branch to fork
    echo "📤 Pushing $ai_branch_name to fork..."
    git push -u fork "$ai_branch_name" --force
    
    # Check if a PR already exists in the fork repo
    echo "🔍 Checking if PR already exists for $ai_branch_name in fork..."
    local existing_pr=$(gh pr list --repo "$PRBOT_FORK_OWNER/$fork_repo" --head "$ai_branch_name" --base "$pr_branch_name" --json number --jq '.[0].number')
    
    if [ -n "$existing_pr" ]; then
        echo "✅ PR already exists: #$existing_pr"
        echo "🔗 https://github.com/$PRBOT_FORK_OWNER/$fork_repo/pull/$existing_pr"
    else
        echo "🔀 Creating PR in fork: $ai_branch_name into $pr_branch_name..."
        gh pr create --repo "$PRBOT_FORK_OWNER/$fork_repo" \
            --base "$pr_branch_name" \
            --head "$ai_branch_name" \
            --title "AI implementations for PR $pr_branch_name" \
            --body "$pr_body"
    fi
}

# Push AI review branch to fork and create a PR within the fork repo
# Usage: push_and_create_pr <repo_name> <pr_branch> <pr_body>
push_and_create_pr() {
    local repo_name=$1
    local pr_branch=$2
    local pr_body=$3
    local fork_repo="${PRBOT_FORK_PREFIX}${repo_name}"
    
    # Ensure repo is set up with origin and fork remotes
    _ensure_repo "$repo_name" || return 1
    
    _push_and_create_fork_pr "$fork_repo" "$pr_branch" "$pr_body"
}
