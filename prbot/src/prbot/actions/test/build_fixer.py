"""Build fixer for test action."""

import re
import subprocess
import tempfile
from enum import Enum
from pathlib import Path

from prbot.config import Config
from prbot.services.cursor.cursor_runner import CursorRunner
from prbot.services.git.git_repo import GitRepo
from prbot.services.github.github_api import GitHubApi, PullRequest


class BuildStage(Enum):
    """Build stages to run."""
    
    COMPILE = "compile"
    TEST = "test"
    BUILD = "build"


# Allowed build tools
ALLOWED_TOOLS = [
    "mvn", "mvnw", "gradle", "gradlew", "npm", "yarn", "pnpm",
    "make", "cmake", "ant", "sbt", "cargo", "go", "dotnet",
    "msbuild", "bazel", "buck", "pants"
]

# Blocked commands
BLOCKED_COMMANDS = [
    "rm", "sudo", "dd", "mkfs", "chmod", "chown", "curl", "wget",
    "ssh", "scp", "nc", "netcat", "kill", "killall", "pkill",
    "shutdown", "reboot", "halt", "poweroff", "eval"
]

MAX_RETRIES = 3


class BuildFixer:
    """Runs builds and fixes errors with AI."""
    
    AI_BRANCH_SUFFIX = "_ai_review"
    
    def __init__(self, git: GitRepo, github: GitHubApi, cursor: CursorRunner, config: Config):
        """Initialize with services."""
        self.git = git
        self.github = github
        self.cursor = cursor
        self.config = config
        self._workdir: Path | None = None
    
    def test_pr(self, pr: PullRequest) -> bool:
        """Run all build stages on a PR."""
        print(f"\n🧪 Testing PR #{pr.number}: {pr.title}")
        print(f"🔗 https://github.com/{pr.repo_owner}/{pr.repo_name}/pull/{pr.number}")
        
        # Check if PR already passed
        status = self.github.get_pr_check_status(pr.repo_owner, pr.repo_name, pr.number)
        print(f"   Checks: {status['passed']} passed, {status['failed']} failed, {status['pending']} pending")
        
        if status["failed"] == 0 and status["pending"] == 0:
            print("   ✅ All checks passed, skipping")
            return True
        
        # Checkout AI branch
        ai_branch = f"{pr.head_branch}{self.AI_BRANCH_SUFFIX}"
        self.git.fetch("origin", pr.head_branch)
        self.git.checkout(ai_branch, create=True, start_point=f"origin/{pr.head_branch}")
        
        initial_sha = self.git.head_sha()
        
        # Create temp workdir for build outputs
        with tempfile.TemporaryDirectory(prefix="prbot_build_") as tmpdir:
            self._workdir = Path(tmpdir)
            
            all_passed = True
            
            # Run stages sequentially
            for stage in [BuildStage.COMPILE, BuildStage.TEST, BuildStage.BUILD]:
                if not self.run_stage(stage):
                    all_passed = False
                    break
            
            self._workdir = None
        
        # Push if we made changes
        final_sha = self.git.head_sha()
        if initial_sha != final_sha:
            print(f"\n📤 Pushing fixes to {ai_branch}...")
            self.git.push("origin", ai_branch, force=True)
            
            # Create PR if needed
            existing_pr = self.github.get_existing_pr(
                pr.repo_owner, pr.repo_name, ai_branch, pr.head_branch
            )
            
            if not existing_pr:
                new_pr = self.github.create_pr(
                    owner=pr.repo_owner,
                    repo=pr.repo_name,
                    head=ai_branch,
                    base=pr.head_branch,
                    title=f"AI build fixes for PR #{pr.number}",
                    body=f"This PR contains AI-generated build fixes for PR #{pr.number}",
                )
                print(f"✅ Created PR #{new_pr}")
        
        if all_passed:
            print("\n✅ All build stages passed!")
        else:
            print("\n⚠️ Some build stages failed")
        
        return all_passed
    
    def run_stage(self, stage: BuildStage) -> bool:
        """Run a single build stage with retry loop."""
        print(f"\n{'━' * 60}")
        print(f"🔨 Stage: {stage.value.title()}")
        print("━" * 60)
        
        # Get build command
        cmd = self.get_build_command(stage)
        print(f"📋 Build command: {cmd}")
        
        self.validate_build_command(cmd)
        
        retries = 0
        while retries < MAX_RETRIES:
            print(f"\n🚀 Running build (attempt {retries + 1}/{MAX_RETRIES})...")
            
            output_file = self._workdir / f"{stage.value}_output.log"
            
            # Run build
            result = subprocess.run(
                cmd,
                shell=True,
                cwd=self.git.path,
                capture_output=True,
                text=True,
            )
            
            # Save output
            output_file.write_text(result.stdout + "\n" + result.stderr)
            
            if result.returncode == 0:
                print(f"✅ {stage.value.title()} passed!")
                return True
            
            print(f"❌ Build failed (exit code: {result.returncode})")
            print("\nLast 20 lines of output:")
            lines = (result.stdout + result.stderr).strip().split("\n")
            for line in lines[-20:]:
                print(f"  {line}")
            
            # Ask AI to fix
            print("\n🤖 Asking AI to fix...")
            self.fix_build_errors(output_file)
            
            # Commit any changes
            self.git.add_all()
            if self.git.has_staged_changes():
                self.git.commit(f"[BUILD FIX - {stage.value.title()}] Fix build errors")
                print("💾 Fix committed")
            else:
                print("ℹ️ No changes made by AI")
            
            retries += 1
        
        print(f"❌ {stage.value.title()} failed after {MAX_RETRIES} attempts")
        return False
    
    def get_build_command(self, stage: BuildStage) -> str:
        """Ask AI for the appropriate build command."""
        cmd_file = self._workdir / f"{stage.value}_cmd.txt"
        
        prompts = {
            BuildStage.COMPILE: f"""Analyze the project at: {self.git.path}
Determine the command to clean and compile it (skip tests).
Write ONLY the command (no explanation) to: {cmd_file}
Examples: "mvn clean compile -DskipTests", "gradle clean compileJava", "npm run build"
""",
            BuildStage.TEST: f"""Analyze the project at: {self.git.path}
Determine the command to run unit tests only.
Write ONLY the command (no explanation) to: {cmd_file}
Examples: "mvn test", "gradle test", "npm test"
""",
            BuildStage.BUILD: f"""Analyze the project at: {self.git.path}
Determine the command for a full build with all tests.
Write ONLY the command (no explanation) to: {cmd_file}
Examples: "mvn package", "gradle build", "npm run build && npm test"
""",
        }
        
        self.cursor.run(prompts[stage])
        
        if not cmd_file.exists():
            raise RuntimeError("AI did not create command file")
        
        return cmd_file.read_text().strip()
    
    def validate_build_command(self, cmd: str) -> None:
        """Validate command is safe to run."""
        # Check for blocked commands
        for blocked in BLOCKED_COMMANDS:
            if re.search(rf"\b{blocked}\b", cmd):
                raise ValueError(f"Build command contains blocked command: {blocked}")
        
        # Check for -f flag
        if re.search(r"-f\b", cmd):
            raise ValueError("Build command contains -f flag")
        
        # Must contain allowed tool
        has_tool = any(re.search(rf"\b{tool}\b", cmd) for tool in ALLOWED_TOOLS)
        if not has_tool:
            raise ValueError(
                f"Build command must contain a recognized build tool: {', '.join(ALLOWED_TOOLS)}"
            )
        
        print("✅ Build command validated")
    
    def fix_build_errors(self, output_file: Path) -> None:
        """Ask AI to fix build errors based on output."""
        prompt = f"""The build failed. Read the end of the build output at: {output_file}
Analyze the errors and determine if the errors were due to test failure or checkstyle failure.
Fix any test or checkstyle errors by editing the source files.

Do not under any circumstances change the build process itself or change the way we run the build, only fix errors in code.
If the build fails due to other reasons, simply do nothing.
"""
        self.cursor.run_isolated(prompt, use_thinking=True)
