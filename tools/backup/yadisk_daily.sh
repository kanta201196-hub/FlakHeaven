#!/usr/bin/env bash
## Daily full project backup to Yandex Disk: disk:/FlakHeaven backup/<YYYY-MM-DD MSK>/.
## Why: Kanta asked (2026-11-06) for one dated folder per day holding everything needed to
## resume the project without GitHub or the shared folder: all git branches, a browsable code
## snapshot, models/docs/source assets from /mnt/project-files, project memory and instructions.
## Builds, marketing videos and older backups are left out (rebuildable or kept elsewhere).
## Kanta also asked (2026-11-06) that the backup happen without him, so the script is safe to run
## again and again the same day: it resumes instead of starting over (see "Resume" below).
##
## Auth: the environment's network secret injects `Authorization: OAuth <token>` for
## cloud-api.yandex.net; this script sends a dummy header and never sees the token.
## Big files are split into PART_SIZE pieces: the cloud egress tunnel drops single uploads
## after ~90 MB / ~60 s, while 40 MB pieces go through at ~7 MB/s.
##
## Resume: the pack is built once per day in $WORK (marker .pack_complete) and reused by later runs
## in the same container; a file already on the Disk with the same size and sha256 is skipped; files
## left in the day folder by an earlier, different pack are removed before SHA256SUMS.txt goes up.
## SHA256SUMS.txt is uploaded last, so its presence on the Disk means the day is complete.
##
## When the Disk cannot take the backup, the script still saves what exists nowhere else
## (project memory, instructions, branch list) to $PF/backups/emergency/<day>/ (newest 3 kept)
## and exits with a code that names the cause, so the scheduled task can tell Kanta:
##   0 done (or already done today)   2 Disk unreachable / token rejected   3 not enough space on the Disk
##   4 source looks broken (shared folder missing or nearly empty; nothing uploaded)
##   5 some files failed to upload or verify after all passes   1 anything else
##
## After a verified run, dated folders older than KEEP_DAYS (default 14, Kanta 2026-11-06) go to the
## Disk trash; nothing else on the Disk is touched.
## Usage: tools/backup/yadisk_daily.sh [work_dir]   (needs ~13 GB free in work_dir)
set -euo pipefail

DAY="${DAY:-$(TZ=Europe/Moscow date +%F)}"
WORK="${1:-${TMPDIR:-/tmp}/yadisk-backup}/$DAY"
REPO="${REPO:-$(git rev-parse --show-toplevel)}"
MEM="${MEM:-/tmp/claude/memory/team/silo}"
PF="${PF:-/mnt/project-files}"
ROOT="${YADISK_ROOT:-disk:/FlakHeaven backup}"
DEST="$ROOT/$DAY"
PART_SIZE="${PART_SIZE:-40M}"
JOBS="${JOBS:-4}"
PASSES="${PASSES:-3}"
MIN_PF_FILES="${MIN_PF_FILES:-500}"   # 2026-11-06: ~2400 files; fewer than 500 means the mount is broken
EMERGENCY_KEEP="${EMERGENCY_KEEP:-3}"
MARGIN_MB="${MARGIN_MB:-1024}"     # free space kept on the Disk on top of the pack
export API="${YADISK_API:-https://cloud-api.yandex.net/v1/disk}"
export AUTH="Authorization: OAuth proxy-injects-real-token"
export WORK DEST
LOGDIR="$(dirname "$WORK")"

## urlencode: percent-encodes a Disk path for a query string.
urlencode() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

## remote_matches: true when $DEST/$1 on the Disk has the local file's size and sha256.
## The Disk fills in sha256 a little after an upload, so a fresh upload is polled for up to ~40 s.
remote_matches() {
  local f="$1" tries="${2:-1}" p meta try rs rh
  p=$(urlencode "$DEST/$f")
  for ((try = 1; try <= tries; try++)); do
    meta=$(curl -sS -f -H "$AUTH" "$API/resources?fields=size,sha256&path=$p" 2>/dev/null) || meta=""
    echo "$meta" | grep -q '"sha256"' && break
    [ "$try" -lt "$tries" ] && sleep 5
  done
  rs=$(echo "$meta" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("size",""))' 2>/dev/null || true)
  rh=$(echo "$meta" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("sha256",""))' 2>/dev/null || true)
  [ "$rs" = "$(stat -c %s "$WORK/$f")" ] && [ "$rh" = "$(sha256sum "$WORK/$f" | cut -d' ' -f1)" ]
}

