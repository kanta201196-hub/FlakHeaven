#!/usr/bin/env bash
## Daily full project backup to Yandex Disk: disk:/FlakHeaven backup/<YYYY-MM-DD MSK>/.
## Why: Kanta asked (2026-11-06) for one dated folder per day holding everything needed to
## resume the project without GitHub or the shared folder: all git branches, a browsable code
## snapshot, models/docs/source assets from /mnt/project-files, project memory and instructions.
## Builds, marketing videos and older backups are left out (rebuildable or kept elsewhere).
## Auth: the environment's network secret injects `Authorization: OAuth <token>` for
## cloud-api.yandex.net; this script sends a dummy header and never sees the token.
## Big files are split into PART_SIZE pieces: the cloud egress tunnel drops single uploads
## after ~90 MB / ~60 s, while 40 MB pieces go through at ~7 MB/s.
## Exits early if the day's folder already has SHA256SUMS.txt. After a verified run, dated folders
## older than KEEP_DAYS (default 14, Kanta 2026-11-06) go to the Disk trash; nothing else is touched.
## Usage: tools/backup/yadisk_daily.sh [work_dir]   (needs ~13 GB free in work_dir)
set -euo pipefail

DAY="$(TZ=Europe/Moscow date +%F)"
WORK="${1:-${TMPDIR:-/tmp}/yadisk-backup}/$DAY"
REPO="${REPO:-$(git rev-parse --show-toplevel)}"
MEM="${MEM:-/tmp/claude/memory/team/silo}"
PF="${PF:-/mnt/project-files}"
ROOT="${YADISK_ROOT:-disk:/FlakHeaven backup}"
DEST="$ROOT/$DAY"
PART_SIZE="${PART_SIZE:-40M}"
JOBS="${JOBS:-4}"
export API="https://cloud-api.yandex.net/v1/disk"
export AUTH="Authorization: OAuth proxy-injects-real-token"
export WORK DEST

## urlencode: percent-encodes a Disk path for a query string.
urlencode() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

## upload_one: uploads $WORK/$1 to $DEST/$1, asking for a fresh upload URL on every try.
upload_one() {
  local f="$1" try href p
  p=$(urlencode "$DEST/$f")
  for try in 1 2 3 4 5; do
    href=$(curl -sS -f -H "$AUTH" "$API/resources/upload?overwrite=true&path=$p" 2>/dev/null \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["href"])' 2>/dev/null) || href=""
    if [ -n "$href" ] && curl -sS -f -T "$WORK/$f" "$href" -o /dev/null 2>/dev/null; then
      echo "uploaded $f"; return 0
    fi
    sleep $((2 ** try))
  done
  echo "UPLOAD FAILED $f" >&2; return 1
}

## verify_one: compares size and sha256 the Disk reports with the local file.
verify_one() {
  local f="$1" p meta try rs rh ls lh
  p=$(urlencode "$DEST/$f")
  for try in 1 2 3 4 5 6 7 8; do   # the Disk fills in sha256 a little after the upload
    meta=$(curl -sS -f -H "$AUTH" "$API/resources?fields=size,sha256&path=$p" 2>/dev/null) || meta=""
    echo "$meta" | grep -q '"sha256"' && break; sleep 5
  done
  rs=$(echo "$meta" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("size",""))' 2>/dev/null || true)
  rh=$(echo "$meta" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("sha256",""))' 2>/dev/null || true)
  ls=$(stat -c %s "$WORK/$f"); lh=$(sha256sum "$WORK/$f" | cut -d' ' -f1)
  if [ "$rs" = "$ls" ] && [ "$rh" = "$lh" ]; then echo "OK $f"; else echo "MISMATCH $f local=$ls remote=$rs" >&2; return 1; fi
}
export -f urlencode upload_one verify_one

if curl -sS -f -o /dev/null -H "$AUTH" "$API/resources?path=$(urlencode "$DEST/SHA256SUMS.txt")" 2>/dev/null; then
  echo "yadisk: $DEST already complete, nothing to do"; exit 0
fi

