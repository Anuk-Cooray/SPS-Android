"""
Smart Parking System (SLIIT J26-IT-335)
YAML Parser for Evaluation Configuration (Zero External Dependencies)
"""

import re
import json
from pathlib import Path
from typing import Dict, Any

def parse_yaml_value(val_str: str) -> Any:
    val_str = val_str.strip()
    if val_str.startswith('"') and val_str.endswith('"'):
        return val_str[1:-1]
    if val_str.startswith("'") and val_str.endswith("'"):
        return val_str[1:-1]
    if val_str.lower() == "true":
        return True
    if val_str.lower() == "false":
        return False
    if val_str.lower() == "null" or val_str == "~":
        return None
    try:
        if "." in val_str or "e" in val_str.lower():
            return float(val_str)
        return int(val_str)
    except ValueError:
        return val_str

def load_config(config_path: Path) -> Dict[str, Any]:
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Pre-clean comments and join bracketed multi-line arrays
    lines = content.splitlines()
    joined_lines = []
    in_bracket = False
    bracket_buf = ""

    for line in lines:
        stripped = line.split("#")[0].rstrip()
        if not stripped:
            continue
        if "[" in stripped and "]" not in stripped:
            in_bracket = True
            bracket_buf = stripped
            continue
        if in_bracket:
            bracket_buf += " " + stripped.strip()
            if "]" in stripped:
                joined_lines.append(bracket_buf)
                in_bracket = False
                bracket_buf = ""
            continue
        joined_lines.append(stripped)

    # Build nested dict from indentation
    root: Dict[str, Any] = {}
    stack = [(0, root)]

    for line in joined_lines:
        indent = len(line) - len(line.lstrip())
        trimmed = line.strip()

        # Pop stack until parent indent is strictly lower than current indent
        while len(stack) > 1 and stack[-1][0] > indent:
            stack.pop()

        parent = stack[-1][1]

        if ":" in trimmed:
            parts = trimmed.split(":", 1)
            key = parts[0].strip()
            val_part = parts[1].strip()

            if not val_part:
                # New nested dict
                new_dict: Dict[str, Any] = {}
                parent[key] = new_dict
                stack.append((indent + 1, new_dict))
            elif val_part.startswith("[") and val_part.endswith("]"):
                # Inline array
                raw_items = val_part[1:-1].split(",")
                arr = [parse_yaml_value(x) for x in raw_items if x.strip()]
                parent[key] = arr
            else:
                parent[key] = parse_yaml_value(val_part)

    return root

if __name__ == "__main__":
    cfg_file = Path(__file__).parent / "config.yaml"
    cfg = load_config(cfg_file)
    print("Successfully parsed config:")
    print("Lot ID:", cfg["facility"]["lot_id"])
    print("Total slots:", cfg["facility"]["total_slots"])
    print("Seeds count:", cfg["simulation"]["seeds_count"])
    print("Hourly profile length:", len(cfg["demand"]["hourly_profile"]))