## sync_one: makes $DEST/$1 match $WORK/$1 (skip if already there, else upload with retries and verify).
## Prints "OK <file>" or "FAILED <file>"; never exits non-zero so one bad part does not stop the batch.
sync_one() {
  local f="$1" try href p
  if remote_matches "$f" 1; then echo "OK $f (already on Disk)"; return 0; fi
  p=$(urlencode "$DEST/$f")
  for try in 1 2 3 4 5; do
    href=$(curl -sS -f -H "$AUTH" "$API/resources/upload?overwrite=true&path=$p" 2>/dev/null \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["href"])' 2>/dev/null) || href=""
    if [ -n "$href" ] && curl -sS -f --max-time 600 -T "$WORK/$f" "$href" -o /dev/null 2>/dev/null \
       && remote_matches "$f" 8; then
      echo "OK $f"; return 0
    fi
    sleep $((2 ** try))
  done
  echo "FAILED $f"
}
export -f urlencode remote_matches sync_one

## api_status: HTTP status of a GET on the Disk API (000 when the network is down).
api_status() { curl -sS -o /dev/null -w '%{http_code}' --max-time 60 -H "$AUTH" "$API/$1" 2>/dev/null || true; }

## emergency_copy: saves the small, irreplaceable part of the project (memory, instructions, branch
## list, a one-line note why) to the shared folder when the Disk did not take the backup.
## GitHub keeps the code and the shared folder keeps the models, so this closes the remaining gap.
emergency_copy() {
  local why="$1" dst="$PF/backups/emergency/$DAY" tmp
  [ -d "$PF" ] || { echo "emergency: shared folder $PF is missing too; nothing saved" >&2; return 0; }
  tmp="$(mktemp -d)"
  build_instructions "$tmp/instructions-and-memory.tar.gz" || true
  ( cd "$REPO" && git for-each-ref --format='%(objectname) %(refname)' refs/remotes/origin ) > "$tmp/repo-refs.txt" 2>/dev/null || true
  printf 'Disk backup for %s failed: %s\nSaved at %s UTC by tools/backup/yadisk_daily.sh\n' \
    "$DAY" "$why" "$(date -u +%FT%TZ)" > "$tmp/WHY.txt"
  mkdir -p "$dst" && cp "$tmp"/* "$dst/" && echo "emergency: saved memory and instructions to $dst"
  rm -rf "$tmp"
  # Keep only the newest EMERGENCY_KEEP day folders (these are this script's own small copies).
  ls -1d "$PF/backups/emergency"/????-??-?? 2>/dev/null | sort | head -n -"$EMERGENCY_KEEP" | xargs -r rm -rf
}

## build_instructions: packs CLAUDE.md, .claude/, project memory and full project instructions into $1.
build_instructions() {
  local out="$1" d; d="$(mktemp -d)"
  git -C "$REPO" show origin/main:CLAUDE.md > "$d/CLAUDE.md"
  git -C "$REPO" archive origin/main .claude | tar -x -C "$d" 2>/dev/null || true
  [ -d "$MEM" ] && cp -r "$MEM" "$d/project-memory"
  cp "$PF"/process/project-instructions* "$d/" 2>/dev/null || true
  tar czf "$out" -C "$d" .
  rm -rf "$d"
}

## fail: prints the reason, makes the emergency copy and exits with the given code.
fail() { echo "yadisk: FAILED ($2): $1" >&2; emergency_copy "$1"; exit "$2"; }

echo "== 0/5 preflight for $DEST"
st=$(api_status "")
case "$st" in
  200) ;;
  401|403) fail "Disk rejected the token (HTTP $st): Kanta must renew the Yandex token in the environment's network secret" 2 ;;
  *) fail "Disk API unreachable (HTTP $st); proxy: $(curl -sS --max-time 20 "$HTTPS_PROXY/__agentproxy/status" 2>/dev/null | tr -s " \n" " " | head -c 300)" 2 ;;
esac
if [ "$(api_status "resources?path=$(urlencode "$DEST/SHA256SUMS.txt")")" = 200 ]; then
  echo "yadisk: $DEST already complete, nothing to do"; exit 0
fi
[ -d "$PF" ] || fail "shared folder $PF is not mounted" 4
pf_files=$(find "$PF" -path "$PF/builds" -prune -o -path "$PF/marketing" -prune -o -path "$PF/backups" -prune -o -type f -print 2>/dev/null | wc -l)
[ "$pf_files" -ge "$MIN_PF_FILES" ] || fail "shared folder has only $pf_files files (expected >= $MIN_PF_FILES): mount looks broken" 4

if [ -f "$WORK/.pack_complete" ] && [ -f "$WORK/SHA256SUMS.txt" ]; then
  echo "== 1/5 reuse today's pack in $WORK (resume)"
else
  echo "== 1/5 build pack in $WORK"
  mkdir -p "$WORK"; rm -rf "${WORK:?}"/* "$WORK/.pack_complete"
  cd "$REPO"
  git fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
  git bundle create "$WORK/repo-all-branches.bundle" --remotes 2>/dev/null
  git bundle verify -q "$WORK/repo-all-branches.bundle" >/dev/null
  git archive --format=tar.gz --prefix=FlakHeaven-main/ -o "$WORK/code-main-snapshot.tar.gz" origin/main
  git rev-parse origin/main > "$WORK/main-head.txt"
  git for-each-ref --format='%(objectname) %(refname)' refs/remotes/origin > "$WORK/repo-refs.txt"
  build_instructions "$WORK/instructions-and-memory.tar.gz"

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
  touch "$WORK/.pack_complete"
fi
need=$(du -sb "$WORK" | cut -f1)
echo "files: $(ls "$WORK" | wc -l), total: $(du -sh "$WORK" | cut -f1)"

echo "== 2/5 check space and create $DEST"
free=$(curl -sS -f -H "$AUTH" "$API/" 2>/dev/null | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["total_space"]-d["used_space"])' 2>/dev/null || echo 0)
# MARGIN_MB on top of the pack. Files already uploaded today are counted twice; that only errs safe.
[ "$free" -ge $((need + MARGIN_MB * 1024 * 1024)) ] \
  || fail "not enough space on the Disk: free $((free / 1024 / 1024)) MB, need $((need / 1024 / 1024)) MB + $MARGIN_MB MB" 3
curl -sS -o /dev/null -X PUT -H "$AUTH" "$API/resources?path=$(urlencode "$ROOT")"
curl -sS -o /dev/null -X PUT -H "$AUTH" "$API/resources?path=$(urlencode "$DEST")"

echo "== 3/5 upload and verify ($JOBS at a time, up to $PASSES passes)"
( cd "$WORK" && ls | grep -vx SHA256SUMS.txt ) > "$LOGDIR/todo-$DAY.txt"
total=$(wc -l < "$LOGDIR/todo-$DAY.txt")
for ((pass = 1; pass <= PASSES; pass++)); do
  xargs -P "$JOBS" -I{} bash -c 'sync_one "$1"' _ {} < "$LOGDIR/todo-$DAY.txt" > "$LOGDIR/sync-$DAY-$pass.log"
  sed -n 's/^FAILED //p' "$LOGDIR/sync-$DAY-$pass.log" > "$LOGDIR/todo-$DAY.txt"
  left=$(wc -l < "$LOGDIR/todo-$DAY.txt")
  echo "pass $pass: $((total - left)) of $total on the Disk"
  [ "$left" -eq 0 ] && break
  [ "$pass" -lt "$PASSES" ] && sleep 60
done
[ "$left" -eq 0 ] || fail "$left of $total files failed to upload/verify: $(head -5 "$LOGDIR/todo-$DAY.txt" | tr '\n' ' ')" 5

echo "== 4/5 remove leftovers of an earlier attempt, then mark the day complete"
# A rerun after a lost container builds a new pack; parts of the old one would break `cat *.part*`.
curl -sS -f -H "$AUTH" "$API/resources?path=$(urlencode "$DEST")&limit=10000&fields=_embedded.items.name" \
  | python3 -c 'import sys,json;[print(i["name"]) for i in json.load(sys.stdin)["_embedded"]["items"]]' \
  | while read -r name; do
      if [ ! -e "$WORK/$name" ]; then
        curl -sS -f -o /dev/null -X DELETE -H "$AUTH" "$API/resources?permanently=true&path=$(urlencode "$DEST/$name")" \
          && echo "removed stale $name"
      fi
    done || echo "warning: could not list $DEST for leftovers"
[ "$(sync_one SHA256SUMS.txt)" = "OK SHA256SUMS.txt" ] || fail "SHA256SUMS.txt failed to upload" 5
echo "verified OK: $total of $total + SHA256SUMS.txt"
echo "yadisk: backup $DEST complete"

echo "== 5/5 retention"
# Kanta 2026-11-06: keep 14 days. Runs only after a fully verified backup, touches only
# YYYY-MM-DD folders under $ROOT, and moves them to the Disk trash (recoverable), not permanently.
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
    done || echo "warning: retention skipped (could not list $ROOT); backup itself is complete"
rm -f "$LOGDIR"/todo-"$DAY".txt
exit 0
