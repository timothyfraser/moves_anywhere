#!/bin/bash

# task_compress_outputs.sh

# Compress the run's outputs into the objects named in docs/RUN_TICKET.md section 2.
# Keeps every original file. Safe to run twice (it overwrites).

echo ------------compressing outputs------------

cd "/cat" || { echo "Failed to change directory"; exit 1; }
IN="inputs"

# Inventory mode writes data.csv; rate mode writes the rate tables instead.
for f in data.csv moveslog.txt rateperhour.csv ratepervehicle.csv rateperdistance.csv \
         rateperstart.csv startspervehicle.csv rateperprofile.csv movesrun.csv; do
  if [ -f "$IN/$f" ]; then
    gzip -c "$IN/$f" > "$IN/$f.gz.part" && mv -f "$IN/$f.gz.part" "$IN/$f.gz" \
      && echo "---compressed $f" || { echo "---gzip failed: $f"; rm -f "$IN/$f.gz.part"; }
  fi
done

# Replication kit: everything in inputs/ except the objects pushed on their own.
# The uncompressed twins of the pushed .gz files are left out too (no duplicates).
mkdir -p /cat/run
KIT="/cat/run/replication.tar.xz"
rm -f "$KIT"
tar -C "$IN" -cJf "$KIT" \
  --exclude='*.part' \
  --exclude=data.csv --exclude=data.csv.gz \
  --exclude=moveslog.txt --exclude=moveslog.txt.gz \
  --exclude=replication.tar.xz --exclude=run_manifest.json \
  . && mv -f "$KIT" "$IN/replication.tar.xz" \
  && echo "---wrote replication.tar.xz" || { echo "---kit failed"; rm -f "$KIT"; }
exit 0
