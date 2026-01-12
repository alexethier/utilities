"""Cursor CLI runner."""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from prbot.config import Config


class CursorRunner:
    """Invokes Cursor CLI for AI operations."""
    
    def __init__(self, config: Config):
        """Initialize with config."""
        self.config = config
    
    def _find_cursor(self) -> str:
        """Find cursor executable path."""
        cursor_path = shutil.which("cursor")
        if not cursor_path:
            raise RuntimeError("cursor executable not found in PATH")
        return cursor_path
    
    def run(self, prompt: str, use_thinking: bool = False) -> int:
        """Run cursor with prompt.
        
        Args:
            prompt: The prompt to send to cursor.
            use_thinking: If True, use the thinking model.
            
        Returns:
            Exit code from cursor process.
        """
        cursor_path = self._find_cursor()
        model = self.config.cursor_model_thinking if use_thinking else self.config.cursor_model_default
        
        result = subprocess.run(
            [cursor_path, "-p", prompt, "-m", model],
            check=False,
        )
        return result.returncode
    
    def run_isolated(self, prompt: str, use_thinking: bool = False) -> int:
        """Run cursor in isolated subprocess with clean environment.
        
        Args:
            prompt: The prompt to send to cursor.
            use_thinking: If True, use the thinking model.
            
        Returns:
            Exit code from cursor process.
        """
        cursor_path = self._find_cursor()
        model = self.config.cursor_model_thinking if use_thinking else self.config.cursor_model_default
        
        # Create temp directory for isolated run
        with tempfile.TemporaryDirectory(prefix="prbot_cursor_") as tmpdir:
            tmpdir_path = Path(tmpdir)
            prompt_file = tmpdir_path / "prompt.txt"
            exit_file = tmpdir_path / "exit"
            log_file = tmpdir_path / "log"
            
            # Write prompt to file
            prompt_file.write_text(prompt)
            
            # Create runner script
            runner_script = tmpdir_path / "run.sh"
            runner_script.write_text(f"""#!/bin/bash
{cursor_path} -m "{model}" -p "$(cat '{prompt_file}')" 2>&1 | tee "{log_file}"
echo $? > "{exit_file}"
""")
            runner_script.chmod(0o755)
            
            # Run in isolated environment
            env = {
                "PATH": f"/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:{Path.home()}/.local/bin",
                "HOME": str(Path.home()),
                "USER": os.environ.get("USER", ""),
                "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
            }
            
            print(f"🤖 Running cursor (model: {model})")
            print(f"📜 Runner dir: {tmpdir}")
            
            process = subprocess.Popen(
                ["/bin/bash", str(runner_script)],
                env=env,
                stdin=subprocess.DEVNULL,
            )
            
            process.wait()
            
            # Read exit code
            if exit_file.exists():
                exit_code = int(exit_file.read_text().strip())
                print(f"✅ Cursor finished (exit code: {exit_code})")
                return exit_code
            else:
                print("⚠️ Cursor finished (no exit code captured)")
                return 1
