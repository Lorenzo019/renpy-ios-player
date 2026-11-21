/*
 * Lettore e scrittore ZIP minimali per RenPlayer.
 * Lettura: metodi 0 (stored) e 8 (deflate), Zip64, dati prefissati (SFX).
 * Scrittura: solo stored, senza Zip64 (pensato per i salvataggi).
 */

#ifndef _FILE_OFFSET_BITS
#define _FILE_OFFSET_BITS 64
#endif

#include "rpcore.h"

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include <zlib.h>

#define BUFSZ (256 * 1024)

struct rpzip {
    int fd;
    uint64_t size;
    rpzip_entry *entries;
    size_t count;
};

static void seterr(char *err, size_t errlen, const char *fmt, ...) {
    if (!err || !errlen) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(err, errlen, fmt, ap);
    va_end(ap);
}

static uint16_t rd16(const unsigned char *p) {
    return (uint16_t) (p[0] | (p[1] << 8));
}

static uint32_t rd32(const unsigned char *p) {
    return (uint32_t) p[0] | ((uint32_t) p[1] << 8) | ((uint32_t) p[2] << 16) | ((uint32_t) p[3] << 24);
}

static uint64_t rd64(const unsigned char *p) {
    return (uint64_t) rd32(p) | ((uint64_t) rd32(p + 4) << 32);
}

static void wr16(unsigned char *p, uint16_t v) {
    p[0] = v & 0xff;
    p[1] = (v >> 8) & 0xff;
}

static void wr32(unsigned char *p, uint32_t v) {
    p[0] = v & 0xff;
    p[1] = (v >> 8) & 0xff;
    p[2] = (v >> 16) & 0xff;
    p[3] = (v >> 24) & 0xff;
}

