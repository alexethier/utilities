#!/bin/bash
# Commenter functions for prbot
# This file is sourced by the main prbot script

# Utilities are sourced by the main prbot script

# Show review action help
show_review_help() {
    cat << EOF
Usage: prbot [global options] review [options]

Find and process PR review comments with laugh reactions from all
open PRs (including drafts) created by the current user.

Options:
  -b, --branch <branch>  Only check the PR for the specified branch in current repo
  -h, --help             Show this help message

Description:
  This action will:
  1. Identify the current GitHub user
  2. Find all open PRs (including drafts) across ALL repositories by that user
     (or just the PR for the specified branch in current repo if -b is used)
  3. For each PR, clone the repository to PRBOT_WORKDIR if not already cloned
  4. Check each PR for review comments with laugh emoji (😄) reactions (without 🚀)
  5. For each eligible comment:
     - Add rocket emoji (🚀) to mark as being handled
     - Call cursor to implement the change
     - Commit the change
  6. Push the AI review branch and create a PR into the original PR branch
     (skipped if PR is already on an _ai_review branch)

Examples:
  # Check all your open PRs
  prbot review

  # Check only the PR for a specific branch
  prbot review -b my-feature-branch

  # Run continuously, checking every 15 minutes
  prbot -l review
  prbot --loop review
EOF
}

# Fetch eligible comments (with laugh reactions but no rocket reactions) from a PR
fetch_eligible_comments() {
    local repo_owner=$1
    local repo_name=$2
    local pr_number=$3

    # Fetch all review comments and filter using emoji signals
    # TODO: Also filter for unresolved comments (requires GraphQL API to check thread resolution status)
    gh api "repos/$repo_owner/$repo_name/pulls/$pr_number/comments" \
        --jq '.[] | select(.reactions.laugh > 0 and (.reactions.rocket // 0) == 0) | {
            id: .id,
            user: .user.login,
            path: .path,
            line: (.line // .original_line // null),
            diff_hunk: .diff_hunk,
            body: .body
        }'
}

