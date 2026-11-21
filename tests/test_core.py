#!/usr/bin/env python3
"""
Test di rpcore (zip + analisi) eseguibili su Linux o macOS:

    python3 tests/test_core.py          # test veloci
    python3 tests/test_core.py --big    # include il file da 4.3 GB (Zip64)
"""

import hashlib
import os
import py_compile
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, "app", "core")

failures = 0


def check(cond, msg):
    global failures
    if cond:
        print("  ok   ", msg)
    else:
        failures += 1
        print("  FAIL ", msg)


def build(tmp):
    exe = os.path.join(tmp, "harness")
    cc = os.environ.get("CC", "cc")
    subprocess.check_call([
        cc, "-O1", "-g", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter",
        "-fsanitize=address,undefined", "-D_FILE_OFFSET_BITS=64",
        os.path.join(ROOT, "tests", "harness.c"),
        os.path.join(CORE, "rpzip.c"),
        os.path.join(CORE, "rpanalyze.c"),
        "-lz", "-o", exe,
    ])
    return exe


def run(exe, *args):
    p = subprocess.run([exe] + list(args), capture_output=True, text=True)
    if p.returncode not in (0, 1):
        print(p.stdout)
        print(p.stderr)
        raise Exception("harness crashed: %r" % (args,))
    return p.stdout


def analyze(exe, zf):
    out = run(exe, "analyze", zf)
    rv = {}
    for l in out.splitlines():
        if "=" in l:
            k, _, v = l.partition("=")
            rv[k] = v
    return rv


def pyc_bytes(tmp, source):
    src = os.path.join(tmp, "vc_version.py")
    with open(src, "w") as f:
        f.write(source)
    dst = os.path.join(tmp, "vc_version.pyc")
    py_compile.compile(src, cfile=dst, doraise=True)
    with open(dst, "rb") as f:
        return f.read()


def py2_marshal_str(s):
    # Simula un .pyo Python 2: stringa marshal tipo 's' + lunghezza.
    b = s.encode("ascii")
    return b"\x03\xf3\r\n\x00\x00\x00\x00c\x00\x00\x00\x00" + b"s" + struct.pack("<I", len(b)) + b + b"N"


def make_zip(path, files, compression=zipfile.ZIP_DEFLATED):
    with zipfile.ZipFile(path, "w", compression) as z:
        for name, data in files.items():
            if name.endswith("/"):
                z.writestr(zipfile.ZipInfo(name), b"")
            else:
                z.writestr(name, data)


