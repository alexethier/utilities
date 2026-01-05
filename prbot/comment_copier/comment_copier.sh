#!/bin/bash
# Comment Copier - Copy PR comments from origin repo to fork repo
# This file is sourced by the main prbot script

# Show copy_comments action help
show_copy_comments_help() {
    cat << EOF
Usage: prbot [global options] copy_comments [options]

Copy PR review comments from a PR on origin to a PR on fork.

Options:
  -b, --branch <branch>  The branch name (required)
  -h, --help             Show this help message

Description:
  This action will:
  1. Find the PR for the given branch on origin ($PRBOT_REPO_OWNER)
  2. Find the corresponding PR for the same branch on fork ($PRBOT_FORK_OWNER)
  3. Fetch all review comments from the origin PR
  4. Copy those comments to the fork PR

Examples:
  prbot copy_comments -b my-feature-branch
EOF
}

# Fetch all review comments from a PR
# Args: repo_owner repo_name pr_number
_fetch_pr_comments() {
    local repo_owner=$1
    local repo_name=$2
    local pr_number=$3
    
    gh api "repos/$repo_owner/$repo_name/pulls/$pr_number/comments" \
        --jq '.[] | {
            path: .path,
            line: (.line // .original_line),
            side: .side,
            body: .body,
            commit_id: .commit_id,
            original_commit_id: .original_commit_id
        }'
}

# Create a review comment on a PR
# Args: repo_owner repo_name pr_number comment_json
_create_pr_comment() {
    local repo_owner=$1
    local repo_name=$2
    local pr_number=$3
    local comment_json=$4
    
    local path=$(echo "$comment_json" | jq -r '.path')
    local line=$(echo "$comment_json" | jq -r '.line')
    local body=$(echo "$comment_json" | jq -r '.body')
    
    # Get the latest commit on the PR for the comment
    local commit_id=$(gh api "repos/$repo_owner/$repo_name/pulls/$pr_number" --jq '.head.sha')
    
    echo "   📝 Adding comment on $path:$line"
    
    # Create the comment
    gh api "repos/$repo_owner/$repo_name/pulls/$pr_number/comments" \
        -X POST \
        -f body="$body" \
        -f path="$path" \
        -f commit_id="$commit_id" \
        -F line="$line" \
        -f side="RIGHT" \
        --silent 2>/dev/null || echo "   ⚠️  Failed to create comment (file/line may not exist in this PR)"
}

# Find PR number for a branch
# Args: repo_owner repo_name branch
_find_pr_for_branch() {
    local repo_owner=$1
    local repo_name=$2
    local branch=$3
    
    gh api "repos/$repo_owner/$repo_name/pulls?state=open&head=$repo_owner:$branch" \
        --jq '.[0].number // empty'
}

# Find or create a PR on fork for a branch
# Args: fork_repo_name branch origin_repo_name origin_pr_number
# Echoes the fork PR number, returns 1 on failure
_find_or_create_fork_pr() {
    local fork_repo_name=$1
    local branch=$2
    local origin_repo_name=$3
    local origin_pr_number=$4
    
    local fork_pr=$(_find_pr_for_branch "$PRBOT_FORK_OWNER" "$fork_repo_name" "$branch")
    
    if [ -z "$fork_pr" ]; then
        echo "📝 No PR found on fork, creating one..." >&2
        
        # Get origin PR title for the new PR
        local origin_pr_title=$(gh api "repos/$PRBOT_REPO_OWNER/$origin_repo_name/pulls/$origin_pr_number" --jq '.title')
        
        # Create draft PR on fork: branch -> main
        gh pr create --repo "$PRBOT_FORK_OWNER/$fork_repo_name" \
            --base "main" \
            --head "$branch" \
            --title "$origin_pr_title" \
            --body "Mirror of $PRBOT_REPO_OWNER/$origin_repo_name PR #$origin_pr_number" \
            --draft >&2
        
        # Get the newly created PR number
        fork_pr=$(_find_pr_for_branch "$PRBOT_FORK_OWNER" "$fork_repo_name" "$branch")
        if [ -z "$fork_pr" ]; then
            echo "❌ Failed to create PR on fork" >&2
            return 1
        fi
        echo "✅ Created fork PR: #$fork_pr" >&2
    else
        echo "✅ Found existing fork PR: #$fork_pr" >&2
    fi
    
    echo "$fork_pr"
}

