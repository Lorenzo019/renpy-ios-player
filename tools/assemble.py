#!/usr/bin/env python3
"""
Costruisce il progetto Xcode di RenPlayer partendo dai pacchetti ufficiali di Ren'Py.

Ingressi (già scaricati ed estratti):
  --renios8  cartella con renios/ di Ren'Py 8.x  (renpy-8.x-renios.zip)
  --renios7  cartella con renios/ di Ren'Py 7.x  (renpy-7.x-renios.zip)
  --sdk8     cartella con l'SDK di Ren'Py 8.x    (renpy-8.x-sdk.tar.bz2)
  --sdk7     cartella con l'SDK di Ren'Py 7.x    (renpy-7.x-sdk.tar.bz2)

Uscita: --out <cartella>/RenPlayer.xcodeproj pronto per xcodebuild.

Il runtime Ren'Py 8 viene linkato normalmente; quello di Ren'Py 7 (Python 2)
viene "prelinkato" in rt7/rp7.o nascondendo tutti i simboli tranne il punto
di ingresso, rinominato in _rp7_lnch_main, così i due Python convivono.
"""

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

PRODUCT = "RenPlayer"
RP7_SYMBOL = "_rp7_lnch_main"
RP85_SYMBOL = "_rp85lnch_main"
ORIG_SYMBOL = "_launcher_main"


def log(*args):
    print("[assemble]", *args, flush=True)


def fail(msg):
    print("[assemble] ERRORE:", msg, file=sys.stderr, flush=True)
    sys.exit(1)


def find_one(path, pattern):
    """Ritorna l'unica sottocartella di `path` che corrisponde a `pattern`, o path stesso."""
    for root, dirs, files in os.walk(path):
        for d in dirs:
            if re.fullmatch(pattern, d):
                return os.path.join(root, d)
    return None


def sdk_root(path):
    if os.path.exists(os.path.join(path, "renpy.py")):
        return path
    for d in sorted(os.listdir(path)):
        p = os.path.join(path, d)
        if os.path.isdir(p) and os.path.exists(os.path.join(p, "renpy.py")):
            return p
    fail("SDK di Ren'Py non trovato in " + path)


def renios_prototype(path):
    for cand in [os.path.join(path, "renios", "prototype"), os.path.join(path, "prototype")]:
        if os.path.exists(os.path.join(cand, "prototype.xcodeproj", "project.pbxproj")):
            return cand
    fail("renios/prototype non trovato in " + path)


def python_version(proto):
    rel = os.path.join(proto, "prebuilt", "release")
    for f in sorted(os.listdir(rel)):
        m = re.fullmatch(r"libpython(\d\.\d+)\.a", f)
        if m:
            return m.group(1)
    fail("libpythonX.Y.a non trovata in " + rel)


def sdk_version(root):
    renpy = os.path.join(root, "renpy")
    candidates = [os.path.join(renpy, n) for n in ("vc_version.py", "vc_version.pyo", "vc_version.pyc")]
    pycache = os.path.join(renpy, "__pycache__")
    if os.path.isdir(pycache):
        candidates += [os.path.join(pycache, n) for n in sorted(os.listdir(pycache)) if n.startswith("vc_version.")]

    for fn in candidates:
        if not os.path.exists(fn):
            continue
        data = open(fn, "rb").read()
        m = re.search(rb"(?<![0-9.])([6-9]\.\d+\.\d+\.\d+)(?![0-9.])", data)
        if m:
            return m.group(1).decode()

    # Ultima possibilità: il nome della cartella (renpy-7.8.7-sdk).
    m = re.search(r"renpy-(\d+\.\d+\.\d+)", os.path.basename(os.path.abspath(root)))
    if m:
        return m.group(1)
    return "?"


# --------------------------------------------------------------------------
# Cartelle base dei runtime
# --------------------------------------------------------------------------

