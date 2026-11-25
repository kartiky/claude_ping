#!/usr/bin/env bash
#
# claude_ping.bash — install a cron job that pings Claude Code.
#
#   ./claude_ping.bash install          # asks what time to run
#   ./claude_ping.bash install --time 09:30
#   ./claude_ping.bash test | status | logs | remove | help
#
# Uses the `claude` already installed on your PATH. No credentials,
# tokens, or environment files are managed here.
#
set -uo pipefail

PROG="$(basename "$0")"
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
TAG="# claude-ping"

if [ -d "$HOME/Library/Logs" ]; then
  LOG="${CLAUDE_PING_LOG:-$HOME/Library/Logs/claude-ping.log}"
else
  LOG="${CLAUDE_PING_LOG:-$HOME/.local/state/claude-ping.log}"
fi

TIME=""
DAYS="1-5"
MODEL="haiku"
PROMPT="ping"
CLAUDE_BIN=""
CMD=""

usage() {
  cat <<EOF
$PROG — run "claude -p ping" on a schedule

USAGE
  $PROG install [--time HH:MM] [--days DAYS] [--model MODEL]
  $PROG remove | status | test | logs | help

COMMANDS
  install   Add or update the cron job. If --time is omitted, you are
            asked for a time (default 07:00).
  remove    Delete the cron job created by this tool.
  status    Show whether it is installed and when it runs.
  test      Run one ping now and print the result.
  logs      Show the log file.
  help      Show this help.

OPTIONS
  --time HH:MM    Time of day, 24-hour clock        (default: ask, then 07:00)
  --days DAYS     Days to run: 1-5, 0-6, 1,3,5, *   (default: 1-5, Mon-Fri)
  --model MODEL   Model alias or full name          (default: haiku)
  --prompt TEXT   Prompt to send                    (default: "ping")
  --log PATH      Log file to write                 (default: $LOG)

EXAMPLES
  $PROG install                    # asks: Time to ping (HH:MM) [07:00]:
  $PROG install --time 09:30       # weekdays at 09:30
  $PROG install --time 18:00 --days '*'
  $PROG test                       # try it once, right now

NOTES
  The job runs the 'claude' command already installed, with your existing
  configuration. This script does not manage credentials or tokens. If the
  CLI is missing when the job runs, it says so in the log and exits.

FILES
  Log: $LOG
EOF
}

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }
warn() { printf '%s: %s\n' "$PROG" "$*" >&2; }

# Find the installed claude: PATH first, then the usual user-local location.
resolve_claude() {
  CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
  if [ -z "$CLAUDE_BIN" ] && [ -x "$HOME/.local/bin/claude" ]; then
    CLAUDE_BIN="$HOME/.local/bin/claude"
  fi
  [ -n "$CLAUDE_BIN" ]
}

valid_time() {
  case "$1" in
    [01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) return 0 ;;
    *) return 1 ;;
  esac
}

valid_days() {
  printf '%s' "$1" | grep -Eq '^\*$|^[0-7](-[0-7])?(,[0-7](-[0-7])?)*$'
}

ask_time() {
  local answer
  if [ -n "$TIME" ]; then
    valid_time "$TIME" || die "invalid time '$TIME' (use HH:MM, e.g. 09:30)"
    return 0
  fi
  if [ ! -t 0 ]; then
    TIME="07:00"
    return 0
  fi
  while :; do
    printf 'Time to ping (HH:MM, 24h) [07:00]: '
    read -r answer || answer=""
    answer="${answer:-07:00}"
    if valid_time "$answer"; then
      TIME="$answer"
      return 0
    fi
    printf 'Please enter a time like 07:00 or 18:30.\n'
  done
}

shq() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

human_days() {
  case "$1" in
    '*') echo "every day" ;;
    '1-5') echo "Mon-Fri" ;;
    *) echo "days $1" ;;
  esac
}