/* pread completo: ritorna 0 se ha letto esattamente len byte. */
static int pread_full(int fd, void *buf, size_t len, uint64_t off) {
    unsigned char *b = (unsigned char *) buf;
    while (len > 0) {
        ssize_t r = pread(fd, b, len, (off_t) off);
        if (r < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        if (r == 0) {
            return -1;
        }
        b += r;
        len -= (size_t) r;
        off += (uint64_t) r;
    }
    return 0;
}

static int write_full(int fd, const void *buf, size_t len) {
    const unsigned char *b = (const unsigned char *) buf;
    while (len > 0) {
        ssize_t r = write(fd, b, len);
        if (r < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        b += r;
        len -= (size_t) r;
    }
    return 0;
}

int rp_sanitize_path(char *p) {
    if (!p) {
        return 0;
    }

    for (char *c = p; *c; c++) {
        if (*c == '\\') {
            *c = '/';
        }
    }

    /* Rimuove '/' e "./" iniziali. */
    char *s = p;
    for (;;) {
        if (s[0] == '/') {
            s++;
        } else if (s[0] == '.' && s[1] == '/') {
            s += 2;
        } else {
            break;
        }
    }
    if (s != p) {
        memmove(p, s, strlen(s) + 1);
    }

    if (!*p) {
        return 0;
    }

    /* Rifiuta i componenti "..", e i caratteri di controllo. */
    const char *c = p;
    while (*c) {
        const char *e = strchr(c, '/');
        size_t len = e ? (size_t) (e - c) : strlen(c);
        if (len == 2 && c[0] == '.' && c[1] == '.') {
            return 0;
        }
        if (!e) {
            break;
        }
        c = e + 1;
    }

    for (const unsigned char *u = (const unsigned char *) p; *u; u++) {
        if (*u < 0x20) {
            return 0;
        }
    }

    return 1;
}

/* Converte un nome CP437 (zip "vecchi" senza flag UTF-8) in UTF-8.
 * Per i caratteri ASCII non cambia nulla. */
static char *cp437_to_utf8(const unsigned char *s, size_t len) {
    static const uint16_t hi[128] = {
        0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7, 0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
        0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9, 0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
        0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA, 0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
        0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
        0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, 0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
        0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B, 0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
        0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4, 0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
        0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248, 0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0,
    };

    char *out = (char *) malloc(len * 3 + 1);
    if (!out) {
        return NULL;
    }
    size_t o = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned c = s[i];
        if (c < 0x80) {
            out[o++] = (char) c;
        } else {
            unsigned u = hi[c - 0x80];
            if (u < 0x800) {
                out[o++] = (char) (0xC0 | (u >> 6));
                out[o++] = (char) (0x80 | (u & 0x3F));
            } else {
                out[o++] = (char) (0xE0 | (u >> 12));
                out[o++] = (char) (0x80 | ((u >> 6) & 0x3F));
                out[o++] = (char) (0x80 | (u & 0x3F));
            }
        }
    }
    out[o] = 0;
    return out;
}

static int valid_utf8(const unsigned char *s, size_t len) {
    size_t i = 0;
    while (i < len) {
        unsigned c = s[i];
        size_t n;
        if (c < 0x80) {
            n = 0;
        } else if ((c & 0xE0) == 0xC0) {
            n = 1;
        } else if ((c & 0xF0) == 0xE0) {
            n = 2;
        } else if ((c & 0xF8) == 0xF0) {
            n = 3;
        } else {
            return 0;
        }
        if (n && i + n >= len) {
            return 0;
        }
        for (size_t k = 1; k <= n; k++) {
            if ((s[i + k] & 0xC0) != 0x80) {
                return 0;
            }
        }
        i += n + 1;
    }
    return 1;
}

static int find_eocd(int fd, uint64_t size, uint64_t *eocd_pos, unsigned char eocd[22]) {
    if (size < 22) {
        return -1;
    }

    uint64_t maxback = 22 + 65535;
    if (maxback > size) {
        maxback = size;
    }

    unsigned char *buf = (unsigned char *) malloc((size_t) maxback);
    if (!buf) {
        return -1;
    }

    uint64_t start = size - maxback;
    if (pread_full(fd, buf, (size_t) maxback, start)) {
        free(buf);
        return -1;
    }

    for (int64_t i = (int64_t) maxback - 22; i >= 0; i--) {
        if (buf[i] == 0x50 && buf[i + 1] == 0x4b && buf[i + 2] == 0x05 && buf[i + 3] == 0x06) {
            uint16_t clen = rd16(buf + i + 20);
            if ((uint64_t) i + 22 + clen <= maxback) {
                memcpy(eocd, buf + i, 22);
                *eocd_pos = start + (uint64_t) i;
                free(buf);
                return 0;
            }
        }
    }

    free(buf);
    return -1;
}

int rpzip_open(const char *path, rpzip **out, char *err, size_t errlen) {
    *out = NULL;

    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        seterr(err, errlen, "Impossibile aprire il file (%s).", strerror(errno));
        return -1;
    }

    struct stat st;
    if (fstat(fd, &st)) {
        seterr(err, errlen, "Impossibile leggere il file (%s).", strerror(errno));
        close(fd);
        return -1;
    }

    uint64_t size = (uint64_t) st.st_size;
    uint64_t eocd_pos = 0;
    unsigned char eocd[22];

    if (find_eocd(fd, size, &eocd_pos, eocd)) {
        seterr(err, errlen, "Non è un file zip valido (fine archivio non trovata). Se l'archivio è .rar o .7z, convertilo in .zip.");
        close(fd);
        return -1;
    }

    uint64_t total = rd16(eocd + 10);
    uint64_t cd_size = rd32(eocd + 12);
    uint64_t cd_off = rd32(eocd + 16);
    int zip64 = 0;

    /* Zip64: cerca il locator subito prima dell'EOCD. */
    if (eocd_pos >= 20) {
        unsigned char loc[20];
        if (!pread_full(fd, loc, 20, eocd_pos - 20) && rd32(loc) == 0x07064b50) {
            uint64_t z64_off = rd64(loc + 8);
            unsigned char z64[56];
            int ok = 0;

            if (!pread_full(fd, z64, 56, z64_off) && rd32(z64) == 0x06064b50) {
                ok = 1;
            } else {
                /* Archivio con dati prefissati: lo Zip64 EOCD sta subito prima del locator. */
                if (eocd_pos >= 20 + 56 && !pread_full(fd, z64, 56, eocd_pos - 20 - 56) && rd32(z64) == 0x06064b50) {
                    ok = 1;
                }
            }

            if (ok) {
                total = rd64(z64 + 32);
                cd_size = rd64(z64 + 40);
                cd_off = rd64(z64 + 48);
                zip64 = 1;
            }
        }
    }

    /* Correzione per dati prefissati (es. archivi autoestraenti). */
    uint64_t delta = 0;
    if (!zip64) {
        if (cd_off + cd_size < eocd_pos) {
            delta = eocd_pos - (cd_off + cd_size);
        }
    }

    if (cd_off + delta + cd_size > size || cd_size > (uint64_t) 1 << 31) {
        seterr(err, errlen, "Archivio zip danneggiato o incompleto (directory centrale fuori dal file).");
        close(fd);
        return -1;
    }

    unsigned char *cd = (unsigned char *) malloc((size_t) cd_size + 1);
    if (!cd) {
        seterr(err, errlen, "Memoria insufficiente.");
        close(fd);
        return -1;
    }

    if (pread_full(fd, cd, (size_t) cd_size, cd_off + delta)) {
        seterr(err, errlen, "Impossibile leggere la directory centrale dello zip.");
        free(cd);
        close(fd);
        return -1;
    }

    size_t cap = total > 0 && total < 10000000 ? (size_t) total : 1024;
    rpzip_entry *entries = (rpzip_entry *) calloc(cap, sizeof(rpzip_entry));
    size_t count = 0;

    if (!entries) {
        seterr(err, errlen, "Memoria insufficiente.");
        free(cd);
        close(fd);
        return -1;
    }

    uint64_t p = 0;
    while (p + 46 <= cd_size) {
        const unsigned char *h = cd + p;
        if (rd32(h) != 0x02014b50) {
            break;
        }

        uint16_t flags = rd16(h + 8);
        uint16_t method = rd16(h + 10);
        uint32_t crc = rd32(h + 16);
        uint64_t csize = rd32(h + 20);
        uint64_t usize = rd32(h + 24);
        uint16_t nlen = rd16(h + 28);
        uint16_t xlen = rd16(h + 30);
        uint16_t clen = rd16(h + 32);
        uint64_t loff = rd32(h + 42);

        if (p + 46 + nlen + xlen + clen > cd_size) {
            break;
        }

        const unsigned char *name = h + 46;
        const unsigned char *extra = name + nlen;

        /* Campo extra Zip64. */
        uint32_t x = 0;
        while (x + 4 <= xlen) {
            uint16_t id = rd16(extra + x);
            uint16_t sz = rd16(extra + x + 2);
            if (x + 4 + sz > xlen) {
                break;
            }
            if (id == 0x0001) {
                const unsigned char *d = extra + x + 4;
                uint32_t q = 0;
                if (usize == 0xFFFFFFFFu && q + 8 <= sz) {
                    usize = rd64(d + q);
                    q += 8;
                }
                if (csize == 0xFFFFFFFFu && q + 8 <= sz) {
                    csize = rd64(d + q);
                    q += 8;
                }
                if (loff == 0xFFFFFFFFu && q + 8 <= sz) {
                    loff = rd64(d + q);
                    q += 8;
                }
            }
            x += 4 + sz;
        }

        char *nm;
        if ((flags & 0x800) || valid_utf8(name, nlen)) {
            nm = (char *) malloc(nlen + 1);
            if (nm) {
                memcpy(nm, name, nlen);
                nm[nlen] = 0;
            }
        } else {
            nm = cp437_to_utf8(name, nlen);
        }

        if (!nm) {
            break;
        }

        int is_dir = nlen > 0 && (name[nlen - 1] == '/' || name[nlen - 1] == '\\');

        if (!rp_sanitize_path(nm)) {
            /* Voce non sicura o vuota: la saltiamo. */
            free(nm);
            p += 46 + nlen + xlen + clen;
            continue;
        }

        /* Rimuove eventuale '/' finale. */
        size_t L = strlen(nm);
        while (L > 0 && nm[L - 1] == '/') {
            nm[--L] = 0;
        }

        if (count == cap) {
            cap *= 2;
            rpzip_entry *ne = (rpzip_entry *) realloc(entries, cap * sizeof(rpzip_entry));
            if (!ne) {
                free(nm);
                break;
            }
            entries = ne;
        }

        rpzip_entry *e = &entries[count++];
        e->name = nm;
        e->comp_size = csize;
        e->uncomp_size = usize;
        e->local_offset = loff + delta;
        e->crc32 = crc;
        e->method = method;
        e->flags = flags;
        e->is_dir = is_dir;

        p += 46 + nlen + xlen + clen;
    }

    free(cd);

    if (count == 0 && total > 0) {
        free(entries);
        seterr(err, errlen, "Archivio zip vuoto o non leggibile.");
        close(fd);
        return -1;
    }

    rpzip *z = (rpzip *) calloc(1, sizeof(rpzip));
    z->fd = fd;
    z->size = size;
    z->entries = entries;
    z->count = count;
    *out = z;
    return 0;
}

