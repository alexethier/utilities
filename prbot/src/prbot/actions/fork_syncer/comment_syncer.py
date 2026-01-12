"""Comment syncer - syncs PR comments from source to target PR."""

from prbot.services.github.github_api import GitHubApi


class CommentSyncer:
    """Syncs review comments and issue comments from one PR to another."""
    
    SYNC_MARKER = "[Synced from"
    
    def __init__(self, github: GitHubApi):
        """Initialize with GitHub API."""
        self.github = github
    
    def sync_comments(
        self,
        source_owner: str,
        source_repo: str,
        source_pr: int,
        target_owner: str,
        target_repo: str,
        target_pr: int,
    ) -> int:
        """Sync comments from source PR to target PR.
        
        Args:
            source_owner: Owner of source repo
            source_repo: Name of source repo
            source_pr: PR number in source repo
            target_owner: Owner of target repo
            target_repo: Name of target repo
            target_pr: PR number in target repo
            
        Returns:
            Number of comments synced.
        """
        synced = 0
        
        # Sync issue comments (general PR comments)
        synced += self._sync_issue_comments(
            source_owner, source_repo, source_pr,
            target_owner, target_repo, target_pr,
        )
        
        # Sync review comments (inline code comments)
        synced += self._sync_review_comments(
            source_owner, source_repo, source_pr,
            target_owner, target_repo, target_pr,
        )
        
        return synced
    
    def _sync_issue_comments(
        self,
        source_owner: str,
        source_repo: str,
        source_pr: int,
        target_owner: str,
        target_repo: str,
        target_pr: int,
    ) -> int:
        """Sync issue comments (general PR comments)."""
        source_repo_obj = self.github.github.get_repo(f"{source_owner}/{source_repo}")
        target_repo_obj = self.github.github.get_repo(f"{target_owner}/{target_repo}")
        
        source_pr_obj = source_repo_obj.get_pull(source_pr)
        target_pr_obj = target_repo_obj.get_pull(target_pr)
        
        # Get existing synced comment IDs from target
        existing_synced = self._parse_synced_comment_ids(target_pr_obj.get_issue_comments())
        
        synced = 0
        for comment in source_pr_obj.get_issue_comments():
            if comment.id in existing_synced:
                continue
            
            # Create synced comment in target
            body = self._format_synced_comment(
                comment.body,
                comment.user.login,
                source_owner,
                source_repo,
                source_pr,
                comment.id,
            )
            target_pr_obj.create_issue_comment(body)
            snippet = comment.body[:20] + ("..." if len(comment.body) > 20 else "")
            print(f"      📝 @{comment.user.login}: {snippet}")
            synced += 1
        
        return synced
    
    def _sync_review_comments(
        self,
        source_owner: str,
        source_repo: str,
        source_pr: int,
        target_owner: str,
        target_repo: str,
        target_pr: int,
    ) -> int:
        """Sync review comments (inline code comments)."""
        source_repo_obj = self.github.github.get_repo(f"{source_owner}/{source_repo}")
        target_repo_obj = self.github.github.get_repo(f"{target_owner}/{target_repo}")
        
        source_pr_obj = source_repo_obj.get_pull(source_pr)
        target_pr_obj = target_repo_obj.get_pull(target_pr)
        
        # Get existing synced comment IDs from target
        existing_synced = self._parse_synced_comment_ids(target_pr_obj.get_review_comments())
        
        synced = 0
        for comment in source_pr_obj.get_review_comments():
            if comment.id in existing_synced:
                continue
            
            # Create synced review comment in target
            body = self._format_synced_comment(
                comment.body,
                comment.user.login,
                source_owner,
                source_repo,
                source_pr,
                comment.id,
            )
            
            snippet = comment.body[:50] + ("..." if len(comment.body) > 50 else "")
            try:
                # Determine which side of the diff and line number
                # LEFT = old code (deleted lines), RIGHT = new code (added lines)
                if comment.side == "LEFT" or (comment.line is None and comment.original_line):
                    # Comment on deleted code
                    side = "LEFT"
                    line = comment.original_line
                else:
                    # Comment on added/modified code
                    side = "RIGHT"
                    line = comment.line
                
                target_pr_obj.create_review_comment(
                    body=body,
                    commit=target_pr_obj.get_commits().reversed[0],
                    path=comment.path,
                    line=line,
                    side=side,
                )
                print(f"      💬 @{comment.user.login} on {comment.path}: {snippet}")
                synced += 1
            except Exception as e:
                # Review comments can fail if file/line doesn't match
                # Fall back to issue comment
                fallback_body = f"**Review comment on `{comment.path}`**\n\n{body}"
                target_pr_obj.create_issue_comment(fallback_body)
                print(f"      💬 @{comment.user.login} on {comment.path} (as issue): {snippet}")
                synced += 1
        
        return synced
    
    def _format_synced_comment(
        self,
        body: str,
        author: str,
        source_owner: str,
        source_repo: str,
        source_pr: int,
        comment_id: int,
    ) -> str:
        """Format a comment for syncing with attribution."""
        return (
            f"{body}\n\n"
            f"---\n"
            f"{self.SYNC_MARKER} {source_owner}/{source_repo}#{source_pr} "
            f"by @{author} | comment:{comment_id}]"
        )
    
    def _parse_synced_comment_ids(self, comments) -> set[int]:
        """Extract original comment IDs from synced comments."""
        ids = set()
        for comment in comments:
            if self.SYNC_MARKER in comment.body:
                # Extract comment ID from marker
                try:
                    marker_part = comment.body.split("comment:")[1]
                    comment_id = int(marker_part.split("]")[0])
                    ids.add(comment_id)
                except (IndexError, ValueError):
                    pass
        return ids