SAVES_PATCH = '''
# --- RenPlayer -------------------------------------------------------------
# Su iOS Ren'Py salverebbe tutto nella cartella Documents dell'app, uguale per
# tutti i giochi. RenPlayer passa una cartella per ogni gioco.
_renplayer_path_to_saves = path_to_saves

def path_to_saves(gamedir, save_directory=None):
    if "RENPLAYER_SAVEDIR" in os.environ:
        if save_directory is None:
            return os.environ["RENPLAYER_SAVEDIR"]
        return os.path.join(os.environ.get("RENPLAYER_DATADIR", os.environ["RENPLAYER_SAVEDIR"]), save_directory)
    return _renplayer_path_to_saves(gamedir, save_directory)

# Moduli Python del gioco (lib/pythonX.Y della versione PC), dopo la libreria standard.
if os.environ.get("RENPLAYER_PYLIB"):
    for _renplayer_p in os.environ["RENPLAYER_PYLIB"].split(":"):
        if _renplayer_p and os.path.isdir(_renplayer_p) and _renplayer_p not in sys.path:
            sys.path.append(_renplayer_p)


class _RenPlayerGameModules(object):
    """
    Ultima risorsa per gli import: cerca il modulo tra i file del gioco, anche
    dentro gli archivi .rpa e in sottocartelle (es. game/src/saga), che
    l'importatore standard di Ren'Py non guarda. Carica sia .py sia .pyc.
    """

    def __init__(self):
        self.index = None

    def _build(self):
        if self.index is not None:
            return self.index
        loader = sys.modules.get("renpy.loader")
        files = getattr(loader, "game_files", None) if loader is not None else None
        if not files:
            return None

        names = set()
        tops = {}
        for _d, fn in files:
            fn = fn.replace(chr(92), "/")
            names.add(fn)
            if not (fn.endswith(".py") or fn.endswith(".pyc")):
                continue
            parts = fn.split("/")
            for i, part in enumerate(parts):
                if i == len(parts) - 1:
                    part = part.rpartition(".")[0]
                if not part or part == "__init__":
                    continue
                prefix = "/".join(parts[:i])
                if prefix:
                    prefix += "/"
                old = tops.get(part)
                if old is None or len(prefix) < len(old):
                    tops[part] = prefix

        self.index = (names, tops)
        return self.index

    def _locate(self, fullname):
        index = self._build()
        if not index:
            return None
        names, tops = index
        parts = fullname.split(".")
        prefix = tops.get(parts[0])
        if prefix is None:
            return None
        base = prefix + "/".join(parts)
        for fn, pkg in ((base + "/__init__.py", True), (base + ".py", False),
                        (base + "/__init__.pyc", True), (base + ".pyc", False)):
            if fn in names:
                return fn, pkg
        for n in names:
            if n.startswith(base + "/"):
                return None, True
        return None

    def find_module(self, fullname, path=None):
        if self._locate(fullname):
            return self
        return None

    def find_spec(self, fullname, path, target=None):
        found = self._locate(fullname)
        if not found:
            return None
        import importlib.util
        return importlib.util.spec_from_loader(fullname, self, is_package=found[1])

    def create_module(self, spec):
        return None

    def _code(self, fn):
        if fn is None:
            return compile("", "<renplayer namespace>", "exec")
        f = sys.modules["renpy.loader"].load(fn, tl=False)
        try:
            data = f.read()
        finally:
            f.close()
        if fn.endswith(".pyc"):
            import marshal
            if sys.version_info >= (3, 7):
                skip = 16
            elif sys.version_info >= (3, 3):
                skip = 12
            else:
                skip = 8
            return marshal.loads(data[skip:])
        import codecs
        if data.startswith(codecs.BOM_UTF8):
            data = data[3:]
        return compile(data, fn, "exec")

    def _prepare(self, module, fullname):
        fn, pkg = self._locate(fullname)
        module.__file__ = fn or fullname
        module.__loader__ = self
        if pkg:
            module.__path__ = []
            module.__package__ = fullname
        else:
            module.__package__ = fullname.rpartition(".")[0]
        print("RenPlayer: modulo %s caricato da %s" % (fullname, fn))
        return self._code(fn)

    def exec_module(self, module):
        code = self._prepare(module, module.__name__)
        exec(code, module.__dict__)

    def load_module(self, fullname):
        if fullname in sys.modules:
            return sys.modules[fullname]
        import types
        module = types.ModuleType(fullname)
        sys.modules[fullname] = module
        try:
            code = self._prepare(module, fullname)
            exec(code, module.__dict__)
        except Exception:
            del sys.modules[fullname]
            raise
        return sys.modules[fullname]


sys.meta_path.append(_RenPlayerGameModules())
# ---------------------------------------------------------------------------


'''