size_t rpzip_count(const rpzip *z) {
    return z ? z->count : 0;
}

const rpzip_entry *rpzip_entry_at(const rpzip *z, size_t i) {
    if (!z || i >= z->count) {
        return NULL;
    }
    return &z->entries[i];
}

uint64_t rpzip_total_uncompressed(const rpzip *z) {
    uint64_t t = 0;
    for (size_t i = 0; i < z->count; i++) {
        t += z->entries[i].uncomp_size;
    }
    return t;
}

void rpzip_close(rpzip *z) {
    if (!z) {
        return;
    }
    for (size_t i = 0; i < z->count; i++) {
        free(z->entries[i].name);
    }
    free(z->entries);
    if (z->fd >= 0) {
        close(z->fd);
    }
    free(z);
}

/* Calcola l'offset dei dati a partire dall'header locale. */
static int data_offset(rpzip *z, const rpzip_entry *e, uint64_t *off, char *err, size_t errlen) {
    unsigned char lh[30];
    if (pread_full(z->fd, lh, 30, e->local_offset) || rd32(lh) != 0x04034b50) {
        seterr(err, errlen, "Header locale non valido per %s.", e->name);
        return -1;
    }
    *off = e->local_offset + 30 + rd16(lh + 26) + rd16(lh + 28);
    if (*off + e->comp_size > z->size) {
        seterr(err, errlen, "Dati di %s oltre la fine del file: archivio incompleto?", e->name);
        return -1;
    }
    return 0;
}

