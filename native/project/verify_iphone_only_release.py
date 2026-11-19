"""Fail if the V1 iPhone app starts packaging the unfinished Watch demo."""

from pathlib import Path

project = Path("PDBridgeNative.xcodeproj/project.pbxproj").read_text()
source = Path("project.yml").read_text()

if "name = PDBridgeWatch;" not in project or "PDBridgeWatch:" not in source:
    raise SystemExit("The preserved Watch development target is missing")
if "PDBridgeWatch.app in Embed Watch Content" in project or "Embed Watch Content" in project:
    raise SystemExit("The V1 iPhone target must not embed the unfinished Watch companion")
if "target: PDBridgeWatch\n        embed: true" in source:
    raise SystemExit("The XcodeGen definition still embeds the Watch companion")

print("iPhone-only V1 release configuration verified; Watch development target preserved.")
