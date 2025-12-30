#!/bin/bash
# Fork Comment Handler - Process PR review comments for PRs in fork repos
# This file is sourced by the main prbot script
#
# Unlike comment_handler.sh, this only works with PRs that are in your fork repo.
# It does not interact with origin at all.

# Show fork_review action help
show_fork_review_help() {
    cat << EOF
Usage: prbot [global options] fork_review [options]

Find and process PR review comments with laugh reactions from PRs
in your fork repositories.

Options:
  -b, --branch <branch>  Only check the PR for the specified branch in current repo
  -h, --help             Show this help message

Description:
  This action will:
  1. Identify the current GitHub user
  2. Find all open PRs in your fork repos (PRBOT_FORK_OWNER)
  3. For each PR, clone the fork repository to PRBOT_WORKDIR
  4. Check each PR for review comments with laugh emoji (😄) reactions (without 🚀)
  5. For each eligible comment:
     - Add rocket emoji (🚀) to mark as being handled
     - Call cursor to implement the change
     - Commit the change
  6. Push the AI review branch and create a PR into the original PR branch

Examples:
  prbot fork_review
  prbot fork_review -b my-feature-branch
EOF
}

# Ensure fork repo is set up - reuses existing clone if available
# Always ensures 'fork' remote exists pointing to the fork repo
# Args: repo_name
_ensure_fork_repo() {
    local repo_name=$1
    local fork_repo="${PRBOT_FORK_PREFIX}${repo_name}"
    
    # Check if repo already exists under REPO_OWNER (from comment_handler usage)
    local main_repo_dir="$PRBOT_WORKDIR/$PRBOT_REPO_OWNER/$repo_name"
    
    if [ -d "$main_repo_dir/.git" ]; then
        # Reuse existing clone
        cd "$main_repo_dir"
        echo "📂 Reusing existing clone at $main_repo_dir"
    else
        # Clone from main repo first (so we have proper origin)
        echo "📁 Creating directory $main_repo_dir..."
        mkdir -p "$main_repo_dir"
        cd "$main_repo_dir"
        
        if [ ! -d ".git" ]; then
            echo "📦 Cloning $PRBOT_REPO_OWNER/$repo_name..."
            git clone "https://github.com/$PRBOT_REPO_OWNER/$repo_name.git" .
        fi
        
        echo "📂 Working in $main_repo_dir"
    fi
    
    # Ensure fork remote exists
    if ! git remote get-url fork &>/dev/null; then
        echo "🔗 Adding fork remote ($PRBOT_FORK_OWNER/$fork_repo)..."
        git remote add fork "https://github.com/$PRBOT_FORK_OWNER/$fork_repo.git"
    fi
}

# Checkout AI review branch for a fork PR
# Args: repo_name pr_branch
_fork_checkout_ai_review_branch() {
    local repo_name="$1"
    local pr_branch="$2"
    
    _ensure_fork_repo "$repo_name"
    
    echo "🔍 PR branch: $pr_branch"
    echo "📥 Fetching $pr_branch from fork..."
    git fetch fork "$pr_branch"
    
    local ai_branch=$(get_ai_review_branch_name "$pr_branch")
    
    if git ls-remote --exit-code fork "refs/heads/$ai_branch" &>/dev/null; then
        echo "🔍 Found existing branch $ai_branch, checking if up-to-date..."
        git fetch fork "$ai_branch"
        
        if git merge-base --is-ancestor "fork/$pr_branch" "fork/$ai_branch"; then
            echo "✅ AI branch is up-to-date with PR, using existing branch"
            git checkout -B "$ai_branch" "fork/$ai_branch"
        else
            echo "🔄 PR has new commits, resetting AI branch from fork/$pr_branch"
            git checkout -B "$ai_branch" --no-track "fork/$pr_branch"
        fi
    else
        echo "🌿 Creating new branch: $ai_branch (based on fork/$pr_branch)"
        git checkout -B "$ai_branch" --no-track "fork/$pr_branch"
    fi
}

# Push AI branch and create PR in fork
# Args: repo_name pr_branch pr_number
_fork_push_and_create_pr() {
    local repo_name="$1"
    local pr_branch="$2"
    local pr_number="$3"
    local ai_branch=$(get_ai_review_branch_name "$pr_branch")
    
    local fork_repo_name="${PRBOT_FORK_PREFIX}${repo_name}"
    echo "📤 Pushing $ai_branch to $PRBOT_FORK_OWNER/$fork_repo_name..."
    git push -u fork "$ai_branch" --force
    
    echo "🔍 Checking if PR already exists..."
    local existing_pr=$(gh pr list --repo "$PRBOT_FORK_OWNER/$fork_repo_name" --head "$ai_branch" --base "$pr_branch" --json number --jq '.[0].number')
    
    if [ -n "$existing_pr" ]; then
        echo "✅ PR already exists: #$existing_pr"
        echo "🔗 https://github.com/$PRBOT_FORK_OWNER/$fork_repo_name/pull/$existing_pr"
    else
        echo "🔀 Creating PR: $ai_branch into $pr_branch..."
        gh pr create --repo "$PRBOT_FORK_OWNER/$fork_repo_name" \
            --base "$pr_branch" \
            --head "$ai_branch" \
            --title "AI implementations for PR #$pr_number" \
            --body "This PR contains AI-generated implementations based on the review comments from PR #$pr_number"
    fi
}

