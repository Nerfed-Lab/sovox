#!/usr/bin/env python3
"""Flip the Sovox and SovoxWidget targets between automatic signing and
manual App Store distribution signing.

Manual distribution signing is what lets this project archive on a team with no
registered devices. Apple refuses to issue a Development provisioning profile to
such a team, and both a device build and an archive ask for one. Distribution
profiles carry no device requirement.

Edits project.pbxproj in place and is idempotent, so it is safe to run twice and
safe to run after Xcode has touched the file.

    ./set-signing.py manual
    ./set-signing.py automatic
"""
import re
import shutil
import sys
from pathlib import Path

PBXPROJ = Path(__file__).parent / "Sovox.xcodeproj" / "project.pbxproj"

APP_ID = "com.rishabh.capturenotes"
WIDGET_ID = "com.rishabh.capturenotes.CaptureWidget"

PROFILES = {
    APP_ID: "Sovox App Store",
    WIDGET_ID: "Sovox Widget App Store",
}

MANUAL_KEYS = ("CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE_SPECIFIER")


def config_blocks(text):
    """Yield (start, end) spans of every XCBuildConfiguration buildSettings block."""
    for match in re.finditer(r"isa = XCBuildConfiguration;\s*\n\t{3}buildSettings = \{\n", text):
        start = match.end()
        depth = 1
        index = start
        while depth and index < len(text):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    yield start, index
                    break
            index += 1


def bundle_id_of(block):
    match = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", block)
    return match.group(1).strip().strip('"') if match else None


def strip_keys(block, keys):
    for key in keys:
        block = re.sub(r"[ \t]*%s = [^;]*;\n" % key, "", block)
    return block


def set_key(block, key, value):
    """Insert or replace a key, keeping the block's own indentation intact.

    The block runs from just after the opening brace to just before the closing
    one, so it ends in the tabs that indent that closing brace. Those have to be
    preserved or the pbxproj comes back with a dangling blank line and a brace at
    column zero.
    """
    quoted_value = value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else '"%s"' % value
    pattern = r"([ \t]*)%s = [^;]*;" % key
    if re.search(pattern, block):
        # Replace in place so a key that was already present keeps its position
        # and the file round trips byte for byte.
        return re.sub(pattern, lambda m: "%s%s = %s;" % (m.group(1), key, quoted_value), block, count=1)

    tail = re.search(r"[ \t]*$", block).group(0)
    body = block[: len(block) - len(tail)]
    if body and not body.endswith("\n"):
        body += "\n"
    quoted = value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else '"%s"' % value
    return body + "\t\t\t\t%s = %s;\n" % (key, quoted) + tail


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("manual", "automatic"):
        print(__doc__)
        return 2

    mode = sys.argv[1]
    text = PBXPROJ.read_text()
    shutil.copy(PBXPROJ, str(PBXPROJ) + ".bak")

    out = []
    cursor = 0
    changed = 0

    for start, end in config_blocks(text):
        block = text[start:end]
        bundle = bundle_id_of(block)
        if bundle not in PROFILES:
            continue

        if mode == "manual":
            block = set_key(block, "CODE_SIGN_STYLE", "Manual")
            block = set_key(block, "CODE_SIGN_IDENTITY", "Apple Distribution")
            block = set_key(block, "PROVISIONING_PROFILE_SPECIFIER", PROFILES[bundle])
        else:
            block = strip_keys(block, MANUAL_KEYS)
            block = set_key(block, "CODE_SIGN_STYLE", "Automatic")

        out.append(text[cursor:start])
        out.append(block)
        cursor = end
        changed += 1

    out.append(text[cursor:])
    PBXPROJ.write_text("".join(out))

    print("signing set to %s in %d build configurations" % (mode, changed))
    if mode == "manual":
        for bundle, profile in PROFILES.items():
            print("  %-42s %s" % (bundle, profile))
        print("\nThe profiles must be installed. Download them from the Profiles")
        print("section of developer.apple.com and double click each one.")
    print("\nprevious file kept at project.pbxproj.bak")
    return 0


if __name__ == "__main__":
    sys.exit(main())
