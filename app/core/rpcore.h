/*
 * rpcore - parti in C puro di RenPlayer (testabili anche su Linux).
 *
 *  - lettore ZIP in streaming (deflate/stored, Zip64)
 *  - scrittore ZIP minimale (stored) per esportare i salvataggi
 *  - analisi di un gioco Ren'Py: radice, versione di Ren'Py, versione di Python
 */

#ifndef RPCORE_H
#define RPCORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Versioni dei runtime inclusi nell'app: rpconfig.h viene generato dalla build. */
#if defined(__has_include)
#if __has_include("rpconfig.h")
#include "rpconfig.h"
#endif
#endif

#ifndef RP_RUNTIME7_VERSION
#define RP_RUNTIME7_VERSION "7.8.7"
#endif

#ifndef RP_RUNTIME8_VERSION
#define RP_RUNTIME8_VERSION "8.3.7"
#endif

#ifndef RP_RUNTIME85_VERSION
#define RP_RUNTIME85_VERSION "8.5.3"
#endif

#define RP_ERRLEN 512

/* ------------------------------------------------------------------------ */
/* Lettore ZIP                                                               */
/* ------------------------------------------------------------------------ */

typedef struct rpzip rpzip;

typedef struct {
    char *name;            /* percorso UTF-8 normalizzato, separatore '/' */
    uint64_t comp_size;
    uint64_t uncomp_size;
    uint64_t local_offset; /* offset dell'header locale (già corretto) */
    uint32_t crc32;
    uint16_t method;
    uint16_t flags;
    int is_dir;
} rpzip_entry;

/* Ritorna nonzero per annullare. `bytes` sono i byte scritti per la voce corrente. */
typedef int (*rp_progress_fn)(void *ctx, uint64_t bytes);

int rpzip_open(const char *path, rpzip **out, char *err, size_t errlen);
size_t rpzip_count(const rpzip *z);
const rpzip_entry *rpzip_entry_at(const rpzip *z, size_t i);

/* Somma delle dimensioni non compresse di tutte le voci. */
uint64_t rpzip_total_uncompressed(const rpzip *z);

int rpzip_extract_to_file(rpzip *z, size_t idx, const char *dest,
                          rp_progress_fn cb, void *ctx,
                          char *err, size_t errlen);

/* Legge una voce in memoria (al massimo `max` byte, altrimenti errore).
 * Il buffer restituito va liberato con free(). */
int rpzip_read_to_memory(rpzip *z, size_t idx, size_t max,
                         unsigned char **out, size_t *outlen,
                         char *err, size_t errlen);

void rpzip_close(rpzip *z);

/* ------------------------------------------------------------------------ */
/* Scrittore ZIP (solo "stored", niente compressione)                        */
/* ------------------------------------------------------------------------ */

typedef struct rpzipw rpzipw;

int rpzipw_open(const char *path, rpzipw **out, char *err, size_t errlen);
int rpzipw_add_file(rpzipw *w, const char *name_in_zip, const char *src_path,
                    char *err, size_t errlen);
/* Chiude e libera `w` in ogni caso. */
int rpzipw_close(rpzipw *w, char *err, size_t errlen);

/* ------------------------------------------------------------------------ */
/* Analisi di un gioco Ren'Py                                                */
/* ------------------------------------------------------------------------ */

/* Legge un file indicato con il percorso completo come appare nell'elenco.
 * Ritorna 0 se ok (buffer da liberare con free()), nonzero altrimenti. */
typedef int (*rp_read_fn)(void *ctx, const char *path,
                          unsigned char **out, size_t *outlen);

typedef struct {
    char root[1024];          /* prefisso della cartella del gioco ("" o "X/") */
    int found;                /* 1 se è stata trovata una cartella game/ */
    char version[64];         /* es. "8.3.7.25031702", "7.4.10" oppure "" */
    int py_major;             /* 2, 3 oppure 0 se sconosciuto */
    char py_tag[16];          /* es. "2.7", "3.9", "3.12" */
    int runtime;              /* 7 (Ren'Py 7.8), 8 (Ren'Py 8.3) oppure 85 (Ren'Py 8.5) */
    int confident;            /* 1 se il runtime è stato scelto in base a prove */
    int newer_than_runtime;   /* 1 se il gioco usa un Ren'Py più nuovo del runtime */
    char evidence[512];       /* spiegazione breve, in italiano */
    char title[256];          /* config.name da options.rpy, se presente */
    char game_version[64];    /* config.version da options.rpy, se presente */
} rp_analysis;

int rp_analyze(const char *const *paths, size_t n, rp_read_fn reader, void *ctx,
               rp_analysis *out);

/* Dato un percorso completo dell'elenco e la radice trovata, ritorna 1 se il
 * file va copiato nella cartella del gioco e mette in *rel il percorso
 * relativo alla radice. */
int rp_should_import(const char *path, const char *root, const char **rel);

/* Ritorna 1 se il nome (ultimo componente) è un file di salvataggio Ren'Py. */
int rp_is_save_file(const char *name);

/* Sceglie il runtime: 7 = Ren'Py 7 (Python 2), 8 = Ren'Py 8.0-8.3 (Python 3.9),
 * 85 = Ren'Py 8.4+ (Python 3.12). In *newer mette 1 se il gioco usa un
 * Ren'Py più recente del runtime scelto. */
int rp_choose_runtime(const char *version, int py_major, const char *py_tag, int *newer);

/* Versione ("8.5.3") del runtime indicato. */
const char *rp_runtime_version(int runtime);

/* Confronta due versioni "a.b.c[.d]" sui primi tre numeri. */
int rp_version_compare3(const char *a, const char *b);

/* Normalizza un percorso: '\\' -> '/', rimuove "./" iniziali e '/' iniziali.
 * Ritorna 0 se il percorso non è sicuro (contiene "..", è vuoto, ecc.). */
int rp_sanitize_path(char *p);

#ifdef __cplusplus
}
#endif

#endif
