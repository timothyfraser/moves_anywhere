"""Fail on any prose paragraph over 400 characters in the given Markdown files.

Usage: python -I .github/scripts/check_paragraphs.py <file.md>...
Adapted from the CAT Platform contract tool for the MOVES Anywhere docs.
A paragraph is a run of consecutive non-blank lines that are not a table row,
list item, heading, HTML comment, HTML tag line (figure/img markup), front matter or inside a code fence.
"""
import re
import sys

LIMIT = 400
LIST = re.compile(r"^\s*([-*+]|\d+[.)])\s")


def paragraphs(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    i = 0
    if lines and lines[0].strip() == "---":
        i = 1
        while i < len(lines) and lines[i].strip() != "---":
            i += 1
        i += 1
    fence = False
    comment = False
    cur, start = [], 0

    def flush():
        nonlocal cur
        if cur:
            yield start, " ".join(s.strip() for s in cur)
        cur = []

    for n in range(i, len(lines)):
        s = lines[n]
        t = s.strip()
        if t.startswith("```") or t.startswith("~~~"):
            yield from flush()
            fence = not fence
            continue
        if fence:
            continue
        if comment:
            if "-->" in t:
                comment = False
            continue
        if t.startswith("<!--"):
            yield from flush()
            if "-->" not in t:
                comment = True
            continue
        if not t or t.startswith("|") or t.startswith("#") or t.startswith("<") or t.startswith("alt=") or t.startswith("alt =") or LIST.match(s):
            yield from flush()
            continue
        if not cur:
            start = n + 1
        cur.append(s)
    yield from flush()


def main(argv):
    if not argv:
        print("usage: check_paragraphs.py <file.md>...", file=sys.stderr)
        return 2
    bad = total = 0
    for path in argv:
        for line, text in paragraphs(path):
            total += 1
            if len(text) > LIMIT:
                bad += 1
                print(f"{path}:{line}: {len(text)} chars")
    if bad:
        return 1
    print(f"ok: {len(argv)} files, {total} paragraphs")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
