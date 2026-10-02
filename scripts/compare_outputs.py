"""Compare two Raven output directories.

Prints "<identical files>/<compared files> <max abs hydrograph difference>".
Lines carrying run timestamps are ignored so that identical simulations
compare as identical.
"""
import os
import re
import sys

test_dir, ref_dir = sys.argv[1], sys.argv[2]
skip = {"Raven_errors.txt", "stdout.txt"}
stamp = re.compile(r"(CreationDate|:Date|Simulation started|elapsed|Time:)", re.I)


def lines(path):
    with open(path, errors="replace") as fh:
        return [ln for ln in fh if not stamp.search(ln)]


files = sorted(f for f in os.listdir(test_dir)
               if f not in skip and os.path.exists(os.path.join(ref_dir, f)))
same, max_diff = 0, 0.0
for f in files:
    a, b = lines(os.path.join(test_dir, f)), lines(os.path.join(ref_dir, f))
    if a == b:
        same += 1
    if "Hydrographs" in f:
        if len(a) != len(b):
            max_diff = float("inf")
        for la, lb in zip(a, b):
            for x, y in zip(re.split(r"[,\s]+", la), re.split(r"[,\s]+", lb)):
                try:
                    max_diff = max(max_diff, abs(float(x) - float(y)))
                except ValueError:
                    pass
print(f"{same}/{len(files)} {max_diff:.3g}")
