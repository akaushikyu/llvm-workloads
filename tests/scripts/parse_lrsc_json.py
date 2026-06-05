#!/usr/bin/env python3

import csv
import json
import sys
from pathlib import Path


def module_name_from_json_path(json_path: Path) -> str:
    name = json_path.name

    if name.endswith(".lrscStats.json"):
        return name[:-len(".lrscStats.json")]

    if name.endswith(".json"):
        return name[:-len(".json")]

    return json_path.stem


def load_json_file(json_path: Path):
    text = json_path.read_text(errors="replace").strip()

    if not text:
        return None

    return json.loads(text)


def parse_lrsc_json_file(json_path: Path):
    module_name = module_name_from_json_path(json_path)
    data = load_json_file(json_path)

    if data is None:
        return []

    # Your real format:
    # {
    #   "function": {
    #     "func_name": {
    #       "total_lrsc_occurrences": N,
    #       ...
    #     }
    #   }
    # }
    if "function" not in data or not isinstance(data["function"], dict):
        raise ValueError(f"Missing top-level 'function' object in {json_path}")

    functions = data["function"]

    rows = []

    for function_name, function_stats in functions.items():
        if not isinstance(function_stats, dict):
            continue

        total_lrsc_occurrences = int(function_stats.get("total_lrsc_occurrences", 0))
        conditional_count = int(function_stats.get(
            "total_loop_seq_conditional_lrsc_occurrences", 0
        ))
        unconditional_count = int(function_stats.get(
            "total_loop_seq_unconditional_lrsc_occurrences", 0
        ))

        lrsc_pairs = total_lrsc_occurrences // 2

        # Skip functions where all useful counts are zero.
        if lrsc_pairs == 0 and conditional_count == 0 and unconditional_count == 0:
            continue

        rows.append({
            "module": module_name,
            "function": function_name,
            "lrsc_pairs": lrsc_pairs,
            "total_loop_seq_conditional_lrsc_occurrences": conditional_count,
            "total_loop_seq_unconditional_lrsc_occurrences": unconditional_count,
        })

    return rows


def main():
    if len(sys.argv) != 3:
        print("usage: parse_lrsc_json.py <json_dir_or_file> <output.csv>", file=sys.stderr)
        print("example: ./parse_lrsc_json.py outTest/lrscStats lrsc_summary.csv", file=sys.stderr)
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_csv = Path(sys.argv[2])

    if input_path.is_file():
        json_files = [input_path]
    else:
        json_files = sorted(input_path.rglob("*.json"))

    all_rows = []

    for json_file in json_files:
        try:
            all_rows.extend(parse_lrsc_json_file(json_file))
        except Exception as e:
            print(f"Skipping {json_file}: {e}", file=sys.stderr)

    with output_csv.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "module",
                "function",
                "lrsc_pairs",
                "total_loop_seq_conditional_lrsc_occurrences",
                "total_loop_seq_unconditional_lrsc_occurrences",
            ],
        )
        writer.writeheader()
        writer.writerows(all_rows)

    print(f"Wrote {len(all_rows)} rows to {output_csv}")


if __name__ == "__main__":
    main()
