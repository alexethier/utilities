# prbot

PR management bot with AI-powered code changes.

## Features

- **review**: Process PR comments with laugh reactions, implement with AI
- **test**: Run builds in 3 stages, fix errors with AI
- **fix_conflict**: Cherry-pick PR commits, resolve conflicts with AI

## Installation

```bash
poetry install
```

## Configuration

Set these environment variables:

```bash
export PRBOT_WORKDIR=/path/to/workdir       # Directory for cloned repos
export PRBOT_REPO_OWNER=your-org            # Default GitHub org/owner
export PRBOT_GITHUB_TOKEN=ghp_...           # GitHub personal access token
```

## Usage

```bash
# Process PR review comments
prbot review [-b BRANCH]

# Run builds and fix errors
prbot test [-b BRANCH]

# Fix merge conflicts
prbot fix_conflict -b BRANCH

# Global options
prbot [--loop] [--verbose] <action> [options]
```

## AI Branch Strategy

AI changes push to suffix branches on origin:

```
PR branch: feature-x
    └── AI review changes → feature-x_ai_review (PR into feature-x)
    └── AI conflict fixes → feature-x_ai_fix_conflicts (PR into feature-x)
```