ENGINE_PATCH = '''
# --- RenPlayer -------------------------------------------------------------
# Opzione "motore del gioco": usa la cartella renpy/ della versione PC (copiata
# in renplayer-engine/) con le parti native di questo runtime.
_renplayer_engine = os.environ.get("RENPLAYER_ENGINE")
if _renplayer_engine and os.path.isdir(os.path.join(_renplayer_engine, "renpy")):
    sys.path.insert(0, _renplayer_engine)

    def path_to_renpy_base():
        return _renplayer_engine
# ---------------------------------------------------------------------------


'''


def make_main_py(sdk, dest):
    src = open(os.path.join(sdk, "renpy.py"), encoding="utf-8").read()
    lines = [l for l in src.splitlines(True) if not l.startswith("#!")]
    src = "".join(lines)

    marker = "def path_to_renpy_base"
    if src.count(marker) != 1 or "def path_to_saves(" not in src:
        fail("renpy.py ha una forma inattesa: impossibile applicare la patch dei salvataggi.")

    src = src.replace(marker, SAVES_PATCH.lstrip("\n") + marker, 1)

    marker2 = "def path_to_logdir"
    if src.count(marker2) != 1:
        fail("renpy.py ha una forma inattesa: impossibile applicare la patch del motore.")
    src = src.replace(marker2, ENGINE_PATCH.lstrip("\n") + marker2, 1)

    with open(dest, "w", encoding="utf-8") as f:
        f.write(src)


CODE_EXT_DROP = (".pyx", ".pxd", ".pxi", ".c", ".h", ".pyi", ".orig", ".rej")


def build_base(sdk, pyver, dest):
    """
    Riproduce il pacchetto "ios" di Ren'Py: main.py, renpy/ compilato, lib/pythonX.Y.
    """
    py2 = pyver.startswith("2")

    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)

    make_main_py(sdk, os.path.join(dest, "main.py"))

    shutil.copytree(os.path.join(sdk, "renpy"), os.path.join(dest, "renpy"),
                    ignore=shutil.ignore_patterns(*["*" + e for e in CODE_EXT_DROP]))

    renpy_dir = os.path.join(dest, "renpy")
    tag = "cpython-" + pyver.replace(".", "")

    compiled = 0
    for root, dirs, files in os.walk(renpy_dir, topdown=False):
        base = os.path.basename(root)

        if base == "__pycache__":
            parent = os.path.dirname(root)
            for f in files:
                m = re.fullmatch(r"(.+)\.([a-z]+-\d+)(\.opt-\d)?\.pyc", f)
                if m and m.group(2) == tag and not m.group(3):
                    target = os.path.join(parent, m.group(1) + ".pyc")
                    if not os.path.exists(target):
                        shutil.move(os.path.join(root, f), target)
            shutil.rmtree(root)
            continue

    # Toglie i sorgenti dove c'è la versione compilata (come fa Ren'Py per iOS).
    compiled_ext = ".pyo" if py2 else ".pyc"
    for root, dirs, files in os.walk(renpy_dir):
        names = set(files)
        for f in files:
            stem, ext = os.path.splitext(f)
            if ext == ".py" and (stem + compiled_ext) in names:
                os.unlink(os.path.join(root, f))
            elif ext == ".rpy" and (stem + ".rpyc") in names:
                os.unlink(os.path.join(root, f))
            elif ext == ".rpym" and (stem + ".rpymc") in names:
                os.unlink(os.path.join(root, f))
            if ext == compiled_ext:
                compiled += 1
            if py2 and ext == ".pyc":
                os.unlink(os.path.join(root, f))

    if compiled == 0:
        log("ATTENZIONE: nessun file %s compilato in renpy/ (%s): Python compilerà all'avvio." % (compiled_ext, sdk))

    libsrc = os.path.join(sdk, "lib", "python" + pyver)
    if not os.path.isdir(libsrc):
        fail("Manca la libreria standard " + libsrc)
    shutil.copytree(libsrc, os.path.join(dest, "lib", "python" + pyver))

    site = os.path.join(dest, "lib", "python" + pyver, "site.pyo" if py2 else "site.pyc")
    if not os.path.exists(site):
        fail("Manca %s: il runtime non troverebbe Python." % site)

    size = 0
    for root, dirs, files in os.walk(dest):
        for f in files:
            size += os.path.getsize(os.path.join(root, f))
    log("base %s: %d file compilati, %.1f MB" % (dest, compiled, size / 1e6))


