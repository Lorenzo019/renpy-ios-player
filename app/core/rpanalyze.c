/*
 * Analisi di un gioco Ren'Py distribuito per PC/Mac/Linux:
 *  - trova la cartella radice (quella che contiene game/)
 *  - rileva la versione di Ren'Py e di Python
 *  - sceglie il runtime (Ren'Py 7 = Python 2, Ren'Py 8 = Python 3)
 */

#include "rpcore.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int has_prefix(const char *s, const char *p) {
    return strncmp(s, p, strlen(p)) == 0;
}

static int ends_with(const char *s, const char *suf) {
    size_t a = strlen(s);
    size_t b = strlen(suf);
    return a >= b && strcmp(s + a - b, suf) == 0;
}

static int ends_with_ci(const char *s, const char *suf) {
    size_t a = strlen(s);
    size_t b = strlen(suf);
    if (a < b) {
        return 0;
    }
    const char *t = s + a - b;
    for (size_t i = 0; i < b; i++) {
        if (tolower((unsigned char) t[i]) != tolower((unsigned char) suf[i])) {
            return 0;
        }
    }
    return 1;
}

static const char *base_name(const char *p) {
    const char *s = strrchr(p, '/');
    return s ? s + 1 : p;
}

static int is_script_file(const char *p) {
    return ends_with(p, ".rpa") || ends_with(p, ".rpyc") || ends_with(p, ".rpy") ||
           ends_with(p, ".rpymc") || ends_with(p, ".rpym") || ends_with(p, ".rpi");
}

static void append(char *dst, size_t dstlen, const char *fmt, const char *arg) {
    size_t l = strlen(dst);
    if (l + 1 >= dstlen) {
        return;
    }
    snprintf(dst + l, dstlen - l, fmt, arg);
}

/* ------------------------------------------------------------------------ */
/* Radice del gioco                                                          */
/* ------------------------------------------------------------------------ */

typedef struct {
    char *root;
    size_t len;
    int scripts;
    int files;
    int has_renpy;
} candidate;

static void find_root(const char *const *paths, size_t n, rp_analysis *out) {
    candidate *c = NULL;
    size_t nc = 0;
    size_t cap = 0;

    for (size_t i = 0; i < n; i++) {
        const char *p = paths[i];

        if (has_prefix(p, "__MACOSX/") || strstr(p, "/__MACOSX/")) {
            continue;
        }

        for (size_t k = 0; p[k]; k++) {
            if ((k == 0 || p[k - 1] == '/') && strncmp(p + k, "game/", 5) == 0 && p[k + 5]) {
                /* candidato: p[0..k) */
                size_t j;
                for (j = 0; j < nc; j++) {
                    if (c[j].len == k && strncmp(c[j].root, p, k) == 0) {
                        break;
                    }
                }

                if (j == nc) {
                    if (nc == cap) {
                        cap = cap ? cap * 2 : 8;
                        candidate *nc2 = (candidate *) realloc(c, cap * sizeof(candidate));
                        if (!nc2) {
                            goto done;
                        }
                        c = nc2;
                    }
                    c[nc].root = (char *) malloc(k + 1);
                    if (!c[nc].root) {
                        goto done;
                    }
                    memcpy(c[nc].root, p, k);
                    c[nc].root[k] = 0;
                    c[nc].len = k;
                    c[nc].scripts = 0;
                    c[nc].files = 0;
                    c[nc].has_renpy = 0;
                    nc++;
                }

                c[j].files++;
                if (is_script_file(p)) {
                    c[j].scripts++;
                }
            }
        }
    }

    for (size_t j = 0; j < nc; j++) {
        for (size_t i = 0; i < n; i++) {
            if (strncmp(paths[i], c[j].root, c[j].len) == 0 && has_prefix(paths[i] + c[j].len, "renpy/")) {
                c[j].has_renpy = 1;
                break;
            }
        }
    }

    {
        long best = -1;
        size_t bi = 0;
        for (size_t j = 0; j < nc; j++) {
            long score = 0;
            if (c[j].scripts) {
                score += 1000000;
            }
            if (c[j].has_renpy) {
                score += 100000;
            }
            /* A parità, la radice più corta. */
            score += 10000 - (long) (c[j].len > 9999 ? 9999 : c[j].len);

            if (score > best) {
                best = score;
                bi = j;
            }
        }

        if (best >= 0 && c[bi].len < sizeof(out->root)) {
            memcpy(out->root, c[bi].root, c[bi].len + 1);
            out->found = 1;
        }
    }

done:
    for (size_t j = 0; j < nc; j++) {
        free(c[j].root);
    }
    free(c);
}

