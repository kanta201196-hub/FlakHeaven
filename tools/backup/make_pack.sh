#!/usr/bin/env bash
# Builds the "resume pack" backup into $1 (default: a dated dir in $TMPDIR).
# Contents: repo state, incremental git bundle, project memory, file manifest.
# The agent session adds threads/PR summaries and README-RESTORE.md, then uploads.
set -euo pipefail
OUT="${1:-${TMPDIR:-/tmp}/ficb-$(date -u +%Y%m%d-%H%M)}"
SINCE="${2:-}"   # commit SHA of the previous backup HEAD (optional, for the incremental bundle)
REPO="${REPO:-$(git rev-parse --show-toplevel)}"
MEM="${MEM:-/tmp/claude/memory/team/silo}"
PF="${PF:-/mnt/project-files}"
mkdir -p "$OUT"
cd "$REPO"
git fetch -q origin '+refs/heads/*:refs/remotes/origin/*' || true
{ echo "# generated $(date -u +%FT%TZ)"; git for-each-ref --format='%(objectname) %(refname)' refs/remotes/origin; } > "$OUT/repo-refs.txt"
if [ -n "$SINCE" ] && git cat-file -e "$SINCE^{commit}" 2>/dev/null; then
  git bundle create "$OUT/repo-incremental.bundle" --branches --remotes "^$SINCE" 2>/dev/null || echo "no new commits" > "$OUT/repo-incremental.NONE"
else
  echo "no base SHA given: full history lives on GitHub (kanta201196-hub/FlakHeaven); only refs recorded" > "$OUT/repo-incremental.NONE"
fi
git rev-parse origin/main > "$OUT/main-head.txt"
[ -d "$MEM" ] && tar czf "$OUT/project-memory.tgz" -C "$(dirname "$MEM")" "$(basename "$MEM")"
# manifest of the shared folder: size + mtime (hashes only for files < 5 MB to stay fast)
( cd "$PF" && find . -type f -not -path './uploads/*' -printf '%s\t%TY-%Tm-%Td\t%p\n' | sort -k3 ) > "$OUT/project-files-manifest.tsv" || true
du -sh "$OUT"/* | sed "s#$OUT/##"
echo "$OUT"
