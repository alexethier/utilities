#!/bin/bash
# Cherry-pick Conflict Fixer
# Fixes conflicts by cherry-picking PR commits onto main with explicit [CONFLICT]/[FIX] commit pairs
#
# This file is sourced by the main prbot script

# Show fix_conflict action help
show_fix_conflict_help() {
    cat << EOF
Usage: prbot [global options] fix_conflict [options]

Fix conflicts by cherry-picking PR commits onto main with explicit [CONFLICT]/[FIX] commit pairs.

Options:
  -b, --branch <branch>  The PR branch to fix conflicts for (required)
  -h, --help             Show this help message

Description:
  This action:
  1. Starts from origin/main
  2. Cherry-picks each PR commit (oldest to newest)
  3. On conflict, creates two commits:
     - [CONFLICT] <msg> - files with conflict markers + conflicts.txt
     - [FIX] <msg> - the AI resolution
  4. Pushes result to fork as <branch>_ai_fix_conflicts
  5. Creates a draft PR for viewing the changes

  The [CONFLICT] commit shows the raw conflict markers.
  The [FIX] commit shows exactly what changed to resolve them.

Examples:
  prbot fix_conflict -b my-feature-branch
EOF
}

# Stage 1: Record conflicts and commit with conflict markers
# Creates conflicts.txt listing conflicted files, then commits everything
# including the conflict markers as [CONFLICT] <msg>
_stage1_commit_conflict() {
    local commit_msg=$1
    
    echo "📝 Stage 1: Recording conflicts..."
    
    # Get conflicted files before marking resolved
    local conflicted_files=$(git diff --name-only --diff-filter=U)
    
    if [ -z "$conflicted_files" ]; then
        echo "⚠️  No conflicts detected"
        return 1
    fi
    
    # Write conflicts list to file (will be committed)
    echo "$conflicted_files" > conflicts.txt
    local total_files=$(echo "$conflicted_files" | wc -l | tr -d ' ')
    echo "   Found $total_files conflicted file(s)"
    
    # Stage everything (with conflict markers intact)
    git add -A
    
    # Commit the conflict state
    git commit -m "[CONFLICT] $commit_msg"
    echo "✅ Committed conflict state"
}

# Stage 2: Fix conflicts with AI and commit resolution
# Reads conflicts.txt, fixes each file, commits as [FIX] <msg>
_stage2_fix_conflict() {
    local commit_msg=$1
    
    echo "🔧 Stage 2: Fixing conflicts with AI..."
    
    if [ ! -f conflicts.txt ]; then
        echo "⚠️  No conflicts.txt found"
        return 1
    fi
    
    local total_files=$(wc -l < conflicts.txt | tr -d ' ')
    local file_num=0
    
    while IFS= read -r file; do
        file_num=$((file_num + 1))
        echo "📝 Fixing $file_num/$total_files: $file"
        
        local abs_file=$(realpath "$file")
        
        local prompt=$(cat <<EOF
Fix the git merge conflict in this file. The conflicts are marked with
<<<<<<< HEAD, =======, and >>>>>>> markers.

Keep both changes where possible, preferring the incoming changes (from the cherry-picked commit)
but ensuring compatibility with the current codebase.

After fixing, the file should have no conflict markers remaining.
Fix one file at a time, unless the change has cross-file implications, other conflicts will be fixed later.

File: $abs_file
EOF
        )
        
        run_cursor_isolated "$prompt"
        
        # Check if conflicts are fixed
        if grep -q "^<<<<<<< " "$file" 2>/dev/null; then
            echo "⚠️  Conflict markers still present in $file, retrying..."
            run_cursor_isolated "$prompt"
        fi
    done < conflicts.txt

    # Cleanup conflicts.txt for next iteration
    rm -f conflicts.txt

    # Stage all fixes
    git add -A
    
    # Commit the fix
    git commit -m "[FIX] $commit_msg"
    echo "✅ Committed fixes for resolved merge conflicts"
}

# Orchestrator: Handle cherry-pick conflict with two-stage commit process
# Stage 1: Commit the conflict markers
# Stage 2: Fix and commit the resolution
handle_cherry_pick_conflict() {
    local commit=$1
    local commit_msg=$2
    
    echo "🔧 Handling conflict for: $commit_msg"
    
    _stage1_commit_conflict "$commit_msg"
    _stage2_fix_conflict "$commit_msg"
    
    echo "✅ Conflict handled with separate [CONFLICT] and [FIX] commits"
}