/* ------------------------------------------------------------------------ */
/* Lettura della versione                                                    */
/* ------------------------------------------------------------------------ */

static int is_vchar(unsigned char ch) {
    return isdigit(ch) || ch == '.';
}

/* Cerca "a.b.c[.d]" con a in 6..9. Preferisce le versioni a 4 componenti. */
static int scan_version(const unsigned char *buf, size_t len, char *out, size_t outlen) {
    char best[64] = "";
    int best_parts = 0;

    for (size_t i = 0; i < len; i++) {
        if (!isdigit(buf[i]) || (i > 0 && is_vchar(buf[i - 1]))) {
            continue;
        }

        size_t j = i;
        while (j < len && is_vchar(buf[j])) {
            j++;
        }

        size_t L = j - i;
        if (L < 5 || L >= sizeof(best)) {
            continue;
        }

        char tmp[64];
        memcpy(tmp, buf + i, L);
        tmp[L] = 0;

        /* Toglie un eventuale punto finale. */
        while (L > 0 && tmp[L - 1] == '.') {
            tmp[--L] = 0;
        }

        int parts = 1;
        int bad = 0;
        for (size_t k = 0; k < L; k++) {
            if (tmp[k] == '.') {
                if (k + 1 < L && tmp[k + 1] == '.') {
                    bad = 1;
                }
                parts++;
            }
        }

        if (bad || parts < 3 || parts > 4) {
            continue;
        }

        int major = atoi(tmp);
        if (major < 6 || major > 9 || tmp[1] != '.') {
            continue;
        }

        if (parts > best_parts) {
            snprintf(best, sizeof(best), "%s", tmp);
            best_parts = parts;
        }

        i = j;
    }

    if (best_parts) {
        snprintf(out, outlen, "%s", best);
        return 1;
    }

    return 0;
}

/* version_tuple = (7, 4, 10, vc_version) */
static int scan_version_tuple(const unsigned char *buf, size_t len, char *out, size_t outlen) {
    const char *key = "version_tuple";
    size_t kl = strlen(key);

    for (size_t i = 0; i + kl < len; i++) {
        if (memcmp(buf + i, key, kl)) {
            continue;
        }

        size_t j = i + kl;
        while (j < len && (buf[j] == ' ' || buf[j] == '\t')) {
            j++;
        }
        if (j >= len || buf[j] != '=') {
            continue;
        }
        j++;
        while (j < len && (buf[j] == ' ' || buf[j] == '\t')) {
            j++;
        }
        if (j >= len || buf[j] != '(') {
            continue;
        }
        j++;

        int nums[3];
        int got = 0;
        while (got < 3 && j < len) {
            while (j < len && (buf[j] == ' ' || buf[j] == '\t')) {
                j++;
            }
            if (j >= len || !isdigit(buf[j])) {
                break;
            }
            int v = 0;
            while (j < len && isdigit(buf[j])) {
                v = v * 10 + (buf[j] - '0');
                j++;
            }
            nums[got++] = v;
            while (j < len && (buf[j] == ' ' || buf[j] == '\t')) {
                j++;
            }
            if (j < len && buf[j] == ',') {
                j++;
            }
        }

        if (got == 3 && nums[0] >= 6 && nums[0] <= 9) {
            snprintf(out, outlen, "%d.%d.%d", nums[0], nums[1], nums[2]);
            return 1;
        }
    }

    return 0;
}

