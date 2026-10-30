#!/usr/bin/env bash
# CKA exam-prep lab runner.
#
#   ./lab.sh list                    list the questions
#   ./lab.sh <q>                     provision the question's environment (setup)
#   ./lab.sh <q> task                print the question
#   ./lab.sh <q> prerequisites       print the prerequisite analysis
#   ./lab.sh <q> validate            check your answer
#   ./lab.sh <q> reset               tear the environment back down
#   ./lab.sh <q> solution            print the solution notes
#
# <q> can be given as "1", "q1", "Question-1" or the full folder name.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage(){
  cat <<'EOF'
Usage:
  ./lab.sh list                    list the questions
  ./lab.sh <q>                     provision the question's environment
  ./lab.sh <q> task                print the question
  ./lab.sh <q> prerequisites       print the prerequisite analysis
  ./lab.sh <q> validate            check your answer
  ./lab.sh <q> reset               tear the environment back down
  ./lab.sh <q> solution            print the solution notes

Actions: setup (default), task, prerequisites, validate, reset, solution
EOF
}

resolve(){
  # Prints the folder path for a question reference, or nothing.
  # Accepts "1", "q1", "Q1", "Question-1", the full folder name, or any
  # case-insensitive part of the folder name ("mariadb").
  # Note: macOS ships bash 3.2, so no ${var,,} - use tr to fold case.
  local ref d num base lower
  ref="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  for d in "$HERE"/Question-*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    base="$(basename "$d")"
    num="${base#Question-}"; num="${num%% *}"
    lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    case "$ref" in
      "$lower"|"$num"|"q$num"|"question-$num") printf '%s\n' "$d"; return 0;;
    esac
  done
  # also accept a bare substring match, e.g. "mariadb"
  for d in "$HERE"/Question-*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    lower="$(printf '%s' "$(basename "$d")" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      *"$ref"*) printf '%s\n' "$d"; return 0;;
    esac
  done
  return 1
}

list_questions(){
  echo "Questions:"
  local d n num title
  for d in "$HERE"/Question-*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    n="$(basename "$d")"
    num="${n#Question-}"; num="${num%% *}"
    title="${n#Question-}"; title="${title#* }"
    printf '%s\t%s\n' "$num" "$title"
  done | sort -n -k1,1 | while IFS=$'\t' read -r num title; do
    printf '  q%-3s %s\n' "$num" "$title"
  done
}

REF="${1:-}"
ACTION="${2:-setup}"

if [ -z "$REF" ] || [ "$REF" = "-h" ] || [ "$REF" = "--help" ]; then
  usage; exit 0
fi

if [ "$REF" = "list" ]; then
  list_questions; exit 0
fi

DIR="$(resolve "$REF")" || {
  echo "Unknown question '$REF'. Try './lab.sh list'." >&2
  exit 1
}

case "$ACTION" in
  setup)
    echo "== Provisioning $(basename "$DIR") =="
    bash "$DIR/LabSetUp.bash";;
  task)
    cat "$DIR/Questions.bash";;
  prerequisites)
    cat "$DIR/Prerequisites.md";;
  validate)
    bash "$DIR/LabValidate.bash";;
  reset)
    bash "$DIR/LabReset.bash";;
  solution)
    cat "$DIR/SolutionNotes.bash";;
  *)
    echo "Unknown action '$ACTION'." >&2; usage >&2; exit 1;;
esac
