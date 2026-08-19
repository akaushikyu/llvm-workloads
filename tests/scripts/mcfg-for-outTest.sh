#!/usr/bin/env bash
set -u

LLVM_ROOT="${LLVM_ROOT:-$HOME/llvm-repos/test/llvm-project}"
LLVM_BUILD="${LLVM_BUILD:-$LLVM_ROOT/build}"

LLC="$LLVM_BUILD/bin/llc"

usage() {
  echo "Usage:"
  echo "  $(basename "$0") MIR_DIRECTORY [CFG_OUTPUT_DIRECTORY]"
  echo
  echo "Example:"
  echo "  $(basename "$0") \\"
  echo "    /path/to/outTest/MIR-after-expand-count \\"
  echo "    /path/to/outTest/CFG"
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 1
fi

if [ ! -x "$LLC" ]; then
  echo "ERROR: llc not found or not executable:"
  echo "  $LLC"
  exit 1
fi

if ! command -v dot >/dev/null 2>&1; then
  echo "ERROR: Graphviz 'dot' command was not found."
  exit 1
fi

# Canonicalize the MIR directory and remove any trailing-slash ambiguity.
MIRDIR="$(realpath "$1")"

if [ ! -d "$MIRDIR" ]; then
  echo "ERROR: MIR directory does not exist:"
  echo "  $MIRDIR"
  exit 1
fi

# Normally MIRDIR is:
#   /.../outTest/MIR-after-expand-count
#
# Therefore OUTROOT becomes:
#   /.../outTest
OUTROOT="$(dirname "$MIRDIR")"

if [ "$#" -eq 2 ]; then
  CFGROOT="$(realpath -m "$2")"
else
  CFGROOT="$OUTROOT/CFG"
fi

DOTROOT="$CFGROOT/DOT-after-expand-count"
SVGROOT="$CFGROOT/SVG-after-expand-count"
LOGDIR="$CFGROOT/LOGs"

mkdir -p \
  "$CFGROOT" \
  "$DOTROOT" \
  "$SVGROOT" \
  "$LOGDIR"

count_mir_functions() {
  local mir="$1"
  local count

  count=$(grep -cE '^name:[[:space:]]*' "$mir" 2>/dev/null || true)
  printf '%s\n' "$count"
}

count_matching_files() {
  local dir="$1"
  local pattern="$2"

  if [ ! -d "$dir" ]; then
    echo 0
    return
  fi

  find "$dir" \
    -maxdepth 1 \
    -type f \
    -name "$pattern" \
    -printf '.' |
    wc -c
}

outputs_are_current() {
  local mir="$1"
  local dot_dir="$2"
  local svg_dir="$3"

  local func_count
  local dot_count
  local svg_count

  func_count=$(count_mir_functions "$mir")
  dot_count=$(count_matching_files "$dot_dir" '*.dot')
  svg_count=$(count_matching_files "$svg_dir" '*.svg')

  # The expected number of outputs must exist.
  if [ "$func_count" -le 0 ]; then
    return 1
  fi

  if [ "$dot_count" -ne "$func_count" ]; then
    return 1
  fi

  if [ "$svg_count" -ne "$func_count" ]; then
    return 1
  fi

  # Regenerate if any DOT or SVG file is older than the MIR input.
  if find "$dot_dir" "$svg_dir" \
      -maxdepth 1 \
      -type f \
      \( -name '*.dot' -o -name '*.svg' \) \
      ! -newer "$mir" \
      -print -quit |
      grep -q .; then
    return 1
  fi

  return 0
}

TOTAL=$(
  find "$MIRDIR" \
    -type f \
    -name '*.after-expand-count.mir' |
    wc -l
)

DONE=0
SKIPPED=0
PROCESSED=0
FAILED=0

progress_bar() {
  local done="$1"
  local total="$2"
  local current="$3"

  local width=40
  local percent=0
  local filled=0
  local empty=0

  if [ "$total" -gt 0 ]; then
    percent=$((done * 100 / total))
    filled=$((done * width / total))
  fi

  empty=$((width - filled))

  local filled_bar
  local empty_bar

  filled_bar=$(printf "%${filled}s" "" | tr ' ' '#')
  empty_bar=$(printf "%${empty}s" "" | tr ' ' '-')

  printf "\r[%s%s] %3d%%  %d/%d  %s" \
    "$filled_bar" \
    "$empty_bar" \
    "$percent" \
    "$done" \
    "$total" \
    "$current"
}

echo "MIR directory:     $MIRDIR"
echo "CFG output root:   $CFGROOT"
echo "DOT output root:   $DOTROOT"
echo "SVG output root:   $SVGROOT"
echo "Log directory:     $LOGDIR"
echo "Total MIR files:   $TOTAL"

if [ "$TOTAL" -eq 0 ]; then
  echo
  echo "ERROR: No *.after-expand-count.mir files found in:"
  echo "  $MIRDIR"
  exit 1
fi

while IFS= read -r -d '' mir; do
  # Produce a path relative to MIRDIR.
  #
  # Example:
  #   mir:
  #     /.../MIR-after-expand-count/subdir/test.after-expand-count.mir
  #
  #   rel:
  #     subdir/test.after-expand-count.mir
  #
  # This prevents the absolute /home/akamran/... path from appearing
  # inside the output directory.
  rel="$(realpath --relative-to="$MIRDIR" "$mir")"
  stem="${rel%.after-expand-count.mir}"

  THIS_DOT_DIR="$DOTROOT/$stem"
  THIS_SVG_DIR="$SVGROOT/$stem"

  mkdir -p "$THIS_DOT_DIR" "$THIS_SVG_DIR"

  safe_log_name="${stem//\//__}"

  dot_log="$LOGDIR/$safe_log_name.dot-machine-cfg.log"
  svg_log="$LOGDIR/$safe_log_name.dot-to-svg.log"

  echo
  echo "==> $mir"

  progress_bar "$DONE" "$TOTAL" "$stem"

  if outputs_are_current \
      "$mir" \
      "$THIS_DOT_DIR" \
      "$THIS_SVG_DIR"; then

    func_count=$(count_mir_functions "$mir")
    dot_count=$(count_matching_files "$THIS_DOT_DIR" '*.dot')
    svg_count=$(count_matching_files "$THIS_SVG_DIR" '*.svg')

    echo
    echo "SKIP: current outputs already exist for $stem"
    echo "      functions=$func_count dots=$dot_count svgs=$svg_count"

    SKIPPED=$((SKIPPED + 1))
    DONE=$((DONE + 1))

    progress_bar "$DONE" "$TOTAL" "$stem"
    echo

    continue
  fi

  # Remove stale or incomplete outputs for this MIR file.
  rm -f "$THIS_DOT_DIR"/*.dot
  rm -f "$THIS_SVG_DIR"/*.svg

  : > "$dot_log"
  : > "$svg_log"

  if ! "$LLC" \
      -mtriple=riscv64-unknown-elf \
      -run-pass=dot-machine-cfg \
      -mcfg-dot-filename-prefix="$THIS_DOT_DIR/cfg" \
      "$mir" \
      -o /dev/null \
      > "$dot_log" \
      2>&1; then

    echo
    echo "!! dot-machine-cfg failed for:"
    echo "   $mir"
    echo "   Log: $dot_log"

    FAILED=$((FAILED + 1))
    DONE=$((DONE + 1))

    progress_bar "$DONE" "$TOTAL" "$stem"
    echo

    continue
  fi

  svg_failed=0

  for dotfile in "$THIS_DOT_DIR"/*.dot; do
    [ -f "$dotfile" ] || continue

    dotbase="$(basename "$dotfile" .dot)"
    svgfile="$THIS_SVG_DIR/$dotbase.svg"

    if ! dot \
        -Tsvg \
        "$dotfile" \
        -o "$svgfile" \
        >> "$svg_log" \
        2>&1; then

      echo "!! dot-to-SVG failed for: $dotfile" >> "$svg_log"
      svg_failed=1
    fi
  done

  if [ "$svg_failed" -ne 0 ]; then
    echo
    echo "!! one or more SVG conversions failed for:"
    echo "   $mir"
    echo "   Log: $svg_log"

    FAILED=$((FAILED + 1))
  else
    PROCESSED=$((PROCESSED + 1))
  fi

  DONE=$((DONE + 1))
  progress_bar "$DONE" "$TOTAL" "$stem"

  echo
  echo "DONE: $mir"

done < <(
  find "$MIRDIR" \
    -type f \
    -name '*.after-expand-count.mir' \
    -print0
)

echo
echo "All done."
echo
echo "DOT output:"
echo "  $DOTROOT"
echo
echo "SVG output:"
echo "  $SVGROOT"
echo
echo "Logs:"
echo "  $LOGDIR"
echo
echo "Summary:"
echo "  Total:     $TOTAL"
echo "  Processed: $PROCESSED"
echo "  Skipped:   $SKIPPED"
echo "  Failed:    $FAILED"