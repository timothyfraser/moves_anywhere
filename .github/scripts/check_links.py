"""Check that every relative link and #anchor in the repository's Markdown files resolves.

Usage: python -I .github/scripts/check_links.py   (run from the repository root)
Files: README.md, CHANGELOG.md, CONTRIBUTING.md and docs/**/*.md.
Anchors follow GitHub rules: lowercase, drop punctuation except hyphens and spaces, spaces to hyphens,
duplicates get -1, -2. http(s) and mailto links are skipped. Exit 1 if any link is broken.
"""
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path.cwd()
MD_LINK = re.compile(r"!?\[[^\]]*\]\(<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\)")
HTML_REF = re.compile(r"""(?:href|src)=["']([^"']+)["']""")
HEADING = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")


def strip_code(text):
    out, fence = [], False
    for line in text.splitlines():
        if line.strip().startswith(("```", "~~~")):
            fence = not fence
            out.append("")
            continue
        out.append("" if fence else re.sub(r"`[^`]*`", "", line))
    return out


def slug(title):
    t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", title)
    t = re.sub(r"<[^>]+>", "", t).replace("`", "").replace("*", "")
    t = t.strip().lower()
    t = re.sub(r"[^\w\- ]", "", t, flags=re.UNICODE)
    return t.replace(" ", "-")


_cache = {}


def anchors(path):
    if path in _cache:
        return _cache[path]
    seen, found, fence = {}, set(), False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip().startswith(("```", "~~~")):
            fence = not fence
            continue
        if fence:
            continue
        m = HEADING.match(line)
        if m:
            s = slug(m.group(2))
            n = seen.get(s, 0)
            seen[s] = n + 1
            found.add(s if n == 0 else f"{s}-{n}")
        for a in re.findall(r"""<a\s+[^>]*(?:id|name)=["']([^"']+)["']""", line):
            found.add(a)
    _cache[path] = found
    return found


def markdown_files():
    files = [ROOT / n for n in ("README.md", "CHANGELOG.md", "CONTRIBUTING.md")]
    files += sorted((ROOT / "docs").rglob("*.md"))
    return [f for f in files if f.is_file()]


def main():
    checked = 0
    broken = []
    for md in markdown_files():
        rel = md.relative_to(ROOT).as_posix()
        lines = strip_code(md.read_text(encoding="utf-8", errors="replace"))
        for n, line in enumerate(lines, 1):
            for t in MD_LINK.findall(line) + HTML_REF.findall(line):
                if re.match(r"^(https?:|mailto:|tel:|data:)", t, re.I) or t.startswith("//"):
                    continue
                checked += 1
                target, _, frag = t.partition("#")
                target = unquote(target)
                dest = md if target == "" else (md.parent / target).resolve()
                if target and not dest.exists():
                    broken.append(f"{rel}:{n}: {t} (file not found)")
                    continue
                if frag and dest.is_file() and dest.suffix.lower() == ".md":
                    if unquote(frag).lower() not in anchors(dest):
                        broken.append(f"{rel}:{n}: {t} (no such heading)")
    print(f"checked {checked}, broken {len(broken)}")
    for b in broken:
        print("  " + b)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