cron_line() {
  local hh mm path
  hh=$((10#${TIME%%:*}))
  mm=$((10#${TIME##*:}))
  path="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  if [ -n "$CLAUDE_BIN" ]; then
    path="$(dirname "$CLAUDE_BIN"):$path"
  fi
  printf '%d %d * * %s PATH=%s %s run --model %s --prompt %s --log %s %s (at %s on %s)\n' \
    "$mm" "$hh" "$DAYS" "$(shq "$path")" "$(shq "$SELF")" "$(shq "$MODEL")" \
    "$(shq "$PROMPT")" "$(shq "$LOG")" "$TAG" "$TIME" "$(human_days "$DAYS")"
}

install_job() {
  resolve_claude || warn "claude CLI not found on PATH; the job will report this when it runs"
  ask_time
  valid_days "$DAYS" || die "invalid --days '$DAYS' (use 1-5, 0-6, 1,3,5, or *)"

  local line existing tmp
  line="$(cron_line)"

  existing="$(crontab -l 2>/dev/null || true)"
  tmp="$(mktemp "${TMPDIR:-/tmp}/claude-ping.XXXXXX")" || die "mktemp failed"

  printf '%s\n' "$existing" | grep -vF "$TAG" | sed '/^[[:space:]]*$/d' > "$tmp" || true
  printf '%s\n' "$line" >> "$tmp"
  crontab "$tmp" || { rm -f "$tmp"; die "crontab rejected the entry"; }
  rm -f "$tmp"

  echo "Installed: at $TIME on $(human_days "$DAYS")"
  if [ -n "$CLAUDE_BIN" ]; then
    echo "  Claude: $CLAUDE_BIN"
  else
    echo "  Claude: not found (the job will report this when it runs)"
  fi
  echo "  Log:    $LOG"
}

remove_job() {
  local existing tmp
  existing="$(crontab -l 2>/dev/null || true)"
  printf '%s\n' "$existing" | grep -Fq "$TAG" || { echo "Nothing to remove."; return 0; }

  tmp="$(mktemp "${TMPDIR:-/tmp}/claude-ping.XXXXXX")" || die "mktemp failed"
  printf '%s\n' "$existing" | grep -vF "$TAG" | sed '/^[[:space:]]*$/d' > "$tmp" || true
  if [ -s "$tmp" ]; then
    crontab "$tmp" || { rm -f "$tmp"; die "crontab update failed"; }
  else
    crontab -r 2>/dev/null || true
  fi
  rm -f "$tmp"
  echo "Removed."
}

status_job() {
  local lines
  lines="$(crontab -l 2>/dev/null | grep -F "$TAG" || true)"
  if [ -z "$lines" ]; then
    echo "Status: not installed"
    return 0
  fi
  echo "Status: installed"
  printf '%s\n' "$lines" | sed -n 's/.*# claude-ping (\(.*\))$/  - \1/p'
  echo "  Log: $LOG"
}

run_ping() {
  "$CLAUDE_BIN" -p "$PROMPT" --model "$MODEL" \
    --no-session-persistence --strict-mcp-config
}

test_job() {
  if ! resolve_claude; then
    printf '%s: claude CLI not found on PATH\n' "$PROG" >&2
    return 127
  fi
  echo "Running: $CLAUDE_BIN -p '$PROMPT' --model $MODEL"
  run_ping
  local rc=$?
  [ "$rc" -eq 0 ] || echo "Failed (exit $rc)."
  return "$rc"
}

run_job() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  exec >>"$LOG" 2>&1
  if ! resolve_claude; then
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') claude CLI not found on PATH; nothing to run"
    exit 127
  fi
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') ping (model=$MODEL)"
  run_ping
  local rc=$?
  echo "=== exit $rc"
  exit "$rc"
}

show_logs() {
  [ -f "$LOG" ] || { echo "No log yet: $LOG"; return 0; }
  tail -n 40 "$LOG"
}

# --- arguments -------------------------------------------------------------

args=()
for a in "$@"; do
  case "$a" in
    --*=*) args+=("${a%%=*}" "${a#*=}") ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]}"

need() { [ $# -ge 2 ] || die "option $1 needs a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    install|remove|status|test|logs|help|run) CMD="$1"; shift ;;
    -h|--help) CMD="help"; shift ;;
    --time) need "$@"; TIME="$2"; shift 2 ;;
    --days) need "$@"; DAYS="$2"; shift 2 ;;
    --model) need "$@"; MODEL="$2"; shift 2 ;;
    --prompt) need "$@"; PROMPT="$2"; shift 2 ;;
    --log) need "$@"; LOG="$2"; shift 2 ;;
    *) die "unknown argument: $1 (try '$PROG help')" ;;
  esac
done

case "${CMD:-help}" in
  install) install_job ;;
  remove) remove_job ;;
  status) status_job ;;
  test) test_job ;;
  logs) show_logs ;;
  run) run_job ;;
  help) usage ;;
esac
