"""Configuration loading from environment variables."""

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Config:
    """Application configuration loaded from environment variables."""
    
    workdir: Path              # PRBOT_WORKDIR
    repo_owner: str            # PRBOT_REPO_OWNER
    github_token: str          # PRBOT_GITHUB_TOKEN
    fork_prefix: str           # PRBOT_FORK_PREFIX (optional, e.g., "aethier-")
    
    # Cursor model settings
    cursor_model_default: str = "sonnet-4.5"
    cursor_model_thinking: str = "opus-4.5-thinking"
    
    @classmethod
    def from_env(cls) -> "Config":
        """Load config from environment variables.
        
        Raises:
            ValueError: If required environment variables are missing.
        """
        missing = []
        
        workdir = os.environ.get("PRBOT_WORKDIR")
        if not workdir:
            missing.append("PRBOT_WORKDIR")
        
        repo_owner = os.environ.get("PRBOT_REPO_OWNER")
        if not repo_owner:
            missing.append("PRBOT_REPO_OWNER")
        
        github_token = os.environ.get("PRBOT_GITHUB_TOKEN")
        if not github_token:
            missing.append("PRBOT_GITHUB_TOKEN")
        
        if missing:
            raise ValueError(
                f"Missing required environment variables: {', '.join(missing)}\n"
                "Please set them before running prbot:\n"
                "  export PRBOT_WORKDIR=/path/to/workdir\n"
                "  export PRBOT_REPO_OWNER=your-org\n"
                "  export PRBOT_GITHUB_TOKEN=ghp_..."
            )
        
        return cls(
            workdir=Path(workdir),
            repo_owner=repo_owner,
            github_token=github_token,
            fork_prefix=os.environ.get("PRBOT_FORK_PREFIX", ""),
            cursor_model_default=os.environ.get("PRBOT_CURSOR_MODEL", "sonnet-4.5"),
            cursor_model_thinking=os.environ.get("PRBOT_CURSOR_THINKING_MODEL", "opus-4.5-thinking"),
        )
