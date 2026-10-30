#!/usr/bin/env bash
# CKA common-v2 lab runner.
#
#   ./lab.sh list                      list the questions
#   ./lab.sh <q>                       provision the question's environment
#   ./lab.sh <q> task                  print the question
#   ./lab.sh <q> prerequisites         print the prerequisite analysis
#   ./lab.sh <q> validate              check the answer
#   ./lab.sh <q> reset                 tear the environment back down
#   ./lab.sh <q> solution              print the solution notes
#
# <q> can be given as "1", "c1", "C1" or any part of the question's slug
# ("multi-container", "gateway", "networkpolicy", ...).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUESTIONS="$HERE/"

usage(){
  cat <<'EOF'
Usage:
  ./lab.sh list                      list the questions
  ./lab.sh <q>                       provision the question's environment
  ./lab.sh <q> task                  print the question
  ./lab.sh <q> prerequisites         print the prerequisite analysis
  ./lab.sh <q> validate              check the answer
  ./lab.sh <q> reset                 tear the environment back down
  ./lab.sh <q> solution              print the solution notes

Actions: setup (default), task, prerequisites, validate, reset, solution
EOF
}

resolve(){
  # Prints the folder path for a question reference, or nothing.
  # macOS ships bash 3.2, so no ${var,,} and no ${var:0:2} substring tricks
  # that older bash handles differently - use cut/tr instead.
  local ref d slug num lower
  ref="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  for d in "$QUESTIONS"c[0-9]*-*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    slug="$(basename "$d")"
    num="$(printf '%s' "$slug" | sed 's/^c//' | cut -d- -f1)"
    num=$((10#$num))
    lower="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')"
    if [ "$ref" = "$num" ] || [ "$ref" = "c$num" ] || [ "$ref" = "$lower" ]; then
      printf '%s\n' "$d"; return 0
    fi
  done
  # substring match on the slug, e.g. "gateway"
  for d in "$QUESTIONS"c[0-9]*-*/; do
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
  local d slug num title
  for d in "$QUESTIONS"c[0-9]*-*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    slug="$(basename "$d")"
    num="$(printf '%s' "$slug" | sed 's/^c//' | cut -d- -f1)"
    num=$((10#$num))
    title="${slug#*-}"; title="$(printf '%s' "$title" | tr '-' ' ')"
    printf '%s\t%s\n' "$num" "$title"
  done | sort -n -k1,1 | while IFS=$'\t' read -r num title; do
    printf '  c%-3s %s\n' "$num" "$title"
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
  setup)         bash "$DIR/LabSetUp.bash";;
  task)          cat "$DIR/Questions.bash";;
  prerequisites) cat "$DIR/Prerequisites.md";;
  validate)      bash "$DIR/LabValidate.bash";;
  reset)         bash "$DIR/LabReset.bash";;
  solution)      cat "$DIR/SolutionNotes.bash";;
  *) echo "Unknown action '$ACTION'." >&2; usage >&2; exit 1;;
esac
