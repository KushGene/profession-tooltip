#!/usr/bin/env python3
"""Zieht den Abschnitt einer Version aus CHANGELOG.md für das Release ("What's new").

Aufruf: extract_changelog.py <tag> [CHANGELOG.md] [Ausgabedatei]

  v1.1.0              -> Abschnitt "## 1.1.0"; fehlt er, bricht das Release ab
  v1.1.0-beta1(-...)  -> "## 1.1.0-beta1", sonst "## 1.1.0", sonst "## Unreleased"
"""
import re
import sys


def find_section(text, name):
    pattern = rf"^## \[?v?{re.escape(name)}\]?(?=\s|$).*$"
    match = re.search(pattern, text, re.MULTILINE | re.IGNORECASE)
    if not match:
        return None
    rest = text[match.end():]
    following = re.search(r"^## ", rest, re.MULTILINE)
    body = rest[:following.start()] if following else rest
    return body.strip()


def main():
    tag = sys.argv[1]
    source = sys.argv[2] if len(sys.argv) > 2 else "CHANGELOG.md"
    target = sys.argv[3] if len(sys.argv) > 3 else ".release-notes.md"
    version = tag[1:] if tag.startswith("v") else tag
    prerelease = "-" in version

    candidates = [version]
    if prerelease:
        base = version.split("-", 1)[0]
        prerelease_name = "-".join(version.split("-")[:2])  # z. B. 1.1.0-beta1 aus 1.1.0-beta1-cfonly
        candidates = list(dict.fromkeys([version, prerelease_name, base, "Unreleased"]))

    with open(source, encoding="utf8") as f:
        text = f.read()
    for name in candidates:
        body = find_section(text, name)
        if body:
            with open(target, "w", encoding="utf8") as f:
                f.write(body + "\n")
            print(f"Changelog für {tag}: Abschnitt '{name}' -> {target}")
            return
    sys.exit(f"Kein Abschnitt in {source} für {tag} gefunden (gesucht: {', '.join(candidates)}). "
             f"Bitte '## {version}' anlegen.")


if __name__ == "__main__":
    main()
