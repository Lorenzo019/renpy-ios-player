#!/bin/bash
# Controlli di base sul bundle .app prodotto da xcodebuild.

set -euo pipefail

APP="$1"
BIN="$APP/RenPlayer"

missing=0
for p in \
    RenPlayer \
    Info.plist \
    Frameworks/MetalANGLE.framework \
    runtimes/versions.json \
    runtimes/rt7/base/main.py \
    runtimes/rt7/base/renpy \
    runtimes/rt7/base/lib/python2.7/site.pyo \
    runtimes/rt8/base/main.py \
    runtimes/rt8/base/renpy \
    runtimes/rt8/base/lib/python3.9/site.pyc \
    runtimes/rt85/base/main.py \
    runtimes/rt85/base/renpy
do
    if [ -e "$APP/$p" ]; then
        echo "ok      $p"
    else
        echo "MANCA   $p"
        missing=1
    fi
done

grep -q "RENPLAYER_SAVEDIR" "$APP/runtimes/rt7/base/main.py" || { echo "Patch dei salvataggi mancante (rt7)"; missing=1; }
grep -q "RENPLAYER_SAVEDIR" "$APP/runtimes/rt8/base/main.py" || { echo "Patch dei salvataggi mancante (rt8)"; missing=1; }
grep -q "RENPLAYER_SAVEDIR" "$APP/runtimes/rt85/base/main.py" || { echo "Patch dei salvataggi mancante (rt85)"; missing=1; }
ls "$APP"/runtimes/rt85/base/lib/python3.*/site.pyc >/dev/null 2>&1 || { echo "MANCA   runtimes/rt85/base/lib/python3.x/site.pyc"; missing=1; }

echo
plutil -p "$APP/Info.plist" | grep -E "CFBundleIdentifier|CFBundleShortVersionString|MinimumOSVersion|UIFileSharingEnabled|LSSupportsOpeningDocumentsInPlace" || true
lipo -info "$BIN"
otool -L "$BIN" | head -30
cat "$APP/runtimes/versions.json"; echo
du -sh "$APP" "$APP/runtimes" "$BIN"

exit $missing