typedef int (*sink_fn)(void *sctx, const unsigned char *buf, size_t len);

static int decode_entry(rpzip *z, const rpzip_entry *e, sink_fn sink, void *sctx,
                        rp_progress_fn cb, void *ctx, char *err, size_t errlen) {
    if (e->flags & 1) {
        seterr(err, errlen, "%s è cifrato: gli zip protetti da password non sono supportati.", e->name);
        return -1;
    }

    if (e->method != 0 && e->method != 8) {
        seterr(err, errlen, "%s usa un metodo di compressione non supportato (%u). Ricomprimi lo zip con compressione standard (Deflate).", e->name, (unsigned) e->method);
        return -1;
    }

    uint64_t off;
    if (data_offset(z, e, &off, err, errlen)) {
        return -1;
    }

    unsigned char *in = (unsigned char *) malloc(BUFSZ);
    unsigned char *outb = (unsigned char *) malloc(BUFSZ);
    if (!in || !outb) {
        free(in);
        free(outb);
        seterr(err, errlen, "Memoria insufficiente.");
        return -1;
    }

    uLong crc = crc32(0L, Z_NULL, 0);
    uint64_t done_out = 0;
    uint64_t remaining = e->comp_size;
    int rv = -1;

    if (e->method == 0) {
        while (remaining > 0) {
            size_t n = remaining > BUFSZ ? BUFSZ : (size_t) remaining;
            if (pread_full(z->fd, in, n, off)) {
                seterr(err, errlen, "Errore di lettura in %s.", e->name);
                goto done;
            }
            off += n;
            remaining -= n;
            crc = crc32(crc, in, (uInt) n);
            if (sink(sctx, in, n)) {
                seterr(err, errlen, "Errore di scrittura per %s (spazio esaurito?).", e->name);
                goto done;
            }
            done_out += n;
            if (cb && cb(ctx, done_out)) {
                seterr(err, errlen, "Annullato.");
                goto done;
            }
        }
    } else {
        z_stream s;
        memset(&s, 0, sizeof(s));
        if (inflateInit2(&s, -MAX_WBITS) != Z_OK) {
            seterr(err, errlen, "Impossibile inizializzare zlib.");
            goto done;
        }

        int zr = Z_OK;
        while (zr != Z_STREAM_END) {
            if (s.avail_in == 0) {
                if (remaining == 0) {
                    break;
                }
                size_t n = remaining > BUFSZ ? BUFSZ : (size_t) remaining;
                if (pread_full(z->fd, in, n, off)) {
                    seterr(err, errlen, "Errore di lettura in %s.", e->name);
                    inflateEnd(&s);
                    goto done;
                }
                off += n;
                remaining -= n;
                s.next_in = in;
                s.avail_in = (uInt) n;
            }

            s.next_out = outb;
            s.avail_out = BUFSZ;
            zr = inflate(&s, Z_NO_FLUSH);
            if (zr != Z_OK && zr != Z_STREAM_END) {
                seterr(err, errlen, "Dati compressi danneggiati in %s (zlib %d).", e->name, zr);
                inflateEnd(&s);
                goto done;
            }

            size_t produced = BUFSZ - s.avail_out;
            if (produced) {
                crc = crc32(crc, outb, (uInt) produced);
                if (sink(sctx, outb, produced)) {
                    seterr(err, errlen, "Errore di scrittura per %s (spazio esaurito?).", e->name);
                    inflateEnd(&s);
                    goto done;
                }
                done_out += produced;
                if (cb && cb(ctx, done_out)) {
                    seterr(err, errlen, "Annullato.");
                    inflateEnd(&s);
                    goto done;
                }
            }
        }

        inflateEnd(&s);

        if (zr != Z_STREAM_END) {
            seterr(err, errlen, "Dati compressi troncati in %s.", e->name);
            goto done;
        }
    }

    if (done_out != e->uncomp_size) {
        seterr(err, errlen, "Dimensione errata per %s.", e->name);
        goto done;
    }

    if ((uint32_t) crc != e->crc32) {
        seterr(err, errlen, "CRC errato per %s: il file zip è danneggiato.", e->name);
        goto done;
    }

    rv = 0;

done:
    free(in);
    free(outb);
    return rv;
}