static int find_path(const char *const *paths, size_t n, const char *full) {
    for (size_t i = 0; i < n; i++) {
        if (strcmp(paths[i], full) == 0) {
            return (int) i;
        }
    }
    return -1;
}

/* Estrae "X.Y" da "cpython-39" o "cpython-312". */
static void tag_from_cpython(const char *s, char *out, size_t outlen) {
    const char *p = strstr(s, "cpython-");
    if (!p) {
        return;
    }
    p += 8;
    if (!isdigit((unsigned char) p[0]) || !isdigit((unsigned char) p[1])) {
        return;
    }
    char rest[8];
    size_t k = 0;
    const char *q = p + 1;
    while (isdigit((unsigned char) *q) && k < sizeof(rest) - 1) {
        rest[k++] = *q++;
    }
    rest[k] = 0;
    snprintf(out, outlen, "%c.%s", p[0], rest);
}

/* Estrae "X.Y" da "lib/python3.9/..." */
static void tag_from_libdir(const char *rel, char *out, size_t outlen) {
    const char *p = rel + strlen("lib/python");
    size_t k = 0;
    char tmp[16];
    while (p[k] && p[k] != '/' && k < sizeof(tmp) - 1) {
        tmp[k] = p[k];
        k++;
    }
    tmp[k] = 0;
    if (k >= 3 && isdigit((unsigned char) tmp[0]) && tmp[1] == '.') {
        snprintf(out, outlen, "%s", tmp);
    }
}

/* Legge una stringa assegnata: <key> = _("...") oppure <key> = "..." */
static int scan_assignment(const unsigned char *buf, size_t len, const char *key, char *out, size_t outlen) {
    size_t kl = strlen(key);

    for (size_t i = 0; i + kl < len; i++) {
        if (memcmp(buf + i, key, kl)) {
            continue;
        }
        if (i > 0 && (isalnum(buf[i - 1]) || buf[i - 1] == '_')) {
            continue;
        }

        size_t j = i + kl;
        if (j < len && (isalnum(buf[j]) || buf[j] == '_')) {
            continue;
        }
        while (j < len && (buf[j] == ' ' || buf[j] == '\t')) {
            j++;
        }
        if (j >= len || buf[j] != '=' || (j + 1 < len && buf[j + 1] == '=')) {
            continue;
        }
        j++;
        while (j < len && (buf[j] == ' ' || buf[j] == '\t')) {
            j++;
        }
        if (j < len && buf[j] == '_') {
            j++;
        }
        while (j < len && (buf[j] == '(' || buf[j] == ' ')) {
            j++;
        }
        if (j < len && (buf[j] == 'u' || buf[j] == 'r') && j + 1 < len && (buf[j + 1] == '"' || buf[j + 1] == '\'')) {
            j++;
        }
        if (j >= len || (buf[j] != '"' && buf[j] != '\'')) {
            continue;
        }

        unsigned char q = buf[j++];
        size_t o = 0;
        while (j < len && buf[j] != q && buf[j] != '\n' && o + 1 < outlen) {
            if (buf[j] == '\\' && j + 1 < len) {
                j++;
            }
            out[o++] = (char) buf[j++];
        }
        out[o] = 0;

        if (j < len && buf[j] == q && o > 0) {
            return 1;
        }
    }

    return 0;
}

/* ------------------------------------------------------------------------ */

const char *rp_runtime_version(int runtime) {
    if (runtime == 7) {
        return RP_RUNTIME7_VERSION;
    }
    if (runtime == 85) {
        return RP_RUNTIME85_VERSION;
    }
    return RP_RUNTIME8_VERSION;
}

