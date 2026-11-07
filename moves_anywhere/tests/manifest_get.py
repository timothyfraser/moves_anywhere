# manifest_get.py #############################################################
#
# What:      manifest_get.py <manifest.json> <dotted.key | output:NAME>: prints the value (sha256 for output:NAME).
# Does:      Loads the manifest JSON and prints the value at the dotted key, or the named output's sha256.
# Called by: tests/test_pack.sh and tests/test_ticket_mode.sh. Not run by launch.sh.
# Reads:     the manifest JSON named in the first argument
# Writes:    stdout only
# Exits:     0, or 1 with a traceback if the file cannot be read
###############################################################################
import json, sys
m = json.load(open(sys.argv[1])); k = sys.argv[2]
if k.startswith("output:"):
    print(next((o["sha256"] for o in m["outputs"] if o["name"] == k[7:]), ""))
else:
    for part in k.split("."):
        m = m.get(part) if isinstance(m, dict) else None
    print(m)
