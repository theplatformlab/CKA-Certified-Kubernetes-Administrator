# shellcheck shell=bash
# Helpers for lab_params: items whose names and values vary per session.
#
# lab_params prints KEY=VALUE lines. The runner seeds the generator per session
# and item, so the same session always gets the same values (also for grading),
# and a manual `./scripts/lab.sh ...` run gets repeatable defaults.
# (The generator state lives in a file: helpers are called in $(...) subshells,
# and bash reseeds $RANDOM in every subshell.)
# Values are exported to lab_setup/lab_check and replace {{KEY}} in README.md.
#
# Example:
#   lab_params() {
#     echo "NS=$(pick team-a team-b billing)"
#     echo "REPLICAS=$(rand_int 2 5)"
#   }

# _rand — next number in [0, 32767]: a hash of the seed and a draw counter.
# (A plain LCG gave near-constant first draws for neighbouring seeds.)
# CKA_RNG_FILE holds "<seed> <counter>".
_rand() {
  local seed n h
  if [[ -n "${CKA_RNG_FILE:-}" && -f "$CKA_RNG_FILE" ]]; then
    read -r seed n <"$CKA_RNG_FILE"
    echo "$seed $(( n + 1 ))" >"$CKA_RNG_FILE"
    h="$(printf '%s:%s' "$seed" "$n" | sha256sum)"
    echo $(( 16#${h:0:6} % 32768 ))
  else
    echo "$RANDOM"
  fi
}

# pick <value>... — one of the arguments
pick() {
  local values=("$@") r
  r=$(_rand)
  echo "${values[r % ${#values[@]}]}"
}

# rand_int <min> <max> — integer in [min, max]
rand_int() {
  local r
  r=$(_rand)
  echo $(( $1 + r % ($2 - $1 + 1) ))
}

# rand_suffix [length] — lowercase letters/digits, valid in DNS names
rand_suffix() {
  local chars=abcdefghijkmnpqrstuvwxyz23456789 out="" i r
  for (( i = 0; i < ${1:-4}; i++ )); do r=$(_rand); out+="${chars:r % ${#chars}:1}"; done
  echo "$out"
}
