#!/usr/bin/env python3
"""Compare a run_manifest.json with the fields documented in docs/RUN_MANIFEST.md.

Usage: python3 -I tests/manifest_fields_check.py <run_manifest.json> [docs/RUN_MANIFEST.md]

The documented field set comes from two places in the doc: the section 3 table
(top-level fields) and the JSON Schema block in section 4 (nested fields, required
list, additionalProperties). Reports undocumented fields, missing required fields,
and top-level fields in the table that the schema lacks (or the reverse).
Exit 0 when clean, 1 otherwise. Standard library only.
"""
import json, os, re, sys


def schema_paths(node, prefix=""):
    """Yield (path, required) for every property in a draft-07 schema node."""
    out = {}
    node = dict(node)
    if "$ref" in node:
        return out
    req = set(node.get("required", []))
    for key, sub in node.get("properties", {}).items():
        p = prefix + key
        out[p] = key in req
        sub = sub.get("items", sub) if sub.get("type") == "array" else sub
        if "$ref" in sub:
            sub = {"properties": {k: v for k, v in
                                  DEFS[sub["$ref"].split("/")[-1]]["properties"].items()},
                   "required": DEFS[sub["$ref"].split("/")[-1]].get("required", [])}
            p2 = p + "[]."
        else:
            p2 = p + "."
        out.update(schema_paths(sub, p2))
    return out


def manifest_paths(obj, prefix=""):
    out = set()
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = prefix + k
            out.add(p)
            if isinstance(v, dict):
                out |= manifest_paths(v, p + ".")
            elif isinstance(v, list) and v and isinstance(v[0], dict):
                for item in v:
                    out |= manifest_paths(item, p + "[].")
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    mpath = sys.argv[1]
    dpath = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "docs", "RUN_MANIFEST.md")
    doc = open(dpath, encoding="utf-8").read()
    manifest = json.load(open(mpath, encoding="utf-8"))

    m = re.search(r"```json\n(\{\s*\"\$schema\".*?\n\})\n```", doc, re.S)
    if not m:
        print("FAIL: no JSON Schema block found in", dpath)
        return 1
    schema = json.loads(m.group(1))
    global DEFS
    DEFS = schema.get("definitions", {})
    sp = schema_paths(schema)

    # section 3 table: top-level field names in backticks in the first column
    sec = doc.split("### 3. Fields")[1].split("### 4.")[0]
    table = set()
    for line in sec.splitlines():
        if line.startswith("| `"):
            table |= set(re.findall(r"`([a-z_]+)`", line.split("|")[1]))

    mp = manifest_paths(manifest)
    problems = []
    # a nested path only counts when its parent is an object in the manifest
    for p in sorted(mp):
        if p not in sp:
            problems.append("UNDOCUMENTED in manifest: " + p)
    for p, required in sorted(sp.items()):
        parent = p.rsplit(".", 1)[0] if "." in p else None
        if p in mp:
            continue
        top = p.split(".")[0].replace("[]", "")
        if "." in p:
            # nested field: only required if the parent exists and is non-null
            par = parent.replace("[]", "")
            if parent not in mp or not isinstance(_get(manifest, par), (dict, list)):
                continue
        if required:
            problems.append("MISSING required field: " + p)
    for t in sorted(table - {k.split(".")[0].replace("[]", "") for k in sp}):
        problems.append("in section 3 table but not in schema: " + t)
    for t in sorted({k for k in sp if "." not in k} - table):
        problems.append("in schema but not in section 3 table: " + t)
    if manifest.get("manifest_version") != 1:
        problems.append("manifest_version is not 1: %r" % manifest.get("manifest_version"))

    print("manifest:", mpath)
    print("documented top-level fields: %d; manifest top-level fields: %d" % (
        len({k for k in sp if '.' not in k}), len(manifest)))
    if problems:
        for pr in problems:
            print(pr)
        print("FAIL: %d problem(s)" % len(problems))
        return 1
    print("PASS: no undocumented or missing fields")
    return 0


def _get(obj, dotted):
    for part in dotted.split("."):
        if isinstance(obj, list):
            obj = obj[0] if obj else {}
        if not isinstance(obj, dict):
            return None
        obj = obj.get(part)
    return obj


if __name__ == "__main__":
    sys.exit(main())
