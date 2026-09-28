#!/usr/bin/env python3
"""THROWAWAY: QuantEcon/actions#143 spike. The draft-PR run.

Asserts the LOCAL preview actions' comment steps ran in THIS run. Each preview
action keeps one marker comment on the PR, rewrites it on every deploy, and
links the workflow run that wrote it in its Build Info, so a comment that
does not link this run was written by an earlier run, not this one.

env: GH_TOKEN, GITHUB_API_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID, PR,
     MARKERS ('|'-separated marker headings to require)
"""
import json
import os
import sys
import urllib.request

api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
repo = os.environ["GITHUB_REPOSITORY"]
run = os.environ["GITHUB_RUN_ID"]
pr = os.environ["PR"]
markers = [m for m in os.environ.get("MARKERS", "").split("|") if m]
summary_path = os.environ.get("GITHUB_STEP_SUMMARY")

if not markers:
    print("::error title=PR comments::no markers to check (MARKERS is empty)")
    sys.exit(1)

req = urllib.request.Request(
    f"{api}/repos/{repo}/issues/{pr}/comments?per_page=100",
    headers={
        "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
        "Accept": "application/vnd.github+json",
    },
)
with urllib.request.urlopen(req, timeout=30) as resp:
    comments = json.load(resp)

rows = ["### PR comments written by the local preview actions", "| marker | result |", "|---|---|"]
fails = 0
for marker in markers:
    hits = [c for c in comments if marker in (c.get("body") or "")]
    this_run = [c for c in hits if f"/actions/runs/{run}" in c["body"]]
    if not hits:
        print(f"::error title=PR comments::no comment containing '{marker}' on PR #{pr}")
        rows.append(f"| {marker} | **missing** |")
        fails += 1
    elif not this_run:
        print(f"::error title=PR comments::the '{marker}' comment does not link run {run}, so the comment step did not run in this run")
        rows.append(f"| {marker} | **stale** (does not link run {run}) |")
        fails += 1
    else:
        print(f"ok: '{marker}' -> {this_run[0]['html_url']}")
        rows.append(f"| {marker} | {this_run[0]['html_url']} |")

if summary_path:
    with open(summary_path, "a", encoding="utf-8") as fh:
        fh.write("\n".join(rows) + "\n")
sys.exit(1 if fails else 0)
