#!/bin/bash
# Jira Generator - Implements Jira tickets using AI
# This script loads a Jira ticket's details and uses cursor to implement it

# Generate implementation prompt from ticket details
_generate_implementation_prompt() {
    local ticket_details="$1"
    
    cat <<EOF
You are implementing a Jira ticket. Here are the ticket details:

$ticket_details

Please implement this ticket in the current codebase. Follow these guidelines:
1. Analyze the existing codebase structure and patterns
2. Make changes that are consistent with the project's style
3. Write clean, maintainable code
4. Add appropriate tests if applicable
5. Do not make changes beyond what the ticket requires

Start by exploring the codebase to understand its structure, then implement the required changes.
EOF
}

# Push branch to fork and create draft PR
# Args: fork_repo branch_name ticket_id ticket_details
_push_and_create_draft_pr() {
    local fork_repo="$1"
    local branch_name="$2"
    local ticket_id="$3"
    local ticket_details="$4"
    
    # Push to fork
    echo "📤 Pushing $branch_name to fork..."
    git push -u fork "$branch_name" --force
    
    # Check if PR already exists
    echo "🔍 Checking if PR already exists..."
    local existing_pr=$(gh pr list --repo "$PRBOT_FORK_OWNER/$fork_repo" --head "$branch_name" --base "main" --json number --jq '.[0].number')
    
    if [ -n "$existing_pr" ]; then
        echo "✅ PR already exists: #$existing_pr"
        echo "🔗 https://github.com/$PRBOT_FORK_OWNER/$fork_repo/pull/$existing_pr"
    else
        echo "🔀 Creating draft PR..."
        local title="$ticket_id: $(echo "$ticket_details" | head -1 | cut -d: -f2- | xargs)"
        gh pr create --repo "$PRBOT_FORK_OWNER/$fork_repo" \
            --base "main" \
            --head "$branch_name" \
            --title "$title" \
            --body "Implements $ticket_id

$ticket_details" \
            --draft
    fi
}

# Implement a Jira ticket
# Args: ticket_id
jira_implement() {
    local ticket_id="$1"
    
    if [ -z "$ticket_id" ]; then
        echo "❌ Usage: jira_implement <TICKET-ID>" >&2
        return 1
    fi
    
    # Get repo info from current directory (sets REPO_OWNER and REPO_NAME)
    get_repo_info
    local repo_name="$REPO_NAME"
    local fork_repo="${PRBOT_FORK_PREFIX}${repo_name}"
    
    # Convert ticket ID to lowercase for branch name
    local branch_name=$(echo "$ticket_id" | tr '[:upper:]' '[:lower:]')
    
    echo "🎫 Loading Jira ticket: $ticket_id"
    
    # Get ticket details
    local ticket_details
    ticket_details=$(jira_get_ticket "$ticket_id")
    if [ $? -ne 0 ]; then
        echo "❌ Failed to load ticket: $ticket_id" >&2
        return 1
    fi
    
    echo "📋 Ticket details:"
    echo "$ticket_details"
    echo ""
    
    # Fetch latest main and create new branch
    echo "🔄 Fetching latest from origin..."
    git fetch origin main
    
    echo "🌿 Creating branch: $branch_name"
    git checkout -B "$branch_name" origin/main
    
    # Record initial commit
    local initial_commit=$(git rev-parse HEAD)
    
    # Generate the implementation prompt
    local prompt=$(_generate_implementation_prompt "$ticket_details")
    
    echo "🤖 Starting AI implementation (thinking model)..."
    echo ""
    
    # Use isolated cursor with thinking model
    run_cursor_isolated "$prompt" "true"
    
    # Check if any changes were made
    local final_commit=$(git rev-parse HEAD)
    if [ "$initial_commit" = "$final_commit" ]; then
        echo "ℹ️  No changes were made by AI"
        return 0
    fi
    
    _push_and_create_draft_pr "$fork_repo" "$branch_name" "$ticket_id" "$ticket_details"
    
    echo "✅ Done!"
}

# Show jira action help
show_jira_help() {
    cat << EOF
Usage: prbot [global options] jira [options]

Implement a Jira ticket using AI.

Options:
  -t, --ticket <TICKET-ID>  The Jira ticket ID to implement (required)
  -h, --help                Show this help message

Required environment variables:
  PRBOT_JIRA_TOKEN    - Jira API token
  PRBOT_JIRA_BASE_URL - Jira base URL  
  PRBOT_JIRA_EMAIL    - Jira account email

Description:
  This action will:
  1. Fetch the ticket details from Jira (title + description)
  2. Create a new branch named after the ticket (lowercase)
  3. Use AI (thinking model) to implement the ticket
  4. Push the branch to fork
  5. Create a draft PR

Examples:
  prbot jira -t PROJ-123
EOF
}

# Action entry point - called from prbot main script
# Args: ticket_id
action_jira() {
    local ticket_id="$1"
    
    if [ -z "$ticket_id" ]; then
        echo "❌ Ticket ID is required. Use -t <TICKET-ID>" >&2
        show_jira_help
        return 1
    fi
    
    jira_implement "$ticket_id"
}

