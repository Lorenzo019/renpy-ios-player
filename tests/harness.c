/* Piccolo programma di prova per rpcore, usato dai test su Linux/macOS. */

#include "../app/core/rpcore.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static int reader(void *ctx, const char *path, unsigned char **out, size_t *outlen) {
    rpzip *z = (rpzip *) ctx;
    for (size_t i = 0; i < rpzip_count(z); i++) {
        if (strcmp(rpzip_entry_at(z, i)->name, path) == 0) {
            char err[RP_ERRLEN];
            return rpzip_read_to_memory(z, i, 1 << 20, out, outlen, err, sizeof(err));
        }
    }
    return -1;
}

static int mkdirs(const char *path) {
    char tmp[4096];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(tmp, 0755) && errno != EEXIST) {
                return -1;
            }
            *p = '/';
        }
    }
    if (mkdir(tmp, 0755) && errno != EEXIST) {
        return -1;
    }
    return 0;
}

static int cancel_after = 0;

static int progress(void *ctx, uint64_t bytes) {
    (void) ctx;
    if (cancel_after && bytes > (uint64_t) cancel_after) {
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    char err[RP_ERRLEN] = "";

    if (argc < 3) {
        fprintf(stderr, "uso: harness list|analyze|extract|writezip|cancel ...\n");
        return 2;
    }

    if (!strcmp(argv[1], "writezip")) {
        rpzipw *w;
        if (rpzipw_open(argv[2], &w, err, sizeof(err))) {
            printf("ERR %s\n", err);
            return 1;
        }
        for (int i = 3; i + 1 < argc; i += 2) {
            if (rpzipw_add_file(w, argv[i], argv[i + 1], err, sizeof(err))) {
                printf("ERR %s\n", err);
                rpzipw_close(w, err, sizeof(err));
                return 1;
            }
        }
        if (rpzipw_close(w, err, sizeof(err))) {
            printf("ERR %s\n", err);
            return 1;
        }
        printf("OK\n");
        return 0;
    }

    if (!strcmp(argv[1], "issave")) {
        printf("%d\n", rp_is_save_file(argv[2]));
        return 0;
    }

    if (!strcmp(argv[1], "sanitize")) {
        char buf[1024];
        snprintf(buf, sizeof(buf), "%s", argv[2]);
        int ok = rp_sanitize_path(buf);
        printf("%d %s\n", ok, ok ? buf : "");
        return 0;
    }

    rpzip *z;
    if (rpzip_open(argv[2], &z, err, sizeof(err))) {
        printf("ERR %s\n", err);
        return 1;
    }

    if (!strcmp(argv[1], "list")) {
        for (size_t i = 0; i < rpzip_count(z); i++) {
            const rpzip_entry *e = rpzip_entry_at(z, i);
            printf("%s\t%llu\t%llu\t%u\t%d\n", e->name, (unsigned long long) e->uncomp_size,
                   (unsigned long long) e->comp_size, (unsigned) e->method, e->is_dir);
        }
        printf("TOTAL %zu %llu\n", rpzip_count(z), (unsigned long long) rpzip_total_uncompressed(z));
    } else if (!strcmp(argv[1], "analyze")) {
        size_t n = rpzip_count(z);
        const char **paths = (const char **) malloc(n * sizeof(char *));
        for (size_t i = 0; i < n; i++) {
            paths[i] = rpzip_entry_at(z, i)->name;
        }
        rp_analysis a;
        int r = rp_analyze(paths, n, reader, z, &a);
        printf("rv=%d\nroot=%s\nfound=%d\nversion=%s\npy_major=%d\npy_tag=%s\nruntime=%d\nconfident=%d\nnewer=%d\ntitle=%s\ngame_version=%s\nevidence=%s\n",
               r, a.root, a.found, a.version, a.py_major, a.py_tag, a.runtime, a.confident,
               a.newer_than_runtime, a.title, a.game_version, a.evidence);
        free(paths);
    } else if (!strcmp(argv[1], "extract") || !strcmp(argv[1], "cancel")) {
        if (argc < 4) {
            return 2;
        }
        if (!strcmp(argv[1], "cancel")) {
            cancel_after = 1000;
        }
        size_t n = rpzip_count(z);
        const char **paths = (const char **) malloc(n * sizeof(char *));
        for (size_t i = 0; i < n; i++) {
            paths[i] = rpzip_entry_at(z, i)->name;
        }
        rp_analysis a;
        rp_analyze(paths, n, reader, z, &a);
        int copied = 0;
        int skipped = 0;
        for (size_t i = 0; i < n; i++) {
            const rpzip_entry *e = rpzip_entry_at(z, i);
            const char *rel = NULL;
            if (!rp_should_import(e->name, a.root, &rel)) {
                skipped++;
                continue;
            }
            char dest[4096];
            snprintf(dest, sizeof(dest), "%s/%s", argv[3], rel);
            if (e->is_dir) {
                mkdirs(dest);
                continue;
            }
            char dir[4096];
            snprintf(dir, sizeof(dir), "%s", dest);
            char *s = strrchr(dir, '/');
            if (s) {
                *s = 0;
                mkdirs(dir);
            }
            if (rpzip_extract_to_file(z, i, dest, progress, NULL, err, sizeof(err))) {
                printf("ERR %s\n", err);
                rpzip_close(z);
                free(paths);
                return 1;
            }
            copied++;
        }
        printf("copied=%d skipped=%d\n", copied, skipped);
        free(paths);
    }

    rpzip_close(z);
    return 0;
}
