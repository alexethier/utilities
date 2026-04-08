"""CLI entry point using argparse."""

import argparse
import sys
import time
from pathlib import Path

from prbot.config import Config
from prbot.services.cursor.cursor_runner import CursorRunner
from prbot.services.git.git_repo import GitRepo
from prbot.services.github.github_api import GitHubApi


def run_review(org: str, repo: str, args: argparse.Namespace, config: Config) -> None:
    """Run the review action."""
    from prbot.actions.review.comment_processor import CommentProcessor
    
    github = GitHubApi(config.github_token)
    cursor = CursorRunner(config)
    
    print(f"🔍 Finding PR for {org}/{repo} branch '{args.branch}'...")
    pr = github.get_pr_by_branch(org, repo, args.branch)
    if not pr:
        print(f"No open PR found for branch '{args.branch}'")
        return
    
    repo_path = config.workdir / org / repo
    git = GitRepo.ensure(f"https://github.com/{org}/{repo}.git", repo_path)
    
    processor = CommentProcessor(git, github, cursor, config)
    processor.process_pr(pr)


def run_test(org: str, repo: str, args: argparse.Namespace, config: Config) -> None:
    """Run the test action."""
    from prbot.actions.test.build_fixer import BuildFixer
    
    github = GitHubApi(config.github_token)
    cursor = CursorRunner(config)
    
    print(f"🔍 Finding PR for {org}/{repo} branch '{args.branch}'...")
    pr = github.get_pr_by_branch(org, repo, args.branch)
    if not pr:
        print(f"No open PR found for branch '{args.branch}'")
        return
    
    repo_path = config.workdir / org / repo
    git = GitRepo.ensure(f"https://github.com/{org}/{repo}.git", repo_path)
    
    fixer = BuildFixer(git, github, cursor, config)
    fixer.test_pr(pr)


def run_fix_conflict(org: str, repo: str, args: argparse.Namespace, config: Config) -> None:
    """Run the fix_conflict action."""
    from prbot.actions.conflict.cherry_pick_fixer import CherryPickFixer
    
    github = GitHubApi(config.github_token)
    cursor = CursorRunner(config)
    
    repo_path = config.workdir / org / repo
    git = GitRepo.ensure(f"https://github.com/{org}/{repo}.git", repo_path)
    
    fixer = CherryPickFixer(git, github, cursor, config)
    fixer.fix_conflicts(args.branch)


def _create_fork_syncer(org: str, repo: str, config: Config):
    """Create a ForkSyncer instance."""
    from prbot.actions.fork_syncer.fork_syncer import ForkSyncer
    
    target_owner = config.repo_owner
    target_repo = f"{config.fork_prefix}{repo}"
    
    github = GitHubApi(config.github_token)
    
    repo_path = config.workdir / target_owner / target_repo
    git = GitRepo.ensure(f"https://github.com/{target_owner}/{target_repo}.git", repo_path)
    
    syncer = ForkSyncer(git, github, config)
    return syncer


def run_sync_branch(org: str, repo: str, args: argparse.Namespace, config: Config) -> None:
    """Sync a single branch from source repo to fork."""
    syncer = _create_fork_syncer(org, repo, config)
    syncer.sync_branch_from_source(org, repo, args.branch)


def run_sync_prs(org: str, repo: str, args: argparse.Namespace, config: Config) -> None:
    """Sync open PRs from source repo to fork. Optionally filter by branch."""
    syncer = _create_fork_syncer(org, repo, config)
    syncer.sync_prs_from_source(org, repo, branch=args.branch)


def main() -> None:
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        prog="prbot",
        description="PR management bot with AI-powered code changes"
    )
    parser.add_argument("--loop", "-l", action="store_true", help="Run continuously every 15 minutes")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose output")
    
    subparsers = parser.add_subparsers(dest="action", required=True)
    
    # Shared repo args: either -r org/repo OR -o org -n name
    def add_repo_args(p):
        p.add_argument("-r", "--repo", help="Repo as org/repo (e.g., snowflake-eng/openflow-core)")
        p.add_argument("-o", "--org", help="Repo org/owner (e.g., snowflake-eng)")
        p.add_argument("-n", "--name", help="Repo name (e.g., openflow-core)")
    
    # review
    review_parser = subparsers.add_parser("review", help="Process PR review comments")
    add_repo_args(review_parser)
    review_parser.add_argument("-b", "--branch", required=True, help="PR branch to process")
    
    # test
    test_parser = subparsers.add_parser("test", help="Run builds and fix errors")
    add_repo_args(test_parser)
    test_parser.add_argument("-b", "--branch", required=True, help="PR branch to test")
    
    # fix_conflict
    conflict_parser = subparsers.add_parser("fix_conflict", help="Fix merge conflicts")
    add_repo_args(conflict_parser)
    conflict_parser.add_argument("-b", "--branch", required=True, help="PR branch to fix")
    
    # sync_branch
    sync_branch_parser = subparsers.add_parser("sync_branch", help="Sync a single branch from source repo to your fork")
    add_repo_args(sync_branch_parser)
    sync_branch_parser.add_argument("-b", "--branch", required=True, help="Branch to sync")
    
    # sync_prs
    sync_prs_parser = subparsers.add_parser("sync_prs", help="Sync your open PRs from source repo to your fork")
    add_repo_args(sync_prs_parser)
    sync_prs_parser.add_argument("-b", "--branch", help="Only sync the PR for this branch")
    
    args = parser.parse_args()
    
    # Resolve org and repo from either -r org/repo or -o org -n name
    raw_repo = getattr(args, "repo", None)
    raw_org = getattr(args, "org", None)
    raw_name = getattr(args, "name", None)
    
    if raw_repo and (raw_org or raw_name):
        print("❌ Use either -r org/repo or -o org -n name, not both")
        sys.exit(1)
    elif raw_repo:
        if "/" not in raw_repo:
            print(f"❌ Invalid -r format: {raw_repo}")
            print("   Expected: org/repo (e.g., snowflake-eng/openflow-core)")
            sys.exit(1)
        org, repo = raw_repo.split("/", 1)
    elif raw_org and raw_name:
        org, repo = raw_org, raw_name
    elif raw_org or raw_name:
        print("❌ Both -o and -n are required when not using -r")
        sys.exit(1)
    else:
        print("❌ Repo required: use -r org/repo or -o org -n name")
        sys.exit(1)
    
    try:
        config = Config.from_env()
    except ValueError as e:
        print(f"❌ Configuration error:\n{e}", file=sys.stderr)
        sys.exit(1)
    
    # Create workdir if needed
    config.workdir.mkdir(parents=True, exist_ok=True)
    
    # Action dispatch
    actions = {
        "review": run_review,
        "test": run_test,
        "fix_conflict": run_fix_conflict,
        "sync_branch": run_sync_branch,
        "sync_prs": run_sync_prs,
    }
    
    action_fn = actions[args.action]
    
    if args.loop:
        print("🔁 Loop mode enabled - will run every 15 minutes")
        print("Press Ctrl+C to stop")
        
        while True:
            print(f"\n⏰ Starting {args.action}...")
            try:
                action_fn(org, repo, args, config)
            except Exception as e:
                print(f"❌ Error: {e}", file=sys.stderr)
            
            print("\n😴 Sleeping for 15 minutes...")
            time.sleep(900)
    else:
        action_fn(org, repo, args, config)


if __name__ == "__main__":
    main()
