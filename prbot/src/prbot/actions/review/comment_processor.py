"""PR comment processor for review action."""

import os

from prbot.config import Config
from prbot.services.cursor.cursor_runner import CursorRunner
from prbot.services.git.git_repo import GitRepo
from prbot.services.github.github_api import GitHubApi, PRComment, PullRequest


class CommentProcessor:
    """Processes PR comments with laugh reactions using AI."""
    
    AI_BRANCH_SUFFIX = "_ai_review"
    
    def __init__(self, git: GitRepo, github: GitHubApi, cursor: CursorRunner, config: Config):
        """Initialize with services."""
        self.git = git
        self.github = github
        self.cursor = cursor
        self.config = config
    
    def process_pr(self, pr: PullRequest) -> None:
        """Process all eligible comments on a PR."""
        print(f"\n📋 Checking PR #{pr.number}: {pr.title}")
        print(f"🔗 https://github.com/{pr.repo_owner}/{pr.repo_name}/pull/{pr.number}")
        
        comments = self.github.get_eligible_comments(pr.repo_owner, pr.repo_name, pr.number)
        
        if not comments:
            print("   No eligible comments found")
            return
        
        print(f"   Found {len(comments)} eligible comment(s)")
        
        # Checkout AI branch
        ai_branch = self.checkout_ai_branch(pr)
        initial_sha = self.git.head_sha()
        
        # Process each comment
        for comment in comments:
            self.process_comment(pr, comment)
        
        # Push if we made changes
        final_sha = self.git.head_sha()
        if initial_sha != final_sha:
            self.push_and_create_pr(pr, ai_branch)
        else:
            print("   No changes made")
    
    def process_comment(self, pr: PullRequest, comment: PRComment) -> None:
        """Process a single comment."""
        print(f"\n😄 Processing comment {comment.id}")
        print(f"   📁 File: {comment.path}")
        if comment.line:
            print(f"   📍 Line: {comment.line}")
        print(f"   💬 Comment: {comment.body}")
        
        # Mark as being handled
        self.github.add_reaction(pr.repo_owner, pr.repo_name, comment.id, "rocket")
        
        # Build prompt
        abs_filepath = self.git.path / comment.path
        
        # Include hunk only if <= 50 lines
        hunk_lines = comment.diff_hunk.count("\n") + 1 if comment.diff_hunk else 0
        code_context = ""
        if hunk_lines <= 50 and comment.diff_hunk:
            code_context = f"""Code context (use this to locate the exact code):
```
{comment.diff_hunk}
```
"""
        
        line_info = ""
        if comment.line:
            line_info = f"Estimated line: {comment.line} (may have shifted due to other changes)\n"
        
        prompt = f"""Please implement the following code review comment:

File: {abs_filepath}
{line_info}{code_context}
Comment: {comment.body}

You do not need to run tests, tests will be run in a later step.
"""
        
        # Run cursor
        self.cursor.run_isolated(prompt, use_thinking=True)
        
        # Commit changes
        self.git.add_all()
        if self.git.has_staged_changes():
            self.git.commit(
                f"Address review comment {comment.id} on {os.path.basename(comment.path)}\n\n"
                f"Comment: {comment.body}\n\n"
                f"Addressed by AI (comment ID: {comment.id})"
            )
            print("   💾 Changes committed")
        else:
            print("   ℹ️ No changes to commit")
    
    def checkout_ai_branch(self, pr: PullRequest) -> str:
        """Checkout or create the AI review branch."""
        ai_branch = f"{pr.head_branch}{self.AI_BRANCH_SUFFIX}"
        
        # Fetch PR branch
        print(f"   📥 Fetching {pr.head_branch}...")
        self.git.fetch("origin", pr.head_branch)
        
        # Check if AI branch exists on origin
        try:
            self.git.fetch("origin", ai_branch)
            ai_branch_exists = True
        except Exception:
            ai_branch_exists = False
        
        if ai_branch_exists:
            # Check if AI branch is up-to-date with PR
            self.git.checkout(ai_branch, create=True, start_point=f"origin/{ai_branch}")
            # TODO: Check if PR has new commits and reset if needed
        else:
            # Create from PR branch
            print(f"   🌿 Creating branch: {ai_branch}")
            self.git.checkout(ai_branch, create=True, start_point=f"origin/{pr.head_branch}")
        
        return ai_branch
    
    def push_and_create_pr(self, pr: PullRequest, ai_branch: str) -> None:
        """Push AI branch and create PR into original PR branch."""
        print(f"\n📤 Pushing {ai_branch}...")
        self.git.push("origin", ai_branch, force=True)
        
        # Check if PR exists
        existing_pr = self.github.get_existing_pr(
            pr.repo_owner, pr.repo_name, ai_branch, pr.head_branch
        )
        
        if existing_pr:
            print(f"✅ PR already exists: #{existing_pr}")
            print(f"🔗 https://github.com/{pr.repo_owner}/{pr.repo_name}/pull/{existing_pr}")
        else:
            branch_snippet = pr.head_branch[:10] + ("..." if len(pr.head_branch) > 10 else "")
            title_snippet = pr.title[:20] + ("..." if len(pr.title) > 20 else "")
            
            new_pr = self.github.create_pr(
                owner=pr.repo_owner,
                repo=pr.repo_name,
                head=ai_branch,
                base=pr.head_branch,
                title=f"AI: {branch_snippet} - {title_snippet} (PR #{pr.number})",
                body=f"AI-generated implementations for review comments.\n\nOriginal PR: #{pr.number}\nBranch: `{pr.head_branch}`\nTitle: {pr.title}",
            )
            print(f"✅ Created PR #{new_pr}")
            print(f"🔗 https://github.com/{pr.repo_owner}/{pr.repo_name}/pull/{new_pr}")