# --------------------------------------------------------------------------
# Prelink di Ren'Py 7
# --------------------------------------------------------------------------

def run(cmd, check=True):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if check and p.returncode:
        raise subprocess.CalledProcessError(p.returncode, cmd, p.stdout, p.stderr)
    return p


def nm(args, obj):
    p = run(["xcrun", "nm"] + args + [obj], check=False)
    return p.stdout.splitlines()


def verify_prelink(obj, symbol, forbidden=frozenset()):
    defined = [l.split()[-1] for l in nm(["-gU"], obj) if l.strip()]
    if defined != [symbol]:
        return "simboli esterni definiti inattesi: %r" % defined[:20]

    undefined = [l.split()[-1] for l in nm(["-u"], obj) if l.strip()]
    bad = [s for s in undefined if re.match(r"^_(_?Py|init_librenpy|launcher_main|Py_)", s)]
    if bad:
        return "simboli Python non risolti (finirebbero sul Python sbagliato!): %r" % bad[:20]

    clash = sorted(set(undefined) & forbidden)
    if clash:
        return "simboli non risolti che finirebbero sulle librerie C di un altro runtime: %r" % clash[:20]

    private = [l for l in nm(["-m"], obj) if "private external" in l and "was a private external" not in l]
    if private:
        return "restano %d simboli 'private external' (conflitti al link): %r" % (len(private), private[:5])

    return None


def rename_symbol(obj, symbol):
    data = open(obj, "rb").read()
    old = b"\x00" + ORIG_SYMBOL.encode() + b"\x00"
    new = b"\x00" + symbol.encode() + b"\x00"
    n = data.count(old)
    if n != 1:
        raise Exception("trovate %d occorrenze di %s nella tabella dei simboli" % (n, ORIG_SYMBOL))
    with open(obj, "wb") as f:
        f.write(data.replace(old, new))


def defined_symbols(libs):
    """Simboli globali definiti in una serie di librerie statiche."""
    rv = set()
    for l in libs:
        for line in nm(["-gUj"], l):
            line = line.strip()
            if line and not line.endswith(":"):
                rv.add(line)
    return rv


