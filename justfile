# Use with `just <task>`

set shell := ["bash", "-lc"]

status:
	# Build, run status, regenerate docs
	forge fmt
	forge build
	python3 scripts/vaults_dev_status.py

build:
	forge fmt
	forge build

gas:
	forge test -vv --gas-report

slither:
	slither .
