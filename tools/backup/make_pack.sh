#!/usr/bin/env bash
# Builds the "resume pack" backup into $1 (default: a dated dir in $TMPDIR).
# Contents: repo state, incremental git bundle, project memory, file manifest.
# The agent session adds threads/PR summaries and README-RESTORE.md, then uploads.
set -euo pipefail
OUT="${1:-${TMPDIR:-/tmp}/ficb-$(date -u +%Y%m%d-%H%M)}"
SINCE="${2:-}"   # path to the previous backup repo-refs.txt (optional, for the incremental bundle)
REPO="${REPO:-$(git rev-parse --show-toplevel)}"
MEM="${MEM:-/tmp/claude/memory/team/silo}"
PF="${PF:-/mnt/project-files}"
mkdir -p "$OUT"
cd "$REPO"
git fetch -q origin '+refs/heads/*:refs/remotes/origin/*' || true
{ echo "# generated $(date -u +%FT%TZ)"; git for-each-ref --format='%(objectname) %(refname)' refs/remotes/origin; } > "$OUT/repo-refs.txt"
# SINCE = previous backup's repo-refs.txt: everything reachable from those SHAs is excluded,
# so the bundle holds only commits added since then (a single ^main exclude would drag in old unmerged branches).
# A refs file whose SHAs are all unknown here (rebased branches, another clone before fetch) must not pass as
# "nothing new": then the bundle is built without excludes, i.e. the full history (review 2026-10-30, R-04).
EXCL=()
KNOWN=0; LISTED=0
if [ -n "$SINCE" ] && [ -f "$SINCE" ]; then
  while read -r sha ref; do
    case "$sha" in \#*|"") continue;; esac
    LISTED=$((LISTED + 1))
    git cat-file -e "$sha^{commit}" 2>/dev/null && { EXCL+=("^$sha"); KNOWN=$((KNOWN + 1)); }
  done < "$SINCE"
  [ "$LISTED" -gt 0 ] && [ "$KNOWN" -eq 0 ] && echo "make_pack: none of the $LISTED refs in $SINCE exist here" >&2
fi
if [ "$KNOWN" -gt 0 ]; then
  # commits added since the previous pack, local branches included (unpushed work is what a backup is for)
  git bundle create "$OUT/repo-incremental.bundle" --branches --remotes "${EXCL[@]}" \
    || echo "no new commits since the refs in $SINCE" > "$OUT/repo-incremental.NONE"
else
  # no usable previous refs: GitHub already holds everything under origin/*, so bundle only what it lacks
  git bundle create "$OUT/repo-incremental.bundle" --branches --not --remotes=origin \
    || echo "no previous refs usable and no local-only commits: history lives on GitHub (kanta201196-hub/FlakHeaven, see repo-refs.txt)" > "$OUT/repo-incremental.NONE"
fi
# Too big to ship through the Drive/PC channels; GitHub already holds these commits.
if [ -f "$OUT/repo-incremental.bundle" ] && [ "$(stat -c %s "$OUT/repo-incremental.bundle")" -gt $(( ${MAX_BUNDLE_MB:-100} * 1048576 )) ]; then
  rm "$OUT/repo-incremental.bundle"; echo "incremental bundle over ${MAX_BUNDLE_MB:-100} MB skipped; commits are on GitHub (see repo-refs.txt)" > "$OUT/repo-incremental.NONE"
fi
git rev-parse origin/main > "$OUT/main-head.txt"
[ -d "$MEM" ] && tar czf "$OUT/project-memory.tgz" -C "$(dirname "$MEM")" "$(basename "$MEM")"
# manifest of the shared folder: size + mtime (hashes only for files < 5 MB to stay fast)
( cd "$PF" && find . -type f -not -path './uploads/*' -printf '%s\t%TY-%Tm-%Td\t%p\n' | sort -k3 ) > "$OUT/project-files-manifest.tsv" || true
du -sh "$OUT"/* | sed "s#$OUT/##"
echo "$OUT"
