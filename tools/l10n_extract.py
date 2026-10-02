#!/usr/bin/env python3
"""Extract user-facing string keys from the iOS sources (SwiftUI LocalizedStringKey semantics).

Interpolations are converted the way SwiftUI/Foundation build localization keys:
  Int-like  -> %lld, everything else -> %@, literal '%' -> '%%'.
Prints JSON {"app": [...keys], "widget": [...keys]}.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "ios"

# Calls whose first string-literal argument is localizable.
CALLS = [
    r"Text", r"Label", r"Button", r"Section", r"Toggle", r"Picker", r"LabeledContent", r"Link", r"navigationTitle",
    r"alert", r"confirmationDialog", r"ContentUnavailableView", r"TextField", r"String\(localized", r"quickLink",
    r"MetricTile\(title", r"InfoRow\(title", r"SetupStep\(number: \d+, title", r"ValueLine\(icon: \"[^\"]*\", value: [^\n]*?label",
    r"Metric\(icon: \"[^\"]*\", value: [^\n]*?label", r"title", r"body", r"configurationDisplayName", r"description",
    r"IntentDescription", r"shortTitle", r"accessibilityLabel\(Text", r"accessibilityValue\(Text", r"prompt: Text",
]

INT_HINTS = ("Int(", "count", "Sessions", "hours", "minutes", "number", "remainingFree", "freeSessionLimit", "min(model")

LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def to_key(lit: str) -> str:
    out = []
    i = 0
    while i < len(lit):
        if lit.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(lit) and depth:
                depth += lit[j] == "("
                depth -= lit[j] == ")"
                j += 1
            expr = lit[i + 2 : j - 1]
            out.append("%lld" if any(h in expr for h in INT_HINTS) else "%@")
            i = j
            continue
        ch = lit[i]
        if ch == "%":
            out.append("%%")
        elif lit.startswith("\\n", i):
            out.append("\n")
            i += 1
        elif lit.startswith('\\"', i):
            out.append('"')
            i += 1
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def extract(paths):
    keys = set()
    pattern = re.compile(r"(?:" + "|".join(CALLS) + r")\s*[:(]?\s*\(?\s*(?:LocalizedStringResource\()?\"")
    for p in paths:
        src = p.read_text()
        for m in pattern.finditer(src):
            start = m.end() - 1
            lm = LITERAL.match(src, start)
            if lm:
                keys.add(to_key(lm.group(1)))
        # ternary / tuple / array literals of LocalizedStringKey (benefits, pages)
        for m in re.finditer(r'\("[a-z0-9.]+", "([^"]+)"\)', src):
            keys.add(to_key(m.group(1)))
        for m in re.finditer(r'(?:title|body): "([^"]+)"', src):
            keys.add(to_key(m.group(1)))
        for m in re.finditer(r'"([A-Z][^"]*\\\([^"]*)"', src):  # interpolated sentences
            if "String(format" not in src[max(0, m.start() - 20): m.start()]:
                pass
    ignore = {"", "OK"}
    return sorted(k for k in keys if k not in ignore and not re.fullmatch(r"[a-z0-9.]+", k) and "://" not in k)


def main():
    app = [p for d in ("SpoolDry", "Shared") for p in (ROOT / d).rglob("*.swift")]
    widget = [p for d in ("SpoolDryWidgets", "Shared") for p in (ROOT / d).rglob("*.swift")]
    print(json.dumps({"app": extract(app), "widget": extract(widget)}, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
