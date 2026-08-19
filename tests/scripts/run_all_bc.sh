#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MCFG=0
BNERD=0

usage() {
  echo "Usage:"
  echo "  $(basename "$0") [+mcfg] [+bnerd]"
  echo
  echo "Options:"
  echo "  -mcfg    Run LLVM dot-machine-cfg and render the generated DOT files to SVG"
  echo "  +bnerd   Run the riscv-insert-bnerd-sc pass"
  echo "  -h       Show this help message"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    +mcfg|--mcfg)
      MCFG=1
      shift
      ;;
    +bnerd)
      BNERD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

LLVM_ROOT="${LLVM_ROOT:-$HOME/llvm-repos/test/llvm-project-other}"
LLVM_BUILD="${LLVM_BUILD:-$LLVM_ROOT/build}"

LLVM_DIS="$LLVM_BUILD/bin/llvm-dis"
LLC="$LLVM_BUILD/bin/llc"

ROOTDIR="$(pwd)"
OUTROOT="$ROOTDIR/outTest"

IRDIR="$OUTROOT/IRs"

if [ "$BNERD" -eq 1 ]; then
  MIR_AFTER_DIR="$OUTROOT/MIR-after-bnerd"
  ASMDIR="$OUTROOT/ASM-after-bnerd"
  OUTPUT_STAGE="after-bnerd"
else
  MIR_AFTER_DIR="$OUTROOT/MIR-after-expand-count"
  ASMDIR="$OUTROOT/ASM-after-expand-count"
  OUTPUT_STAGE="after-expand-count"
fi

JSONDIR="$OUTROOT/LRSC-json"
LOGDIR="$OUTROOT/LOGs"
GREPDIR="$OUTROOT/GREPs"

# Staged symbolic links keep generated .lrscStats.json files inside outTest.
BC_STAGE_DIR="$OUTROOT/BC-input"

RESULTDIR="$OUTROOT/FINAL-results"
CFGDIR="$OUTROOT/CFG"
MCFG_DOT_DIR="$CFGDIR/DOT-after-expand-count"
MCFG_SVG_DIR="$CFGDIR/SVG-after-expand-count"

SUMMARY_CSV="$RESULTDIR/lrsc_summary.csv"
LONGEST_CSV="$RESULTDIR/longest_lr_path_loops.csv"

PARSE_SCRIPT="$SCRIPT_DIR/parse_lrsc_json.py"
LONGEST_SCRIPT="$SCRIPT_DIR/extract_longest_lr_path_loops.py"

# Using an array prevents accidental option concatenation such as:
# -mattr=+a,-zaamo,+bnerd-O2
LLC_COMMON_ARGS=(
  -mtriple=riscv64-unknown-elf
  -mattr=+a,-zaamo,+bnerd
  -O2
)

mkdir -p \
  "$IRDIR" \
  "$MIR_AFTER_DIR" \
  "$ASMDIR" \
  "$JSONDIR" \
  "$LOGDIR" \
  "$GREPDIR" \
  "$BC_STAGE_DIR" \
  "$RESULTDIR"

if [ "$MCFG" -eq 1 ]; then
  mkdir -p "$CFGDIR" "$MCFG_DOT_DIR" "$MCFG_SVG_DIR"
fi

# Older versions of this script produced a redundant MIR-before-bnerd checkpoint.
rm -rf -- "$OUTROOT/MIR-before-bnerd"

BC_FILES=()

while IFS= read -r -d '' bc; do
  BC_FILES+=("$bc")
done < <(
  find . \
    -path './outTest' -prune \
    -o -type f -name '*.bc' -print0
)