static int fd_sink(void *sctx, const unsigned char *buf, size_t len) {
    return write_full(*(int *) sctx, buf, len);
}

int rpzip_extract_to_file(rpzip *z, size_t idx, const char *dest,
                          rp_progress_fn cb, void *ctx,
                          char *err, size_t errlen) {
    const rpzip_entry *e = rpzip_entry_at(z, idx);
    if (!e) {
        seterr(err, errlen, "Voce inesistente.");
        return -1;
    }

    int fd = open(dest, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        seterr(err, errlen, "Impossibile creare %s (%s).", dest, strerror(errno));
        return -1;
    }

    int rv = decode_entry(z, e, fd_sink, &fd, cb, ctx, err, errlen);

    if (close(fd) && rv == 0) {
        seterr(err, errlen, "Errore di scrittura (%s).", strerror(errno));
        rv = -1;
    }

    if (rv) {
        unlink(dest);
    }

    return rv;
}

typedef struct {
    unsigned char *buf;
    size_t len;
    size_t max;
} memsink;

static int mem_sink(void *sctx, const unsigned char *buf, size_t len) {
    memsink *m = (memsink *) sctx;
    if (m->len + len > m->max) {
        return -1;
    }
    memcpy(m->buf + m->len, buf, len);
    m->len += len;
    return 0;
}

