# A collection of LLVM bitcodes for testing

This repository holds a collection of workloads for testing and analyzing with custom `llc`.
These workloads can be programs and LLVM bitcodes.

## LLVM Bitcodes
Using the `wllvm` framework available [here](https://github.com/travitch/whole-program-llvm) to create bitcodes of large programs.

## Workloads
- [llvm-libc](tests/bitcodes/llvm-libc.bca)
    - LLVM libc 
    - To extract the individual bitcode files, execute `llvm-ar x llvm-libc.bca`. 
    - The individual bitcode files are hidden. To expose them, execute `ls -la`

- [musl-libc](tests/bitodes/musl-libc.bca)
    - Use WLLVM to generate bitcode
    - Run the following command to configure and build the `musl-libc`:
        ```
         WLLVM_CONFIGURE_ONLY=1 CC="wllvm --target=riscv64-unknown-linux-musl -march=rv64gc -mabi=lp64d -fuse-ld=lld" \
         AR="/opt/riscv-llvm/bin/llvm-ar" RANLIB="/opt/riscv-llvm/bin/llvm-ranlib" \
         ./configure --prefix=/home/kaushika/REPOS/libc-versions/musl-1.2.6/build/ --target=riscv64-unknown-linux-musl
        ```
    - Followed by `make`
    - To package the bitcode archive of `musl-libc`, navigate to `lib` directory and run `extract-bc -a /opt/riscv-llvm/bin/llvm-ar libc.a`. This will generate a `libc.bca`
    - To extract the individual bitcode files, execute `llvm-ar x musl-libc.bca`. 
- [uclibc](tests/bits/uclibc-libc.bca)
   - First install the linux cross headers for riscv -- `sudo apt install gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu linux-libc-dev-riscv64-cross`
   - Clone the uclibc-ng repo and run the following command to configure uclibc for RISC-V: 'make menuconfig', select `riscv64` in target architecture.
   - Open the `.config` file, and update the `KERNEL_HEADERS=` to `KERNEL_HEADERS=/usr/riscv64-linux-gnu/include`, which is the location of the riscv linux kernel headers 
   - To compile uclibc with LLVM, a few changes a required. These changes do the following: (1) convert nested functions that are unacceptable by clang but fine by gcc, and (2) remove GNU assembler directive. Apply the `clang-uclibc.patch` using `git apply clang-uclibc.patch`.
   - Before using `wllvm`, first compile uclibc using `clang` to generate the `bits/` include files by running
   ```
    make VERBOSE=1  CROSS_COMPILE=riscv64-linux-gnu- \
    CC="clang --target=riscv64-linux-gnu" \
    AR=/opt/riscv-llvm/bin/llvm-ar   \
    RANLIB=/opt/riscv-llvm/bin/llvm-ranlib \
    NM=/opt/riscv-llvm/bin/llvm-nm \
    STRIP=llvm-strip
   ```
   - Once the `include/bits/` directory is created, we can run `wllvm` by changing `CC="clang..` to `CC="wllvm..`
   - Follow the same steps for the above libc to package the bitcode archive and extract the individual bitcode files
# Script Usage

## `tests/scripts/run_all_bc.sh`

### What it does

`run_all_bc.sh` is the main script that runs the full bitcode analysis pipeline over all `.bc` files in the current directory tree.

You must run this script from the directory where the `.bc` files are present, or from a parent directory that contains them.

It finds `.bc` files recursively, converts them to LLVM IR, runs the required RISC-V LLVM passes, generates LR/SC JSON data, and writes final CSV summaries.

It can also optionally generate machine CFG output.

### Usage

```bash
cd <directory-containing-bc-files>
bash tests/scripts/run_all_bc.sh
```

Or, if the script is outside the current directory, use the correct relative path:

```bash
cd <directory-containing-bc-files>
bash /path/to/tests/scripts/run_all_bc.sh
```

Generate machine CFG output:

```bash
cd <directory-containing-bc-files>
bash /path/to/tests/scripts/run_all_bc.sh -mcfg
```

Show help:

```bash
bash tests/scripts/run_all_bc.sh -h
```

### Requirements

The script expects LLVM tools at:

```bash
$HOME/llvm-repos/test/llvm-project/build/bin/llvm-dis
$HOME/llvm-repos/test/llvm-project/build/bin/llc
```

You can override the default LLVM location by setting `LLVM_ROOT`:

```bash
export LLVM_ROOT=/path/to/llvm-project
```

By default, the script expects the LLVM build directory to be:

```bash
$LLVM_ROOT/build
```

If your LLVM build directory is somewhere else, set `LLVM_BUILD` directly:

```bash
export LLVM_BUILD=/path/to/llvm-build
```

Example:

```bash
export LLVM_ROOT=$HOME/src/llvm-project
export LLVM_BUILD=$LLVM_ROOT/build
cd <directory-containing-bc-files>
bash /path/to/tests/scripts/run_all_bc.sh
```

It also depends on:

```bash
tests/scripts/parse_lrsc_json.py
tests/scripts/extract_longest_lr_path_loops.py
tests/scripts/mcfg-for-outTest.sh
```

If `-mcfg` is used, Graphviz must be installed. The script uses Graphviz’s `dot` command to convert machine CFG `.dot` files into `.svg` images.

Check whether it is installed with:

```bash
dot -V
```

### Outputs

All outputs are written under:

```bash
outTest/
```

Important output paths:

```bash
outTest/IRs/
outTest/MIR-before-bnerd/
outTest/MIR-after-expand-count/
outTest/LRSC-json/
outTest/LOGs/
outTest/GREPs/
outTest/FINAL-results/
```

Final CSV files:

```bash
outTest/FINAL-results/lrsc_summary.csv
outTest/FINAL-results/longest_lr_path_loops.csv
```

---

## `tests/scripts/parse_lrsc_json.py`

### Purpose

`parse_lrsc_json.py` parses LR/SC JSON files and creates a CSV summary showing LR/SC counts per function.

It is intended to post-process JSON output produced by the `riscv-count-lr-sc` pass.

### Usage

```bash
python3 tests/scripts/parse_lrsc_json.py <json_dir_or_file> <output.csv>
```

Example:

```bash
python3 tests/scripts/parse_lrsc_json.py \
  outTest/LRSC-json \
  outTest/FINAL-results/lrsc_summary.csv
```

### Input

The first argument can be either:

```bash
<single-json-file>
```

or:

```bash
<directory-containing-json-files>
```

If a directory is provided, the script recursively searches for:

```bash
*.json
```

### Output

The script writes a CSV with the following columns:

```csv
module,function,lrsc_pairs,total_loop_seq_conditional_lrsc_occurrences,total_loop_seq_unconditional_lrsc_occurrences
```

### Capabilities

- Processes a single JSON file or a directory tree of JSON files.
- Extracts LR/SC statistics per function.
- Converts total LR/SC occurrence counts into LR/SC pair counts.
- Skips functions with no useful LR/SC data.
- Continues processing even if one JSON file fails.
- Produces a CSV suitable for spreadsheet analysis or later scripting.

---

## `tests/scripts/extract_longest_lr_path_loops.py`

### Purpose

`extract_longest_lr_path_loops.py` extracts the longest terminating LR path for each function from LR/SC JSON files.

It writes a CSV showing the selected path, termination cause, distance, and number of loops.

### Usage

```bash
python3 tests/scripts/extract_longest_lr_path_loops.py <inputs...> -o <output.csv>
```

Example:

```bash
python3 tests/scripts/extract_longest_lr_path_loops.py \
  outTest/LRSC-json \
  -o outTest/FINAL-results/longest_lr_path_loops.csv
```

Multiple inputs are supported:

```bash
python3 tests/scripts/extract_longest_lr_path_loops.py \
  outTest/LRSC-json \
  extra-results/module.lrsc.json \
  -o longest_lr_path_loops.csv
```

### Input

Inputs may be files or directories.

The script looks for:

```bash
*.lrsc.json
```

Directories are searched recursively.

### Output

The script writes a CSV with these columns:

```csv
module,function,longest terminating path in the function,cause,distance,number of loops
```

### Capabilities

- Processes one or more LR/SC JSON files.
- Recursively scans directories.
- Finds the longest terminating LR path per function.
- Reports the path’s termination cause.
- Reports path distance.
- Reports number of loops.
- Skips functions with no terminating LR path.
- Uses deterministic tie-breaking.
- Continues processing other files if one file fails.
- Prints a summary after completion.

### Selection Rule

For each function, the script selects the terminating LR path with the greatest distance.

Tie-breaking is deterministic:

1. Larger distance
2. Larger number of loops
3. Lexicographically larger LR key
4. Lexicographically larger terminating path name

---

## `tests/scripts/mcfg-for-outTest.sh`

### What it does

`mcfg-for-outTest.sh` generates machine CFG DOT files and SVG renderings from MIR files produced by `run_all_bc.sh`.

It runs LLVM’s `dot-machine-cfg` pass on `.after-expand-count.mir` files and converts the resulting DOT files to SVG using Graphviz.

This script is normally run automatically when `run_all_bc.sh` is executed with the `-mcfg` option.

### Usage

```bash
bash tests/scripts/mcfg-for-outTest.sh [MIR-directory]
```

If no MIR directory is provided, the script defaults to:

```bash
outTest/MIR-after-expand-count
```

Example:

```bash
bash tests/scripts/mcfg-for-outTest.sh outTest/MIR-after-expand-count
```

### Requirements

LLVM `llc` is expected at:

```bash
$HOME/llvm-repos/test/llvm-project/build/bin/llc
```

You can override the default LLVM location by setting `LLVM_ROOT`:

```bash
export LLVM_ROOT=/path/to/llvm-project
```

By default, the script expects the LLVM build directory to be:

```bash
$LLVM_ROOT/build
```

If your LLVM build directory is somewhere else, set `LLVM_BUILD` directly:

```bash
export LLVM_BUILD=/path/to/llvm-build
```

Example:

```bash
export LLVM_ROOT=$HOME/src/llvm-project
export LLVM_BUILD=$LLVM_ROOT/build
bash tests/scripts/mcfg-for-outTest.sh outTest/MIR-after-expand-count
```

Graphviz is also required:

```bash
dot
```

### Input

The input directory should contain MIR files named:

```bash
*.after-expand-count.mir
```

These files are normally generated by:

```bash
tests/scripts/run_all_bc.sh
```

### Output

Output is written under:

```bash
outTest/
```

Main output directories:

```bash
outTest/DOT-after-expand-count/
outTest/SVG-after-expand-count/
outTest/LOGs/
```
