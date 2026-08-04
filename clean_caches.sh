#!/usr/bin/env bash
#
# clean_caches.sh — macOS developer cache cleaner
#
# Safe by default: runs in DRY-RUN mode and only reports what would be
# deleted and how much space each target uses. Nothing is removed unless
# you pass --force.
#
# Usage:
#   ./clean_caches.sh                 # dry run: report sizes only
#   ./clean_caches.sh --force         # actually delete (asks once for confirmation)
#   ./clean_caches.sh --force --yes   # delete without confirmation prompt
#   ./clean_caches.sh --aggressive    # also include risky targets (pub cache, gradle, simulators)
#
# Everything this script deletes is a cache: it will be re-downloaded or
# rebuilt on demand. The "aggressive" targets are still safe but will make
# your next build/fetch noticeably slower.

set -u

FORCE=0
ASSUME_YES=0
AGGRESSIVE=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --yes) ASSUME_YES=1 ;;
    --aggressive) AGGRESSIVE=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (see --help)" >&2
      exit 1
      ;;
  esac
done

BOLD=$(tput bold 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

TOTAL_KB=0

human_size() {
  local kb=$1
  if (( kb >= 1048576 )); then
    printf "%.1f GB" "$(echo "$kb / 1048576" | bc -l)"
  elif (( kb >= 1024 )); then
    printf "%.1f MB" "$(echo "$kb / 1024" | bc -l)"
  else
    printf "%d KB" "$kb"
  fi
}

# Reports the size of a path and deletes its contents when --force is set.
process_path() {
  local label=$1
  local path=$2

  # Expand globs safely; skip silently when nothing matches.
  local matches=()
  for p in $path; do
    [ -e "$p" ] && matches+=("$p")
  done
  [ ${#matches[@]} -eq 0 ] && return 0

  local kb
  kb=$(du -sk "${matches[@]}" 2>/dev/null | awk '{s+=$1} END {print s+0}')
  (( kb == 0 )) && return 0

  TOTAL_KB=$((TOTAL_KB + kb))
  printf "  %-45s %s%12s%s\n" "$label" "$BOLD" "$(human_size "$kb")" "$RESET"

  if (( FORCE )); then
    for p in "${matches[@]}"; do
      rm -rf "$p" 2>/dev/null
    done
  fi
}

# Runs a tool's own cleanup command (preferred over rm when available).
run_tool_clean() {
  local label=$1
  shift
  if command -v "$1" >/dev/null 2>&1; then
    if (( FORCE )); then
      echo "  ${label}..."
      "$@" >/dev/null 2>&1
    else
      echo "  ${label} (would run: $*)"
    fi
  fi
}

echo
if (( FORCE )); then
  echo "${RED}${BOLD}== DELETE MODE ==${RESET}"
  if (( ! ASSUME_YES )); then
    printf "This will permanently remove the caches listed below. Continue? [y/N] "
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  fi
else
  echo "${GREEN}${BOLD}== DRY RUN == (nothing will be deleted; use --force to clean)${RESET}"
fi

echo
echo "${BOLD}System & app caches${RESET}"
process_path "User app caches (~/Library/Caches)"   "$HOME/Library/Caches/*"
process_path "Saved application state"              "$HOME/Library/Saved Application State/*"
process_path "Trash"                                "$HOME/.Trash/*"

echo
echo "${BOLD}Xcode / iOS${RESET}"
process_path "Xcode DerivedData"                    "$HOME/Library/Developer/Xcode/DerivedData/*"
process_path "Xcode Archives"                       "$HOME/Library/Developer/Xcode/Archives/*"
process_path "Old iOS device support symbols"       "$HOME/Library/Developer/Xcode/iOS DeviceSupport/*"
process_path "CoreSimulator caches"                 "$HOME/Library/Developer/CoreSimulator/Caches/*"

echo
echo "${BOLD}Package managers & toolchains${RESET}"
process_path "CocoaPods cache"                      "$HOME/Library/Caches/CocoaPods"
process_path "npm cache"                            "$HOME/.npm/_cacache"
process_path "yarn cache"                           "$HOME/Library/Caches/Yarn"
process_path "pip cache"                            "$HOME/Library/Caches/pip"
run_tool_clean "Homebrew cleanup" brew cleanup --prune=all -s

if (( AGGRESSIVE )); then
  echo
  echo "${YELLOW}${BOLD}Aggressive targets (next builds will be slower)${RESET}"
  process_path "Dart/Flutter pub cache"             "$HOME/.pub-cache/hosted"
  process_path "Gradle caches"                      "$HOME/.gradle/caches/*"
  process_path "Gradle wrapper distributions"       "$HOME/.gradle/wrapper/dists/*"
  run_tool_clean "Delete unavailable iOS simulators" xcrun simctl delete unavailable
fi

echo
if (( FORCE )); then
  echo "${GREEN}${BOLD}Freed approximately: $(human_size "$TOTAL_KB")${RESET}"
else
  echo "${BOLD}Total reclaimable: $(human_size "$TOTAL_KB")${RESET}"
  echo "Run again with --force to delete (add --aggressive for the extra targets)."
fi
echo
