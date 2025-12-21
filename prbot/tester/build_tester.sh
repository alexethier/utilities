#!/bin/bash
# Build Tester functions for prbot
# This file is sourced by the main prbot script
#
# Runs builds in 3 stages (compile, unit tests, full build),
# prompting Cursor AI to fix any errors at each stage.

# Utilities are sourced by the main prbot script

# Config
PRBOT_MAX_RETRIES=3

# Create temp work directory for this run, echoes the path
_create_test_workdir() {
    local workdir=$(mktemp -d "/tmp/prbot_test_XXXXXX")
    echo "$workdir"
}

# Check if PR has passed all checks
# Returns 0 if all checks passed, 1 otherwise
_pr_checks_passed() {
    local repo_owner=$1
    local repo_name=$2
    local pr_number=$3
    
    # Get check status using JSON
    # bucket can be: pass, fail, pending, skipping, cancel
    local checks_json=$(gh pr checks "$pr_number" --repo "$repo_owner/$repo_name" --json name,bucket 2>/dev/null)
    
    local total=$(echo "$checks_json" | jq 'length')
    local passed=$(echo "$checks_json" | jq '[.[] | select(.bucket == "pass")] | length')
    local failed=$(echo "$checks_json" | jq '[.[] | select(.bucket == "fail")] | length')
    local pending=$(echo "$checks_json" | jq '[.[] | select(.bucket == "pending")] | length')
    
    echo "   Checks: $total total, $passed passed, $failed failed, $pending pending"
    
    local needs_work=$((failed + pending))
    if [ "$needs_work" -gt 0 ]; then
        echo "🔧 PR #$pr_number has $failed failed + $pending pending checks, will attempt fixes"
        return 1
    fi
    
    echo "✅ PR #$pr_number passed $passed / $total checks, skipping"
    return 0
}

# Show test action help
show_test_help() {
    cat << EOF
Usage: prbot [global options] test [options]

Run builds in 3 stages and fix any errors with AI.

Options:
  -b, --branch <branch>  Only test the PR for the specified branch in current repo
  -h, --help             Show this help message

Description:
  This action will:
  1. Identify the current GitHub user
  2. Find all open PRs (including drafts) across ALL repositories by that user
     (or just the PR for the specified branch in current repo if -b is used)
  3. For each PR, clone the repository to PRBOT_WORKDIR if not already cloned
  4. Run 3 build stages, fixing errors at each stage:
     - Stage 1: Compile (skip tests)
     - Stage 2: Unit tests
     - Stage 3: Full build
  5. Each fix is committed with [BUILD FIX - <Stage>] prefix
  6. Push the AI review branch and create a PR into the original PR branch

Examples:
  # Test all your open PRs
  prbot test

  # Test only the PR for a specific branch
  prbot test -b my-feature-branch

  # Run continuously, checking every 15 minutes
  prbot -l test
  prbot --loop test
EOF
}

# Stage prompts
_get_stage_prompt() {
    local stage=$1
    local cmd_file=$2
    
    case "$stage" in
        compile)
            cat <<EOF
Analyze this project and determine the command to compile it (skip tests).
Write ONLY the command (no explanation) to: $cmd_file
Examples: "mvn compile -DskipTests", "gradle compileJava", "npm run build"
EOF
            ;;
        test)
            cat <<EOF
Analyze this project and determine the command to run unit tests only.
Write ONLY the command (no explanation) to: $cmd_file
Examples: "mvn test", "gradle test", "npm test"
EOF
            ;;
        build)
            cat <<EOF
Analyze this project and determine the command for a full build with all tests.
Write ONLY the command (no explanation) to: $cmd_file
Examples: "mvn package", "gradle build", "npm run build && npm test"
EOF
            ;;
    esac
}

# Get fix prompt
_get_fix_prompt() {
    local output_file=$1
    
    cat <<EOF
The build failed. Read the end of the build output at: $output_file
Analyze the errors and determine if the errors were due to test failure or checkstyle failure.
Fix any test or checkstyle errors by editing the source files.

Do not under any circumstances change the build process itself or change the way we run the build, only fix errors in code.
If the build fails due to other reasons, simply do nothing.
EOF
}

