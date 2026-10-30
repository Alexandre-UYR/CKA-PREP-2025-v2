#!/bin/bash
set -euo pipefail

# Kept for backwards compatibility. The full runner is ../lab.sh, which adds
# validate, reset, prerequisites and solution on top of what this does.
#
#   ./scripts/run-question.sh "Question-9 Network-Policy"
#
# runs the setup and prints the question, exactly as it always did.

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/run-question.sh \"Question-XX Topic\"" >&2
  echo "   or:  ./lab.sh <q> [setup|task|validate|reset|prerequisites|solution]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QUESTION_DIR="$*"
if [[ ! -d "$QUESTION_DIR" ]]; then
  echo "Question directory '$QUESTION_DIR' not found" >&2
  exit 1
fi

"$ROOT/lab.sh" "$(basename "$QUESTION_DIR")" setup
echo
echo "==> Question"
"$ROOT/lab.sh" "$(basename "$QUESTION_DIR")" task
echo
echo "Hints: see $QUESTION_DIR/SolutionNotes.bash"
echo "Check your answer with: ./lab.sh $(basename "$QUESTION_DIR") validate"
