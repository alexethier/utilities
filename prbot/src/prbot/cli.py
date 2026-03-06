"""CLI entry point using argparse."""

import argparse
import sys
import time
from pathlib import Path

from prbot.config import Config
from prbot.services.cursor.cursor_runner import CursorRunner
from prbot.services.git.git_repo import GitRepo
from prbot.services.github.github_api import GitHubApi


def run_review(args: argparse.Namespace, config: Config) -> None:
    """Run the review action."""
    from prbot.actions.review.comment_processor import CommentProcessor
    
    # Parse repo
    if "/" not in args.repo:
        print(f"❌ Invalid repo format: {args.repo}")
        print("   Expected: org/repo (e.g., myorg/myrepo)")
        sys.exit(1)
    repo_owner, repo_name = args.repo.split("/", 1)
    
    github = GitHubApi(config.github_token)
    cursor = CursorRunner(config)
    
    print(f"🔍 Finding PR for {repo_owner}/{repo_name} branch '{args.branch}'...")
    pr = github.get_pr_by_branch(repo_owner, repo_name, args.branch)
    if not pr:
        print(f"No open PR found for branch '{args.branch}'")
        return
    
    repo_path = config.workdir / repo_owner / repo_name
    git = GitRepo.ensure(f"https://github.com/{repo_owner}/{repo_name}.git", repo_path)
    
    processor = CommentProcessor(git, github, cursor, config)
    processor.process_pr(pr)


def run_test(args: argparse.Namespace, config: Config) -> None:
    """Run the test action."""
    from prbot.actions.test.build_fixer import BuildFixer
    
    # Parse repo
    if "/" not in args.repo:
        print(f"❌ Invalid repo format: {args.repo}")
        print("   Expected: org/repo (e.g., myorg/myrepo)")
        sys.exit(1)
    repo_owner, repo_name = args.repo.split("/", 1)
    
    github = GitHubApi(config.github_token)
    cursor = CursorRunner(config)
    
    print(f"🔍 Finding PR for {repo_owner}/{repo_name} branch '{args.branch}'...")
    pr = github.get_pr_by_branch(repo_owner, repo_name, args.branch)
    if not pr:
        print(f"No open PR found for branch '{args.branch}'")
        return
    
    repo_path = config.workdir / repo_owner / repo_name
    git = GitRepo.ensure(f"https://github.com/{repo_owner}/{repo_name}.git", repo_path)
    
    fixer = BuildFixer(git, github, cursor, config)
    fixer.test_pr(pr)


def run_fix_conflict(args: argparse.Namespace, config: Config) -> None:
    """Run the fix_conflict action."""
    from prbot.actions.conflict.cherry_pick_fixer import CherryPickFixer
    
    # Parse repo
    if "/" not in args.repo:
        print(f"❌ Invalid repo format: {args.repo}")
        print("   Expected: org/repo (e.g., myorg/myrepo)")
        sys.exit(1)
    repo_owner, repo_name = args.repo.split("/", 1)
    
    github = GitHubApi(config.github_token)
    cursor = CursorRunner(config)
    
    # Ensure repo in workdir
    repo_path = config.workdir / repo_owner / repo_name
    git = GitRepo.ensure(f"https://github.com/{repo_owner}/{repo_name}.git", repo_path)
    
    fixer = CherryPickFixer(git, github, cursor, config)
    fixer.fix_conflicts(args.branch)


def run_fork_sync(args: argparse.Namespace, config: Config) -> None:
    """Run the fork_sync action."""
    from prbot.actions.fork_syncer.fork_syncer import ForkSyncer
    
    # Parse source repo
    if "/" not in args.repo:
        print(f"❌ Invalid repo format: {args.repo}")
        print("   Expected: org/repo (e.g., myorg/myrepo)")
        sys.exit(1)
    
    source_owner, source_repo = args.repo.split("/", 1)
    
    # Target is derived: PRBOT_REPO_OWNER / PRBOT_FORK_PREFIX + source_repo_name
    target_owner = config.repo_owner
    target_repo = f"{config.fork_prefix}{source_repo}"
    
    github = GitHubApi(config.github_token)
    
    # Clone/open repo in workdir
    repo_path = config.workdir / target_owner / target_repo
    git = GitRepo.ensure(f"https://github.com/{target_owner}/{target_repo}.git", repo_path)
    
    syncer = ForkSyncer(git, github, config)
    syncer.sync(source_owner, source_repo, args.branch)


def main() -> None:
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        prog="prbot",
        description="PR management bot with AI-powered code changes"
    )
    parser.add_argument("--loop", "-l", action="store_true", help="Run continuously every 15 minutes")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose output")
    
    subparsers = parser.add_subparsers(dest="action", required=True)
    
    # review
    review_parser = subparsers.add_parser("review", help="Process PR review comments")
    review_parser.add_argument("-r", "--repo", required=True, help="Target repo (e.g., org/repo)")
    review_parser.add_argument("-b", "--branch", required=True, help="PR branch to process")
    
    # test
    test_parser = subparsers.add_parser("test", help="Run builds and fix errors")
    test_parser.add_argument("-r", "--repo", required=True, help="Target repo (e.g., org/repo)")
    test_parser.add_argument("-b", "--branch", required=True, help="PR branch to test")
    
    # fix_conflict
    conflict_parser = subparsers.add_parser("fix_conflict", help="Fix merge conflicts")
    conflict_parser.add_argument("-r", "--repo", required=True, help="Target repo (e.g., org/repo)")
    conflict_parser.add_argument("-b", "--branch", required=True, help="PR branch to fix")
    
    # fork_sync
    fork_sync_parser = subparsers.add_parser("fork_sync", help="Sync branches/PRs from source repo to your fork")
    fork_sync_parser.add_argument("-r", "--repo", required=True, help="Source repo to sync from (e.g., org/repo)")
    fork_sync_parser.add_argument("-b", "--branch", help="Only sync this branch (otherwise syncs all your PRs)")
    
    args = parser.parse_args()
    
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
        "fork_sync": run_fork_sync,
    }
    
    action_fn = actions[args.action]
    
    if args.loop:
        print("🔁 Loop mode enabled - will run every 15 minutes")
        print("Press Ctrl+C to stop")
        
        while True:
            print(f"\n⏰ Starting {args.action}...")
            try:
                action_fn(args, config)
            except Exception as e:
                print(f"❌ Error: {e}", file=sys.stderr)
            
            print("\n😴 Sleeping for 15 minutes...")
            time.sleep(900)
    else:
        action_fn(args, config)


if __name__ == "__main__":
    main()