int rp_choose_runtime(const char *version, int py_major, const char *py_tag, int *newer) {
    int vmaj = 0;
    int vmin = 0;
    int tagmin = -1;
    int rt;

    if (version && version[0]) {
        sscanf(version, "%d.%d", &vmaj, &vmin);
    }
    if (py_tag && py_tag[0] == '3' && py_tag[1] == '.') {
        tagmin = atoi(py_tag + 2);
    }

    if (py_major == 2 || (vmaj >= 6 && vmaj <= 7)) {
        rt = 7;
    } else if (vmaj > 8 || (vmaj == 8 && vmin >= 4)) {
        /* Ren'Py 8.4+ usa Python 3.12. */
        rt = 85;
    } else if (vmaj == 8) {
        rt = 8;
    } else if (tagmin >= 10) {
        rt = 85;
    } else {
        rt = 8;
    }

    if (newer) {
        *newer = 0;
        const char *rv = rp_runtime_version(rt);
        if (vmaj) {
            if (vmaj > atoi(rv) || (vmaj == atoi(rv) && rp_version_compare3(version, rv) > 0)) {
                *newer = 1;
            }
        } else if (rt == 85 && tagmin > 12) {
            *newer = 1;
        }
    }

    return rt;
}

int rp_version_compare3(const char *a, const char *b) {
    int va[3] = { 0, 0, 0 };
    int vb[3] = { 0, 0, 0 };
    sscanf(a, "%d.%d.%d", &va[0], &va[1], &va[2]);
    sscanf(b, "%d.%d.%d", &vb[0], &vb[1], &vb[2]);
    for (int i = 0; i < 3; i++) {
        if (va[i] != vb[i]) {
            return va[i] < vb[i] ? -1 : 1;
        }
    }
    return 0;
}