# Process a single PR comment by calling cursor with the comment details
process_pr_comment() {
    local comment=$1
    local repo_owner=$2
    local repo_name=$3
    
    # Extract comment details
    local comment_id=$(echo "$comment" | jq -r '.id')
    local filepath=$(echo "$comment" | jq -r '.path')
    local line=$(echo "$comment" | jq -r '.line // empty')
    local diff_hunk_raw=$(echo "$comment" | jq -r '.diff_hunk // empty')
    local body=$(echo "$comment" | jq -r '.body')
    
    # Include hunk only if it's 50 lines or less, otherwise omit it entirely
    local hunk_lines=$(echo "$diff_hunk_raw" | wc -l)
    local diff_hunk
    if [ "$hunk_lines" -le 50 ]; then
        diff_hunk="$diff_hunk_raw"
    else
        diff_hunk=""
    fi
    
    echo ""
    echo "😄 Will handle this comment $comment_id"
    echo "📁 File: $filepath"
    [ -n "$line" ] && echo "📍 Line: $line (estimated)"
    echo "💬 Comment: $body"
    if [ -n "$diff_hunk" ]; then
        echo "📏 Diff hunk: $hunk_lines lines"
    else
        echo "📏 Diff hunk: $hunk_lines lines (too large, omitted)"
    fi

    # Add rocket emoji reaction to mark as handled to prevent duplicate processing
    # echo "🚀 Adding rocket reaction to comment $comment_id..."
    gh api "repos/$repo_owner/$repo_name/pulls/comments/$comment_id/reactions" \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -f content=rocket

    local abs_filepath=$(realpath "$filepath")

    # Build code context section only if hunk is available
    local code_context=""
    if [ -n "$diff_hunk" ]; then
        code_context="Code context (use this to locate the exact code):
\`\`\`
$diff_hunk
\`\`\`
"
    fi

    # Build line info if available
    local line_info=""
    [ -n "$line" ] && line_info="Estimated line: $line (may have shifted due to other changes)"$'\n'

    # Call cursor with the comment details
    local prompt=$(cat <<EOF
Please implement the following code review comment:

File: $abs_filepath
${line_info}${code_context}
Comment: $body

You do not need to run tests, tests will be run in a later step.
EOF
    )

    run_cursor_isolated "$prompt" true

    # Commit any changes made by cursor
    git add -A
    if ! git diff --cached --quiet; then
        echo "💾 Committing changes..."
        git commit -m "Address review comment $comment_id on $(basename "$filepath")

Comment: $body

Addressed by AI (comment ID: $comment_id)"
    else
        echo "ℹ️  No changes to commit for comment $comment_id"
    fi

}

# Process a list of PRs
process_prs() {
    local prs=$1
    
    # Process each PR
    echo "$prs" | jq -c '.' | while IFS= read -r pr; do
        repo_owner=$(echo "$pr" | jq -r '.repo_owner')
        repo_name=$(echo "$pr" | jq -r '.repo_name')
        pr_number=$(echo "$pr" | jq -r '.number')
        pr_title=$(echo "$pr" | jq -r '.title')

        echo ""
        echo "📋 Checking PR comments for $repo_owner/$repo_name PR #$pr_number..."
        
        process_pr "$repo_owner" "$repo_name" "$pr_number" "$pr_title"
    done
    
    echo ""
    echo "✅ Finished checking PRs"
}

# Process a single PR - check for comments and display if found
process_pr() {
    local repo_owner=$1
    local repo_name=$2
    local pr_number=$3
    local pr_title=$4
    
    # Checkout the AI review branch for this PR
    local comments=$(fetch_eligible_comments "$repo_owner" "$repo_name" "$pr_number")
    
    if [ -n "$comments" ]; then
        local pr_branch=$(get_pr_branch "$repo_name" "$pr_number")
        checkout_ai_review_branch "$repo_name" "$pr_branch"

        # Display PR header once
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📝 PR #$pr_number: $pr_title"
        echo "🔗 https://github.com/$repo_owner/$repo_name/pull/$pr_number"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Loop through each comment and process it
        while IFS= read -r comment; do
            if [ -n "$comment" ]; then
                process_pr_comment "$comment" "$repo_owner" "$repo_name"
            fi
        done <<< "$comments"
        
        # Ensure PR branch exists on fork (needed as base for AI PR)
        push_to_fork "$repo_name" "$pr_branch"
        
        # Push the AI review branch and create a PR
        push_and_create_pr "$repo_name" "$pr_branch" "This PR contains AI-generated implementations based on the review comments from PR #$pr_number"
    fi
}

process_all_user_prs() {
    # Get all open PRs by the current user across all repositories (excluding archived repos)
    echo "🔍 Finding all open PRs (including drafts) by $CURRENT_USER across all repositories..."
    
    # Get raw PR data and extract owner/name from full repository name
    prs=$(gh search prs --author="$CURRENT_USER" --state=open archived:false --json number,title,repository,headRefName \
        --jq '.[] | 
            (.repository.nameWithOwner | split("/")) as $repo_parts |
            {
                repo_owner: $repo_parts[0],
                repo_name: $repo_parts[1],
                number: .number,
                title: .title,
                branch: .headRefName
            }')

    # Filter out AI-generated branches (_ai_review, _ai_fix_conflicts)
    prs=$(echo "$prs" | jq -c 'select(.branch | test("_ai_review$|_ai_fix_conflicts$") | not)')
    
    if [ -z "$prs" ]; then
        echo "ℹ️  No non-AI PRs found for user $CURRENT_USER"
        return 0
    fi

    process_prs "$prs"
}

process_single_branch_pr() {
    local branch=$1
    
    # Check for PR on specific branch in current repo
    echo "🔍 Finding PR for branch: $branch in current repo..."
    
    # A single branch can have multiple PRs merging into different target branches
    prs=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls?state=open&head=$REPO_OWNER:$branch" \
        --jq ".[] | select(.user.login == \"$CURRENT_USER\") | {
            repo_owner: \"$REPO_OWNER\",
            repo_name: \"$REPO_NAME\",
            number: .number,
            title: .title
        }")
    
    if [ -z "$prs" ]; then
        echo "ℹ️  No open PR found for branch '$branch' by user $CURRENT_USER"
        echo "   Are you in the right git repo?"
        return 0
    fi

    process_prs "$prs"
}

action_review() {
    local branch=$1
    
    echo "🔍 Getting current user..."
    get_current_user
    echo "👤 User: $CURRENT_USER"
    
    if [ -n "$branch" ]; then
        echo "🔍 Finding repository information..."
        get_repo_info
        echo "📂 Repository: $REPO_OWNER/$REPO_NAME"
        process_single_branch_pr "$branch"
    else
        process_all_user_prs
    fi
}