def main():
    big = "--big" in sys.argv
    tmp = tempfile.mkdtemp(prefix="rpcore-test-")
    try:
        exe = build(tmp)

        # ------------------------------------------------------------------
        print("Ren'Py 8.3 (cartella radice, deflate)")
        rpa = os.urandom(300000)
        script = b"RENPY RPC2" + os.urandom(5000)
        files = {
            "MyGame-1.0-pc/": b"",
            "MyGame-1.0-pc/game/": b"",
            "MyGame-1.0-pc/game/archive.rpa": rpa,
            "MyGame-1.0-pc/game/script.rpyc": script,
            "MyGame-1.0-pc/game/options.rpy": b'define config.name = _("My Game")\ndefine config.version = "1.0"\n',
            "MyGame-1.0-pc/game/saves/persistent": b"p",
            "MyGame-1.0-pc/renpy/__pycache__/vc_version.cpython-39.pyc": pyc_bytes(tmp, "branch = 'fix'\nofficial = True\nnightly = False\nversion = '8.3.7.25031702'\nversion_name = 'Second Star to the Right'\n"),
            "MyGame-1.0-pc/renpy/common/00start.rpyc": b"x",
            "MyGame-1.0-pc/lib/py3-windows-x86_64/python.exe": b"MZ",
            "MyGame-1.0-pc/lib/python3.9/site.pyc": b"x",
            "MyGame-1.0-pc/MyGame.exe": b"MZ",
            "MyGame-1.0-pc/MyGame.py": b"#",
            "MyGame-1.0-pc/MyGame.sh": b"#",
            "MyGame-1.0-pc/README.txt": b"leggimi",
            "MyGame-1.0-pc/MyGame.app/Contents/Info.plist": b"x",
            "__MACOSX/MyGame-1.0-pc/._MyGame.exe": b"x",
        }
        z8 = os.path.join(tmp, "g8.zip")
        make_zip(z8, files)
        a = analyze(exe, z8)
        check(a["root"] == "MyGame-1.0-pc/", "radice " + a["root"])
        check(a["version"] == "8.3.7.25031702", "versione " + a["version"])
        check(a["py_major"] == "3" and a["py_tag"] == "3.9", "python " + a["py_major"] + " " + a["py_tag"])
        check(a["runtime"] == "8" and a["confident"] == "1", "runtime 8")
        check(a["newer"] == "0", "non più nuovo del runtime")
        check(a["title"] == "My Game" and a["game_version"] == "1.0", "titolo %r versione %r" % (a["title"], a["game_version"]))

        dest = os.path.join(tmp, "out8")
        out = run(exe, "extract", z8, dest)
        check(out.startswith("copied="), out.strip())
        got = sorted(os.path.relpath(os.path.join(dp, f), dest) for dp, dn, fn in os.walk(dest) for f in fn)
        check(got == ["MyGame.py", "README.txt", "game/archive.rpa", "game/options.rpy", "game/saves/persistent", "game/script.rpyc"], "file importati %r" % got)
        with open(os.path.join(dest, "game/archive.rpa"), "rb") as f:
            check(f.read() == rpa, "contenuto .rpa identico")

        # ------------------------------------------------------------------
        print("Ren'Py 8.5 (Python 3.12) -> runtime 8.5")
        z85 = os.path.join(tmp, "g85.zip")
        make_zip(z85, {
            "New-2.0-pc/game/script.rpyc": b"x",
            "New-2.0-pc/renpy/__pycache__/vc_version.cpython-312.pyc": pyc_bytes(tmp, "version = '8.5.2.26010301'\n"),
            "New-2.0-pc/lib/py3-linux-x86_64/x": b"x",
        })
        a = analyze(exe, z85)
        check(a["version"] == "8.5.2.26010301", "versione " + a["version"])
        check(a["runtime"] == "85" and a["newer"] == "0", "runtime 8.5, non più nuovo (%s %s)" % (a["runtime"], a["newer"]))
        check(a["py_tag"] == "3.12", "tag " + a["py_tag"])

        print("Ren'Py 8.6 -> runtime 8.5 ma segnalato più nuovo")
        z86 = os.path.join(tmp, "g86.zip")
        make_zip(z86, {
            "N/game/script.rpyc": b"x",
            "N/renpy/__pycache__/vc_version.cpython-312.pyc": pyc_bytes(tmp, "version = '8.6.1.26111705'\n"),
            "N/lib/python3.12/site.pyc": b"x",
        })
        a = analyze(exe, z86)
        check(a["runtime"] == "85" and a["newer"] == "1", "runtime %s newer %s" % (a["runtime"], a["newer"]))

        print("Ren'Py 8.4 senza versione esatta (solo lib/python3.12)")
        z84 = os.path.join(tmp, "g84.zip")
        make_zip(z84, {
            "M/game/script.rpyc": b"x",
            "M/lib/python3.12/site.pyc": b"x",
            "M/lib/py3-windows-x86_64/x.exe": b"x",
        })
        a = analyze(exe, z84)
        check(a["runtime"] == "85" and a["newer"] == "0" and a["py_tag"] == "3.12", "runtime %s tag %s" % (a["runtime"], a["py_tag"]))

        # ------------------------------------------------------------------
        print("Ren'Py 7.4 (pyo, lib/py2-*, senza versione esatta)")
        z74 = os.path.join(tmp, "g74.zip")
        make_zip(z74, {
            "BeingADIK-0.8.2-pc/game/images.rpa": b"x" * 1000,
            "BeingADIK-0.8.2-pc/game/script.rpyc": b"x",
            "BeingADIK-0.8.2-pc/renpy/__init__.pyo": b"\x03\xf3\r\n" + b"\x00" * 50,
            "BeingADIK-0.8.2-pc/renpy/vc_version.pyo": py2_marshal_str("vc_version") + b"i\x82\x08\x00\x00",
            "BeingADIK-0.8.2-pc/lib/py2-linux-x86_64/BeingADIK": b"\x7fELF",
            "BeingADIK-0.8.2-pc/lib/pythonlib2.7/site.pyo": b"x",
        })
        a = analyze(exe, z74)
        check(a["root"] == "BeingADIK-0.8.2-pc/", "radice")
        check(a["version"] == "", "nessuna versione inventata (%r)" % a["version"])
        check(a["py_major"] == "2" and a["runtime"] == "7" and a["confident"] == "1", "runtime 7 (Python 2)")

        # ------------------------------------------------------------------
        print("Ren'Py 7.5 (vc_version.pyo con versione)")
        z75 = os.path.join(tmp, "g75.zip")
        make_zip(z75, {
            "G/game/script.rpyc": b"x",
            "G/renpy/vc_version.pyo": py2_marshal_str("7.5.3.22090809"),
            "G/lib/py2-windows-x86_64/x.exe": b"x",
        })
        a = analyze(exe, z75)
        check(a["version"] == "7.5.3.22090809" and a["runtime"] == "7", "versione %s runtime %s" % (a["version"], a["runtime"]))

        # ------------------------------------------------------------------
        print("Ren'Py 6.99 (renpy/__init__.py)")
        z6 = os.path.join(tmp, "g6.zip")
        make_zip(z6, {
            "Old/game/script.rpyc": b"x",
            "Old/renpy/__init__.py": b"vc_version = 0\nversion_tuple = (6, 99, 14, vc_version)\n",
            "Old/lib/windows-i686/python.exe": b"x",
        })
        a = analyze(exe, z6)
        check(a["version"] == "6.99.14" and a["runtime"] == "7", "versione %s runtime %s" % (a["version"], a["runtime"]))

        # ------------------------------------------------------------------
        print("App Mac (autorun)")
        zm = os.path.join(tmp, "mac.zip")
        make_zip(zm, {
            "Game-1.0-mac/Game.app/Contents/MacOS/Game": b"x",
            "Game-1.0-mac/Game.app/Contents/Resources/autorun/game/script.rpyc": b"x",
            "Game-1.0-mac/Game.app/Contents/Resources/autorun/renpy/__pycache__/vc_version.cpython-39.pyc": pyc_bytes(tmp, "version = '8.1.3.23091805'\n"),
            "Game-1.0-mac/Game.app/Contents/Resources/autorun/lib/python3.9/site.pyc": b"x",
        })
        a = analyze(exe, zm)
        check(a["root"] == "Game-1.0-mac/Game.app/Contents/Resources/autorun/", "radice " + a["root"])
        check(a["version"] == "8.1.3.23091805", "versione")

        # ------------------------------------------------------------------
        print("Nessun gioco Ren'Py")
        zn = os.path.join(tmp, "none.zip")
        make_zip(zn, {"foo/bar.txt": b"x"})
        a = analyze(exe, zn)
        check(a["rv"] == "-1" and a["found"] == "0", "segnala che manca game/")

        # ------------------------------------------------------------------
        print("Zip64 per numero di voci (70000) e gioco alla radice")
        z64 = os.path.join(tmp, "many.zip")
        with zipfile.ZipFile(z64, "w", zipfile.ZIP_STORED) as z:
            z.writestr("game/script.rpyc", b"x")
            for i in range(70000):
                z.writestr("game/images/%05d.txt" % i, b"%d" % i)
        out = run(exe, "list", z64)
        check("TOTAL 70001" in out, out.strip().splitlines()[-1])
        a = analyze(exe, z64)
        check(a["root"] == "" and a["found"] == "1", "radice vuota")
        dest = os.path.join(tmp, "outmany")
        out = run(exe, "extract", z64, dest)
        check("copied=70001" in out, out.strip())
        with open(os.path.join(dest, "game/images/69999.txt"), "rb") as f:
            check(f.read() == b"69999", "ultimo file corretto")
        shutil.rmtree(dest)

        # ------------------------------------------------------------------
        print("Dati prefissati (stile autoestraente)")
        zp = os.path.join(tmp, "prefixed.zip")
        with open(zp, "wb") as f:
            f.write(b"MZ" + os.urandom(5000))
            with open(z8, "rb") as g:
                f.write(g.read())
        dest = os.path.join(tmp, "outp")
        out = run(exe, "extract", zp, dest)
        check(out.startswith("copied=6"), out.strip())

        # ------------------------------------------------------------------
        print("Nomi CP437, backslash, percorsi pericolosi")
        zc = os.path.join(tmp, "cp437.zip")
        with zipfile.ZipFile(zc, "w") as z:
            z.writestr("game/script.rpyc", b"x")
            z.writestr("game/caffX.txt", b"cp")
        # Nome ASCII scritto senza flag UTF-8: lo trasformiamo in CP437 ('é' = 0x82).
        data = open(zc, "rb").read().replace(b"caffX", b"caff\x82")
        open(zc, "wb").write(data)
        out = run(exe, "list", zc)
        check("game/caffé.txt" in out, "nome CP437 convertito in UTF-8")

        zb = os.path.join(tmp, "bad.zip")
        with zipfile.ZipFile(zb, "w") as z:
            z.writestr("game/script.rpyc", b"x")
            z.writestr("../../evil.txt", b"x")
            z.writestr("/abs/evil2.txt", b"x")
        out = run(exe, "list", zb)
        check("evil.txt" not in out.split("abs/")[0] or "../" not in out, "nessun '..' nell'elenco")
        check("../" not in out, "percorsi con '..' scartati")
        check("abs/evil2.txt" in out, "percorso assoluto reso relativo")

        print("sanitize")
        check(run(exe, "sanitize", "a\\b\\c.txt").strip() == "1 a/b/c.txt", "backslash")
        check(run(exe, "sanitize", "./x/../y").strip().startswith("0"), "'..' rifiutato")
        check(run(exe, "sanitize", "//x").strip() == "1 x", "slash iniziali")

        # ------------------------------------------------------------------
        print("Zip troncato / non zip")
        zt = os.path.join(tmp, "trunc.zip")
        with open(z8, "rb") as f:
            d = f.read()
        with open(zt, "wb") as f:
            f.write(d[: len(d) // 2])
        out = run(exe, "list", zt)
        check(out.startswith("ERR"), out.strip())
        zr = os.path.join(tmp, "fake.rar")
        with open(zr, "wb") as f:
            f.write(b"Rar!\x1a\x07\x00" + os.urandom(1000))
        out = run(exe, "list", zr)
        check(out.startswith("ERR") and ".rar" in out, out.strip())

        # CRC sbagliato
        zcrc = os.path.join(tmp, "crc.zip")
        make_zip(zcrc, {"game/script.rpyc": b"hello world" * 100}, zipfile.ZIP_STORED)
        d = bytearray(open(zcrc, "rb").read())
        i = d.find(b"hello world")
        d[i] ^= 0xFF
        open(zcrc, "wb").write(bytes(d))
        out = run(exe, "extract", zcrc, os.path.join(tmp, "outcrc"))
        check(out.startswith("ERR") and "CRC" in out, out.strip())
        check(not os.path.exists(os.path.join(tmp, "outcrc", "game", "script.rpyc")), "file parziale rimosso")

        # Annullamento
        out = run(exe, "cancel", z8, os.path.join(tmp, "outcancel"))
        check("Annullato" in out, out.strip())

        # ------------------------------------------------------------------
        print("Scrittura zip dei salvataggi")
        s1 = os.path.join(tmp, "1-1-LT1.save")
        s2 = os.path.join(tmp, "persistent")
        with open(s1, "wb") as f:
            f.write(os.urandom(123456))
        with open(s2, "wb") as f:
            f.write(b"")
        zw = os.path.join(tmp, "saves.zip")
        out = run(exe, "writezip", zw, "saves/1-1-LT1.save", s1, "saves/persistent", s2)
        check(out.strip() == "OK", out.strip())
        with zipfile.ZipFile(zw) as z:
            check(z.testzip() is None, "zip valido per Python")
            check(z.read("saves/1-1-LT1.save") == open(s1, "rb").read(), "contenuto identico")
            check(z.namelist() == ["saves/1-1-LT1.save", "saves/persistent"], "nomi")
        if shutil.which("unzip"):
            p = subprocess.run(["unzip", "-t", zw], capture_output=True, text=True)
            check(p.returncode == 0, "unzip -t")

        print("Moduli Python del gioco in lib/")
        check(run(exe, "pylib", "G/lib/python3.12/saga/__init__.pyc", "G/").strip() == "1 python3.12 saga/__init__.pyc", "lib/python3.12/saga")
        check(run(exe, "pylib", "G/lib/pythonlib2.7/foo.pyo", "G/").strip() == "1 python2.7 foo.pyo", "lib/pythonlib2.7 -> python2.7")
        check(run(exe, "pylib", "G/lib/python3.12/saga/_speed.so", "G/").strip().startswith("0"), "moduli nativi esclusi")
        check(run(exe, "pylib", "G/lib/py3-windows-x86_64/python.exe", "G/").strip().startswith("0"), "binari della piattaforma esclusi")
        check(run(exe, "pylib", "G/game/x.rpy", "G/").strip().startswith("0"), "file del gioco non sono moduli")

        check(run(exe, "issave", "a/1-1-LT1.save").strip() == "1", "riconosce .save")
        check(run(exe, "issave", "persistent").strip() == "1", "riconosce persistent")
        check(run(exe, "issave", "._x.save").strip() == "0", "ignora ._")
        check(run(exe, "issave", "log.txt").strip() == "0", "ignora altri file")

        # ------------------------------------------------------------------
        if big:
            print("Zip64 per dimensione (4.3 GB di zeri)")
            zbig = os.path.join(tmp, "big.zip")
            size = (1 << 32) + 300 * 1024 * 1024
            with zipfile.ZipFile(zbig, "w", zipfile.ZIP_DEFLATED) as z:
                z.writestr("game/script.rpyc", b"x")
                with z.open("game/huge.rpa", "w", force_zip64=True) as f:
                    chunk = b"\0" * (16 << 20)
                    left = size
                    while left:
                        n = min(left, len(chunk))
                        f.write(chunk[:n])
                        left -= n
                z.writestr("game/after.txt", b"after")
            out = run(exe, "list", zbig)
            check("game/huge.rpa\t%d" % size in out, "dimensione > 4 GB letta")
            dest = os.path.join(tmp, "outbig")
            out = run(exe, "extract", zbig, dest)
            check("copied=3" in out, out.strip())
            check(os.path.getsize(os.path.join(dest, "game/huge.rpa")) == size, "file da 4.3 GB estratto")
            with open(os.path.join(dest, "game/after.txt"), "rb") as f:
                check(f.read() == b"after", "voce dopo i 4 GB")
            shutil.rmtree(dest)
            os.unlink(zbig)

            print("Zip64 per offset (voci oltre i 4 GB nel file)")
            zoff = os.path.join(tmp, "offset.zip")
            chunk = os.urandom(16 << 20)
            with zipfile.ZipFile(zoff, "w", zipfile.ZIP_STORED, allowZip64=True) as z:
                z.writestr("game/script.rpyc", b"x")
                with z.open("game/big.rpa", "w", force_zip64=True) as f:
                    left = size
                    while left:
                        n = min(left, len(chunk))
                        f.write(chunk[:n])
                        left -= n
                z.writestr("game/after.txt", b"after-offset")
            out = run(exe, "list", zoff)
            check("game/after.txt\t12" in out, "voce dopo i 4 GB elencata")
            dest = os.path.join(tmp, "outoff")
            out = run(exe, "extract", zoff, dest)
            check("copied=3" in out, out.strip())
            with open(os.path.join(dest, "game/after.txt"), "rb") as f:
                check(f.read() == b"after-offset", "voce con offset > 4 GB estratta")
            shutil.rmtree(dest)
            os.unlink(zoff)

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    print("FALLITI:", failures)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
