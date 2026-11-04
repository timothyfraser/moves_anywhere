import json, sys
# manifest_get.py <manifest.json> <dotted.key | output:NAME>: prints the value (sha256 for output:NAME).
m = json.load(open(sys.argv[1])); k = sys.argv[2]
if k.startswith("output:"):
    print(next((o["sha256"] for o in m["outputs"] if o["name"] == k[7:]), ""))
else:
    for part in k.split("."):
        m = m.get(part) if isinstance(m, dict) else None
    print(m)
