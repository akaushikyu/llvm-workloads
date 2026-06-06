#!/usr/bin/env bash
set -u

LLVM_ROOT="${LLVM_ROOT:-$HOME/llvm-repos/test/llvm-project}"
LLVM_BUILD="${LLVM_BUILD:-$LLVM_ROOT/build}"
LLC="$LLVM_BUILD/bin/llc"

ROOTDIR="$(pwd)"
OUTROOT="$ROOTDIR/outTest"

MIRDIR="${1:-$OUTROOT/MIR-after-expand-count}"

DOTROOT="$OUTROOT/DOT-after-expand-count"
SVGROOT="$OUTROOT/SVG-after-expand-count"
LOGDIR="$OUTROOT/LOGs"

mkdir -p "$DOTROOT" "$SVGROOT" "$LOGDIR"

if [ ! -d "$MIRDIR" ]; then
  echo "ERROR: MIR directory does not exist:"
  echo "  $MIRDIR"
  exit 1
fi

TOTAL=$(find "$MIRDIR" -type f -name '*.after-expand-count.mir' | wc -l)
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
    "$filled_bar" "$empty_bar" "$percent" "$done" "$total" "$current"
}

count_mir_functions() {
  local mir="$1"
  grep -E '^name:[[:space:]]*' "$mir" | wc -l
}

has_complete_outputs() {
  local mir="$1"
  local dot_dir="$2"
  local svg_dir="$3"

  local func_count=0
  local dot_count=0
  local svg_count=0

  func_count=$(count_mir_functions "$mir")

  if [ -d "$dot_dir" ]; then
    dot_count=$(find "$dot_dir" -maxdepth 1 -type f -name '*.dot' | wc -l)
  fi

  if [ -d "$svg_dir" ]; then
    svg_count=$(find "$svg_dir" -maxdepth 1 -type f -name '*.svg' | wc -l)
  fi

  [ "$func_count" -gt 0 ] &&
  [ "$dot_count" -eq "$func_count" ] &&
  [ "$svg_count" -eq "$func_count" ]
}

echo "MIR directory: $MIRDIR"
echo "Total MIR files: $TOTAL"

if [ "$TOTAL" -eq 0 ]; then
  echo "ERROR: No *.after-expand-count.mir files found in:"
  echo "  $MIRDIR"
  exit 1
fi

while IFS= read -r -d '' mir; do
  rel="${mir#$MIRDIR/}"
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

  if has_complete_outputs "$mir" "$THIS_DOT_DIR" "$THIS_SVG_DIR"; then
    func_count=$(count_mir_functions "$mir")
    dot_count=$(find "$THIS_DOT_DIR" -maxdepth 1 -type f -name '*.dot' 2>/dev/null | wc -l)
    svg_count=$(find "$THIS_SVG_DIR" -maxdepth 1 -type f -name '*.svg' 2>/dev/null | wc -l)

    echo
    echo "SKIP: complete outputs found for $stem"
    echo "      functions=$func_count dots=$dot_count svgs=$svg_count"

    SKIPPED=$((SKIPPED + 1))
    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$stem"

    echo
    continue
  fi

  rm -f "$THIS_DOT_DIR"/*.dot
  rm -f "$THIS_SVG_DIR"/*.svg
  : > "$dot_log"
  : > "$svg_log"

  if ! "$LLC" \
      -mtriple=riscv64-unknown-elf \
      --run-pass=dot-machine-cfg \
      -mcfg-dot-filename-prefix="$THIS_DOT_DIR/cfg" \
      "$mir" \
      > "$dot_log" \
      2>&1; then
    echo
    echo "!! dot-machine-cfg failed for $mir"
    echo "   log: $dot_log"

    FAILED=$((FAILED + 1))
    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$stem"

    echo
    continue
  fi

  for dotfile in "$THIS_DOT_DIR"/*.dot; do
    [ -f "$dotfile" ] || continue

    dotbase="$(basename "$dotfile" .dot)"

    if ! dot -Tsvg "$dotfile" \
        -o "$THIS_SVG_DIR/$dotbase.svg" \
        >> "$svg_log" \
        2>&1; then
      echo "!! dot->svg failed for $dotfile" >> "$svg_log"
    fi
  done

  PROCESSED=$((PROCESSED + 1))
  DONE=$((DONE + 1))
  progress_bar "$DONE" "$TOTAL" "$stem"

  echo
  echo "DONE: $mir"

done < <(find "$MIRDIR" -type f -name '*.after-expand-count.mir' -print0)

echo
echo "All done."
echo "DOT output: $DOTROOT"
echo "SVG output: $SVGROOT"
echo "Logs:       $LOGDIR"
echo
echo "Summary:"
echo "  Total:     $TOTAL"
echo "  Processed: $PROCESSED"
echo "  Skipped:   $SKIPPED"
echo "  Failed:    $FAILED"
