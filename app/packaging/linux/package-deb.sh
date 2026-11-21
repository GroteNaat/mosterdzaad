#!/usr/bin/env bash
set -euo pipefail
stage="build/packages/deb-root"
mkdir -p "$stage/DEBIAN" "$stage/opt/mosterdzaad" "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/256x256/apps"
cp -a build/linux/x64/release/bundle/. "$stage/opt/mosterdzaad/"
cp packaging/linux/mosterdzaad.desktop "$stage/usr/share/applications/"
cp macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png "$stage/usr/share/icons/hicolor/256x256/apps/mosterdzaad.png"
cat > "$stage/DEBIAN/control" <<'EOF'
Package: mosterdzaad
Version: 0.4.0
Architecture: amd64
Maintainer: Mosterdzaad <noreply@mosterdzaad.local>
Depends: libgtk-3-0, libstdc++6, libc6 (>= 2.35), libsecret-1-0, libjsoncpp25
Section: utils
Priority: optional
Description: Persoonlijke Bijbelstudie met lokale studieboekmappen.
EOF
dpkg-deb --root-owner-group --build "$stage" build/packages/Mosterdzaad-linux-amd64.deb