# Validate build command for safety
# Exits 1 immediately if command is unsafe
_validate_build_cmd() {
    local cmd=$1
    
    # Blocked commands - dangerous operations
    local blocked="rm|sudo|dd|mkfs|chmod|chown|curl|wget|ssh|scp|nc|netcat|kill|killall|pkill|shutdown|reboot|halt|poweroff|eval"
    if echo "$cmd" | grep -qE "\b($blocked)\b"; then
        echo "❌ UNSAFE: Build command contains blocked command - aborting"
        echo "   Blocked: $blocked"
        exit 1
    fi
    
    # Disallowed flags
    if echo "$cmd" | grep -qE '\-f\b'; then
        echo "❌ UNSAFE: Build command contains '-f' flag - aborting"
        exit 1
    fi
    
    # Must contain a known build tool
    local allowed_tools="mvn|mvnw|gradle|gradlew|npm|yarn|pnpm|make|cmake|ant|sbt|cargo|go|dotnet|msbuild|bazel|buck|pants"
    if ! echo "$cmd" | grep -qE "\b($allowed_tools)\b"; then
        echo "❌ UNSAFE: Build command does not contain a recognized build tool - aborting"
        echo "   Allowed: mvn, gradle, gradlew, npm, yarn, pnpm, make, cmake, ant, sbt, cargo, go, dotnet, msbuild, bazel, buck, pants"
        exit 1
    fi
    
    echo "✅ Build command validated"
}

# Run a single build stage
# Args: stage stage_name workdir
# Returns 0 if stage passed, 1 if failed after max retries
_run_stage() {
    local stage=$1
    local stage_name=$2
    local workdir=$3
    local cmd_file="$workdir/build_cmd.txt"
    local output_file="$workdir/build_output.log"
    local retries=0
    local fixes_made=0
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔨 Stage: $stage_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get build command from AI
    echo "🤖 Asking AI for build command..."
    rm -f "$cmd_file"
    
    local cmd_prompt=$(_get_stage_prompt "$stage" "$cmd_file")
    run_cursor "$cmd_prompt"
    
    if [ ! -f "$cmd_file" ]; then
        echo "❌ AI did not create command file"
        return 1
    fi
    
    local build_cmd=$(cat "$cmd_file" | tr -d '\n')
    echo "📋 Build command: $build_cmd"
    
    # Validate command before executing
    _validate_build_cmd "$build_cmd"
    
    # Retry loop
    while [ $retries -lt $PRBOT_MAX_RETRIES ]; do
        echo ""
        echo "🚀 Running build (attempt $((retries + 1))/$PRBOT_MAX_RETRIES)..."
        
        # Execute build command, capture output
        rm -f "$output_file"
        eval "$build_cmd" > "$output_file" 2>&1
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "✅ $stage_name passed!"
            return 0
        fi
        
        echo "❌ Build failed (exit code: $exit_code)"
        echo "📄 Output saved to: $output_file"
        
        # Show last 20 lines of output
        echo ""
        echo "Last 20 lines of output:"
        tail -20 "$output_file"
        echo ""
        
        # Ask AI to fix
        echo "🤖 Asking AI to fix the errors..."
        local fix_prompt=$(_get_fix_prompt "$output_file")
        run_cursor "$fix_prompt" true
        
        # Check if AI made changes
        git add -A
        if ! git diff --cached --quiet; then
            echo "💾 Committing fix..."
            git commit -m "[BUILD FIX - $stage_name] Fix build errors

Build command: $build_cmd
Exit code: $exit_code

Fixed by AI"
            fixes_made=$((fixes_made + 1))
        else
            echo "ℹ️  No changes made by AI"
        fi
        
        retries=$((retries + 1))
    done
    
    echo "❌ $stage_name failed after $PRBOT_MAX_RETRIES attempts"
    return 1
}

