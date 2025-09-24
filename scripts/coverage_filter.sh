#!/usr/bin/env bash
set -euo pipefail

# Filter an lcov.info file produced by `forge coverage` so it only includes
# production Solidity contracts intended for audit. Excludes:
#  - forge script/ deployment files (they already appear as SF:script/...)
#  - mocks under src/mocks/
#  - experimental or test helper contracts under src/erc20/ (staking rewards etc.)
#  - MockAdapter (kept if you want to audit, default excluded here)
#  - any file whose basename starts with Mock (defensive)
#
# Usage:
#   scripts/coverage_filter.sh lcov.info lcov.prod.info
#
# The output maintains valid LCOV format so downstream tooling still works.

INPUT=${1:-lcov.info}
OUTPUT=${2:-lcov.prod.info}

if [[ ! -f "$INPUT" ]]; then
  echo "Input LCOV file not found: $INPUT" >&2
  exit 1
fi

# We treat each record as the text block ending with 'end_of_record'. Use awk record separator.
awk 'BEGIN{RS="end_of_record\n"; ORS="end_of_record\n"}
     {
       # quick skip if not a source file section
       if ($0 !~ /\nSF:/) next;
       # capture the SF line
       match($0, /SF:([^\n]+)/, m);
       sf=m[1];
       keep=1;
       # must live under src/
       if (sf !~ /^src\//) keep=0;
       # drop mocks & test helpers
       if (sf ~ /src\/mocks\//) keep=0;
       if (sf ~ /\/Mock[A-Za-z0-9_]*\.sol$/) keep=0; # any file ending with Mock*.sol
       if (sf ~ /src\/messaging\/MockAdapter\.sol$/) keep=0;
       if (sf ~ /src\/erc20\//) keep=0; # ancillary examples
       # (Optional) keep SuperchainAdapter, Hub, Router, SpokeVault, USDzy, policy/pps, zpx, gateway, factory, usdzy/*, messaging/* except MockAdapter
       if (keep==1) print $0;
     }' "$INPUT" > "$OUTPUT"

echo "Wrote filtered coverage to $OUTPUT"
