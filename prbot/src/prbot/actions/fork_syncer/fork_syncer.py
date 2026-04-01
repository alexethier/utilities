"""Fork syncer - syncs branches and PRs from source repo to target."""

from prbot.actions.fork_syncer.comment_syncer import CommentSyncer
from prbot.config import Config
from prbot.services.git.git_repo import GitRepo
from prbot.services.github.github_api import GitHubApi, PullRequest


class ForkSyncer:
    """Syncs branches and PRs from a public source repo to a private fork."""
    
    def __init__(self, git: GitRepo, github: GitHubApi, config: Config):
        """Initialize with services."""
        self.git = git
        self.github = github
        self.config = config
        
        # Get target repo info from git remote
        self.target_owner, self.target_repo = self.git.parse_github_url(
            self.git.get_remote_url("origin")
        )
        self.comment_syncer = CommentSyncer(github)
    
    def _print_header(self, source_owner: str, source_repo: str) -> None:
        """Print sync header."""
        print()
        print("━" * 60)
        print(f"🔄 Syncing from {source_owner}/{source_repo}")
        print(f"   Target: {self.target_owner}/{self.target_repo}")
        print("━" * 60)
    
    def sync_branch_from_source(self, source_owner: str, source_repo: str, branch: str) -> None:
        """Sync a single branch from source repo to target."""
        self._print_header(source_owner, source_repo)
        remote_name = self._add_source_remote(source_owner, source_repo)
        self._sync_branch(remote_name, branch)
    
    def sync_prs_from_source(self, source_owner: str, source_repo: str, branch: str | None = None) -> None:
        """Sync open PRs from source repo to target. Optionally filter by branch."""
        self._print_header(source_owner, source_repo)
        remote_name = self._add_source_remote(source_owner, source_repo)
        self._sync_prs(source_owner, source_repo, remote_name, branch=branch)
    
    def _sync_branch(self, remote_name: str, branch: str) -> None:
        """Sync a single branch from source to target."""
        print(f"\n📥 Syncing branch: {branch}")
        
        # Fetch from source
        print(f"   Fetching from {remote_name}...")
        self.git.fetch(remote_name, branch)
        
        # Checkout and push to origin
        self.git.checkout(branch, create=True, start_point=f"{remote_name}/{branch}")
        
        print(f"   Pushing to origin...")
        self.git.push("origin", branch, force=True)
        
        print(f"   ✅ Branch {branch} synced")
    
    def _sync_prs(self, source_owner: str, source_repo: str, remote_name: str, branch: str | None = None) -> None:
        """Sync open PRs authored by current user from source to target."""
        current_user = self.github.get_current_user()
        print(f"\n🔍 Finding open PRs by {current_user} in {source_owner}/{source_repo}...")
        
        source_prs = self._get_source_prs(source_owner, source_repo, current_user)
        
        if branch:
            source_prs = [pr for pr in source_prs if pr.head_branch == branch]
        
        if not source_prs:
            if branch:
                print(f"   No open PR found for branch '{branch}'")
            else:
                print("   No open PRs found")
            return
        
        print(f"   Found {len(source_prs)} open PR(s)")
        
        for pr in source_prs:
            self._sync_pr(pr, remote_name)
    
    def _get_source_prs(self, owner: str, repo: str, user: str) -> list[PullRequest]:
        """Get open PRs from source repo authored by user."""
        try:
            gh_repo = self.github.github.get_repo(f"{owner}/{repo}")
        except Exception as e:
            print(f"   ❌ Could not access source repo: {owner}/{repo}")
            print(f"      Error: {e}")
            print()
            print(f"      Your PRBOT_GITHUB_TOKEN may not have access to this repo.")
            print(f"      If 'gh' CLI works, try using its token:")
            print(f"        export PRBOT_GITHUB_TOKEN=$(gh auth token)")
            return []
        
        prs = []
        
        for pr in gh_repo.get_pulls(state="open"):
            # Only include PRs by the specified user
            if pr.user.login != user:
                continue
            
            prs.append(PullRequest(
                number=pr.number,
                title=pr.title,
                head_branch=pr.head.ref,
                base_branch=pr.base.ref,
                repo_owner=owner,
                repo_name=repo,
            ))
        
        return prs
    
    def _sync_pr(self, pr: PullRequest, remote_name: str) -> None:
        """Sync a single PR: branches and create PR in target."""
        print(f"\n📋 Syncing PR #{pr.number}: {pr.title}")
        print(f"   {pr.head_branch} → {pr.base_branch}")
        
        # Sync head branch
        print(f"   📥 Syncing head branch: {pr.head_branch}")
        try:
            self.git.fetch(remote_name, pr.head_branch)
            self.git.checkout(pr.head_branch, create=True, start_point=f"{remote_name}/{pr.head_branch}")
            self.git.push("origin", pr.head_branch, force=True)
        except Exception as e:
            print(f"   ⚠️ Failed to sync head branch: {e}")
            return
        
        # Sync base branch
        print(f"   📥 Syncing base branch: {pr.base_branch}")
        try:
            self.git.fetch(remote_name, pr.base_branch)
            self.git.checkout(pr.base_branch, create=True, start_point=f"{remote_name}/{pr.base_branch}")
            self.git.push("origin", pr.base_branch, force=True)
        except Exception as e:
            print(f"   ⚠️ Failed to sync base branch: {e}")
            return
        
        # Check if PR exists in target
        existing_pr = self.github.get_existing_pr(
            self.target_owner, self.target_repo, pr.head_branch, pr.base_branch
        )
        
        target_pr_number = None
        if existing_pr:
            print(f"   ✅ PR already exists: #{existing_pr}")
            target_pr_number = existing_pr
        else:
            # Create PR in target
            try:
                new_pr = self.github.create_pr(
                    owner=self.target_owner,
                    repo=self.target_repo,
                    head=pr.head_branch,
                    base=pr.base_branch,
                    title=f"[Sync] {pr.title}",
                    # URL in backticks to prevent GitHub cross-reference on source PR
                    body=f"Synced from {pr.repo_owner}/{pr.repo_name} PR #{pr.number}\n\nOriginal: `https://github.com/{pr.repo_owner}/{pr.repo_name}/pull/{pr.number}`",
                )
                print(f"   ✅ Created PR #{new_pr}")
                target_pr_number = new_pr
            except Exception as e:
                print(f"   ⚠️ Failed to create PR: {e}")
        
        # Sync comments
        if target_pr_number:
            print(f"   💬 Syncing comments...")
            synced = self.comment_syncer.sync_comments(
                pr.repo_owner, pr.repo_name, pr.number,
                self.target_owner, self.target_repo, target_pr_number,
            )
            if synced:
                print(f"   ✅ Synced {synced} comment(s)")
    
    def _add_source_remote(self, source_owner: str, source_repo: str) -> str:
        """Add source repo as a git remote. Returns remote name."""
        remote_name = f"source_{source_owner}_{source_repo}".replace("-", "_")
        url = f"https://github.com/{source_owner}/{source_repo}.git"
        
        if not self.git.has_remote(remote_name):
            print(f"\n🔗 Adding remote: {remote_name}")
            self.git.add_remote(remote_name, url)
        
        return remote_name
