#!/usr/bin/env python3
"""Summarize LCOV line coverage (lines & branches optional) for a given file.

Usage:
  python scripts/coverage_summary.py lcov.prod.info
"""
import sys, re

path = sys.argv[1] if len(sys.argv) > 1 else 'lcov.prod.info'
try:
    data = open(path, 'r', encoding='utf-8').read().splitlines()
except FileNotFoundError:
    print(f"File not found: {path}", file=sys.stderr)
    sys.exit(1)

total_lf = total_lh = 0
files = []  # (sf, lh, lf)
sf = None
lh = lf = 0
for line in data:
    if line.startswith('SF:'):
        sf = line[3:]
        lh = lf = 0
    elif line.startswith('LF:'):
        lf = int(line[3:])
    elif line.startswith('LH:'):
        lh = int(line[3:])
    elif line == 'end_of_record':
        if sf and lf > 0:
            total_lf += lf
            total_lh += lh
            files.append((sf, lh, lf))
        sf = None

def pct(a,b):
    return 0.0 if b==0 else (100.0*a/b)

print("Prod Coverage Summary (line-level):")
print(f" Total: {pct(total_lh,total_lf):.2f}% ({total_lh}/{total_lf}) across {len(files)} files\n")
print(" Per-file (sorted ascending):")
for sf, lh, lf in sorted(files, key=lambda x: pct(x[1], x[2])):
    print(f"  {pct(lh,lf):5.2f}%  {lh:4d}/{lf:<4d}  {sf}")

low = [f for f in files if pct(f[1], f[2]) < 85.0]
print("\n Files <85%:")
for sf, lh, lf in low:
    print(f"  - {sf} ({pct(lh,lf):.2f}%)")

if len(low)==0:
    print("\nAll production files meet the 85% threshold.")