echo "== 1/4 build pack in $WORK"
mkdir -p "$WORK"; rm -rf "${WORK:?}"/*
cd "$REPO"
git fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
git bundle create "$WORK/repo-all-branches.bundle" --remotes 2>/dev/null
git bundle verify -q "$WORK/repo-all-branches.bundle" >/dev/null
git archive --format=tar.gz --prefix=FlakHeaven-main/ -o "$WORK/code-main-snapshot.tar.gz" origin/main
git rev-parse origin/main > "$WORK/main-head.txt"
git for-each-ref --format='%(objectname) %(refname)' refs/remotes/origin > "$WORK/repo-refs.txt"

INSTR="$(mktemp -d)"
git show origin/main:CLAUDE.md > "$INSTR/CLAUDE.md"
git archive origin/main .claude | tar -x -C "$INSTR" 2>/dev/null || true
[ -d "$MEM" ] && cp -r "$MEM" "$INSTR/project-memory"
cp "$PF"/process/project-instructions* "$INSTR/" 2>/dev/null || true
tar czf "$WORK/instructions-and-memory.tar.gz" -C "$INSTR" .
rm -rf "$INSTR"

# Shared folder minus builds, marketing, older backups and root-level screen recordings/old rar protos.
tar -cf "$WORK/project-files.tar" -C "$PF" --no-wildcards-match-slash \
  --exclude=./builds --exclude=./marketing --exclude=./backups \
  --exclude='./*.mp4' --exclude='./*.rar' . 2>/dev/null || [ -s "$WORK/project-files.tar" ]

# Whole-file sums (to check after joining), then split everything larger than one part.
( cd "$WORK" && sha256sum -- repo-all-branches.bundle code-main-snapshot.tar.gz project-files.tar > WHOLE_FILES_SHA256.txt )
for big in repo-all-branches.bundle code-main-snapshot.tar.gz project-files.tar; do
  split -b "$PART_SIZE" -d -a 3 "$WORK/$big" "$WORK/$big.part" && rm "$WORK/$big"
done
cat > "$WORK/README_RU.txt" <<EOF
Бэкап Flak Heaven за $DAY (собран $(date -u +%FT%TZ)), main = $(cut -c1-12 "$WORK/main-head.txt").

Большие файлы порезаны на куски по $PART_SIZE (.part000, .part001, ...). Сначала склеить:
  Windows (cmd в этой папке):  copy /b repo-all-branches.bundle.part* repo-all-branches.bundle
  Linux/Mac:                   cat repo-all-branches.bundle.part* > repo-all-branches.bundle
(так же для code-main-snapshot.tar.gz и project-files.tar). Проверка склейки: WHOLE_FILES_SHA256.txt.

repo-all-branches.bundle   — весь git: все ветки и история.  git clone repo-all-branches.bundle FlakHeaven
code-main-snapshot.tar.gz  — код и ассеты игры (ветка main), просто распаковать (7-Zip).
project-files.tar          — общая папка проекта: модели (models_src, blend), документы, визуал, загрузки.
                             Без сборок, маркетинга и старых бэкапов.
instructions-and-memory.tar.gz — CLAUDE.md, навыки .claude, память проекта, полные инструкции проекта.
SHA256SUMS.txt             — суммы всех файлов этой папки (sha256sum -c SHA256SUMS.txt).
EOF
( cd "$WORK" && sha256sum -- * > SHA256SUMS.txt )
echo "files: $(ls "$WORK" | wc -l), total: $(du -sh "$WORK" | cut -f1)"

echo "== 2/4 create $DEST"
curl -sS -o /dev/null -X PUT -H "$AUTH" "$API/resources?path=$(urlencode "$ROOT")"
curl -sS -o /dev/null -X PUT -H "$AUTH" "$API/resources?path=$(urlencode "$DEST")"

echo "== 3/4 upload ($JOBS at a time)"
# SHA256SUMS.txt goes last: its presence marks the day as complete.
( cd "$WORK" && ls | grep -vx SHA256SUMS.txt ) | xargs -P "$JOBS" -I{} bash -c 'upload_one "$1"' _ {} > "$WORK/../upload-$DAY.log"
echo "uploaded $(grep -c '^uploaded' "$WORK/../upload-$DAY.log") files"

echo "== 4/4 verify size and sha256 on the Disk"
( cd "$WORK" && ls | grep -vx SHA256SUMS.txt ) | xargs -P "$JOBS" -I{} bash -c 'verify_one "$1"' _ {} > "$WORK/../verify-$DAY.log"
upload_one SHA256SUMS.txt && verify_one SHA256SUMS.txt >> "$WORK/../verify-$DAY.log"
echo "verified OK: $(grep -c '^OK' "$WORK/../verify-$DAY.log") of $(ls "$WORK" | wc -l)"
echo "yadisk: backup $DEST complete"

# Retention (Kanta 2026-11-06: keep 14 days). Runs only after a fully verified backup, touches
# only YYYY-MM-DD folders under $ROOT, and moves them to the Disk trash (recoverable), not permanently.
KEEP_DAYS="${KEEP_DAYS:-14}"
CUTOFF="$(TZ=Europe/Moscow date -d "$DAY - $((KEEP_DAYS - 1)) days" +%F)"
curl -sS -f -H "$AUTH" "$API/resources?path=$(urlencode "$ROOT")&limit=1000&fields=_embedded.items.name,_embedded.items.type" \
  | python3 -c 'import sys,json,re
for i in json.load(sys.stdin)["_embedded"]["items"]:
    if i["type"]=="dir" and re.fullmatch(r"\d{4}-\d{2}-\d{2}",i["name"]): print(i["name"])' \
  | while read -r old; do
      if [[ "$old" < "$CUTOFF" ]]; then
        curl -sS -f -o /dev/null -X DELETE -H "$AUTH" "$API/resources?path=$(urlencode "$ROOT/$old")" \
          && echo "retention: moved $old to trash (older than $KEEP_DAYS days)"
      fi
    done
