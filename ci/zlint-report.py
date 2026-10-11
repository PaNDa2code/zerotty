#!/usr/bin/env python3
"""Turn zlint JSON Lines output into a Markdown PR comment (Codeberg/Forgejo)."""
import json
import os
import sys
import urllib.request
from collections import defaultdict

MARKER = "<!-- zlint-report -->"  # identifies our comment so we can replace it
MAX_FINDINGS = 200                # keeps the comment under the size limit
LEVEL_ORDER = ["error", "warn", "notice"]
OPEN_LEVELS = {"error"}           # levels whose <details> start expanded

env = os.environ


def load_findings(path):
    findings = []
    try:
        with open(path) as f:
            for line in f:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue  # skip non-JSON lines
                if isinstance(d, dict) and "source_name" in d:
                    findings.append(d)
    except FileNotFoundError:
        pass
    return findings


def line_of(d):
    labels = d.get("labels") or []
    return labels[0]["start"]["line"] if labels else 1


def level_rank(level):
    return LEVEL_ORDER.index(level) if level in LEVEL_ORDER else len(LEVEL_ORDER)


def render_findings(findings, base_url):
    if not findings:
        if env.get("CI_PIPELINE_STATUS") == "failure":
            return "⚠️ zlint failed but produced no parsable findings. Check the pipeline log."
        return "No findings. ✅"

    findings.sort(key=lambda d: (level_rank(d["level"]), d["source_name"], line_of(d)))
    total = len(findings)
    hidden = max(0, total - MAX_FINDINGS)
    shown = findings[:MAX_FINDINGS]

    by_level = defaultdict(lambda: defaultdict(list))
    for d in shown:
        by_level[d["level"]][d["source_name"]].append(d)

    counts = defaultdict(int)
    for d in findings:
        counts[d["level"]] += 1
    summary = ", ".join(f"{n} {lvl}" for lvl, n in sorted(counts.items(), key=lambda x: level_rank(x[0])))

    out = [f"**{total} finding(s)**: {summary}", ""]

    for level, files in by_level.items():
        is_open = " open" if level in OPEN_LEVELS else ""
        out.append(f"<details{is_open}><summary><b>{level}</b> ({counts[level]})</summary>\n")
        for path, items in files.items():
            out.append(f"**`{path}`** ({len(items)})\n")
            for d in items:
                ln = line_of(d)
                link = f"{base_url}/{path}#L{ln}"
                out.append(f"- [L{ln}]({link}) `{d['code']}`: {d['message']}")
            out.append("")
        out.append("</details>\n")

    if hidden:
        out.append(f"_…and {hidden} more, see the pipeline log._\n")

    # one "how to fix" entry per rule instead of repeating it per finding
    helps = {(d["code"], d.get("help")) for d in findings if d.get("help")}
    if helps:
        out.append("<details><summary>How to fix</summary>\n")
        out.extend(f"- `{code}`: {text}" for code, text in sorted(helps))
        out.append("\n</details>")

    return "\n".join(out)


def build_comment(findings):
    base_url = f"{env['CI_FORGE_URL']}/{env['CI_REPO']}/src/commit/{env['CI_COMMIT_SHA']}"
    return "\n".join([
        MARKER,
        "### zlint report",
        f"Commit `{env['CI_COMMIT_SHA'][:8]}` by @{env['CI_COMMIT_AUTHOR']}",
        "",
        render_findings(findings, base_url),
        "",
        f"[Pipeline #{env['CI_PIPELINE_NUMBER']}]({env['CI_PIPELINE_URL']})",
    ])


def api(method, path, payload=None):
    url = f"{env['CI_FORGE_URL']}/api/v1/repos/{env['CI_REPO']}{path}"
    req = urllib.request.Request(
        url,
        method=method,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={
            "Authorization": f"token {env['BOT_TOKEN']}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
        return json.loads(body) if body else None


def post_comment(body):
    pr = env["CI_COMMIT_PULL_REQUEST"]
    # delete our previous report(s), then post a fresh one (a new comment notifies people)
    for c in api("GET", f"/issues/{pr}/comments?limit=100") or []:
        if MARKER in c.get("body", ""):
            try:
                api("DELETE", f"/issues/comments/{c['id']}")
            except Exception as e:
                print(f"could not delete comment {c['id']}: {e}", file=sys.stderr)
    api("POST", f"/issues/{pr}/comments", {"body": body})


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "lint.json"
    comment = build_comment(load_findings(path))

    if not env.get("BOT_TOKEN"):
        print("No BOT_TOKEN (fork PR or local run); printing instead of posting:\n")
        print(comment)
        return

    post_comment(comment)
    print("Comment posted.")


if __name__ == "__main__":
    main()