int rp_analyze(const char *const *paths, size_t n, rp_read_fn reader, void *ctx,
               rp_analysis *out) {
    memset(out, 0, sizeof(*out));

    find_root(paths, n, out);

    const char *root = out->root;
    size_t rl = strlen(root);

    /* --- Indizi su Python -------------------------------------------------- */
    int py2 = 0;
    int py3 = 0;
    char py2_why[256] = "";
    char py3_why[256] = "";
    char tag[16] = "";

    for (size_t i = 0; i < n; i++) {
        const char *p = paths[i];
        if (strncmp(p, root, rl)) {
            continue;
        }
        const char *rel = p + rl;

        if (has_prefix(rel, "renpy/")) {
            if (ends_with(rel, ".pyo")) {
                if (!py2) {
                    snprintf(py2_why, sizeof(py2_why), "file .pyo in renpy/");
                }
                py2 += 10;
            } else if (strstr(rel, "/__pycache__/") && strstr(rel, ".cpython-3")) {
                if (!py3) {
                    snprintf(py3_why, sizeof(py3_why), "renpy/__pycache__ (CPython 3)");
                }
                py3 += 10;
                if (!tag[0]) {
                    tag_from_cpython(rel, tag, sizeof(tag));
                }
            }
        } else if (has_prefix(rel, "lib/")) {
            if (has_prefix(rel, "lib/python3.")) {
                if (!py3) {
                    snprintf(py3_why, sizeof(py3_why), "cartella lib/python3");
                }
                py3 += 5;
                tag_from_libdir(rel, tag, sizeof(tag));
            } else if (has_prefix(rel, "lib/python2.") || has_prefix(rel, "lib/pythonlib2.")) {
                if (!py2) {
                    snprintf(py2_why, sizeof(py2_why), "cartella lib/python2.7");
                }
                py2 += 5;
                if (!tag[0]) {
                    snprintf(tag, sizeof(tag), "2.7");
                }
            } else if (has_prefix(rel, "lib/py3-")) {
                if (!py3) {
                    snprintf(py3_why, sizeof(py3_why), "cartella lib/py3-*");
                }
                py3 += 3;
            } else if (has_prefix(rel, "lib/py2-")) {
                if (!py2) {
                    snprintf(py2_why, sizeof(py2_why), "cartella lib/py2-*");
                }
                py2 += 3;
            } else if (has_prefix(rel, "lib/windows-") || has_prefix(rel, "lib/linux-") ||
                       has_prefix(rel, "lib/darwin-") || has_prefix(rel, "lib/mac-")) {
                if (!py2) {
                    snprintf(py2_why, sizeof(py2_why), "struttura lib/ di Ren'Py 6-7.3");
                }
                py2 += 1;
            }
        } else if (has_prefix(rel, "game/cache/bytecode")) {
            if (has_prefix(rel, "game/cache/bytecode-3")) {
                if (!py3) {
                    snprintf(py3_why, sizeof(py3_why), "cache bytecode Python 3");
                }
                py3 += 2;
                if (!tag[0]) {
                    const char *d = rel + strlen("game/cache/bytecode-");
                    if (isdigit((unsigned char) d[0]) && isdigit((unsigned char) d[1])) {
                        char t[8];
                        size_t k = 0;
                        const char *q = d + 1;
                        while (isdigit((unsigned char) *q) && k < sizeof(t) - 1) {
                            t[k++] = *q++;
                        }
                        t[k] = 0;
                        snprintf(tag, sizeof(tag), "%c.%s", d[0], t);
                    }
                }
            } else if (strcmp(rel, "game/cache/bytecode.rpyb") == 0) {
                if (!py2) {
                    snprintf(py2_why, sizeof(py2_why), "cache bytecode Python 2");
                }
                py2 += 2;
            }
        }
    }

    /* --- Versione di Ren'Py ------------------------------------------------ */
    char vsrc[256] = "";

    if (reader) {
        static const char *const candidates[] = {
            "renpy/vc_version.py",
            "renpy/vc_version.pyo",
            "renpy/vc_version.pyc",
            NULL,
        };

        char full[2048];
        for (int k = 0; candidates[k] && !out->version[0]; k++) {
            snprintf(full, sizeof(full), "%s%s", root, candidates[k]);
            if (find_path(paths, n, full) < 0) {
                continue;
            }
            unsigned char *buf = NULL;
            size_t len = 0;
            if (reader(ctx, full, &buf, &len) == 0 && buf) {
                if (scan_version(buf, len, out->version, sizeof(out->version))) {
                    snprintf(vsrc, sizeof(vsrc), "%s", candidates[k]);
                }
                free(buf);
            }
        }

        /* renpy/__pycache__/vc_version.cpython-XY.pyc */
        if (!out->version[0]) {
            for (size_t i = 0; i < n; i++) {
                const char *p = paths[i];
                if (strncmp(p, root, rl)) {
                    continue;
                }
                const char *rel = p + rl;
                if (has_prefix(rel, "renpy/__pycache__/vc_version.") && ends_with(rel, ".pyc")) {
                    unsigned char *buf = NULL;
                    size_t len = 0;
                    if (reader(ctx, p, &buf, &len) == 0 && buf) {
                        if (scan_version(buf, len, out->version, sizeof(out->version))) {
                            snprintf(vsrc, sizeof(vsrc), "%s", rel);
                        }
                        free(buf);
                    }
                    if (out->version[0]) {
                        break;
                    }
                }
            }
        }

        /* Ren'Py più vecchi: version_tuple in renpy/__init__.py */
        if (!out->version[0]) {
            snprintf(full, sizeof(full), "%srenpy/__init__.py", root);
            if (find_path(paths, n, full) >= 0) {
                unsigned char *buf = NULL;
                size_t len = 0;
                if (reader(ctx, full, &buf, &len) == 0 && buf) {
                    if (scan_version_tuple(buf, len, out->version, sizeof(out->version))) {
                        snprintf(vsrc, sizeof(vsrc), "renpy/__init__.py");
                    }
                    free(buf);
                }
            }
        }

        /* Nome e versione del gioco da options.rpy */
        snprintf(full, sizeof(full), "%sgame/options.rpy", root);
        if (find_path(paths, n, full) >= 0) {
            unsigned char *buf = NULL;
            size_t len = 0;
            if (reader(ctx, full, &buf, &len) == 0 && buf) {
                scan_assignment(buf, len, "config.name", out->title, sizeof(out->title));
                scan_assignment(buf, len, "config.version", out->game_version, sizeof(out->game_version));
                free(buf);
            }
        }
    }

    /* --- Decisione ----------------------------------------------------------- */
    int vmajor = out->version[0] ? atoi(out->version) : 0;

    if (vmajor >= 8) {
        out->py_major = 3;
    } else if (vmajor >= 6) {
        out->py_major = 2;
    } else if (py2 > py3) {
        out->py_major = 2;
    } else if (py3 > py2) {
        out->py_major = 3;
    } else {
        out->py_major = 0;
    }

    if (out->py_major == 2 && !tag[0]) {
        snprintf(tag, sizeof(tag), "2.7");
    }
    if (out->py_major == 2 && tag[0] == '3') {
        snprintf(tag, sizeof(tag), "2.7");
    }
    if (out->py_major == 3 && tag[0] == '2') {
        tag[0] = 0;
    }
    snprintf(out->py_tag, sizeof(out->py_tag), "%s", tag);

    out->runtime = rp_choose_runtime(out->version, out->py_major, out->py_tag, &out->newer_than_runtime);
    out->confident = out->py_major != 0;

    /* --- Spiegazione --------------------------------------------------------- */
    out->evidence[0] = 0;

    if (!out->found) {
        append(out->evidence, sizeof(out->evidence), "%s", "Cartella game/ non trovata: probabilmente non è un gioco Ren'Py per PC. ");
    }

    if (out->version[0]) {
        append(out->evidence, sizeof(out->evidence), "Versione letta da %s. ", vsrc);
    } else {
        append(out->evidence, sizeof(out->evidence), "%s", "Versione esatta non trovata. ");
    }

    if (out->py_major == 2 && py2_why[0]) {
        append(out->evidence, sizeof(out->evidence), "Python 2: %s.", py2_why);
    } else if (out->py_major == 3 && py3_why[0]) {
        append(out->evidence, sizeof(out->evidence), "Python 3: %s.", py3_why);
    } else if (out->py_major == 0) {
        append(out->evidence, sizeof(out->evidence), "%s", "Nessun indizio su Python: uso Ren'Py 8 (puoi cambiarlo a mano).");
    }

    return out->found ? 0 : -1;
}

