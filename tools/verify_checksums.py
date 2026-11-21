#!/usr/bin/env python3
"""
Verifica i file scaricati con il checksums.txt pubblicato da renpy.org
(righe "<hash> <nome file>", con sezioni md5, sha1 e sha256).

    verify_checksums.py checksums.txt file1 [file2 ...]
"""

import hashlib
import os
import re
import sys

ALGOS = {32: "md5", 40: "sha1", 64: "sha256", 128: "sha512"}


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    known = {}
    for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
        m = re.match(r"^([0-9a-f]{32}|[0-9a-f]{40}|[0-9a-f]{64}|[0-9a-f]{128})\s+\*?(\S+)\s*$", line.strip())
        if m:
            known.setdefault(m.group(2), []).append(m.group(1))

    ok = True
    for path in sys.argv[2:]:
        name = os.path.basename(path)
        hashes = known.get(name, [])
        if not hashes:
            print("NESSUN CHECKSUM per", name)
            ok = False
            continue

        algos = {ALGOS[len(h)]: h for h in hashes}
        hs = {a: hashlib.new(a) for a in algos}
        with open(path, "rb") as f:
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                for h in hs.values():
                    h.update(b)

        for a, expected in algos.items():
            got = hs[a].hexdigest()
            if got != expected:
                print("ERRATO %s %s: atteso %s, ottenuto %s" % (a, name, expected, got))
                ok = False
            else:
                print("ok %s %s" % (a, name))

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
