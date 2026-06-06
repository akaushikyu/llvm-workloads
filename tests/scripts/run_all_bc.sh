#!/usr/bin/env bash
set -u

# Directory where this script physically lives.
# Helper scripts are loaded from here.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MCFG=0

usage() {
  echo "Usage:"
  echo "  $(basename "$0") [-mcfg]"
  echo
  echo "Options:"
  echo "  -mcfg    After LRSC CSV generation, run mcfg-for-outTest.sh on outTest/"
  echo "  -h       Show this help message"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -mcfg|--mcfg)
      MCFG=1
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

LLVM_ROOT="${LLVM_ROOT:-$HOME/llvm-repos/test/llvm-project}"
LLVM_BUILD="${LLVM_BUILD:-$LLVM_ROOT/build}"

LLVM_DIS="$LLVM_BUILD/bin/llvm-dis"
LLC="$LLVM_BUILD/bin/llc"

# Directory where you run this script from.
# .bc files are searched from here.
ROOTDIR="$(pwd)"
OUTROOT="$ROOTDIR/outTest"

IRDIR="$OUTROOT/IRs"
MIR_BEFORE_DIR="$OUTROOT/MIR-before-bnerd"
MIR_AFTER_DIR="$OUTROOT/MIR-after-expand-count"
JSONDIR="$OUTROOT/LRSC-json"
LOGDIR="$OUTROOT/LOGs"
GREPDIR="$OUTROOT/GREPs"

RESULTDIR="$OUTROOT/FINAL-results"
CFGDIR="$OUTROOT/CFG"

SUMMARY_CSV="$RESULTDIR/lrsc_summary.csv"
LONGEST_CSV="$RESULTDIR/longest_lr_path_loops.csv"

PARSE_SCRIPT="$SCRIPT_DIR/parse_lrsc_json.py"
LONGEST_SCRIPT="$SCRIPT_DIR/extract_longest_lr_path_loops.py"
MCFG_SCRIPT="$SCRIPT_DIR/mcfg-for-outTest.sh"

MCFG_LOG="$RESULTDIR/mcfg-for-outTest.log"

mkdir -p \
  "$IRDIR" \
  "$MIR_BEFORE_DIR" \
  "$MIR_AFTER_DIR" \
  "$JSONDIR" \
  "$LOGDIR" \
  "$GREPDIR" \
  "$RESULTDIR"

if [ "$MCFG" -eq 1 ]; then
  mkdir -p "$CFGDIR"
fi

TOTAL=$(find . -type f -name '*.bc' | wc -l)
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
    "$filled_bar" "$empty_bar" "$percent" "$done" "$total" "$current"
}

echo "Total .bc files: $TOTAL"
echo "Script dir:       $SCRIPT_DIR"
echo "Run dir:          $ROOTDIR"
echo "Output root:      $OUTROOT"
echo "Final result dir: $RESULTDIR"

if [ "$MCFG" -eq 1 ]; then
  echo "CFG dir:          $CFGDIR"
fi

echo

echo "Helper scripts:"
echo "  $PARSE_SCRIPT"
echo "  $LONGEST_SCRIPT"

if [ "$MCFG" -eq 1 ]; then
  echo "  $MCFG_SCRIPT"
fi

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

if [ "$MCFG" -eq 1 ] && [ ! -f "$MCFG_SCRIPT" ]; then
  echo "ERROR: MCFG script not found:"
  echo "  $MCFG_SCRIPT"
  exit 1
fi

find . -type f -name '*.bc' -print0 | while IFS= read -r -d '' bc; do
  rel="${bc#./}"
  stem="${rel%.bc}"
  safe="${stem//\//_}"
  safe="${safe#.}"

  bc_abs="$ROOTDIR/$rel"

  ll="$IRDIR/$safe.ll"

  mir_before="$MIR_BEFORE_DIR/$safe.before-bnerd.mir"
  mir_after="$MIR_AFTER_DIR/$safe.after-expand-count.mir"

  llvm_dis_log="$LOGDIR/$safe.llvm-dis.log"
  stop_log="$LOGDIR/$safe.stop-before-bnerd.log"
  pass_log="$LOGDIR/$safe.expand-count.log"

  lrsc_grep="$GREPDIR/$safe.after-expand-count.lrsc.txt"
  cfg_grep="$GREPDIR/$safe.after-expand-count.cfg.txt"

  scattered_json="$mir_before.lrscStats.json"

  echo
  echo "==> $bc"
  progress_bar "$DONE" "$TOTAL" "$safe"

  if ! "$LLVM_DIS" "$bc_abs" -o "$ll" > "$llvm_dis_log" 2>&1; then
    echo
    echo "!! llvm-dis failed for $bc"
    echo "   Log: $llvm_dis_log"
    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$safe"
    continue
  fi

  if ! "$LLC" \
      -mtriple=riscv64-unknown-elf \
      -mattr=+a,-zaamo \
      -O2 \
      "$bc_abs" \
      -stop-before=riscv-insert-bnerd-sc \
      -o "$mir_before" \
      > "$stop_log" \
      2>&1; then
    echo
    echo "!! stop-before bnerd failed for $bc"
    echo "   Log: $stop_log"
    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$safe"
    continue
  fi

  rm -f "$scattered_json"
  rm -f "$JSONDIR/$safe".*.lrsc.json

  if ! "$LLC" \
      -mtriple=riscv64-unknown-elf \
      -mattr=+a,-zaamo \
      -run-pass=riscv-expand-inline-asm,riscv-count-lr-sc \
      -verify-machineinstrs \
      -dump-insn-stats-json \
      "$mir_before" \
      -o "$mir_after" \
      > /dev/null \
      2> "$pass_log"; then
    echo
    echo "!! expand+count failed for $bc"
    echo "   Log: $pass_log"
    DONE=$((DONE + 1))
    progress_bar "$DONE" "$TOTAL" "$safe"
    continue
  fi

  if [ -f "$scattered_json" ]; then
    python3 - "$scattered_json" "$JSONDIR" "$safe" <<'PY'