# Push fixed branch to fork and create draft PR
_push_and_create_draft_pr() {
    local pr_branch=$1
    local fixed_branch=$2
    local fork_repo=$3
    
    # Push to fork
    echo ""
    echo "📤 Pushing $fixed_branch to fork..."
    git push -u fork "$fixed_branch" --force
    echo "✅ Push successful"
    
    # Create draft PR with apply instructions
    echo ""
    echo "📋 Creating draft PR for viewing..."
    
    local pr_body="## Conflict Fixes for $pr_branch

This branch contains your PR commits cherry-picked onto main with explicit conflict resolution:
- \`[CONFLICT]\` commits show the raw conflict markers + \`conflicts.txt\`
- \`[FIX]\` commits show exactly what changed to resolve them

### To apply these fixes to your PR branch:

\`\`\`bash
git fetch fork $fixed_branch && \
  git push origin fork/$fixed_branch:$pr_branch --force
\`\`\`

**Warning:** This will force push and replace your PR branch.

---
DO NOT MERGE this draft PR. It is for viewing only."

    # Check if draft PR already exists
    local existing_pr=$(gh pr list --repo "$PRBOT_FORK_OWNER/$fork_repo" \
        --head "$fixed_branch" --base main --json number --jq '.[0].number')
    
    if [ -n "$existing_pr" ]; then
        echo "✅ Draft PR already exists: #$existing_pr"
        echo "🔗 https://github.com/$PRBOT_FORK_OWNER/$fork_repo/pull/$existing_pr"
    else
        gh pr create --repo "$PRBOT_FORK_OWNER/$fork_repo" \
            --base main \
            --head "$fixed_branch" \
            --title "Tmp View: Fixed conflicts for $pr_branch" \
            --body "$pr_body" \
            --draft
    fi
    
    # Output instructions
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Conflict fixing complete!"
    echo ""
    echo "Fixed branch: $fixed_branch"
    echo "View the draft PR on fork to see changes."
    echo ""
    echo "To apply to PR branch:"
    echo "  git fetch fork $fixed_branch"
    echo "  git push origin fork/$fixed_branch:$pr_branch --force"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Cleanup when no conflicts found - delete draft PR and branch if they exist
_cleanup_no_conflicts() {
    local fixed_branch=$1
    local fork_repo=$2
    
    echo ""
    echo "🧹 Cleaning up (no conflicts needed fixing)..."
    
    # Check if draft PR exists and close it
    local existing_pr=$(gh pr list --repo "$PRBOT_FORK_OWNER/$fork_repo" \
        --head "$fixed_branch" --base main --json number --jq '.[0].number')
    
    if [ -n "$existing_pr" ]; then
        echo "🗑️  Closing draft PR #$existing_pr..."
        gh pr close "$existing_pr" --repo "$PRBOT_FORK_OWNER/$fork_repo" --delete-branch 2>/dev/null || true
    fi
    
    # Delete the branch on fork if it exists
    if git ls-remote --exit-code fork "refs/heads/$fixed_branch" &>/dev/null; then
        echo "🗑️  Deleting $fixed_branch from fork..."
        git push fork --delete "$fixed_branch" 2>/dev/null || true
    fi
    
    # Delete the local branch if it exists
    if git show-ref --verify --quiet "refs/heads/$fixed_branch"; then
        echo "🗑️  Deleting local branch $fixed_branch..."
        git checkout main
        git branch -D "$fixed_branch" 2>/dev/null || true
    fi
    
    echo "✅ Cleanup complete - PR branch is already up-to-date with main"
}

# Main function to fix PR conflicts
fix_pr_conflicts() {
    local repo_name=$1
    local pr_branch=$2
    local fixed_branch="${pr_branch}_ai_fix_conflicts"
    local fork_repo="${PRBOT_FORK_PREFIX}${repo_name}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 Fixing conflicts for: $pr_branch"
    echo "   Output branch: $fixed_branch"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    _ensure_repo "$repo_name" || return 1
    
    # 1. Start from main
    echo ""
    echo "📥 Fetching main and $pr_branch..."
    git fetch origin main "$pr_branch"
    git checkout -B "$fixed_branch" origin/main
    
    # 2. Get PR commits (oldest first)
    local commits=$(git rev-list --reverse origin/main..origin/$pr_branch)
    local total_commits=$(echo "$commits" | wc -w | tr -d ' ')
    
    if [ -z "$commits" ] || [ "$total_commits" -eq 0 ]; then
        echo "ℹ️  No commits to cherry-pick (PR branch is up-to-date with main)"
        return 0
    fi
    
    echo "📋 Found $total_commits commit(s) to cherry-pick"
    
    # 3. Cherry-pick each with conflict fixing
    local commit_num=0
    local conflicts_found=0
    for commit in $commits; do
        commit_num=$((commit_num + 1))
        local commit_msg=$(git log -1 --format=%s "$commit")
        echo ""
        echo "🍒 Cherry-picking $commit_num/$total_commits: $commit_msg"
        
        if git cherry-pick "$commit" 2>/dev/null; then
            echo "✅ Applied cleanly"
        else
            # Has conflicts - use two-stage conflict handler
            conflicts_found=$((conflicts_found + 1))
            handle_cherry_pick_conflict "$commit" "$commit_msg"
            
            # Abort the failed cherry-pick (we've handled it manually with separate commits)
            git cherry-pick --abort 2>/dev/null || true
        fi
    done
    
    # 4. Handle result based on whether conflicts were found
    echo ""
    if [ "$conflicts_found" -eq 0 ]; then
        echo "✅ No conflicts encountered - all $total_commits commit(s) applied cleanly"
        _cleanup_no_conflicts "$fixed_branch" "$fork_repo"
    else
        echo "🔧 Fixed $conflicts_found conflict(s) out of $total_commits commit(s)"
        _push_and_create_draft_pr "$pr_branch" "$fixed_branch" "$fork_repo"
    fi
}

# Action handler for fix_conflict
action_fix_conflict() {
    if [ -z "$BRANCH" ]; then
        echo "Error: -b/--branch is required for fix_conflict action"
        echo "Run 'prbot fix_conflict --help' for usage."
        exit 1
    fi
    
    echo "🔍 Finding repository information..."
    get_repo_info
    echo "📂 Repository: $REPO_OWNER/$REPO_NAME"
    
    fix_pr_conflicts "$REPO_NAME" "$BRANCH"
}

