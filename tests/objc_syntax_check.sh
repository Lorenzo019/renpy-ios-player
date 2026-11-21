#!/bin/bash
# Controllo di sintassi del codice Objective-C su Linux (clang + intestazioni
# GNUstep + stub di UIKit). Serve solo a trovare errori prima della build vera
# su macOS; non sostituisce Xcode.
#
# Richiede: clang, libgnustep-base-dev, intestazioni di libobjc2 in $LIBOBJC2.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBOBJC2="${LIBOBJC2:-/tmp/objcheck/libobjc2}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT"/app/src/*.m "$ROOT"/app/src/*.h "$ROOT"/app/core/*.h "$TMP"/
cp "$ROOT"/tests/objc-stubs/UIKitStub.h "$TMP"/
for f in "$TMP"/*.m "$TMP"/*.h; do
    sed -i -e 's/@import UIKit;/#import "UIKitStub.h"/' \
           -e 's/@import UniformTypeIdentifiers;//' \
           -e 's/@import Foundation;/#import <Foundation\/Foundation.h>/' "$f"
done

status=0
for f in "$TMP"/*.m; do
    echo "== $(basename "$f")"
    clang -fsyntax-only -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
        -Wall -Wextra -Wno-unused-parameter -Wno-objc-root-class \
        -Wno-nullability-completeness -Wno-deprecated-declarations \
        -DGNUSTEP -DGNUSTEP_BASE_LIBRARY=1 -DGNU_RUNTIME=1 \
        -I"$LIBOBJC2" -I/usr/include/GNUstep -I"$TMP" "$f" || status=1
done
exit $status
