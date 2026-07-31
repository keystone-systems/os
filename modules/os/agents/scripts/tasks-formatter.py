#!/usr/bin/env python3
# agentctl tasks formatter: renders TASKS.yaml as a sorted, columnar table.
# Extracted from agentctl.nix for independent linting and testing.
import sys
import re
from datetime import datetime

lines = sys.stdin.read()

tasks = []
current = {}
in_tasks = False
for line in lines.splitlines():
    if line.strip() == "tasks:":
        in_tasks = True
        continue
    if not in_tasks:
        continue
    m = re.match(r"^\s+-\s+([\w_]+):\s*(.*)", line)
    if m:
        if current:
            tasks.append(current)
        current = {m.group(1): m.group(2).strip().strip('"').strip("'")}
        continue
    m = re.match(r"^\s+([\w_]+):\s*(.*)", line)
    if m:
        current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
if current:
    tasks.append(current)

if not tasks:
    print("No tasks found.")
    sys.exit(0)

# Active tasks first, then completed in reverse order (latest first)
order = {"in_progress": 0, "pending": 1, "blocked": 2, "error": 3, "completed": 4}
for i, t in enumerate(tasks):
    t["_orig_idx"] = i
tasks.sort(key=lambda t: (order.get(t.get("status", ""), 5), -t["_orig_idx"]))

icons = {"completed": "done", "in_progress": "run ", "pending": "wait", "blocked": "blkd", "error": "err "}


def parse_ts(s):
    if not s or s in ("-", "null", ""):
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def fmt_date(s):
    ts = parse_ts(s)
    if not ts:
        return "-"
    return ts.strftime("%b %d %H:%M")


def fmt_duration(started, completed):
    ts_start = parse_ts(started)
    ts_end = parse_ts(completed)
    if not ts_start or not ts_end:
        return "-"
    secs = int((ts_end - ts_start).total_seconds())
    if secs < 0:
        return "-"
    if secs < 60:
        return str(secs) + "s"
    mins = secs // 60
    if mins < 60:
        return str(mins) + "m"
    hours = mins // 60
    rem = mins % 60
    return str(hours) + "h" + (str(rem) + "m" if rem else "")


def get_date(t):
    status = t.get("status", "")
    if status == "completed":
        return fmt_date(t.get("completed_at", ""))
    elif status == "in_progress":
        return fmt_date(t.get("started_at", ""))
    else:
        return fmt_date(t.get("created_at", ""))


def get_workflow(t):
    w = t.get("workflow", "")
    if not w or w in ("null", ""):
        return "-"
    return w[:20]


hdr = ["#", "STATUS", "NAME", "PROJECT", "SOURCE", "MODEL", "DATE", "WORKFLOW", "DUR", "DESCRIPTION"]
rows = []
for i, t in enumerate(tasks):
    rows.append([
        str(i + 1),
        icons.get(t.get("status", ""), t.get("status", "")[:4]),
        t.get("name", "")[:30],
        t.get("project", "-")[:15],
        t.get("source", "-")[:10],
        t.get("model", "-")[:6],
        get_date(t),
        get_workflow(t),
        fmt_duration(t.get("started_at", ""), t.get("completed_at", "")),
        t.get("description", "")[:50],
    ])

widths = [len(h) for h in hdr]
for row in rows:
    for j, cell in enumerate(row):
        widths[j] = max(widths[j], len(cell))


def fmt(row):
    return "  ".join(cell.ljust(widths[j]) for j, cell in enumerate(row))


print(fmt(hdr))
print("  ".join("-" * w for w in widths))
for row in rows:
    print(fmt(row))

counts = {}
for t in tasks:
    s = t.get("status", "unknown")
    counts[s] = counts.get(s, 0) + 1

parts = []
for status, label in [("in_progress", "running"), ("pending", "pending"),
                       ("blocked", "blocked"), ("error", "errored"), ("completed", "done")]:
    if counts.get(status, 0) > 0:
        parts.append(str(counts[status]) + " " + label)
if parts:
    print("")
    print("  " + ", ".join(parts))
