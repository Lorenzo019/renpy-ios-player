#!/bin/bash
# Scarica, verifica ed estrae i pacchetti ufficiali di Ren'Py necessari alla build.
#
#   RENPY7=7.8.7 RENPY8=8.3.7 tools/fetch_renpy.sh downloads work

set -euo pipefail

DL="${1:-downloads}"
WORK="${2:-work}"
RENPY7="${RENPY7:-7.8.7}"
RENPY8="${RENPY8:-8.3.7}"
RENPY85="${RENPY85:-8.5.3}"
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$DL" "$WORK"

fetch() {
    local url="$1" out="$2"
    if [ -s "$out" ]; then
        echo "Già presente: $out"
        return
    fi
    echo "Scarico $url"
    curl -fL --retry 4 --retry-delay 5 --connect-timeout 30 -o "$out.part" "$url"
    mv "$out.part" "$out"
}

for v in "$RENPY7" "$RENPY8" "$RENPY85"; do
    base="https://www.renpy.org/dl/$v"
    curl -fsSL --retry 4 -o "$DL/checksums-$v.txt" "$base/checksums.txt"
    for f in "renpy-$v-renios.zip" "renpy-$v-sdk.tar.bz2"; do
        fetch "$base/$f" "$DL/$f"
    done
    if ! python3 "$HERE/verify_checksums.py" "$DL/checksums-$v.txt" "$DL/renpy-$v-renios.zip" "$DL/renpy-$v-sdk.tar.bz2"; then
        rm -f "$DL/renpy-$v-renios.zip" "$DL/renpy-$v-sdk.tar.bz2"
        echo "Checksum non validi: file rimossi, rilancia la build." >&2
        exit 1
    fi
done

rm -rf "$WORK/renios7" "$WORK/renios8" "$WORK/renios85" "$WORK/sdk7" "$WORK/sdk8" "$WORK/sdk85"
mkdir -p "$WORK/renios7" "$WORK/renios8" "$WORK/renios85" "$WORK/sdk7" "$WORK/sdk8" "$WORK/sdk85"

unzip -q "$DL/renpy-$RENPY7-renios.zip" -d "$WORK/renios7"
unzip -q "$DL/renpy-$RENPY8-renios.zip" -d "$WORK/renios8"
unzip -q "$DL/renpy-$RENPY85-renios.zip" -d "$WORK/renios85"
tar -xjf "$DL/renpy-$RENPY7-sdk.tar.bz2" -C "$WORK/sdk7"
tar -xjf "$DL/renpy-$RENPY8-sdk.tar.bz2" -C "$WORK/sdk8"
tar -xjf "$DL/renpy-$RENPY85-sdk.tar.bz2" -C "$WORK/sdk85"

echo "Contenuto:"
ls "$WORK"/renios7 "$WORK"/renios8 "$WORK"/renios85 "$WORK"/sdk7 "$WORK"/sdk8 "$WORK"/sdk85
ls "$WORK"/renios8/renios/prototype/prebuilt/release | head -50
ls "$WORK"/renios7/renios/prototype/prebuilt/release | head -50
ls "$WORK"/renios85/renios/prototype/prebuilt/release | head -60
