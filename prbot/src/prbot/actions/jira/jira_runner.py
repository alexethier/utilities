"""Orchestrate Jira-driven implementation on the target fork."""

from __future__ import annotations

import sys

from prbot.actions.fork_syncer.fork_syncer import ForkSyncer
from prbot.config import Config
from prbot.services.cursor.cursor_runner import CursorRunner
from prbot.services.git.git_repo import GitRepo
from prbot.services.github.github_api import GitHubApi
from prbot.services.jira.acli_client import fetch_ticket_blob


def _origin_has_branch(git: GitRepo, branch: str) -> bool:
    out = git.repo.git.ls_remote("origin", f"refs/heads/{branch}")
    return bool(out and out.strip())


def run_jira_flow(
    source_org: str,
    source_repo: str,
    jira_ticket: str,
    base: str,
    config: Config,
) -> None:
    """Sync base from source to fork, fetch Jira, implement with Cursor, open PR on target fork."""
    target_owner = config.repo_owner
    target_repo = f"{config.fork_prefix}{source_repo}"
    ticket = jira_ticket.strip()
    if not ticket:
        print("❌ Jira ticket id is empty")
        return

    repo_path = config.workdir / target_owner / target_repo
    git = GitRepo.ensure(
        f"https://github.com/{target_owner}/{target_repo}.git",
        repo_path,
    )
    github = GitHubApi(config.github_token)
    syncer = ForkSyncer(git, github, config)

    print()
    print("━" * 60)
    print(f"🎫 Jira flow: {ticket}")
    print(f"   Source: {source_org}/{source_repo}")
    print(f"   Target: {target_owner}/{target_repo}")
    print(f"   Base branch (from source): {base}")
    print("━" * 60)

    syncer.sync_branch_from_source(source_org, source_repo, base)

    print(f"\n📥 Fetching Jira issue via acli...")
    try:
        blob = fetch_ticket_blob(ticket)
    except Exception as e:
        print(f"❌ {e}", file=sys.stderr)
        raise

    print(blob[:500] + ("…" if len(blob) > 500 else ""))

    if _origin_has_branch(git, ticket):
        print(f"❌ Branch '{ticket}' already exists on origin. Remove it or use another ticket.")
        return

    print(f"\n🌿 Creating branch '{ticket}' from '{base}'...")
    git.checkout(ticket, create=True, start_point=base)

    initial_sha = git.head_sha()
    cursor = CursorRunner(config)

    prompt = f"""You are implementing a Jira-driven change in this repository.

Repository root: {git.path}

Ticket context:
{blob}

Implement the requested work in this codebase. Make focused, coherent edits.
You do not need to run tests unless the ticket explicitly requires it; CI may run later.
"""

    cursor.run_isolated(prompt, use_thinking=True, cwd=git.path)

    git.add_all()
    if git.has_staged_changes():
        git.commit(
            f"{ticket}: implement per Jira issue\n\n"
            f"Automated implementation via prbot jira."
        )
        print("   💾 Changes committed")
    else:
        print("   ℹ️ No staged changes to commit")

    final_sha = git.head_sha()
    if initial_sha == final_sha:
        print("   No changes made; skipping push and PR")
        return

    print(f"\n📤 Pushing {ticket}...")
    git.push("origin", ticket, force=False)

    existing = github.get_existing_pr(target_owner, target_repo, ticket, base)
    if existing:
        print(f"✅ PR already exists: #{existing}")
        print(f"🔗 https://github.com/{target_owner}/{target_repo}/pull/{existing}")
        return

    summary_line = next(
        (ln for ln in blob.splitlines() if ln.startswith("Summary: ")),
        "",
    )
    summary_text = summary_line.removeprefix("Summary: ").strip() or ticket
    title = f"{ticket}: {summary_text}"[:120]

    body = (
        f"Automated implementation for Jira issue `{ticket}`.\n\n"
        f"```\n{blob[:12000]}{'…' if len(blob) > 12000 else ''}\n```"
    )

    new_pr = github.create_pr(
        owner=target_owner,
        repo=target_repo,
        head=ticket,
        base=base,
        title=title,
        body=body,
    )
    print(f"✅ Created PR #{new_pr}")
    print(f"🔗 https://github.com/{target_owner}/{target_repo}/pull/{new_pr}")
