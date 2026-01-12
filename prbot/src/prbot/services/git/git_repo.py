"""Git repository operations using GitPython."""

import re
from pathlib import Path

from git import Repo
from git.exc import GitCommandError
from git.objects import Commit


class GitRepo:
    """Wrapper around GitPython for repository operations."""
    
    def __init__(self, path: Path):
        """Initialize with an existing repository path."""
        self.path = path
        self.repo = Repo(path)
    
    @classmethod
    def clone(cls, url: str, path: Path) -> "GitRepo":
        """Clone a repository to path."""
        path.parent.mkdir(parents=True, exist_ok=True)
        Repo.clone_from(url, path)
        return cls(path)
    
    @classmethod
    def ensure(cls, url: str, path: Path) -> "GitRepo":
        """Clone if not exists, otherwise open existing."""
        if path.exists() and (path / ".git").exists():
            return cls(path)
        return cls.clone(url, path)
    
    # Branch operations
    
    def fetch(self, remote: str = "origin", branch: str | None = None) -> None:
        """Fetch from remote, optionally a specific branch."""
        remote_obj = self.repo.remote(remote)
        if branch:
            remote_obj.fetch(branch)
        else:
            remote_obj.fetch()
    
    def checkout(self, branch: str, create: bool = False, start_point: str | None = None) -> None:
        """Checkout a branch, optionally creating it."""
        if create:
            if start_point:
                self.repo.git.checkout("-B", branch, start_point)
            else:
                self.repo.git.checkout("-B", branch)
        else:
            self.repo.git.checkout(branch)
    
    def push(self, remote: str = "origin", branch: str | None = None, force: bool = False) -> None:
        """Push to remote."""
        args = []
        if force:
            args.append("--force")
        if branch:
            args.extend([remote, branch])
        else:
            args.append(remote)
        self.repo.git.push(*args)
    
    def current_branch(self) -> str:
        """Get the current branch name."""
        return self.repo.active_branch.name
    
    # Commit operations
    
    def add_all(self) -> None:
        """Stage all changes."""
        self.repo.git.add("-A")
    
    def commit(self, message: str) -> str:
        """Commit staged changes. Returns commit SHA."""
        self.repo.index.commit(message)
        return self.repo.head.commit.hexsha
    
    def has_changes(self) -> bool:
        """Check if there are uncommitted changes (staged or unstaged)."""
        return self.repo.is_dirty(untracked_files=True)
    
    def has_staged_changes(self) -> bool:
        """Check if there are staged changes."""
        return len(self.repo.index.diff("HEAD")) > 0
    
    def head_sha(self) -> str:
        """Get HEAD commit SHA."""
        return self.repo.head.commit.hexsha
    
    # Cherry-pick / merge
    
    def cherry_pick(self, commit: str) -> bool:
        """Cherry-pick a commit. Returns True if clean, False if conflicts."""
        try:
            self.repo.git.cherry_pick(commit)
            return True
        except GitCommandError:
            return False
    
    def cherry_pick_abort(self) -> None:
        """Abort an in-progress cherry-pick."""
        try:
            self.repo.git.cherry_pick("--abort")
        except GitCommandError:
            pass  # No cherry-pick in progress
    
    def get_conflicted_files(self) -> list[str]:
        """Get list of files with conflicts."""
        # Unmerged files have a status that includes 'U'
        status_output = self.repo.git.diff("--name-only", "--diff-filter=U")
        if not status_output:
            return []
        return status_output.strip().split("\n")
    
    def get_commits_between(self, base: str, head: str) -> list[Commit]:
        """Get commits between base and head (oldest first)."""
        commits = list(self.repo.iter_commits(f"{base}..{head}"))
        commits.reverse()  # oldest first
        return commits
    
    # Remote management
    
    def has_remote(self, name: str) -> bool:
        """Check if a remote exists."""
        return name in [r.name for r in self.repo.remotes]
    
    def add_remote(self, name: str, url: str) -> None:
        """Add a git remote."""
        if not self.has_remote(name):
            self.repo.create_remote(name, url)
    
    def get_remote_url(self, remote: str = "origin") -> str:
        """Get URL for a remote."""
        return self.repo.remote(remote).url
    
    @staticmethod
    def parse_github_url(url: str) -> tuple[str, str]:
        """Parse GitHub URL to (owner, repo_name)."""
        # Handle SSH: git@github.com:owner/repo.git
        # Handle HTTPS: https://github.com/owner/repo.git
        match = re.search(r"github\.com[:/]([^/]+)/([^/.]+)", url)
        if not match:
            raise ValueError(f"Could not parse GitHub URL: {url}")
        return match.group(1), match.group(2)