# Process a single fork PR
# Args: repo_name (original, without prefix) pr_number pr_title
_fork_process_pr() {
    local repo_name=$1
    local pr_number=$2
    local pr_title=$3
    local fork_repo_name="${PRBOT_FORK_PREFIX}${repo_name}"
    
    local comments=$(fetch_eligible_comments "$PRBOT_FORK_OWNER" "$fork_repo_name" "$pr_number")
    
    if [ -n "$comments" ]; then
        local pr_branch=$(get_pr_branch "$PRBOT_FORK_OWNER" "$fork_repo_name" "$pr_number")
        _fork_checkout_ai_review_branch "$repo_name" "$pr_branch"

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📝 PR #$pr_number: $pr_title"
        echo "🔗 https://github.com/$PRBOT_FORK_OWNER/$fork_repo_name/pull/$pr_number"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local initial_commit=$(git rev-parse HEAD)
        
        while IFS= read -r comment; do
            if [ -n "$comment" ]; then
                process_pr_comment "$comment" "$PRBOT_FORK_OWNER" "$fork_repo_name"
            fi
        done <<< "$comments"
        
        local final_commit=$(git rev-parse HEAD)
        if [ "$initial_commit" != "$final_commit" ]; then
            _fork_push_and_create_pr "$repo_name" "$pr_branch" "$pr_number"
        fi
    fi
}

# Process all PRs in fork repos by current user
_fork_process_all_user_prs() {
    echo "🔍 Finding all open PRs by $CURRENT_USER in fork repos..."
    
    # Search for PRs where the repo owner is the fork owner
    local raw_prs=$(gh search prs --author="$CURRENT_USER" --state=open --owner="$PRBOT_FORK_OWNER" archived:false --json number,title,repository \
        --jq '.[] | 
            (.repository.nameWithOwner | split("/")) as $repo_parts |
            {
                repo_name: $repo_parts[1],
                number: .number,
                title: .title
            }')
    
    if [ -z "$raw_prs" ]; then
        echo "ℹ️  No PRs found in fork repos for user $CURRENT_USER"
        return 0
    fi
    
    # Filter out AI branches
    while IFS= read -r pr; do
        local fork_repo_name=$(echo "$pr" | jq -r '.repo_name')
        local pr_number=$(echo "$pr" | jq -r '.number')
        local pr_title=$(echo "$pr" | jq -r '.title')
        
        # Strip fork prefix to get original repo name
        local repo_name="${fork_repo_name#$PRBOT_FORK_PREFIX}"
        
        local branch=$(get_pr_branch "$PRBOT_FORK_OWNER" "$fork_repo_name" "$pr_number")
        
        # Skip AI-generated branches
        if [[ "$branch" == *"_ai_review" ]] || [[ "$branch" == *"_ai_fix_conflicts" ]]; then
            continue
        fi
        
        echo ""
        echo "📋 Checking PR comments for $PRBOT_FORK_OWNER/$fork_repo_name PR #$pr_number..."
        _fork_process_pr "$repo_name" "$pr_number" "$pr_title"
    done <<< "$raw_prs"
    
    echo ""
    echo "✅ Finished checking fork PRs"
}

# Process PR for a specific branch in current fork repo
_fork_process_single_branch_pr() {
    local branch=$1
    
    # Get repo name from current directory
    get_repo_info
    local repo_name="$REPO_NAME"
    local fork_repo_name="${PRBOT_FORK_PREFIX}${repo_name}"
    
    echo "🔍 Finding PR for branch: $branch in $PRBOT_FORK_OWNER/$fork_repo_name..."
    
    local prs=$(gh api "repos/$PRBOT_FORK_OWNER/$fork_repo_name/pulls?state=open&head=$PRBOT_FORK_OWNER:$branch" \
        --jq ".[] | select(.user.login == \"$CURRENT_USER\") | {
            number: .number,
            title: .title
        }")
    
    if [ -z "$prs" ]; then
        echo "ℹ️  No open PR found for branch '$branch' by user $CURRENT_USER"
        return 0
    fi
    
    while IFS= read -r pr; do
        local pr_number=$(echo "$pr" | jq -r '.number')
        local pr_title=$(echo "$pr" | jq -r '.title')
        _fork_process_pr "$repo_name" "$pr_number" "$pr_title"
    done <<< "$prs"
}

# Action entry point
action_fork_review() {
    local branch=$1
    
    echo "🔍 Getting current user..."
    get_current_user
    echo "👤 User: $CURRENT_USER"
    echo "🍴 Fork owner: $PRBOT_FORK_OWNER"
    
    if [ -n "$branch" ]; then
        _fork_process_single_branch_pr "$branch"
    else
        _fork_process_all_user_prs
    fi
}