int rp_should_import(const char *path, const char *root, const char **rel_out) {
    size_t rl = strlen(root);
    if (strncmp(path, root, rl)) {
        return 0;
    }

    const char *rel = path + rl;
    if (!*rel) {
        return 0;
    }

    if (has_prefix(rel, "__MACOSX/") || strstr(rel, "/__MACOSX/")) {
        return 0;
    }

    const char *bn = base_name(rel);
    if (has_prefix(bn, "._") || strcmp(bn, ".DS_Store") == 0 || strcmp(bn, "Thumbs.db") == 0 ||
        strcmp(bn, "desktop.ini") == 0) {
        return 0;
    }

    /* Primo componente. */
    const char *slash = strchr(rel, '/');
    size_t fl = slash ? (size_t) (slash - rel) : strlen(rel);

    if ((fl == 5 && strncmp(rel, "renpy", 5) == 0) || (fl == 3 && strncmp(rel, "lib", 3) == 0)) {
        return 0;
    }

    if (fl > 4 && strncmp(rel + fl - 4, ".app", 4) == 0) {
        return 0;
    }

    if (!slash) {
        static const char *const skip[] = {
            ".exe", ".sh", ".py", ".pyo", ".pyc", ".dll", ".so", ".dylib", ".command", ".bat", ".pdb",
            NULL,
        };
        for (int k = 0; skip[k]; k++) {
            if (ends_with_ci(rel, skip[k])) {
                return 0;
            }
        }
    }

    if (rel_out) {
        *rel_out = rel;
    }
    return 1;
}

int rp_is_save_file(const char *name) {
    const char *bn = base_name(name);
    if (has_prefix(bn, "._")) {
        return 0;
    }
    return ends_with(bn, ".save") || strcmp(bn, "persistent") == 0;
}