int rpzip_read_to_memory(rpzip *z, size_t idx, size_t max,
                         unsigned char **out, size_t *outlen,
                         char *err, size_t errlen) {
    *out = NULL;
    *outlen = 0;

    const rpzip_entry *e = rpzip_entry_at(z, idx);
    if (!e) {
        seterr(err, errlen, "Voce inesistente.");
        return -1;
    }

    if (e->uncomp_size > max) {
        seterr(err, errlen, "%s è troppo grande.", e->name);
        return -1;
    }

    memsink m;
    m.max = (size_t) e->uncomp_size;
    m.len = 0;
    m.buf = (unsigned char *) malloc(m.max + 1);
    if (!m.buf) {
        seterr(err, errlen, "Memoria insufficiente.");
        return -1;
    }

    if (decode_entry(z, e, mem_sink, &m, NULL, NULL, err, errlen)) {
        free(m.buf);
        return -1;
    }

    m.buf[m.len] = 0;
    *out = m.buf;
    *outlen = m.len;
    return 0;
}

/* ------------------------------------------------------------------------ */
/* Scrittore                                                                 */
/* ------------------------------------------------------------------------ */

typedef struct {
    char *name;
    uint32_t crc;
    uint32_t size;
    uint32_t offset;
    uint16_t time;
    uint16_t date;
} wentry;

struct rpzipw {
    int fd;
    uint64_t pos;
    wentry *entries;
    size_t count;
    size_t cap;
    int failed;
};

int rpzipw_open(const char *path, rpzipw **out, char *err, size_t errlen) {
    *out = NULL;
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        seterr(err, errlen, "Impossibile creare %s (%s).", path, strerror(errno));
        return -1;
    }
    rpzipw *w = (rpzipw *) calloc(1, sizeof(rpzipw));
    w->fd = fd;
    *out = w;
    return 0;
}

static void dos_time(time_t t, uint16_t *dtime, uint16_t *ddate) {
    struct tm tmv;
    localtime_r(&t, &tmv);
    if (tmv.tm_year < 80) {
        tmv.tm_year = 80;
        tmv.tm_mon = 0;
        tmv.tm_mday = 1;
        tmv.tm_hour = tmv.tm_min = tmv.tm_sec = 0;
    }
    *dtime = (uint16_t) ((tmv.tm_hour << 11) | (tmv.tm_min << 5) | (tmv.tm_sec / 2));
    *ddate = (uint16_t) (((tmv.tm_year - 80) << 9) | ((tmv.tm_mon + 1) << 5) | tmv.tm_mday);
}

