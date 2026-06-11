#!/usr/bin/env python3
"""
Extract, for every function in one or more LRSC JSON dumps, the terminating path
with the greatest distance and write a CSV with:

module,function,longest terminating path in the function,cause,distance,number of loops

Rows with no terminating LR path are skipped from the CSV, but counted in the log.

The "number of loops" column is read directly from the JSON field:

  numberOfLoops

Tie-break rule: if multiple terminating paths have the same max distance within a
function, choose the one with the larger numberOfLoops; if still tied, choose
lexicographically by LR key and path for deterministic output.

Input paths may be either:
  - individual *.lrsc.json files
  - directories containing *.lrsc.json files, searched recursively
"""

import argparse
import csv
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

CSV_COLUMNS = [
    "module",
    "function",
    "longest terminating path in the function",
    "cause",
    "distance",
    "number of loops",
]


def get_number_of_loops(path_obj: Dict[str, Any]) -> int:
    """
    Read numberOfLoops directly from the JSON.

    Example:
      "numberOfLoops": 0
    """
    value = path_obj.get("numberOfLoops", 0)

    if value is None:
        return 0

    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def expand_input_paths(input_paths: List[str]) -> List[Path]:
    json_files: List[Path] = []

    for input_path in input_paths:
        path = Path(input_path).expanduser()

        if path.is_dir():
            json_files.extend(sorted(path.rglob("*.lrsc.json")))
        elif path.is_file():
            json_files.append(path)
        else:
            print(f"WARNING: input path does not exist, skipping: {path}")

    return sorted(set(json_files))


def extract_rows(json_path: Path) -> Tuple[List[List[Any]], int, int]:
    with json_path.open("r", encoding="utf-8") as f:
        data: Dict[str, Any] = json.load(f)

    module = data.get("module") or json_path.name
    functions = data.get("function", {}) or {}

    rows: List[List[Any]] = []
    functions_seen = 0
    functions_skipped_zero = 0

    for function_name, function_obj in functions.items():
        functions_seen += 1

        best_key: Optional[Tuple[int, int, str, str]] = None
        best_row: Optional[Tuple[str, str, int, int]] = None

        lr_paths = function_obj.get("lr_paths", {}) or {}

        for lr_key, lr_obj in lr_paths.items():
            terminating_paths = lr_obj.get("terminating_paths", {}) or {}

            for terminating_path, path_obj in terminating_paths.items():
                distance = int(path_obj.get("distance", 0))
                number_of_loops = get_number_of_loops(path_obj)
                cause = str(path_obj.get("cause", ""))

                candidate_key = (
                    distance,
                    number_of_loops,
                    str(lr_key),
                    str(terminating_path),
                )

                if best_key is None or candidate_key > best_key:
                    best_key = candidate_key
                    best_row = (
                        str(terminating_path),
                        cause,
                        distance,
                        number_of_loops,
                    )

        if best_row is None:
            functions_skipped_zero += 1
            continue

        terminating_path, cause, distance, number_of_loops = best_row

        rows.append(
            [
                module,
                function_name,
                terminating_path,
                cause,
                distance,
                number_of_loops,
            ]
        )

    return rows, functions_seen, functions_skipped_zero


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Extract each function's longest LR terminating path. "
            "The loop count is read from the JSON field numberOfLoops. "
            "Functions with no terminating LR path are skipped. "
            "Input paths may be files or directories."
        )
    )

    parser.add_argument(
        "inputs",
        nargs="+",
        help="Input *.lrsc.json file(s) or directory/directories containing them",
    )

    parser.add_argument(
        "-o",
        "--output",
        required=True,
        help="Output CSV path",
    )

    args = parser.parse_args()

    json_files = expand_input_paths(args.inputs)

    if len(json_files) == 0:
        raise SystemExit("ERROR: no *.lrsc.json files found.")

    all_rows: List[List[Any]] = []
    total_functions_seen = 0
    total_functions_skipped_zero = 0
    files_failed = 0

    for json_file in json_files:
        try:
            rows, functions_seen, functions_skipped_zero = extract_rows(json_file)
        except Exception as e:
            files_failed += 1
            print(f"WARNING: failed to process {json_file}: {e}")
            continue

        all_rows.extend(rows)
        total_functions_seen += functions_seen
        total_functions_skipped_zero += functions_skipped_zero

    with open(args.output, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(CSV_COLUMNS)
        writer.writerows(all_rows)

    rows_written = len(all_rows)

    print("Done.")
    print(f"Input JSON files found: {len(json_files)}")
    print(f"Input JSON files failed: {files_failed}")
    print(f"Input JSON files processed: {len(json_files) - files_failed}")
    print(f"Total functions seen: {total_functions_seen}")
    print(f"Rows written to CSV file: {rows_written}")
    print(f"Functions skipped with no terminating LR path: {total_functions_skipped_zero}")
    print(f"Output CSV: {args.output}")


if __name__ == "__main__":
    main()
