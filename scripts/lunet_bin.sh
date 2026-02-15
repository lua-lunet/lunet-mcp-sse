#!/usr/bin/env bash
set -euo pipefail

LUNET_DIR="${LUNET_DIR:-../lunet}"
LUNET_REF="${LUNET_REF:-codex/httpc-libcurl}"
DO_BUILD=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--build)
		DO_BUILD=1
		shift
		;;
	*)
		echo "Unknown argument: $1" >&2
		exit 2
		;;
	esac
done

if [[ ! -d "$LUNET_DIR/.git" ]]; then
	echo "ERROR: lunet repo not found at $LUNET_DIR" >&2
	echo "Clone it first: git clone https://github.com/lua-lunet/lunet.git $LUNET_DIR" >&2
	exit 1
fi

if ! git -C "$LUNET_DIR" rev-parse "$LUNET_REF" >/dev/null 2>&1; then
	echo "ERROR: required lunet ref $LUNET_REF not found in $LUNET_DIR" >&2
	echo "Run: git -C \"$LUNET_DIR\" fetch --all --tags" >&2
	exit 1
fi

if ! git -C "$LUNET_DIR" merge-base --is-ancestor "$LUNET_REF" HEAD; then
	echo "ERROR: lunet checkout does not include required ref $LUNET_REF in $LUNET_DIR" >&2
	echo "Run: git -C \"$LUNET_DIR\" checkout $LUNET_REF && git -C \"$LUNET_DIR\" pull --ff-only" >&2
	exit 1
fi

find_runner() {
	find "$LUNET_DIR/build" -path '*/release/lunet-run' -type f 2>/dev/null | head -1
}

RUNNER_BIN="$(find_runner)"
if [[ -z "$RUNNER_BIN" && "$DO_BUILD" -eq 1 ]]; then
	(
		cd "$LUNET_DIR"
		xmake f -m release --lunet_trace=n --lunet_verbose_trace=n -y
		xmake build lunet-bin
	)
	RUNNER_BIN="$(find_runner)"
fi

if [[ -z "$RUNNER_BIN" ]]; then
	echo "ERROR: lunet-run not found under $LUNET_DIR/build" >&2
	echo "Run: (cd \"$LUNET_DIR\" && xmake f -m release --lunet_trace=n --lunet_verbose_trace=n -y && xmake build lunet-bin)" >&2
	exit 1
fi

echo "$RUNNER_BIN"
