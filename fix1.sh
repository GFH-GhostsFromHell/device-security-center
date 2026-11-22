#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

D=ghost-protocol-desktop
O=$D/device-security-desktop

# 1. pull the desktop project back up out of the nested folder
git mv --force "$O/pom.xml" "$D/pom.xml"
[ -f "$O/README.md" ] && git mv --force "$O/README.md" "$D/README.md"
mkdir -p "$D/src/main/java/com" "$D/src/test/java/com"
git mv --force "$O/src/main/java/com/gfh" "$D/src/main/java/com/gfh"
[ -d "$O/src/test/java/com/gfh" ] && git mv --force "$O/src/test/java/com/gfh" "$D/src/test/java/com/gfh"
rm -rf "$O"

# 2. desktop classes into the new package
for f in "$D"/src/main/java/com/gfh/devicesecurity/*.java; do
  [ -e "$f" ] && git mv --force "$f" "$D/src/main/java/com/ztsec/ghost/"
done
for f in "$D"/src/test/java/com/gfh/devicesecurity/*.java; do
  [ -e "$f" ] && git mv --force "$f" "$D/src/test/java/com/ztsec/ghost/"
done
rm -rf "$D/src/main/java/com/gfh" "$D/src/test/java/com/gfh"

# 3. portal classes into the new package
P=portal/src/main/java/com
T=portal/src/test/java/com
git mv --force "$P/example/remoteportal/RemotePortalApplication.java" \
              "$P/ztsec/ghost/portal/RemotePortalApplication.java"
for f in "$P"/example/remoteportal/device/*.java; do
  [ -e "$f" ] && git mv --force "$f" "$P/ztsec/ghost/portal/ops/"
done
for f in "$T"/example/remoteportal/device/*.java; do
  [ -e "$f" ] && git mv --force "$f" "$T/ztsec/ghost/portal/ops/"
done
rm -rf "$P/example" "$T/example"

# 4. rewrite identifiers everywhere
grep -rlI --exclude-dir=.git --exclude-dir=target . | while read -r f; do
  sed -i \
    -e 's|com\.gfh\.devicesecurity|com.ztsec.ghost|g' \
    -e 's|com\.example\.remoteportal\.device|com.ztsec.ghost.portal.ops|g' \
    -e 's|com\.example\.remoteportal|com.ztsec.ghost.portal|g' \
    -e 's|device-security-desktop|ghost-protocol-desktop|g' \
    -e 's|/api/device-security|/api/zt01|g' \
    -e 's|device_security_|zt_|g' \
    -e 's|DEVICE_ADMIN_|ZT_OPERATOR_|g' \
    -e 's|DEVICE_CLIENT_|ZT_ASSET_|g' \
    -e 's|ROLE_ADMIN|ROLE_OPERATOR|g' \
    -e 's|ROLE_CLIENT|ROLE_ASSET|g' \
    -e 's|"ADMIN"|"OPERATOR"|g' \
    -e 's|"CLIENT"|"ASSET"|g' \
    -e 's|\.gfhlk|.zt01|g' \
    -e 's|\.gfhenc|.zts|g' \
    -e 's|GFHLOCK1|ZTPROTO1|g' \
    -e 's|Device Security Center|GHOST PROTOCOL|g' \
    -e 's|device security center|GHOST PROTOCOL|g' \
    "$f"
done

# 5. rename the workflow files
W=.github/workflows
git mv --force "$W/build-device-security-desktop.yml" "$W/build-ghost-protocol-desktop.yml"
git mv --force "$W/build-device-security-portal.yml" "$W/build-ghost-protocol-portal.yml"
git mv --force "$W/validate-device-security-web.yml" "$W/validate-ghost-protocol-web.yml"

# 6. the sweep must hand over its own deadline, not let the shell invent one
sed -i 's|onArm.accept(new String\[\]{caseId, amount, address, code});|onArm.accept(new String[]{caseId, amount, address, code, timer.deadline().toString()});|' \
  "$D/src/main/java/com/ztsec/ghost/SweepPanel.java"

git add -A
echo "structure repaired"
echo "remaining old paths (should be empty):"
find . -path ./.git -prune -o -name '*remoteportal*' -print -o -name '*devicesecurity*' -print
