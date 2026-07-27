#!/bin/bash
# patch-catalyst-embed.sh — #60: xcodegen (2.44.1) emits the widget appex into the
# app's "Embed Foundation Extensions" phase WITHOUT a platform filter, so Mac
# Catalyst builds fail ("embedded content built for iOS"). This re-applies
# `platformFilter = ios;` to that PBXBuildFile after every `xcodegen` run:
#
#   xcodegen && ./Scripts/patch-catalyst-embed.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'EOF'
p = "ShadyGarageSpeed.xcodeproj/project.pbxproj"
s = open(p).read()
old = "ShadyGarageSpeedWidget.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = "
i = s.find(old)
assert i > 0, "embed build file not found — run xcodegen first"
j = s.find("};", i)
seg = s[i:j]
if "platformFilter" not in seg:
    seg2 = seg.replace("settings = {ATTRIBUTES", "platformFilter = ios; settings = {ATTRIBUTES")
    open(p, "w").write(s[:i] + seg2 + s[j:])
    print("patched platformFilter = ios")
else:
    print("already patched")
EOF
