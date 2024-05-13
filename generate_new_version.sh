#!/usr/bin/env bash

set -euo pipefail

[ -z "${1:-}" ] && echo "No release version provided. Aborting." && exit 1 || release=$1

# Images
for image in "simplerisk" "simplerisk-minimal"; do
	(cd $image && ./generate_dockerfile.pl "$release") # Run this on a subshell
done

# Stack
./update_stack.pl "$release"

# GitHub Action workflows
sed -i -r "s/(version:) \"[0-9]{8,}-[0-9]{3,}\"/\1 \"${release}\"/g" .github/workflows/push*
