#!/usr/bin/env bash
# Role-to-model table for vetdd. One place to change.
#
# Usage: models.sh <role>          prints the model for the role
#        models.sh --list          prints every role and its model; fails if any override is invalid
#
# Roles:
#   author        Claude subagent that writes product code and tests (Agent tool `model`)
#   refactorer    Claude subagent that refactors after the slices are green; never the author
#   explorer      Claude subagent for read-only investigation
#   arena-runner  Claude subagents that compete in an arena (comma-separated, one lane each)
#   judge         Codex model for the final verdict (`codex exec -m`)
#   judge-effort  reasoning effort passed to codex (`model_reasoning_effort`)
#
# The judge is always a different family from the author (principle 6).
# Override any role with VETDD_MODEL_<ROLE> (dashes become underscores, upper case),
# e.g. VETDD_MODEL_JUDGE=gpt-6-astra. Invalid overrides exit 2.

set -euo pipefail

ROLES="author refactorer explorer arena-runner judge judge-effort"

declare_default() {
  case "$1" in
    author)        echo "opus" ;;
    refactorer)    echo "opus" ;;
    explorer)      echo "haiku" ;;
    arena-runner)  echo "opus,fable,sonnet" ;;
    judge)         echo "gpt-6-sol" ;;
    judge-effort)  echo "high" ;;
    *) return 1 ;;
  esac
}

invalid() { echo "models.sh: invalid model name for $1: $2" >&2; exit 2; }

# One model name: letters, digits, and . _ : / - ; must start with a letter or digit so it can
# never be read as a command-line option.
check_name() {
  case "$2" in
    ""|[!A-Za-z0-9]*|*[!A-Za-z0-9._:/-]*) invalid "$1" "$2" ;;
  esac
}

is_claude() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    *claude*|*anthropic*|*opus*|*sonnet*|*haiku*|*fable*) return 0 ;;
    *) return 1 ;;
  esac
}

# Author-side roles run through the Agent tool, whose `model` takes the Claude aliases below; the
# judge must not be Claude. Together these keep author and judge in different families (principle 6).
check_author() {
  case "$2" in
    opus|sonnet|haiku|fable) ;;
    *) echo "models.sh: $1 must be an Agent tool model alias (opus, sonnet, haiku, fable), got $2" >&2; exit 2 ;;
  esac
}

# The value for a role, validated per role.
validate() {
  local role="$1" value="$2" item items
  case "$role" in
    judge-effort)
      case "$value" in minimal|low|medium|high|xhigh|max) ;; *) invalid "$role" "$value" ;; esac ;;
    arena-runner)
      case "$value" in ""|,*|*,|*,,*|*[!A-Za-z0-9._:/,-]*) invalid "$role" "$value" ;; esac
      IFS=, read -r -a items <<< "$value"
      for item in "${items[@]}"; do check_author "$role" "$item"; done ;;
    judge)
      check_name "$role" "$value"
      if is_claude "$value"; then
        echo "models.sh: judge must be a different model family from the authors, got $value" >&2; exit 2
      fi ;;
    author|refactorer|explorer) check_author "$role" "$value" ;;
    *) check_name "$role" "$value" ;;
  esac
}

lookup() {
  local role="$1" var value
  # Reject unknown roles before building a variable name from the argument: `${!var}` evaluates an
  # array subscript in the name, so an unchecked role could run a command substitution.
  declare_default "$role" >/dev/null || { echo "models.sh: unknown role: $role" >&2; exit 2; }
  var="VETDD_MODEL_$(printf '%s' "$role" | tr 'a-z-' 'A-Z_')"
  # A variable set to the empty string is an invalid override, not a request for the default.
  if [ -n "${!var+set}" ]; then value="${!var}"; else value="$(declare_default "$role")"; fi
  validate "$role" "$value"
  printf '%s\n' "$value"
}

case "${1:-}" in
  --list)
    for r in $ROLES; do
      model="$(lookup "$r")" || exit 2
      printf '%-13s %s\n' "$r" "$model"
    done ;;
  "") echo "usage: models.sh <role> | --list" >&2; exit 2 ;;
  *) lookup "$1" ;;
esac