import json
import re
import sys
import hashlib
from pathlib import Path

input_json = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
module_name = sys.argv[3]

MAX_FILENAME_LEN = 220
EXT = ".lrsc.json"

def safe_filename(s):
    s = s.replace("/", "_")
    s = s.replace("\\", "_")
    s = s.replace(" ", "_")
    s = re.sub(r"[^A-Za-z0-9_.$@+-]", "_", s)
    return s

def shorten(s, max_len):
    if len(s) <= max_len:
        return s

    h = hashlib.sha1(s.encode("utf-8")).hexdigest()[:12]
    keep = max_len - len(h) - 1

    if keep < 8:
        return h

    return s[:keep] + "-" + h

with input_json.open("r", errors="replace") as f:
    data = json.load(f)

functions = data.get("function", {})

module_safe = safe_filename(module_name)
module_part = shorten(module_safe, 80)

for func_name, func_stats in functions.items():
    func_safe = safe_filename(func_name)

    max_func_len = MAX_FILENAME_LEN - len(module_part) - len(EXT) - 1
    func_part = shorten(func_safe, max_func_len)

    out_name = f"{module_part}.{func_part}{EXT}"

    if len(out_name) > MAX_FILENAME_LEN:
        module_part_short = shorten(module_safe, 40)
        max_func_len = MAX_FILENAME_LEN - len(module_part_short) - len(EXT) - 1
        func_part = shorten(func_safe, max_func_len)
        out_name = f"{module_part_short}.{func_part}{EXT}"

    out_path = output_dir / out_name

    one_func_json = {
        "module": module_name,
        "function": {
            func_name: func_stats
        }
    }

    with out_path.open("w") as out:
        json.dump(one_func_json, out, indent=2)

input_json.unlink()
PY
  else
    echo "!! expected LRSC JSON not found: $scattered_json" >> "$pass_log"
  fi

  grep -nE 'LR_|SC_' "$mir_after" > "$lrsc_grep" 2>/dev/null || true
  grep -nE '^bb\.|^[[:space:]]*successors:' "$mir_after" > "$cfg_grep" 2>/dev/null || true

  DONE=$((DONE + 1))
  progress_bar "$DONE" "$TOTAL" "$safe"

  echo
  echo "DONE: $bc"
done

echo
echo "Finished LLVM pass run."
echo "Generated JSON dir:"
echo "  $JSONDIR"
echo

echo "Running post-processing scripts..."

echo
echo "Generating LRSC summary CSV..."
echo "  Input:  $JSONDIR"
echo "  Output: $SUMMARY_CSV"

if ! python3 "$PARSE_SCRIPT" "$JSONDIR" "$SUMMARY_CSV" > "$RESULTDIR/parse_lrsc_json.log" 2>&1; then
  echo "ERROR: parse_lrsc_json.py failed."
  echo "Check log:"
  echo "  $RESULTDIR/parse_lrsc_json.log"
  exit 1
fi

echo
echo "Generating longest LR path loop CSV..."
echo "  Input:  $JSONDIR"
echo "  Output: $LONGEST_CSV"

if ! python3 "$LONGEST_SCRIPT" "$JSONDIR" -o "$LONGEST_CSV" > "$RESULTDIR/extract_longest_lr_path_loops.log" 2>&1; then
  echo "ERROR: extract_longest_lr_path_loops.py failed."
  echo "Check log:"
  echo "  $RESULTDIR/extract_longest_lr_path_loops.log"
  exit 1
fi

if [ "$MCFG" -eq 1 ]; then
  echo
  echo "Generating MCFG output..."
  echo "  Script: $MCFG_SCRIPT"
  echo "  Input:  $OUTROOT/"
  echo "  CFG dir: $CFGDIR"
  echo "  Log:    $MCFG_LOG"

  mkdir -p "$CFGDIR"

  if ! (
    cd "$CFGDIR" || exit 1
    bash "$MCFG_SCRIPT" "$OUTROOT/"
  ) > "$MCFG_LOG" 2>&1; then
    echo "ERROR: mcfg-for-outTest.sh failed."
    echo "Check log:"
    echo "  $MCFG_LOG"
    exit 1
  fi
fi

echo
echo "All done."
echo
echo "Final results:"
echo "  $SUMMARY_CSV"
echo "  $LONGEST_CSV"

if [ "$MCFG" -eq 1 ]; then
  echo "  $CFGDIR"
fi

echo
echo "Logs:"
echo "  $RESULTDIR/parse_lrsc_json.log"
echo "  $RESULTDIR/extract_longest_lr_path_loops.log"

if [ "$MCFG" -eq 1 ]; then
  echo "  $MCFG_LOG"
fi