def prelink(name, libs, symbol, out, minos, forbidden=frozenset()):
    """
    Unisce le librerie di un runtime in un unico oggetto con tutti i simboli
    nascosti tranne il punto di ingresso, rinominato in `symbol`.
    """
    assert len(symbol) == len(ORIG_SYMBOL)

    for l in libs:
        if not os.path.exists(l):
            fail("Manca " + l)

    os.makedirs(os.path.dirname(out), exist_ok=True)

    base = ["xcrun", "-sdk", "iphoneos", "clang", "-arch", "arm64",
            "-miphoneos-version-min=" + minos, "-r", "-nostdlib", "-Wl,-u," + ORIG_SYMBOL]

    attempts = []
    for classic in (False, True):
        for mode in ("alias", "rename"):
            for force_common in (True, False):
                cmd = list(base)
                if classic:
                    cmd.append("-Wl,-ld_classic")
                if force_common:
                    cmd.append("-Wl,-d")
                if mode == "alias":
                    cmd += ["-Wl,-alias," + ORIG_SYMBOL + "," + symbol, "-Wl,-exported_symbol," + symbol]
                else:
                    cmd += ["-Wl,-exported_symbol," + ORIG_SYMBOL]
                cmd += libs + ["-o", out]
                attempts.append(("%s%s%s" % (mode, "+classic" if classic else "", "+d" if force_common else ""), mode, cmd))

    errors = []
    for aname, mode, cmd in attempts:
        if os.path.exists(out):
            os.unlink(out)
        try:
            run(cmd)
            if mode == "rename":
                rename_symbol(out, symbol)
            problem = verify_prelink(out, symbol, forbidden)
            if problem:
                errors.append("%s: %s" % (aname, problem))
                continue
            log("prelink %s riuscito (%s): %s, %.1f MB" % (name, aname, out, os.path.getsize(out) / 1e6))
            return
        except subprocess.CalledProcessError as e:
            errors.append("%s: ld ha fallito: %s" % (aname, (e.stderr or e.stdout or "").strip()[-800:]))
        except Exception as e:
            errors.append("%s: %s" % (aname, e))

    for e in errors:
        print("  -", e, file=sys.stderr)
    fail("prelink di %s non riuscito con nessuna strategia." % name)


SHARED_LIBS = ("libSDL2.a", "libSDL2_image.a")
RUNTIME_LIBS = ("librenpython.a", "librenpy.a")


def c_libs(libdir):
    return sorted(f for f in os.listdir(libdir)
                  if f.endswith(".a") and f not in RUNTIME_LIBS and not f.startswith("libpython"))


# --------------------------------------------------------------------------
# Progetto Xcode
# --------------------------------------------------------------------------

def object_id(name):
    return hashlib.md5(("renplayer:" + name).encode()).hexdigest()[:24].upper()


def sub_once(pattern, repl, text, what, count=1, flags=0):
    new, n = re.subn(pattern, repl, text, count=0, flags=flags)
    if n < count:
        fail("modifica al progetto Xcode non applicata (%s): trovate %d occorrenze" % (what, n))
    return new


def add_sources(pbx, files):
    """Aggiunge file sorgente al gruppo principale e alla fase Sources."""
    m = re.search(r"mainGroup = ([0-9A-F]{24});", pbx)
    if not m:
        fail("mainGroup non trovato nel progetto")
    main_group = m.group(1)

    buildfiles = []
    filerefs = []
    group_children = []
    source_entries = []

    for fn in files:
        ext = os.path.splitext(fn)[1]
        ftype = {".m": "sourcecode.c.objc", ".c": "sourcecode.c.c", ".h": "sourcecode.c.h"}[ext]
        ref = object_id("ref:" + fn)
        filerefs.append('\t\t%s /* %s */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = %s; path = "%s"; sourceTree = "<group>"; };\n' % (ref, fn, ftype, fn))
        group_children.append("\t\t\t\t%s /* %s */,\n" % (ref, fn))
        if ext in (".m", ".c"):
            bf = object_id("build:" + fn)
            buildfiles.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (bf, fn, ref, fn))
            source_entries.append("\t\t\t\t%s /* %s in Sources */,\n" % (bf, fn))

    pbx = pbx.replace("/* End PBXBuildFile section */", "".join(buildfiles) + "/* End PBXBuildFile section */", 1)
    pbx = pbx.replace("/* End PBXFileReference section */", "".join(filerefs) + "/* End PBXFileReference section */", 1)

    # Figli del gruppo principale.
    gm = re.search(r"(\t\t%s (?:/\* .*? \*/ )?= \{\s*isa = PBXGroup;\s*children = \(\n)" % main_group, pbx)
    if not gm:
        fail("gruppo principale non trovato")
    pbx = pbx[:gm.end()] + "".join(group_children) + pbx[gm.end():]

    # Fase Sources.
    sm = re.search(r"(isa = PBXSourcesBuildPhase;\s*buildActionMask = \d+;\s*files = \(\n)", pbx)
    if not sm:
        fail("fase Sources non trovata")
    pbx = pbx[:sm.end()] + "".join(source_entries) + pbx[sm.end():]

    return pbx


