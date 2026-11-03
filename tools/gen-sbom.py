#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Write a CycloneDX SBOM for the firmware from sbom/components.toml.

    ./tools/gen-sbom.py -o sbom.cdx.json
    ./tools/gen-sbom.py --demo-bug 5 -o sbom.cdx.json   include seeded defect 5

The firmware version comes from project() in CMakeLists.txt. Set
SOURCE_DATE_EPOCH to get a fixed timestamp.
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import sys
import tomllib
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
REQUIRED = ("name", "version", "supplier", "license", "cpe")
SCOPES = ("required", "excluded")


def fail(message):
    sys.exit(f"gen-sbom: {message}")


def project_version():
    text = (ROOT / "CMakeLists.txt").read_text()
    match = re.search(r"project\(\s*\S+\s+VERSION\s+([0-9.]+)", text)
    if not match:
        fail("no project(... VERSION x.y.z) in CMakeLists.txt")
    return match.group(1)


def fetchcontent_tag(name):
    # Only this repo's own CMake files, never the ones under build trees.
    files = [ROOT / "CMakeLists.txt"] + [
        p for p in ROOT.glob("*/CMakeLists.txt") if not p.parent.name.startswith("build")
    ]
    for path in files:
        for block in re.findall(r"FetchContent_Declare\((.*?)\)", path.read_text(), re.S):
            words = block.split()
            if words and words[0] == name and "GIT_TAG" in words:
                return words[words.index("GIT_TAG") + 1]
    fail(f"no FetchContent_Declare({name} ... GIT_TAG ...) found")


def component(entry):
    missing = [key for key in REQUIRED if not entry.get(key)]
    if missing:
        fail(f"component {entry.get('name', '?')} is missing {', '.join(missing)}")
    scope = entry.get("scope", "required")
    if scope not in SCOPES:
        fail(f"component {entry['name']}: scope must be one of {', '.join(SCOPES)}")
    if "fetchcontent" in entry:
        tag = fetchcontent_tag(entry["fetchcontent"])
        if tag.lstrip("v") != entry["version"]:
            fail(f"component {entry['name']} is version {entry['version']} "
                 f"but the build fetches {tag}")

    out = {
        "type": "library",
        "bom-ref": f"{entry['name']}@{entry['version']}",
        "supplier": {"name": entry["supplier"]},
        "name": entry["name"],
        "version": entry["version"],
        "scope": scope,
        "licenses": [{"license": {"id": entry["license"]}}],
        "cpe": entry["cpe"],
    }
    if entry.get("purl"):
        out["purl"] = entry["purl"]
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-o", "--output", required=True, help="where to write the SBOM")
    parser.add_argument("--demo-bug", type=int, default=int(os.environ.get("DEMO_BUG", "0")),
                        help="seeded defect number (default: $DEMO_BUG, or 0)")
    args = parser.parse_args()

    config = tomllib.loads((ROOT / "sbom" / "components.toml").read_text())
    firmware = config["firmware"]
    components = [
        component(entry) for entry in config.get("component", [])
        if entry.get("demo_bug", args.demo_bug) == args.demo_bug
    ]

    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    when = (datetime.datetime.fromtimestamp(int(epoch), datetime.timezone.utc) if epoch
            else datetime.datetime.now(datetime.timezone.utc))
    firmware_ref = f"{firmware['name']}@{project_version()}"

    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "version": 1,
        "metadata": {
            "timestamp": when.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "tools": {"components": [{"type": "application", "name": "gen-sbom.py"}]},
            "component": {
                "type": "firmware",
                "bom-ref": firmware_ref,
                "supplier": {"name": firmware["supplier"]},
                "name": firmware["name"],
                "version": project_version(),
                "licenses": [{"license": {"id": firmware["license"]}}],
            },
        },
        "components": components,
        "dependencies": [{
            "ref": firmware_ref,
            "dependsOn": [c["bom-ref"] for c in components if c["scope"] == "required"],
        }],
    }

    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(bom, indent=2) + "\n")
    print(f"wrote {output} ({len(components)} components)")


if __name__ == "__main__":
    main()
