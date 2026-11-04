#!/bin/bash

# task_compress_outputs.sh

# Compress the run's outputs (data.csv.gz, moveslog.txt.gz, and the rate tables in rate mode).
# Keeps every original file. Safe to run twice (it overwrites).
# replication.tar.xz and run_manifest.json belong to task_pack.sh, not here.
# launch.sh runs this as a child process (never sourced), so it may exit normally.

echo ------------compressing outputs------------

cd "/cat" || { echo "Failed to change directory"; exit 1; }
IN="inputs"
rc=0

# Inventory mode writes data.csv; rate mode writes the rate tables instead.
for f in data.csv moveslog.txt rateperhour.csv ratepervehicle.csv rateperdistance.csv \
         rateperstart.csv startspervehicle.csv rateperprofile.csv movesrun.csv; do
  if [ -f "$IN/$f" ]; then
    gzip -c "$IN/$f" > "$IN/$f.gz.part" && mv -f "$IN/$f.gz.part" "$IN/$f.gz" \
      && echo "---compressed $f" || { echo "---gzip failed: $f"; rm -f "$IN/$f.gz.part"; rc=1; }
  fi
done
exit "$rc"