TOTAL=${#BC_FILES[@]}
DONE=0

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

echo "Total .bc files: $TOTAL"
echo "Script dir:       $SCRIPT_DIR"
echo "Run dir:          $ROOTDIR"
echo "Output root:      $OUTROOT"
echo "Final result dir: $RESULTDIR"

if [ "$BNERD" -eq 1 ]; then
  echo "Bnerd pass:       enabled"
else
  echo "Bnerd pass:       disabled"
fi

if [ "$MCFG" -eq 1 ]; then
  echo "CFG dir:          $CFGDIR"
fi

echo
echo "Helper scripts:"
echo "  $PARSE_SCRIPT"
echo "  $LONGEST_SCRIPT"

echo

if [ ! -x "$LLVM_DIS" ]; then
  echo "ERROR: llvm-dis not found or not executable:"
  echo "  $LLVM_DIS"
  exit 1
fi

if [ ! -x "$LLC" ]; then
  echo "ERROR: llc not found or not executable:"
  echo "  $LLC"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 was not found."
  exit 1
fi

if [ "$MCFG" -eq 1 ] && ! command -v dot >/dev/null 2>&1; then
  echo "ERROR: Graphviz 'dot' was not found."
  exit 1
fi

if [ ! -f "$PARSE_SCRIPT" ]; then
  echo "ERROR: parse script not found:"
  echo "  $PARSE_SCRIPT"
  exit 1
fi

if [ ! -f "$LONGEST_SCRIPT" ]; then
  echo "ERROR: longest-path script not found:"
  echo "  $LONGEST_SCRIPT"
  exit 1
fi


if [ "$TOTAL" -eq 0 ]; then
  echo "No .bc files were found."
  exit 0
fi

for bc in "${BC_FILES[@]}"; do
  rel="${bc#./}"
  stem="${rel%.bc}"

  safe="${stem//\//_}"
  safe="${safe#.}"

  bc_abs="$ROOTDIR/$rel"

  ll="$IRDIR/$safe.ll"

  mir_after="$MIR_AFTER_DIR/$safe.$OUTPUT_STAGE.mir"
  asm_after="$ASMDIR/$safe.$OUTPUT_STAGE.s"

  llvm_dis_log="$LOGDIR/$safe.llvm-dis.log"
  pass_log="$LOGDIR/$safe.expand-count.log"
  asm_log="$LOGDIR/$safe.asm-from-bc.log"

  lrsc_grep="$GREPDIR/$safe.after-expand-count.lrsc.txt"
  cfg_grep="$GREPDIR/$safe.after-expand-count.cfg.txt"

  THIS_DOT_DIR="$MCFG_DOT_DIR/$safe"
  THIS_SVG_DIR="$MCFG_SVG_DIR/$safe"
  dot_log="$LOGDIR/$safe.dot-machine-cfg.log"
  svg_log="$LOGDIR/$safe.dot-to-svg.log"

  # Pass the BC file through an outTest-local symbolic link.
  # This causes the custom JSON output to stay under outTest.
  staged_bc="$BC_STAGE_DIR/$safe.bc"
  staged_json="$staged_bc.lrscStats.json"

  echo
  echo "==> $bc"
  progress_bar "$DONE" "$TOTAL" "$safe"

  if ! "$LLVM_DIS" \
      "$bc_abs" \
      -o "$ll" \
      > "$llvm_dis_log" \
      2>&1; then
    echo
    echo "!! llvm-dis failed for $bc"
    echo "   Log: $llvm_dis_log"

    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$safe"
    continue
  fi

  rm -f -- "$staged_bc" "$staged_json"
  rm -f -- "$JSONDIR/$safe".*.lrsc.json

  if ! ln -s -- "$bc_abs" "$staged_bc"; then
    echo
    echo "!! could not create staged BC link for $bc"
    echo "   Link: $staged_bc"

    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$safe"
    continue
  fi

  # Run the custom passes through the normal code-generation pipeline.
  #
  # Required pipeline order:
  #
  #   riscv-expand-inline-asm
  #   riscv-count-lr-sc
  #   riscv-insert-bnerd-sc
  #
  # Keep this as the single MIR checkpoint used for inspection.
  #
  # When -mcfg is enabled, dot-machine-cfg is already inserted into the live
  # RISC-V pass pipeline immediately after riscv-count-lr-sc. Stop after the
  # printer instead of after the count pass so the printer actually runs.
  PASS_STOP_ARGS=(-stop-after=riscv-count-lr-sc)
  LIVE_MCFG_ARGS=()
  BNERD_ARGS=()

  if [ "$BNERD" -eq 1 ]; then
    BNERD_ARGS=(-riscv-run-bnerd)
    PASS_STOP_ARGS=(-stop-after=dot-machine-cfg)
  fi

  if [ "$MCFG" -eq 1 ]; then
    rm -rf -- "$THIS_DOT_DIR" "$THIS_SVG_DIR"
    mkdir -p "$THIS_DOT_DIR" "$THIS_SVG_DIR"

    # If Bnerd is disabled, stop after the CFG printer so it runs.
    # If Bnerd is enabled, continue through riscv-insert-bnerd-sc.
    if [ "$BNERD" -eq 0 ]; then
      PASS_STOP_ARGS=(-stop-after=dot-machine-cfg)
    fi

    LIVE_MCFG_ARGS=(
      -riscv-dump-lrsc-mcfg
      -mcfg-dot-filename-prefix="$THIS_DOT_DIR/cfg"
    )
  fi

  if ! "$LLC" \
      "${LLC_COMMON_ARGS[@]}" \
      -verify-machineinstrs \
      -dump-insn-stats-json \
      -debug-only=riscv-expand-inline-asm \
      "${BNERD_ARGS[@]}" \
      "${LIVE_MCFG_ARGS[@]}" \
      "${PASS_STOP_ARGS[@]}" \
      "$staged_bc" \
      -o "$mir_after" \
      > "$pass_log" \
      2>&1; then
    echo
    echo "!! expand+count failed for $bc"
    echo "   Log: $pass_log"

    rm -f -- "$staged_bc"

    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$safe"
    continue
  fi

  # Keep the saved MIR untouched; it is for inspection only.

  if [ "$MCFG" -eq 1 ]; then
    svg_failed=0
    : > "$svg_log"

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
        svg_failed=1
      fi
    done

    if [ "$svg_failed" -ne 0 ]; then
      echo
      echo "!! one or more SVG conversions failed for:"
      echo "   $bc"
      echo "   Log: $svg_log"
    fi

    # dot-machine-cfg writes diagnostics to stderr, which is part of pass_log
    # because it ran in the same llc invocation.
    cp -- "$pass_log" "$dot_log" 2>/dev/null || true
  fi

  # Generate assembly directly from BC so the saved MIR never has to be reparsed.
  if ! "$LLC" \
      "${LLC_COMMON_ARGS[@]}" \
      -verify-machineinstrs \
      "${BNERD_ARGS[@]}" \
      "$staged_bc" \
      -o "$asm_after" \
      > "$asm_log" \
      2>&1; then
    echo
    echo "!! assembly generation from BC failed for $bc"
    echo "   BC:  $staged_bc"
    echo "   Log: $asm_log"

    rm -f -- "$staged_bc"

    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$safe"
    continue
  fi

  # Normally the JSON file is based on the input filename.
  # These fallback paths also cover implementations that use the output
  # filename or resolve the symbolic link before creating the JSON.
  json_candidates=(
    "$staged_json"
    "$bc_abs.lrscStats.json"
    "$mir_after.lrscStats.json"
  )

  scattered_json=""

  for candidate in "${json_candidates[@]}"; do
    if [ -f "$candidate" ]; then
      scattered_json="$candidate"
      break
    fi
  done

  if [ -n "$scattered_json" ]; then
    python3 - "$scattered_json" "$JSONDIR" "$safe" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

input_json = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
module_name = sys.argv[3]

MAX_FILENAME_LEN = 220
EXT = ".lrsc.json"


def safe_filename(value):
    value = value.replace("/", "_")
    value = value.replace("\\", "_")
    value = value.replace(" ", "_")
    value = re.sub(r"[^A-Za-z0-9_.$@+-]", "_", value)
    return value


def shorten(value, max_len):
    if len(value) <= max_len:
        return value

    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:12]
    keep = max_len - len(digest) - 1

    if keep < 8:
        return digest

    return value[:keep] + "-" + digest