int rpzipw_add_file(rpzipw *w, const char *name_in_zip, const char *src_path,
                    char *err, size_t errlen) {
    int sfd = open(src_path, O_RDONLY);
    if (sfd < 0) {
        seterr(err, errlen, "Impossibile leggere %s (%s).", src_path, strerror(errno));
        return -1;
    }

    struct stat st;
    if (fstat(sfd, &st) || (uint64_t) st.st_size > 0xFFFFFFFEu || w->pos > 0xF0000000u) {
        seterr(err, errlen, "File troppo grande per l'esportazione: %s", src_path);
        close(sfd);
        return -1;
    }

    unsigned char *buf = (unsigned char *) malloc(BUFSZ);
    if (!buf) {
        close(sfd);
        seterr(err, errlen, "Memoria insufficiente.");
        return -1;
    }

    /* Prima passata: CRC. */
    uLong crc = crc32(0L, Z_NULL, 0);
    uint64_t off = 0;
    uint64_t size = (uint64_t) st.st_size;
    while (off < size) {
        size_t n = size - off > BUFSZ ? BUFSZ : (size_t) (size - off);
        if (pread_full(sfd, buf, n, off)) {
            seterr(err, errlen, "Errore di lettura in %s.", src_path);
            free(buf);
            close(sfd);
            return -1;
        }
        crc = crc32(crc, buf, (uInt) n);
        off += n;
    }

    if (w->count == w->cap) {
        size_t ncap = w->cap ? w->cap * 2 : 16;
        wentry *ne = (wentry *) realloc(w->entries, ncap * sizeof(wentry));
        if (!ne) {
            seterr(err, errlen, "Memoria insufficiente.");
            free(buf);
            close(sfd);
            return -1;
        }
        w->entries = ne;
        w->cap = ncap;
    }

    wentry *e = &w->entries[w->count];
    e->name = strdup(name_in_zip);
    e->crc = (uint32_t) crc;
    e->size = (uint32_t) size;
    e->offset = (uint32_t) w->pos;
    dos_time(st.st_mtime, &e->time, &e->date);

    size_t nlen = strlen(e->name);
    unsigned char lh[30];
    wr32(lh, 0x04034b50);
    wr16(lh + 4, 20);
    wr16(lh + 6, 0x800);
    wr16(lh + 8, 0);
    wr16(lh + 10, e->time);
    wr16(lh + 12, e->date);
    wr32(lh + 14, e->crc);
    wr32(lh + 18, e->size);
    wr32(lh + 22, e->size);
    wr16(lh + 26, (uint16_t) nlen);
    wr16(lh + 28, 0);

    if (write_full(w->fd, lh, 30) || write_full(w->fd, e->name, nlen)) {
        goto werr;
    }
    w->pos += 30 + nlen;

    /* Seconda passata: copia. */
    off = 0;
    while (off < size) {
        size_t n = size - off > BUFSZ ? BUFSZ : (size_t) (size - off);
        if (pread_full(sfd, buf, n, off) || write_full(w->fd, buf, n)) {
            goto werr;
        }
        off += n;
    }
    w->pos += size;
    w->count++;

    free(buf);
    close(sfd);
    return 0;

werr:
    seterr(err, errlen, "Errore di scrittura dello zip (spazio esaurito?).");
    free(e->name);
    free(buf);
    close(sfd);
    w->failed = 1;
    return -1;
}

int rpzipw_close(rpzipw *w, char *err, size_t errlen) {
    int rv = w->failed ? -1 : 0;
    uint64_t cd_start = w->pos;
    uint64_t cd_size = 0;

    for (size_t i = 0; i < w->count && rv == 0; i++) {
        wentry *e = &w->entries[i];
        size_t nlen = strlen(e->name);
        unsigned char ch[46];
        memset(ch, 0, sizeof(ch));
        wr32(ch, 0x02014b50);
        wr16(ch + 4, (3 << 8) | 20); /* creato su Unix */
        wr16(ch + 6, 20);
        wr16(ch + 8, 0x800);
        wr16(ch + 10, 0);
        wr16(ch + 12, e->time);
        wr16(ch + 14, e->date);
        wr32(ch + 16, e->crc);
        wr32(ch + 20, e->size);
        wr32(ch + 24, e->size);
        wr16(ch + 28, (uint16_t) nlen);
        wr32(ch + 38, (uint32_t) (0100644u << 16));
        wr32(ch + 42, e->offset);
        if (write_full(w->fd, ch, 46) || write_full(w->fd, e->name, nlen)) {
            rv = -1;
            break;
        }
        cd_size += 46 + nlen;
    }

    if (rv == 0) {
        unsigned char eocd[22];
        memset(eocd, 0, sizeof(eocd));
        wr32(eocd, 0x06054b50);
        wr16(eocd + 8, (uint16_t) w->count);
        wr16(eocd + 10, (uint16_t) w->count);
        wr32(eocd + 12, (uint32_t) cd_size);
        wr32(eocd + 16, (uint32_t) cd_start);
        if (write_full(w->fd, eocd, 22)) {
            rv = -1;
        }
    }

    if (close(w->fd)) {
        rv = -1;
    }

    if (rv) {
        seterr(err, errlen, "Errore durante la scrittura dello zip.");
    }

    for (size_t i = 0; i < w->count; i++) {
        free(w->entries[i].name);
    }
    free(w->entries);
    free(w);
    return rv;
}