# Ensure branch exists on fork, push from origin if not
# Args: branch
# Returns 0 if branch exists/pushed, 1 on failure
_ensure_branch_on_fork() {
    local branch=$1
    
    # Check if branch exists on fork remote
    if git ls-remote --heads fork "$branch" | grep -q "$branch"; then
        echo "✅ Branch '$branch' exists on fork" >&2
        return 0
    fi
    
    echo "📤 Branch '$branch' not on fork, pushing from origin..." >&2
    
    # Fetch the branch from origin first
    git fetch origin "$branch" 2>/dev/null || {
        echo "❌ Failed to fetch branch '$branch' from origin" >&2
        return 1
    }
    
    # Push to fork
    git push fork "origin/$branch:refs/heads/$branch" || {
        echo "❌ Failed to push branch '$branch' to fork" >&2
        return 1
    }
    
    echo "✅ Pushed branch '$branch' to fork" >&2
    return 0
}

# Copy comments from origin PR to fork PR
# Args: branch
copy_comments() {
    local branch=$1
    
    if [ -z "$branch" ]; then
        echo "❌ Branch name is required"
        return 1
    fi
    
    # Get repo info from current directory
    get_repo_info
    local repo_name="$REPO_NAME"
    local fork_repo_name="${PRBOT_FORK_PREFIX}${repo_name}"
    
    echo "🔍 Looking for PRs for branch: $branch"
    echo "   Origin: $PRBOT_REPO_OWNER/$repo_name"
    echo "   Fork:   $PRBOT_FORK_OWNER/$fork_repo_name"
    echo ""
    
    # Find origin PR
    local origin_pr=$(_find_pr_for_branch "$PRBOT_REPO_OWNER" "$repo_name" "$branch")
    if [ -z "$origin_pr" ]; then
        echo "❌ No open PR found for branch '$branch' on origin ($PRBOT_REPO_OWNER/$repo_name)"
        return 1
    fi
    echo "✅ Found origin PR: #$origin_pr"
    echo "   🔗 https://github.com/$PRBOT_REPO_OWNER/$repo_name/pull/$origin_pr"
    
    # Ensure branch exists on fork
    _ensure_branch_on_fork "$branch" || return 1
    
    # Find or create fork PR
    local fork_pr=$(_find_or_create_fork_pr "$fork_repo_name" "$branch" "$repo_name" "$origin_pr")
    if [ -z "$fork_pr" ]; then
        return 1
    fi
    echo "   🔗 https://github.com/$PRBOT_FORK_OWNER/$fork_repo_name/pull/$fork_pr"
    echo ""
    
    # Fetch comments from origin PR
    echo "📥 Fetching comments from origin PR #$origin_pr..."
    local comments=$(_fetch_pr_comments "$PRBOT_REPO_OWNER" "$repo_name" "$origin_pr")
    
    if [ -z "$comments" ]; then
        echo "ℹ️  No comments found on origin PR"
        return 0
    fi
    
    local count=$(echo "$comments" | wc -l)
    echo "   Found $count comment(s)"
    echo ""
    
    # Copy each comment to fork PR
    echo "📤 Copying comments to fork PR #$fork_pr..."
    while IFS= read -r comment; do
        if [ -n "$comment" ]; then
            _create_pr_comment "$PRBOT_FORK_OWNER" "$fork_repo_name" "$fork_pr" "$comment"
        fi
    done <<< "$comments"
    
    echo ""
    echo "✅ Done copying comments!"
}

# Action entry point
action_copy_comments() {
    local branch=$1
    
    if [ -z "$branch" ]; then
        echo "❌ Branch name is required. Use -b <branch>"
        show_copy_comments_help
        return 1
    fi
    
    copy_comments "$branch"
}