with input_json.open("r", errors="replace") as input_file:
    data = json.load(input_file)

functions = data.get("function", {})

module_safe = safe_filename(module_name)
module_part = shorten(module_safe, 80)

for func_name, func_stats in functions.items():
    func_safe = safe_filename(func_name)

    max_func_len = (
        MAX_FILENAME_LEN
        - len(module_part)
        - len(EXT)
        - 1
    )

    func_part = shorten(func_safe, max_func_len)
    out_name = f"{module_part}.{func_part}{EXT}"

    if len(out_name) > MAX_FILENAME_LEN:
        module_part_short = shorten(module_safe, 40)

        max_func_len = (
            MAX_FILENAME_LEN
            - len(module_part_short)
            - len(EXT)
            - 1
        )

        func_part = shorten(func_safe, max_func_len)
        out_name = f"{module_part_short}.{func_part}{EXT}"

    out_path = output_dir / out_name

    one_func_json = {
        "module": module_name,
        "function": {
            func_name: func_stats
        }
    }

    with out_path.open("w") as output_file:
        json.dump(one_func_json, output_file, indent=2)

input_json.unlink()
PY

    if [ "$?" -ne 0 ]; then
      echo "!! JSON splitting failed for $bc" >> "$pass_log"
    fi
  else
    echo "!! expected LRSC JSON was not found" >> "$pass_log"
    echo "   Checked:" >> "$pass_log"

    for candidate in "${json_candidates[@]}"; do
      echo "     $candidate" >> "$pass_log"
    done
  fi

  rm -f -- "$staged_bc"

  grep -nE \
    'LR_|SC_' \
    "$mir_after" \
    > "$lrsc_grep" \
    2>/dev/null || true

  grep -nE \
    '^bb\.|^[[:space:]]*successors:' \
    "$mir_after" \
    > "$cfg_grep" \
    2>/dev/null || true

  DONE=$((DONE + 1))
  progress_bar "$DONE" "$TOTAL" "$safe"

  echo
  echo "DONE: $bc"