def rewrite_ldflags(pbx):
    def repl(m):
        body = m.group(1)
        items = re.findall(r'"([^"]+)"|([^\s,()]+)', body)
        flags = [a or b for a, b in items]
        if "-lrenpython" not in flags:
            return m.group(0)
        out = []
        for f in flags:
            if f.startswith("-lpython"):
                if "-lpython3.9" not in out:
                    out.append("-lpython3.9")
                    out.append("$(SRCROOT)/rt7/rp7.o")
                    out.append("$(SRCROOT)/rt85/rp85.o")
            elif f in ("-lstdc++", "-lc++"):
                continue
            else:
                out.append(f)
        out.append("-lc++")
        lines = "".join('\t\t\t\t\t"%s",\n' % f for f in out)
        return "OTHER_LDFLAGS = (\n%s\t\t\t\t);" % lines

    new, n = re.subn(r"OTHER_LDFLAGS = \((.*?)\);", repl, pbx, flags=re.S)
    if new.count("rt7/rp7.o") < 2 or new.count("rt85/rp85.o") < 2:
        fail("OTHER_LDFLAGS non aggiornati (%d)" % new.count("rt7/rp7.o"))
    return new


def build_pbxproj(pbx, bundle_id, sources, minos, app_version):
    # main.c -> main.m (il nostro main è Objective-C)
    pbx = sub_once(r"lastKnownFileType = sourcecode\.c\.c; path = main\.c;",
                   "lastKnownFileType = sourcecode.c.objc; path = main.m;", pbx, "main.m")
    pbx = pbx.replace("/* main.c */", "/* main.m */").replace("/* main.c in Sources */", "/* main.m in Sources */")

    # base -> runtimes (cartella con rt7/ e rt8/)
    pbx = sub_once(r"lastKnownFileType = folder; path = base;", "lastKnownFileType = folder; path = runtimes;", pbx, "runtimes")
    pbx = pbx.replace("/* base */", "/* runtimes */").replace("/* base in Resources */", "/* runtimes in Resources */")

    pbx = rewrite_ldflags(pbx)

    pbx = sub_once(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = %s;" % minos, pbx, "deployment target")
    pbx = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = [^;]+;", "PRODUCT_BUNDLE_IDENTIFIER = %s;" % bundle_id, pbx)
    pbx = re.sub(r"DEVELOPMENT_TEAM = [^;]+;", 'DEVELOPMENT_TEAM = "";', pbx)
    pbx = re.sub(r"\n\s*DevelopmentTeam = [^;]+;", "", pbx)
    pbx = re.sub(r'"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = "[^"]*";', '"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "";', pbx)

    pbx = add_sources(pbx, sources)

    # Nome del prodotto/target.
    pbx = pbx.replace("prototype", PRODUCT)
    return pbx


def write_info_plist(path, version):
    plist = {
        "CFBundleDevelopmentRegion": "it",
        "CFBundleDisplayName": PRODUCT,
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleSignature": "????",
        "CFBundleVersion": "1",
        "LSRequiresIPhoneOS": True,
        "UILaunchStoryboardName": "Launch Screen",
        "UIRequiresFullScreen": True,
        "UIStatusBarHidden": True,
        "UIApplicationSupportsIndirectInputEvents": True,
        "UISupportedInterfaceOrientations": [
            "UIInterfaceOrientationLandscapeRight",
            "UIInterfaceOrientationLandscapeLeft",
        ],
        "UISupportedInterfaceOrientations~ipad": [
            "UIInterfaceOrientationLandscapeRight",
            "UIInterfaceOrientationLandscapeLeft",
        ],
        # Cartella Documents visibile nell'app File.
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
        # "Apri con RenPlayer" per gli zip.
        "CFBundleDocumentTypes": [
            {
                "CFBundleTypeName": "Archivio ZIP",
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "Alternate",
                "LSItemContentTypes": ["public.zip-archive", "com.pkware.zip-archive"],
            },
        ],
        "ITSAppUsesNonExemptEncryption": False,
    }
    with open(path, "wb") as f:
        plistlib.dump(plist, f)


def write_icon(project, app):
    src = os.path.join(app, "icon.png")
    iconset = os.path.join(project, "Media.xcassets", "AppIcon.appiconset")
    if not os.path.exists(src):
        log("icona non trovata, uso quella del prototipo")
        return
    if os.path.exists(iconset):
        shutil.rmtree(iconset)
    os.makedirs(iconset)
    shutil.copy(src, os.path.join(iconset, "icon.png"))
    with open(os.path.join(iconset, "Contents.json"), "w") as f:
        json.dump({
            "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }, f, indent=2)


def compare_libs(dir7, dir8):
    """Le librerie C devono essere le stesse per i due runtime."""
    shared = []
    for fn in sorted(os.listdir(dir8)):
        if not fn.endswith(".a") or fn in ("librenpython.a", "librenpy.a") or fn.startswith("libpython"):
            continue
        p7 = os.path.join(dir7, fn)
        if not os.path.exists(p7):
            log("ATTENZIONE: %s manca in Ren'Py 7" % fn)
            continue
        h7 = hashlib.sha256(open(p7, "rb").read()).hexdigest()
        h8 = hashlib.sha256(open(os.path.join(dir8, fn), "rb").read()).hexdigest()
        shared.append((fn, h7 == h8))
    same = sum(1 for _, s in shared if s)
    log("librerie C identiche tra 7 e 8: %d su %d" % (same, len(shared)))
    for fn, s in shared:
        if not s:
            log("  diversa: %s (atteso se cambia solo la data negli archivi)" % fn)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--renios7", required=True)
    ap.add_argument("--renios8", required=True)
    ap.add_argument("--sdk7", required=True)
    ap.add_argument("--sdk8", required=True)
    ap.add_argument("--renios85", required=True)
    ap.add_argument("--sdk85", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--app", default=os.path.join(REPO, "app"))
    ap.add_argument("--bundle-id", default="io.github.renplayer")
    ap.add_argument("--version", default="1.0")
    ap.add_argument("--minos", default="15.0")
    ap.add_argument("--skip-prelink", action="store_true", help="solo per prove senza Xcode")
    args = ap.parse_args()

    proto8 = renios_prototype(args.renios8)
    proto7 = renios_prototype(args.renios7)
    proto85 = renios_prototype(args.renios85)
    sdk8 = sdk_root(args.sdk8)
    sdk7 = sdk_root(args.sdk7)
    sdk85 = sdk_root(args.sdk85)

    v8 = sdk_version(sdk8)
    v7 = sdk_version(sdk7)
    v85 = sdk_version(sdk85)
    log("Ren'Py 8:", v8, sdk8)
    log("Ren'Py 7:", v7, sdk7)
    log("Ren'Py 8.5:", v85, sdk85)

    out = args.out
    if os.path.exists(out):
        shutil.rmtree(out)

    # 1. Prototipo di Ren'Py 8 (contiene le librerie C e MetalANGLE).
    shutil.copytree(proto8, out, symlinks=True, ignore=shutil.ignore_patterns(
        "base", "project.xcworkspace", "xcuserdata", "xcshareddata", ".DS_Store", "debug"))

    rel8 = os.path.join(out, "prebuilt", "release")
    rel7 = os.path.join(proto7, "prebuilt", "release")
    if not os.path.isdir(rel8):
        fail("prebuilt/release mancante nel renios di Ren'Py 8")

    for need in ("librenpython.a", "librenpy.a", "libpython3.9.a", "libSDL2.a"):
        if not os.path.exists(os.path.join(rel8, need)):
            fail("Manca %s nel renios di Ren'Py 8 (versione con Python diverso da 3.9?)" % need)

    if os.path.isdir(rel7):
        compare_libs(rel7, rel8)

    # 2. Sorgenti di RenPlayer.
    os.unlink(os.path.join(out, "main.c"))
    sources = []
    for sub in ("src", "core"):
        d = os.path.join(args.app, sub)
        for fn in sorted(os.listdir(d)):
            if os.path.splitext(fn)[1] not in (".m", ".c", ".h"):
                continue
            shutil.copy(os.path.join(d, fn), os.path.join(out, fn))
            if fn not in ("main.m", "Log.m"):
                sources.append(fn)

    with open(os.path.join(out, "rpconfig.h"), "w") as f:
        f.write('#define RP_RUNTIME7_VERSION "%s"\n' % ".".join(v7.split(".")[:3]))
        f.write('#define RP_RUNTIME8_VERSION "%s"\n' % ".".join(v8.split(".")[:3]))
        f.write('#define RP_RUNTIME85_VERSION "%s"\n' % ".".join(v85.split(".")[:3]))
    sources.append("rpconfig.h")

    # 3. Progetto Xcode.
    xcp_old = os.path.join(out, "prototype.xcodeproj")
    xcp = os.path.join(out, PRODUCT + ".xcodeproj")
    os.rename(xcp_old, xcp)
    pbx_path = os.path.join(xcp, "project.pbxproj")
    pbx = open(pbx_path, encoding="utf-8").read()
    pbx = build_pbxproj(pbx, args.bundle_id, sources, args.minos, args.version)
    with open(pbx_path, "w", encoding="utf-8") as f:
        f.write(pbx)

    write_info_plist(os.path.join(out, "Info.plist"), args.version)
    write_icon(out, args.app)

    # 4. Runtime.
    runtimes = os.path.join(out, "runtimes")
    build_base(sdk8, "3.9", os.path.join(runtimes, "rt8", "base"))
    build_base(sdk7, "2.7", os.path.join(runtimes, "rt7", "base"))
    build_base(sdk85, python_version(proto85), os.path.join(runtimes, "rt85", "base"))
    with open(os.path.join(runtimes, "versions.json"), "w") as f:
        json.dump({"rt7": v7, "rt8": v8, "rt85": v85}, f)

    # 5. Ren'Py 7 prelinkato.
    rel85 = os.path.join(proto85, "prebuilt", "release")
    py85 = python_version(proto85)

    if args.skip_prelink:
        log("prelink saltato (--skip-prelink)")
    else:
        # Ren'Py 7: stesse librerie C di Ren'Py 8.3 (stessa build), solo Python e renpy.
        prelink("Ren'Py 7", [os.path.join(rel7, n) for n in ("librenpython.a", "librenpy.a", "libpython2.7.a")],
                RP7_SYMBOL, os.path.join(out, "rt7", "rp7.o"), args.minos)

        # Ren'Py 8.5: build diversa, porta con sé tutte le sue librerie C tranne SDL2,
        # che deve essere unica (registra classi Objective-C) ed è la stessa versione.
        libs85 = [os.path.join(rel85, n) for n in ("librenpython.a", "librenpy.a", "libpython%s.a" % py85)]
        libs85 += [os.path.join(rel85, n) for n in c_libs(rel85) if n not in SHARED_LIBS]
        forbidden = defined_symbols([os.path.join(rel8, n) for n in c_libs(rel8) if n not in SHARED_LIBS])
        log("Ren'Py 8.5: %d librerie, %d simboli C di 8.3 da non toccare" % (len(libs85), len(forbidden)))
        prelink("Ren'Py 8.5", libs85, RP85_SYMBOL, os.path.join(out, "rt85", "rp85.o"), args.minos, forbidden)

    log("progetto pronto:", xcp)


if __name__ == "__main__":
    main()
