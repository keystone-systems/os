#!/usr/bin/env python3
"""Find likely missing project tags by searching note content for project names."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

GENERIC_TAGS = {
    "index",
    "indexes",
    "project",
    "projects",
    "note",
    "notes",
    "report",
    "reports",
    "literature",
    "research",
}
DEFAULT_DIRS = ("notes", "literature", "reports", "index", "spikes")


@dataclass
class Project:
    slug: str
    aliases: list[str]


def parse_frontmatter(path: Path) -> tuple[dict[str, object], str]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
      return {}, text
    parts = text.split("\n---\n", 1)
    if len(parts) != 2:
      return {}, text
    raw, body = parts
    lines = raw.splitlines()[1:]
    data: dict[str, object] = {}
    i = 0
    while i < len(lines):
      line = lines[i]
      if not line or line.startswith("#"):
        i += 1
        continue
      if line.startswith("tags:"):
        raw_tags = line.split(":", 1)[1].strip()
        tags: list[str] = []
        if raw_tags.startswith("[") and raw_tags.endswith("]"):
          tags = [item.strip().strip("\"'") for item in raw_tags[1:-1].split(",") if item.strip()]
          i += 1
        else:
          i += 1
          while i < len(lines) and lines[i].startswith("  - "):
            tags.append(lines[i][4:].strip().strip("\"'"))
            i += 1
        data["tags"] = tags
        continue
      if line.startswith("subprojects:"):
        subprojects: list[str] = []
        i += 1
        while i < len(lines) and lines[i].startswith("  - "):
          subprojects.append(lines[i][4:].strip().strip("\"'"))
          i += 1
        data["subprojects"] = subprojects
        continue
      if ":" in line:
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip("\"'")
      i += 1
    return data, body


def derive_projects(index_dir: Path) -> list[Project]:
    projects: dict[str, set[str]] = {}
    for path in sorted(index_dir.glob("*.md")):
      frontmatter, _body = parse_frontmatter(path)
      tags = [str(tag) for tag in frontmatter.get("tags", [])]
      if "project" not in tags and not any(tag.startswith("project/") for tag in tags):
        continue
      slug_tags = []
      for tag in tags:
        if tag in GENERIC_TAGS:
          continue
        if tag.startswith("project/"):
          slug_tags.append(tag.split("/", 1)[1])
        else:
          slug_tags.append(tag)
      title = str(frontmatter.get("title", "")).strip()
      title_slug = slugify(title) if title else ""
      slug = slug_tags[0] if slug_tags else title_slug
      if not slug:
        continue
      aliases = projects.setdefault(slug, set())
      aliases.add(slug)
      aliases.add(slug.replace("-", " "))
      if title:
        aliases.add(title)
        aliases.add(title.replace("-", " "))
      for subproject in frontmatter.get("subprojects", []):
        sub = str(subproject).strip()
        if sub:
          aliases.add(sub)
          aliases.add(sub.replace("-", " "))
    return [Project(slug=slug, aliases=sorted(clean_aliases(values))) for slug, values in sorted(projects.items())]


def clean_aliases(values: set[str]) -> set[str]:
    cleaned = set()
    for value in values:
      alias = " ".join(value.split()).strip()
      if len(alias) < 3:
        continue
      cleaned.add(alias)
    return cleaned


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def find_matches(repo: Path, project: Project, search_dirs: list[str]) -> list[Path]:
    dirs = [str(repo / dirname) for dirname in search_dirs if (repo / dirname).exists()]
    if not dirs or not project.aliases:
      return []
    alias_patterns = sorted(project.aliases, key=len, reverse=True)
    pattern = r"(?i)\\b(" + "|".join(re.escape(alias) for alias in alias_patterns) + r")\\b"
    cmd = ["rg", "-l", "-g", "*.md", "-e", pattern, *dirs]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode not in (0, 1):
      raise RuntimeError(result.stderr.strip() or "rg failed")
    paths = []
    for raw in result.stdout.splitlines():
      path = Path(raw)
      if path.match("*/prototype/*.md"):
        continue
      if path.parts and "spikes" in path.parts and path.name != "README.md":
        continue
      paths.append(path)
    return sorted(set(paths))


def has_project_tag(path: Path, slug: str) -> bool:
    frontmatter, _body = parse_frontmatter(path)
    tags = {str(tag) for tag in frontmatter.get("tags", [])}
    return slug in tags or f"project/{slug}" in tags


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", help="Path to the notes repository")
    parser.add_argument("--dirs", nargs="+", default=list(DEFAULT_DIRS), help="Directories to search")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    index_dir = repo / "index"
    if not index_dir.exists():
      print("No index/ directory found.", file=sys.stderr)
      return 1

    projects = derive_projects(index_dir)
    if not projects:
      print("No project hubs found in index/.", file=sys.stderr)
      return 1

    findings: list[tuple[str, Path]] = []
    for project in projects:
      for path in find_matches(repo, project, args.dirs):
        rel = path.relative_to(repo)
        if rel.parts[:1] == ("index",) and path.name != "README.md" and has_project_tag(path, project.slug):
          continue
        if not has_project_tag(path, project.slug):
          findings.append((project.slug, rel))

    print("# Missing project tags")
    print()
    if not findings:
      print("No likely missing project tags found.")
      return 0

    grouped: dict[str, list[Path]] = {}
    for slug, rel in findings:
      grouped.setdefault(slug, []).append(rel)

    for slug, paths in sorted(grouped.items()):
      print(f"## {slug}")
      for rel in sorted(set(paths)):
        print(f"- {rel}")
      print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