# Test a single PR
# Args: repo_owner repo_name pr_number pr_title workdir
test_pr() {
    local repo_owner=$1
    local repo_name=$2
    local pr_number=$3
    local pr_title=$4
    local workdir=$5
    
    # Skip if PR already passed all checks
    echo "🔍 Checking PR #$pr_number status..."
    if _pr_checks_passed "$repo_owner" "$repo_name" "$pr_number"; then
        return 0
    fi
    
    local pr_branch=$(get_pr_branch "$repo_name" "$pr_number")
    
    # Checkout the AI review branch for this PR
    checkout_ai_review_branch "$repo_name" "$pr_branch"
    
    # Display PR header
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🧪 Testing PR #$pr_number: $pr_title"
    echo "🔗 https://github.com/$repo_owner/$repo_name/pull/$pr_number"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local all_passed=true
    local any_fixes=false
    
    # Track if we made any commits
    local initial_commit=$(git rev-parse HEAD)
    
    # Run stages sequentially - skip remaining stages if any stage fails
    # (no point running tests if compile fails, no point running full build if tests fail)
    if ! _run_stage "compile" "Compile" "$workdir"; then
        all_passed=false
    fi
    
    if [ "$all_passed" = true ]; then
        if ! _run_stage "test" "Unit Tests" "$workdir"; then
            all_passed=false
        fi
    fi
    
    if [ "$all_passed" = true ]; then
        if ! _run_stage "build" "Full Build" "$workdir"; then
            all_passed=false
        fi
    fi
    
    # Check if we made any commits
    local final_commit=$(git rev-parse HEAD)
    if [ "$initial_commit" != "$final_commit" ]; then
        any_fixes=true
    fi
    
    # Push if any fixes were made
    if [ "$any_fixes" = true ]; then
        echo ""
        echo "📤 Pushing fixes..."
        
        # Ensure PR branch exists on fork (needed as base for AI PR)
        push_to_fork "$repo_name" "$pr_branch"
        
        # Push the AI review branch and create a PR
        push_and_create_pr "$repo_name" "$pr_branch" "This PR contains AI-generated build fixes for PR #$pr_number"
    else
        echo ""
        echo "ℹ️  No fixes needed - all stages passed on first try"
    fi
    
    if [ "$all_passed" = true ]; then
        echo ""
        echo "✅ All build stages passed!"
    else
        echo ""
        echo "⚠️  Some build stages failed after max retries"
    fi
}

# Process a list of PRs for testing
# Args: prs workdir
test_process_prs() {
    local prs=$1
    local workdir=$2
    
    # Process each PR
    echo "$prs" | jq -c '.' | while IFS= read -r pr; do
        repo_owner=$(echo "$pr" | jq -r '.repo_owner')
        repo_name=$(echo "$pr" | jq -r '.repo_name')
        pr_number=$(echo "$pr" | jq -r '.number')
        pr_title=$(echo "$pr" | jq -r '.title')

        echo ""
        echo "🧪 Testing PR $repo_owner/$repo_name PR #$pr_number..."
        
        test_pr "$repo_owner" "$repo_name" "$pr_number" "$pr_title" "$workdir"
    done
    
    echo ""
    echo "✅ Finished testing PRs"
}

# Process all PRs by current user
# Args: workdir
test_process_all_user_prs() {
    local workdir=$1
    
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

    test_process_prs "$prs" "$workdir"
}

# Process single branch PR for testing
# Args: branch workdir
test_process_single_branch_pr() {
    local branch=$1
    local workdir=$2
    
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

    test_process_prs "$prs" "$workdir"
}

# Main action handler for test
action_test() {
    local branch=$1
    
    # Create temp work directory for this run
    local workdir=$(_create_test_workdir)
    echo "📁 Test workdir: $workdir"
    
    echo "🔍 Getting current user..."
    get_current_user
    echo "👤 User: $CURRENT_USER"
    
    if [ -n "$branch" ]; then
        echo "🔍 Finding repository information..."
        get_repo_info
        echo "📂 Repository: $REPO_OWNER/$REPO_NAME"
        test_process_single_branch_pr "$branch" "$workdir"
    else
        test_process_all_user_prs "$workdir"
    fi
}
