#!/bin/sh
# SPDX-License-Identifier: GPL-2.0

set -eu

obj="${1:-/tmp/vmlinux_pre_btfids}"
nm_bin="${NM:-llvm-nm}"
bpftool_bin="${BPFTOOL:-bpftool}"

if [ ! -f "$obj" ]; then
	echo "missing input: $obj" >&2
	exit 1
fi

if ! command -v "$nm_bin" >/dev/null 2>&1; then
	echo "missing tool: $nm_bin" >&2
	exit 1
fi

if ! command -v "$bpftool_bin" >/dev/null 2>&1; then
	echo "missing tool: $bpftool_bin" >&2
	exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

"$nm_bin" "$obj" 2>/dev/null | awk '
function join_name(parts, start, end,    out, i) {
	out = parts[start]
	for (i = start + 1; i <= end; i++)
		out = out "__" parts[i]
	return out
}

/__BTF_ID__/ {
	name = $3
	sub(/^__BTF_ID__/, "", name)
	n = split(name, parts, /__/)
	kind = parts[1]

	if (kind == "set" || n < 3)
		next

	sym = join_name(parts, 2, n - 1)
	print kind "\t" sym
}
' | sort -u > "$tmpdir/requests"

"$bpftool_bin" btf dump file "$obj" format raw 2>/dev/null | awk '
match($0, /^\[[0-9]+\] (STRUCT|UNION|TYPEDEF|FUNC) '\''([^'\'']+)'\''/, m) {
	print tolower(m[1]) "\t" m[2]
}
' | sort -u > "$tmpdir/present"

comm -23 "$tmpdir/requests" "$tmpdir/present" > "$tmpdir/missing"

printf 'input: %s\n' "$obj"
printf 'requested ids: %s\n' "$(wc -l < "$tmpdir/requests" | tr -d ' ')"
printf 'present ids:   %s\n' "$(wc -l < "$tmpdir/present" | tr -d ' ')"
printf 'missing ids:   %s\n' "$(wc -l < "$tmpdir/missing" | tr -d ' ')"

if [ -s "$tmpdir/missing" ]; then
	printf '\nmissing:\n'
	cat "$tmpdir/missing"
fi