done

echo
echo "Finished LLVM pass run."
echo "Generated MIR dir:"
echo "  $MIR_AFTER_DIR"
echo "Generated ASM dir:"
echo "  $ASMDIR"
echo "Generated JSON dir:"
echo "  $JSONDIR"
echo

echo "Running post-processing scripts..."

echo
echo "Generating LRSC summary CSV..."
echo "  Input:  $JSONDIR"
echo "  Output: $SUMMARY_CSV"

if ! python3 \
    "$PARSE_SCRIPT" \
    "$JSONDIR" \
    "$SUMMARY_CSV" \
    > "$RESULTDIR/parse_lrsc_json.log" \
    2>&1; then
  echo "ERROR: parse_lrsc_json.py failed."
  echo "Check log:"
  echo "  $RESULTDIR/parse_lrsc_json.log"
  exit 1
fi

echo
echo "Generating longest LR path loop CSV..."
echo "  Input:  $JSONDIR"
echo "  Output: $LONGEST_CSV"

if ! python3 \
    "$LONGEST_SCRIPT" \
    "$JSONDIR" \
    -o "$LONGEST_CSV" \
    > "$RESULTDIR/extract_longest_lr_path_loops.log" \
    2>&1; then
  echo "ERROR: extract_longest_lr_path_loops.py failed."
  echo "Check log:"
  echo "  $RESULTDIR/extract_longest_lr_path_loops.log"
  exit 1
fi

echo
echo "All done."
echo
echo "Final results:"
echo "  $SUMMARY_CSV"
echo "  $LONGEST_CSV"
echo "  $MIR_AFTER_DIR"
echo "  $ASMDIR"

if [ "$MCFG" -eq 1 ]; then
  echo "  $MCFG_DOT_DIR"
  echo "  $MCFG_SVG_DIR"
fi

echo
echo "Logs:"
echo "  $RESULTDIR/parse_lrsc_json.log"
echo "  $RESULTDIR/extract_longest_lr_path_loops.log"