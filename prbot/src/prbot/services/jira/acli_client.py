"""Fetch Jira issue text via Atlassian CLI (acli)."""

from __future__ import annotations

import json
import shutil
import subprocess

ACLI_AUTH_HINT = "Hint: run acli jira auth login --web"
ACLI_TIMEOUT_SEC = 120


class JiraFetchError(RuntimeError):
    """Raised when acli fails or returns unusable output."""


def _extract_json_object(stdout: str) -> str:
    s = stdout.strip()
    if not s:
        return s
    start = s.find("{")
    end = s.rfind("}")
    if start >= 0 and end > start:
        return s[start : end + 1]
    return s


def _adf_to_text(node: object) -> str:
    if node is None:
        return ""
    if isinstance(node, str):
        return node
    if isinstance(node, dict):
        if node.get("type") == "text":
            return str(node.get("text", ""))
        parts: list[str] = []
        for child in node.get("content") or []:
            parts.append(_adf_to_text(child))
        return "\n".join(p for p in parts if p) or ""
    if isinstance(node, list):
        return "\n".join(_adf_to_text(x) for x in node)
    return str(node)


def _description_to_text(desc: object) -> str:
    if desc is None:
        return ""
    if isinstance(desc, str):
        return desc.strip()
    if isinstance(desc, dict):
        return _adf_to_text(desc).strip()
    return str(desc).strip()


def _issue_dict(data: dict) -> dict:
    """Normalize acli / Jira-style JSON to a flat-ish dict with summary, description."""
    if "fields" in data and isinstance(data["fields"], dict):
        f = data["fields"]
        return {
            "key": data.get("key"),
            "summary": f.get("summary"),
            "description": f.get("description"),
            "status": (f.get("status") or {}).get("name") if isinstance(f.get("status"), dict) else f.get("status"),
            "issuetype": (f.get("issuetype") or {}).get("name") if isinstance(f.get("issuetype"), dict) else f.get("issuetype"),
        }
    return {
        "key": data.get("key"),
        "summary": data.get("summary"),
        "description": data.get("description"),
        "status": data.get("status"),
        "issuetype": data.get("issuetype"),
    }


def format_issue_blob(ticket_id: str, data: dict) -> str:
    """Render parsed issue JSON as one text blob for prompts."""
    norm = _issue_dict(data)
    key = norm.get("key") or ticket_id
    summary = norm.get("summary") or ""
    desc = _description_to_text(norm.get("description"))
    status = norm.get("status") or ""
    itype = norm.get("issuetype") or ""

    lines = [
        f"Jira issue: {key}",
        f"Summary: {summary}",
    ]
    if itype:
        lines.append(f"Type: {itype}")
    if status:
        lines.append(f"Status: {status}")
    lines.append("")
    lines.append("Description:")
    lines.append(desc if desc else "(empty)")
    return "\n".join(lines)


def fetch_ticket_blob(ticket_id: str) -> str:
    """Run `acli jira workitem view <ticket_id> --json` and return a plain-text blob."""
    tid = (ticket_id or "").strip()
    if not tid:
        raise JiraFetchError(f"Empty Jira ticket id\n{ACLI_AUTH_HINT}")

    acli = shutil.which("acli")
    if not acli:
        raise JiraFetchError(f"acli executable not found in PATH\n{ACLI_AUTH_HINT}")

    try:
        result = subprocess.run(
            [acli, "jira", "workitem", "view", tid, "--json"],
            capture_output=True,
            text=True,
            timeout=ACLI_TIMEOUT_SEC,
        )
    except subprocess.TimeoutExpired as e:
        raise JiraFetchError(
            f"acli timed out after {ACLI_TIMEOUT_SEC}s\n{ACLI_AUTH_HINT}"
        ) from e

    if result.returncode != 0:
        err = (result.stderr or "").strip() or (result.stdout or "").strip() or "(no output)"
        raise JiraFetchError(f"acli failed ({result.returncode}): {err}\n{ACLI_AUTH_HINT}")

    raw = _extract_json_object(result.stdout or "")
    if not raw:
        raise JiraFetchError(f"Empty output from acli\n{ACLI_AUTH_HINT}")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise JiraFetchError(
            f"Invalid JSON from acli: {e}\nStdout (truncated): {(result.stdout or '')[:500]}\n{ACLI_AUTH_HINT}"
        ) from e

    if not isinstance(data, dict):
        raise JiraFetchError(f"Expected JSON object from acli, got {type(data).__name__}\n{ACLI_AUTH_HINT}")

    return format_issue_blob(tid, data)
