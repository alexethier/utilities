"""GitHub API operations using PyGithub."""

from dataclasses import dataclass

from github import Github


@dataclass
class PRComment:
    """A PR review comment."""
    
    id: int
    user: str
    path: str
    line: int | None
    diff_hunk: str
    body: str


@dataclass
class PullRequest:
    """A pull request."""
    
    number: int
    title: str
    head_branch: str
    base_branch: str
    repo_owner: str
    repo_name: str


class GitHubApi:
    """Wrapper around PyGithub for GitHub operations."""
    
    def __init__(self, token: str):
        """Initialize with GitHub token."""
        self.github = Github(token)
    
    # PR operations
    
    def get_pr(self, owner: str, repo: str, pr_number: int) -> PullRequest:
        """Get a pull request by number."""
        gh_repo = self.github.get_repo(f"{owner}/{repo}")
        pr = gh_repo.get_pull(pr_number)
        return PullRequest(
            number=pr.number,
            title=pr.title,
            head_branch=pr.head.ref,
            base_branch=pr.base.ref,
            repo_owner=owner,
            repo_name=repo,
        )
    
    def get_pr_by_branch(self, owner: str, repo: str, branch: str) -> PullRequest | None:
        """Find PR with given branch as head. Returns None if not found."""
        gh_repo = self.github.get_repo(f"{owner}/{repo}")
        prs = gh_repo.get_pulls(state="open", head=f"{owner}:{branch}")
        for pr in prs:
            return PullRequest(
                number=pr.number,
                title=pr.title,
                head_branch=pr.head.ref,
                base_branch=pr.base.ref,
                repo_owner=owner,
                repo_name=repo,
            )
        return None
    
    def list_user_prs(self, user: str | None = None) -> list[PullRequest]:
        """List open PRs by user. If user is None, uses authenticated user."""
        if user is None:
            user = self.get_current_user()
        
        # Search for open PRs authored by user
        query = f"is:pr is:open author:{user} archived:false"
        issues = self.github.search_issues(query)
        
        prs = []
        for issue in issues:
            # Extract owner/repo from repository_url
            # Format: https://api.github.com/repos/owner/repo
            repo_parts = issue.repository_url.split("/")
            owner = repo_parts[-2]
            repo_name = repo_parts[-1]
            
            # Get full PR details
            gh_repo = self.github.get_repo(f"{owner}/{repo_name}")
            pr = gh_repo.get_pull(issue.number)
            
            # Skip AI-generated branches
            if pr.head.ref.endswith("_ai_review") or pr.head.ref.endswith("_ai_fix_conflicts"):
                continue
            
            prs.append(PullRequest(
                number=pr.number,
                title=pr.title,
                head_branch=pr.head.ref,
                base_branch=pr.base.ref,
                repo_owner=owner,
                repo_name=repo_name,
            ))
        
        return prs
    
    def get_pr_check_status(self, owner: str, repo: str, pr_number: int) -> dict:
        """Get PR check status. Returns {passed: int, failed: int, pending: int}."""
        gh_repo = self.github.get_repo(f"{owner}/{repo}")
        pr = gh_repo.get_pull(pr_number)
        
        # Get commit status
        commit = pr.head.sha
        statuses = gh_repo.get_commit(commit).get_combined_status()
        
        # Also get check runs
        check_runs = gh_repo.get_commit(commit).get_check_runs()
        
        passed = 0
        failed = 0
        pending = 0
        
        # Count statuses
        for status in statuses.statuses:
            if status.state == "success":
                passed += 1
            elif status.state == "failure" or status.state == "error":
                failed += 1
            else:
                pending += 1
        
        # Count check runs
        for check in check_runs:
            if check.conclusion == "success":
                passed += 1
            elif check.conclusion in ("failure", "cancelled", "timed_out"):
                failed += 1
            elif check.status != "completed":
                pending += 1
        
        return {"passed": passed, "failed": failed, "pending": pending}
    
    # Comment operations
    
    def get_eligible_comments(self, owner: str, repo: str, pr_number: int) -> list[PRComment]:
        """Get comments with laugh reaction but no rocket reaction."""
        gh_repo = self.github.get_repo(f"{owner}/{repo}")
        pr = gh_repo.get_pull(pr_number)
        
        eligible = []
        for comment in pr.get_review_comments():
            reactions = {r.content for r in comment.get_reactions()}
            
            # Must have laugh, must not have rocket
            if "laugh" in reactions and "rocket" not in reactions:
                eligible.append(PRComment(
                    id=comment.id,
                    user=comment.user.login,
                    path=comment.path,
                    line=comment.line or comment.original_line,
                    diff_hunk=comment.diff_hunk or "",
                    body=comment.body,
                ))
        
        return eligible
    
    def add_reaction(self, owner: str, repo: str, comment_id: int, reaction: str) -> None:
        """Add a reaction to a comment."""
        gh_repo = self.github.get_repo(f"{owner}/{repo}")
        # Get the comment and add reaction
        # PyGithub doesn't have a direct method, so we use the underlying requester
        gh_repo._requester.requestJsonAndCheck(
            "POST",
            f"/repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions",
            input={"content": reaction},
            headers={"Accept": "application/vnd.github+json"},
        )
    
    # PR creation
    
    def create_pr(
        self,
        owner: str,
        repo: str,
        head: str,
        base: str,
        title: str,
        body: str,
        draft: bool = False
    ) -> int:
        """Create a pull request. Returns PR number."""
        gh_repo = self.github.get_repo(f"{owner}/{repo}")
        pr = gh_repo.create_pull(title=title, body=body, head=head, base=base, draft=draft)
        return pr.number
    
    def get_existing_pr(self, owner: str, repo: str, head: str, base: str) -> int | None:
        """Get existing PR number for head->base, or None if not exists."""
        gh_repo = self.github.get_repo(f"{owner}/{repo}")
        prs = gh_repo.get_pulls(state="open", head=f"{owner}:{head}", base=base)
        for pr in prs:
            return pr.number
        return None
    
    # User
    
    def get_current_user(self) -> str:
        """Get the authenticated user's login."""
        return self.github.get_user().login
