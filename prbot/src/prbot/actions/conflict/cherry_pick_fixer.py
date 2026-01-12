"""Cherry-pick conflict fixer for fix_conflict action."""

from pathlib import Path

from prbot.config import Config
from prbot.services.cursor.cursor_runner import CursorRunner
from prbot.services.git.git_repo import GitRepo
from prbot.services.github.github_api import GitHubApi


class CherryPickFixer:
    """Fixes merge conflicts by cherry-picking with AI resolution."""
    
    AI_BRANCH_SUFFIX = "_ai_fix_conflicts"
    
    def __init__(self, git: GitRepo, github: GitHubApi, cursor: CursorRunner, config: Config):
        """Initialize with services."""
        self.git = git
        self.github = github
        self.cursor = cursor
        self.config = config
    
    def fix_conflicts(self, pr_branch: str) -> None:
        """Cherry-pick PR commits onto main, fixing conflicts with AI."""
        fixed_branch = f"{pr_branch}{self.AI_BRANCH_SUFFIX}"
        owner, repo_name = self.git.parse_github_url(self.git.get_remote_url())
        
        print()
        print("━" * 60)
        print(f"🔧 Fixing conflicts for: {pr_branch}")
        print(f"   Output branch: {fixed_branch}")
        print("━" * 60)
        
        # Fetch main and PR branch
        print("\n📥 Fetching main and PR branch...")
        self.git.fetch("origin", "main")
        self.git.fetch("origin", pr_branch)
        
        # Start from main
        self.git.checkout(fixed_branch, create=True, start_point="origin/main")
        
        # Get PR commits (oldest first)
        commits = self.git.get_commits_between("origin/main", f"origin/{pr_branch}")
        
        if not commits:
            print("ℹ️ No commits to cherry-pick (PR branch is up-to-date with main)")
            return
        
        print(f"📋 Found {len(commits)} commit(s) to cherry-pick")
        
        # Cherry-pick each
        conflicts_found = 0
        for i, commit in enumerate(commits):
            commit_msg = commit.message.split("\n")[0]
            print(f"\n🍒 Cherry-picking {i + 1}/{len(commits)}: {commit_msg}")
            
            if self.git.cherry_pick(commit.hexsha):
                print("   ✅ Applied cleanly")
            else:
                conflicts_found += 1
                self.handle_conflict(commit.hexsha, commit_msg)
                self.git.cherry_pick_abort()
        
        # Handle result
        if conflicts_found == 0:
            print(f"\n✅ No conflicts - all {len(commits)} commit(s) applied cleanly")
            self._cleanup_no_conflicts(fixed_branch, owner, repo_name)
        else:
            print(f"\n🔧 Fixed {conflicts_found} conflict(s) out of {len(commits)} commit(s)")
            self.push_and_create_draft_pr(pr_branch, fixed_branch, owner, repo_name)
    
    def handle_conflict(self, commit_sha: str, commit_msg: str) -> None:
        """Handle a single conflict with two-stage commit process."""
        print(f"   🔧 Handling conflict...")
        self.stage1_commit_conflict(commit_msg)
        self.stage2_fix_conflict(commit_msg)
        print("   ✅ Conflict resolved")
    
    def stage1_commit_conflict(self, commit_msg: str) -> None:
        """Commit conflict markers and conflicts.txt as [CONFLICT] commit."""
        # Get conflicted files
        conflicted = self.git.get_conflicted_files()
        
        if not conflicted:
            print("   ⚠️ No conflicts detected")
            return
        
        # Write conflicts.txt
        conflicts_file = self.git.path / "conflicts.txt"
        conflicts_file.write_text("\n".join(conflicted))
        print(f"   📝 Found {len(conflicted)} conflicted file(s)")
        
        # Stage everything (with conflict markers)
        self.git.add_all()
        self.git.commit(f"[CONFLICT] {commit_msg}")
    
    def stage2_fix_conflict(self, commit_msg: str) -> None:
        """Fix conflicts with AI and commit as [FIX] commit."""
        conflicts_file = self.git.path / "conflicts.txt"
        
        if not conflicts_file.exists():
            print("   ⚠️ No conflicts.txt found")
            return
        
        conflicted = conflicts_file.read_text().strip().split("\n")
        
        for i, file in enumerate(conflicted):
            print(f"   📝 Fixing {i + 1}/{len(conflicted)}: {file}")
            
            abs_file = self.git.path / file
            
            prompt = f"""Fix the git merge conflict in this file. The conflicts are marked with
<<<<<<< HEAD, =======, and >>>>>>> markers.

Keep both changes where possible, preferring the incoming changes (from the cherry-picked commit)
but ensuring compatibility with the current codebase.

After fixing, the file should have no conflict markers remaining.
Fix one file at a time, unless the change has cross-file implications, other conflicts will be fixed later.

File: {abs_file}
"""
            
            self.cursor.run_isolated(prompt, use_thinking=True)
            
            # Check if conflicts remain
            if abs_file.exists() and "<<<<<<< " in abs_file.read_text():
                print("   ⚠️ Conflict markers still present, retrying...")
                self.cursor.run_isolated(prompt, use_thinking=True)
        
        # Cleanup and commit
        conflicts_file.unlink(missing_ok=True)
        self.git.add_all()
        self.git.commit(f"[FIX] {commit_msg}")
    
    def push_and_create_draft_pr(
        self, pr_branch: str, fixed_branch: str, owner: str, repo_name: str
    ) -> None:
        """Push fixed branch and create draft PR."""
        print(f"\n📤 Pushing {fixed_branch}...")
        self.git.push("origin", fixed_branch, force=True)
        
        pr_body = f"""## Conflict Fixes for {pr_branch}

This branch contains your PR commits cherry-picked onto main with explicit conflict resolution:
- `[CONFLICT]` commits show the raw conflict markers + `conflicts.txt`
- `[FIX]` commits show exactly what changed to resolve them

### To apply these fixes to your PR branch:

```bash
git fetch origin {fixed_branch} && \\
  git push origin origin/{fixed_branch}:{pr_branch} --force
```

**Warning:** This will force push and replace your PR branch.

---
DO NOT MERGE this draft PR. It is for viewing only.
"""
        
        # Check if PR exists
        existing_pr = self.github.get_existing_pr(owner, repo_name, fixed_branch, "main")
        
        if existing_pr:
            print(f"✅ Draft PR already exists: #{existing_pr}")
        else:
            new_pr = self.github.create_pr(
                owner=owner,
                repo=repo_name,
                head=fixed_branch,
                base="main",
                title=f"Tmp View: Fixed conflicts for {pr_branch}",
                body=pr_body,
                draft=True,
            )
            print(f"✅ Created draft PR #{new_pr}")
        
        print()
        print("━" * 60)
        print("✅ Conflict fixing complete!")
        print()
        print(f"Fixed branch: {fixed_branch}")
        print("View the draft PR to see changes.")
        print()
        print("To apply to PR branch:")
        print(f"  git fetch origin {fixed_branch}")
        print(f"  git push origin origin/{fixed_branch}:{pr_branch} --force")
        print("━" * 60)
    
    def _cleanup_no_conflicts(self, fixed_branch: str, owner: str, repo_name: str) -> None:
        """Cleanup when no conflicts found."""
        print("\n🧹 Cleaning up (no conflicts needed fixing)...")
        
        # Check if draft PR exists and close it
        existing_pr = self.github.get_existing_pr(owner, repo_name, fixed_branch, "main")
        if existing_pr:
            print(f"   🗑️ Draft PR #{existing_pr} exists - please close manually")
        
        # Delete remote branch if exists
        try:
            self.git.push("origin", f":{fixed_branch}")
            print(f"   🗑️ Deleted {fixed_branch} from origin")
        except Exception:
            pass
        
        print("✅ Cleanup complete - PR branch is already up-to-date with main")
