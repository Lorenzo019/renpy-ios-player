/*
 * RenPlayer - importazione di giochi (zip o cartella) e dei salvataggi.
 */

#import "RPCommon.h"

#include <sys/stat.h>

@implementation RPImportTask
@end

/* Stato condiviso con la callback C di avanzamento. */
@interface RPProgressState : NSObject
@property (nonatomic, weak) RPImportTask *task;
@property (nonatomic, copy) RPProgressBlock block;
@property (nonatomic) unsigned long long done;
@property (nonatomic) unsigned long long total;
@property (nonatomic) CFAbsoluteTime lastReport;
@property (nonatomic, copy) NSString *status;
@end

@implementation RPProgressState

- (void)reportWithCurrent:(unsigned long long)current force:(BOOL)force {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!force && now - self.lastReport < 0.15) {
        return;
    }
    self.lastReport = now;

    double frac = self.total ? (double) (self.done + current) / (double) self.total : 0.0;
    if (frac > 1.0) {
        frac = 1.0;
    }

    NSString *status = [NSString stringWithFormat:@"%@\n%@ di %@", self.status,
                        [RPStore formatBytes:self.done + current], [RPStore formatBytes:self.total]];
    RPProgressBlock block = self.block;
    dispatch_async(dispatch_get_main_queue(), ^{
        block(frac, status);
    });
}

@end

static int progress_cb(void *ctx, uint64_t bytes) {
    RPProgressState *st = (__bridge RPProgressState *) ctx;
    if (st.task.cancelled) {
        return 1;
    }
    [st reportWithCurrent:bytes force:NO];
    return 0;
}

/* Lettore per rp_analyze che legge dallo zip. */
typedef struct {
    rpzip *zip;
} zipctx;

static int zip_reader(void *ctx, const char *path, unsigned char **out, size_t *outlen) {
    zipctx *zc = (zipctx *) ctx;
    for (size_t i = 0; i < rpzip_count(zc->zip); i++) {
        const rpzip_entry *e = rpzip_entry_at(zc->zip, i);
        if (strcmp(e->name, path) == 0) {
            char err[RP_ERRLEN];
            return rpzip_read_to_memory(zc->zip, i, 1 << 20, out, outlen, err, sizeof(err));
        }
    }
    return -1;
}

static dispatch_queue_t import_queue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("renplayer.import", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static void finish(RPImportCompletion completion, RPGame *game, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        completion(game, error);
    });
}

static BOOL ensure_parent(NSURL *file, NSError **error) {
    return [[NSFileManager defaultManager] createDirectoryAtURL:file.URLByDeletingLastPathComponent
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:error];
}

/* Accesso coordinato (scarica i file da iCloud se serve) + security scope. */
static void with_access(NSURL *url, BOOL scoped, void (^body)(NSURL *readable, NSError *err)) {
    BOOL started = scoped ? [url startAccessingSecurityScopedResource] : NO;

    NSFileCoordinator *coord = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSError *cerr = nil;
    __block BOOL ran = NO;

    [coord coordinateReadingItemAtURL:url
                              options:NSFileCoordinatorReadingWithoutChanges
                                error:&cerr
                           byAccessor:^(NSURL *newURL) {
        ran = YES;
        body(newURL, nil);
    }];

    if (!ran) {
        body(url, cerr ?: RPError(@"Impossibile accedere al file."));
    }

    if (started) {
        [url stopAccessingSecurityScopedResource];
    }
}

@implementation RPImporter

+ (RPImportTask *)importArchive:(NSURL *)url
                 securityScoped:(BOOL)scoped
                deleteWhenDone:(BOOL)deleteWhenDone
                       progress:(RPProgressBlock)progress
                     completion:(RPImportCompletion)completion {
    RPImportTask *task = [[RPImportTask alloc] init];
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    dispatch_async(import_queue(), ^{
        with_access(url, scoped, ^(NSURL *readable, NSError *accessError) {
            if (accessError) {
                finish(completion, nil, accessError);
                return;
            }
            NSError *error = nil;
            RPGame *game = [self doImportArchive:readable
                                     displayName:url.lastPathComponent
                                            task:task
                                        progress:progress
                                           error:&error];
            if (game && deleteWhenDone) {
                [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
            }
            finish(completion, game, error);
        });
    });

    return task;
}

+ (nullable RPGame *)doImportArchive:(NSURL *)url
                         displayName:(NSString *)displayName
                                task:(RPImportTask *)task
                            progress:(RPProgressBlock)progress
                               error:(NSError **)error {
    char err[RP_ERRLEN] = "";
    rpzip *zip = NULL;

    dispatch_async(dispatch_get_main_queue(), ^{
        progress(0, @"Lettura dell'archivio…");
    });

    if (rpzip_open(url.fileSystemRepresentation, &zip, err, sizeof(err))) {
        *error = RPError([NSString stringWithUTF8String:err] ?: @"Errore nello zip.");
        return nil;
    }

    size_t n = rpzip_count(zip);
    const char **paths = calloc(n ? n : 1, sizeof(char *));
    for (size_t i = 0; i < n; i++) {
        paths[i] = rpzip_entry_at(zip, i)->name;
    }

    rp_analysis a;
    zipctx zc = { zip };
    int arv = rp_analyze(paths, n, zip_reader, &zc, &a);
    free(paths);

    if (arv != 0) {
        rpzip_close(zip);
        *error = RPError(@"Nello zip non c'è una cartella \"game\": non sembra la versione PC/Mac/Linux di un gioco Ren'Py.\n\nLe versioni Android (.apk) non sono supportate.");
        return nil;
    }

    /* Quali file copiare e quanto spazio serve. */
    NSMutableIndexSet *selected = [NSMutableIndexSet indexSet];
    unsigned long long total = 0;
    for (size_t i = 0; i < n; i++) {
        const rpzip_entry *e = rpzip_entry_at(zip, i);
        if (rp_should_import(e->name, a.root, NULL)) {
            [selected addIndex:i];
            total += e->uncomp_size;
        }
    }

    unsigned long long avail = [RPStore availableBytes];
    unsigned long long margin = 300ull * 1024 * 1024;
    if (avail < total + margin) {
        rpzip_close(zip);
        *error = RPError([NSString stringWithFormat:@"Spazio insufficiente: servono circa %@, liberi %@.",
                          [RPStore formatBytes:total + margin], [RPStore formatBytes:avail]]);
        return nil;
    }

    NSString *title = a.title[0] ? [NSString stringWithUTF8String:a.title] : nil;
    if (title.length == 0) {
        title = [RPStore titleFromFileName:displayName];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *tmp = [[RPStore gamesURL] URLByAppendingPathComponent:
                  [NSString stringWithFormat:@".import-%@", [NSUUID UUID].UUIDString] isDirectory:YES];
    [fm createDirectoryAtURL:tmp withIntermediateDirectories:YES attributes:nil error:nil];

    RPProgressState *st = [[RPProgressState alloc] init];
    st.task = task;
    st.block = progress;
    st.total = total;
    st.status = [NSString stringWithFormat:@"Estrazione di %@", title];

    BOOL ok = YES;

    for (NSUInteger i = selected.firstIndex; i != NSNotFound; i = [selected indexGreaterThanIndex:i]) {
        @autoreleasepool {
            const rpzip_entry *e = rpzip_entry_at(zip, i);
            const char *rel = NULL;
            rp_should_import(e->name, a.root, &rel);
            NSString *relS = rel ? [NSString stringWithUTF8String:rel] : nil;
            if (!relS) {
                continue;
            }
            NSURL *dest = [tmp URLByAppendingPathComponent:relS];

            if (e->is_dir) {
                [fm createDirectoryAtURL:dest withIntermediateDirectories:YES attributes:nil error:nil];
                continue;
            }

            if (!ensure_parent(dest, nil)) {
                snprintf(err, sizeof(err), "Impossibile creare la cartella per %s.", rel);
                ok = NO;
                break;
            }

            if (rpzip_extract_to_file(zip, i, dest.fileSystemRepresentation, progress_cb,
                                      (__bridge void *) st, err, sizeof(err))) {
                ok = NO;
                break;
            }

            st.done += e->uncomp_size;
            [st reportWithCurrent:0 force:NO];
        }
    }

    rpzip_close(zip);

    if (!ok) {
        [fm removeItemAtURL:tmp error:nil];
        *error = RPError(task.cancelled ? @"Importazione annullata." :
                         ([NSString stringWithUTF8String:err] ?: @"Errore durante l'estrazione."));
        return nil;
    }

    /* La radice è stata "appiattita": il gioco è direttamente nella cartella. */
    a.root[0] = 0;
    return [self finalizeImport:tmp analysis:&a title:title source:displayName size:total error:error];
}

+ (nullable RPGame *)finalizeImport:(NSURL *)tmp
                           analysis:(rp_analysis *)a
                              title:(NSString *)title
                             source:(NSString *)source
                               size:(unsigned long long)size
                              error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *folder = [RPStore uniqueFolderNameFor:title];
    NSURL *final = [[RPStore gamesURL] URLByAppendingPathComponent:folder isDirectory:YES];

    if (![fm moveItemAtURL:tmp toURL:final error:error]) {
        [fm removeItemAtURL:tmp error:nil];
        return nil;
    }

    RPGame *g = [[RPGame alloc] init];
    g.folderName = folder;
    [g fillFromAnalysis:a];
    g.title = title;
    g.sourceName = source;
    g.sizeBytes = size;
    g.importedAt = [NSDate date];

    [fm createDirectoryAtURL:g.saveDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    if (![g saveMetadata:error]) {
        return nil;
    }

    return g;
}

+ (RPImportTask *)importFolder:(NSURL *)url
                securityScoped:(BOOL)scoped
                      progress:(RPProgressBlock)progress
                    completion:(RPImportCompletion)completion {
    RPImportTask *task = [[RPImportTask alloc] init];
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    dispatch_async(import_queue(), ^{
        with_access(url, scoped, ^(NSURL *readable, NSError *accessError) {
            if (accessError) {
                finish(completion, nil, accessError);
                return;
            }
            NSError *error = nil;
            RPGame *game = [self doImportFolder:readable
                                    displayName:url.lastPathComponent
                                           task:task
                                       progress:progress
                                          error:&error];
            finish(completion, game, error);
        });
    });

    return task;
}

+ (nullable RPGame *)doImportFolder:(NSURL *)dir
                        displayName:(NSString *)displayName
                               task:(RPImportTask *)task
                           progress:(RPProgressBlock)progress
                              error:(NSError **)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        progress(0, @"Analisi della cartella…");
    });

    rp_analysis a;
    NSArray<NSString *> *files = nil;
    if (![RPStore analyzeDirectory:dir analysis:&a files:&files totalSize:NULL]) {
        *error = RPError(@"Nella cartella non c'è una sottocartella \"game\": non sembra un gioco Ren'Py per PC/Mac/Linux.");
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    NSMutableArray<NSString *> *rels = [NSMutableArray array];
    unsigned long long total = 0;

    for (NSString *f in files) {
        const char *rel = NULL;
        if (!rp_should_import(f.UTF8String, a.root, &rel)) {
            continue;
        }
        NSString *relS = [NSString stringWithUTF8String:rel];
        if (!relS) {
            continue;
        }
        [selected addObject:f];
        [rels addObject:relS];
        NSDictionary *attrs = [fm attributesOfItemAtPath:[dir URLByAppendingPathComponent:f].path error:nil];
        total += attrs.fileSize;
    }

    unsigned long long avail = [RPStore availableBytes];
    unsigned long long margin = 300ull * 1024 * 1024;
    if (avail < total + margin) {
        *error = RPError([NSString stringWithFormat:@"Spazio insufficiente: servono circa %@, liberi %@.",
                          [RPStore formatBytes:total + margin], [RPStore formatBytes:avail]]);
        return nil;
    }

    NSString *title = a.title[0] ? [NSString stringWithUTF8String:a.title] : nil;
    if (title.length == 0) {
        title = [RPStore titleFromFileName:displayName];
    }

    NSURL *tmp = [[RPStore gamesURL] URLByAppendingPathComponent:
                  [NSString stringWithFormat:@".import-%@", [NSUUID UUID].UUIDString] isDirectory:YES];
    [fm createDirectoryAtURL:tmp withIntermediateDirectories:YES attributes:nil error:nil];

    RPProgressState *st = [[RPProgressState alloc] init];
    st.task = task;
    st.block = progress;
    st.total = total;
    st.status = [NSString stringWithFormat:@"Copia di %@", title];

    for (NSUInteger i = 0; i < selected.count; i++) {
        @autoreleasepool {
            if (task.cancelled) {
                [fm removeItemAtURL:tmp error:nil];
                *error = RPError(@"Importazione annullata.");
                return nil;
            }

            NSURL *src = [dir URLByAppendingPathComponent:selected[i]];
            NSURL *dst = [tmp URLByAppendingPathComponent:rels[i]];
            NSError *e = nil;
            if (!ensure_parent(dst, &e) || ![fm copyItemAtURL:src toURL:dst error:&e]) {
                [fm removeItemAtURL:tmp error:nil];
                *error = RPError([NSString stringWithFormat:@"Errore copiando %@: %@", rels[i], e.localizedDescription]);
                return nil;
            }

            NSDictionary *attrs = [fm attributesOfItemAtPath:dst.path error:nil];
            st.done += attrs.fileSize;
            [st reportWithCurrent:0 force:NO];
        }
    }

    a.root[0] = 0;
    return [self finalizeImport:tmp analysis:&a title:title source:displayName size:total error:error];
}

/* ------------------------------------------------------------------------ */
/* Salvataggi                                                                */
/* ------------------------------------------------------------------------ */

+ (void)importSaves:(NSArray<NSURL *> *)urls
             intoGame:(RPGame *)game
           completion:(RPSavesCompletion)completion {
    dispatch_async(import_queue(), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *saves = game.saveDirectory;
        [fm createDirectoryAtURL:saves withIntermediateDirectories:YES attributes:nil error:nil];

        __block NSUInteger count = 0;
        __block NSURL *backup = nil;
        __block NSError *firstError = nil;

        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyyMMdd-HHmmss";
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        NSString *stamp = [df stringFromDate:[NSDate date]];

        /* Prima di sovrascrivere un file, lo sposta nella cartella di backup. */
        BOOL (^prepare)(NSString *) = ^BOOL(NSString *name) {
            NSURL *dst = [saves URLByAppendingPathComponent:name];
            if (![fm fileExistsAtPath:dst.path]) {
                return YES;
            }
            if (!backup) {
                backup = [[[game.directory URLByAppendingPathComponent:@"renplayer-backup" isDirectory:YES]
                           URLByAppendingPathComponent:stamp isDirectory:YES] copy];
                [fm createDirectoryAtURL:backup withIntermediateDirectories:YES attributes:nil error:nil];
            }
            NSURL *b = [backup URLByAppendingPathComponent:name];
            [fm removeItemAtURL:b error:nil];
            return [fm moveItemAtURL:dst toURL:b error:nil];
        };

        void (^copyFile)(NSURL *) = ^(NSURL *src) {
            NSString *name = src.lastPathComponent;
            if (!rp_is_save_file(name.fileSystemRepresentation)) {
                return;
            }
            if (!prepare(name)) {
                return;
            }
            NSError *e = nil;
            if ([fm copyItemAtURL:src toURL:[saves URLByAppendingPathComponent:name] error:&e]) {
                count++;
            } else if (!firstError) {
                firstError = e;
            }
        };

        for (NSURL *url in urls) {
            with_access(url, YES, ^(NSURL *readable, NSError *accessError) {
                if (accessError) {
                    if (!firstError) {
                        firstError = accessError;
                    }
                    return;
                }

                NSNumber *isDir = nil;
                [readable getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];

                if (isDir.boolValue) {
                    NSDirectoryEnumerator *en = [fm enumeratorAtURL:readable
                                         includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                                                            options:0
                                                       errorHandler:nil];
                    for (NSURL *u in en) {
                        NSNumber *d = nil;
                        [u getResourceValue:&d forKey:NSURLIsDirectoryKey error:nil];
                        if (!d.boolValue) {
                            copyFile(u);
                        }
                    }
                } else if ([readable.pathExtension.lowercaseString isEqualToString:@"zip"]) {
                    char err[RP_ERRLEN] = "";
                    rpzip *zip = NULL;
                    if (rpzip_open(readable.fileSystemRepresentation, &zip, err, sizeof(err))) {
                        if (!firstError) {
                            firstError = RPError([NSString stringWithUTF8String:err] ?: @"Zip non valido.");
                        }
                        return;
                    }
                    for (size_t i = 0; i < rpzip_count(zip); i++) {
                        const rpzip_entry *e = rpzip_entry_at(zip, i);
                        if (e->is_dir || !rp_is_save_file(e->name)) {
                            continue;
                        }
                        NSString *name = [[NSString stringWithUTF8String:e->name] lastPathComponent];
                        if (!name.length || !prepare(name)) {
                            continue;
                        }
                        NSURL *dst = [saves URLByAppendingPathComponent:name];
                        if (rpzip_extract_to_file(zip, i, dst.fileSystemRepresentation, NULL, NULL, err, sizeof(err)) == 0) {
                            count++;
                        } else if (!firstError) {
                            firstError = RPError([NSString stringWithUTF8String:err] ?: @"Errore nello zip.");
                        }
                    }
                    rpzip_close(zip);
                } else {
                    copyFile(readable);
                }
            });
        }

        NSString *backupRel = backup ? [NSString stringWithFormat:@"renplayer-backup/%@", stamp] : nil;
        NSError *rerr = nil;
        if (count == 0) {
            rerr = firstError ?: RPError(@"Nessun salvataggio trovato. Servono i file .save e/o il file \"persistent\".");
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(count, backupRel, rerr);
        });
    });
}

+ (nullable NSURL *)exportSavesOfGame:(RPGame *)game error:(NSError **)error {
    NSArray<NSURL *> *files = [game saveFiles];
    if (files.count == 0) {
        if (error) {
            *error = RPError(@"Questo gioco non ha ancora salvataggi.");
        }
        return nil;
    }

    NSString *name = [NSString stringWithFormat:@"%@ - salvataggi.zip", [RPStore uniqueFolderNameFor:game.title]];
    NSURL *dir = [[NSFileManager defaultManager].temporaryDirectory URLByAppendingPathComponent:[NSUUID UUID].UUIDString isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *out = [dir URLByAppendingPathComponent:name];

    char err[RP_ERRLEN] = "";
    rpzipw *w = NULL;
    if (rpzipw_open(out.fileSystemRepresentation, &w, err, sizeof(err))) {
        if (error) {
            *error = RPError([NSString stringWithUTF8String:err] ?: @"Errore.");
        }
        return nil;
    }

    for (NSURL *f in files) {
        if (rpzipw_add_file(w, f.lastPathComponent.UTF8String, f.fileSystemRepresentation, err, sizeof(err))) {
            rpzipw_close(w, err, sizeof(err));
            if (error) {
                *error = RPError([NSString stringWithUTF8String:err] ?: @"Errore.");
            }
            return nil;
        }
    }

    if (rpzipw_close(w, err, sizeof(err))) {
        if (error) {
            *error = RPError([NSString stringWithUTF8String:err] ?: @"Errore.");
        }
        return nil;
    }

    return out;
}

/* ------------------------------------------------------------------------ */
/* File aggiuntivi (mod, traduzioni, .rpy...)                                */
/* ------------------------------------------------------------------------ */

static BOOL skip_junk(NSString *rel) {
    NSString *bn = rel.lastPathComponent;
    return [rel hasPrefix:@"__MACOSX/"] || [rel containsString:@"/__MACOSX/"] || [bn hasPrefix:@"._"] ||
           [bn isEqualToString:@".DS_Store"] || [bn isEqualToString:@"Thumbs.db"] || [bn isEqualToString:@".renplayer.json"];
}

+ (void)addFiles:(NSArray<NSURL *> *)urls
          toGame:(RPGame *)game
      completion:(RPSavesCompletion)completion {
    dispatch_async(import_queue(), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *base = game.baseDirectory;

        __block NSUInteger count = 0;
        __block NSURL *backup = nil;
        __block NSError *firstError = nil;

        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyyMMdd-HHmmss";
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        NSString *stamp = [[df stringFromDate:[NSDate date]] stringByAppendingString:@"-file"];

        void (^noteError)(NSError *) = ^(NSError *e) {
            if (!firstError && e) {
                firstError = e;
            }
        };

        /* Prepara la destinazione (relativa alla cartella del gioco): crea le
         * cartelle e sposta nel backup un eventuale file già presente. */
        NSURL * (^prepare)(NSString *) = ^NSURL *(NSString *rel) {
            NSURL *dst = [base URLByAppendingPathComponent:rel];
            NSError *e = nil;
            if (!ensure_parent(dst, &e)) {
                noteError(e);
                return nil;
            }
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:dst.path isDirectory:&isDir]) {
                if (isDir) {
                    noteError(RPError([NSString stringWithFormat:@"%@ è una cartella: non la sostituisco con un file.", rel]));
                    return nil;
                }
                if (!backup) {
                    backup = [[game.directory URLByAppendingPathComponent:@"renplayer-backup" isDirectory:YES]
                              URLByAppendingPathComponent:stamp isDirectory:YES];
                }
                NSURL *b = [backup URLByAppendingPathComponent:rel];
                ensure_parent(b, nil);
                [fm removeItemAtURL:b error:nil];
                if (![fm moveItemAtURL:dst toURL:b error:&e]) {
                    noteError(e);
                    return nil;
                }
            }
            return dst;
        };

        void (^copyOne)(NSURL *, NSString *) = ^(NSURL *src, NSString *rel) {
            if (skip_junk(rel)) {
                return;
            }
            NSURL *dst = prepare(rel);
            if (!dst) {
                return;
            }
            NSError *e = nil;
            if ([fm copyItemAtURL:src toURL:dst error:&e]) {
                count++;
            } else {
                noteError(e);
            }
        };

        for (NSURL *url in urls) {
            with_access(url, YES, ^(NSURL *readable, NSError *accessError) {
                if (accessError) {
                    noteError(accessError);
                    return;
                }

                NSNumber *isDir = nil;
                [readable getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];

                if (isDir.boolValue) {
                    rp_analysis a;
                    NSArray<NSString *> *files = nil;
                    BOOL found = [RPStore analyzeDirectory:readable analysis:&a files:&files totalSize:NULL];

                    for (NSString *f in files) {
                        @autoreleasepool {
                            NSURL *src = [readable URLByAppendingPathComponent:f];
                            if (found) {
                                /* La cartella contiene game/: la radice corrisponde alla cartella del gioco. */
                                const char *rel = NULL;
                                if (!rp_should_import(f.UTF8String, a.root, &rel)) {
                                    continue;
                                }
                                NSString *relS = [NSString stringWithUTF8String:rel];
                                if (relS) {
                                    copyOne(src, relS);
                                }
                            } else {
                                NSString *rel = [NSString stringWithFormat:@"game/%@/%@", readable.lastPathComponent, f];
                                copyOne(src, rel);
                            }
                        }
                    }
                    return;
                }

                if ([readable.pathExtension.lowercaseString isEqualToString:@"zip"]) {
                    char err[RP_ERRLEN] = "";
                    rpzip *zip = NULL;
                    if (rpzip_open(readable.fileSystemRepresentation, &zip, err, sizeof(err))) {
                        noteError(RPError([NSString stringWithUTF8String:err] ?: @"Zip non valido."));
                        return;
                    }

                    size_t n = rpzip_count(zip);
                    const char **paths = calloc(n ? n : 1, sizeof(char *));
                    for (size_t i = 0; i < n; i++) {
                        paths[i] = rpzip_entry_at(zip, i)->name;
                    }
                    rp_analysis a;
                    zipctx zc = { zip };
                    BOOL found = rp_analyze(paths, n, zip_reader, &zc, &a) == 0;
                    free(paths);

                    unsigned long long need = rpzip_total_uncompressed(zip);
                    if ([RPStore availableBytes] < need + 100ull * 1024 * 1024) {
                        rpzip_close(zip);
                        noteError(RPError([NSString stringWithFormat:@"Spazio insufficiente per %@ (servono circa %@).",
                                           readable.lastPathComponent, [RPStore formatBytes:need]]));
                        return;
                    }

                    for (size_t i = 0; i < n; i++) {
                        @autoreleasepool {
                            const rpzip_entry *e = rpzip_entry_at(zip, i);
                            if (e->is_dir) {
                                continue;
                            }

                            NSString *relS = nil;
                            if (found) {
                                const char *rel = NULL;
                                if (!rp_should_import(e->name, a.root, &rel)) {
                                    continue;
                                }
                                relS = [NSString stringWithUTF8String:rel];
                            } else {
                                NSString *name = [NSString stringWithUTF8String:e->name];
                                relS = name ? [@"game/" stringByAppendingString:name] : nil;
                            }

                            if (!relS || skip_junk(relS)) {
                                continue;
                            }

                            NSURL *dst = prepare(relS);
                            if (!dst) {
                                continue;
                            }

                            if (rpzip_extract_to_file(zip, i, dst.fileSystemRepresentation, NULL, NULL, err, sizeof(err)) == 0) {
                                count++;
                            } else {
                                noteError(RPError([NSString stringWithUTF8String:err] ?: @"Errore nello zip."));
                            }
                        }
                    }

                    rpzip_close(zip);
                    return;
                }

                copyOne(readable, [@"game/" stringByAppendingString:readable.lastPathComponent]);
            });
        }

        NSString *backupRel = backup ? [@"renplayer-backup/" stringByAppendingString:stamp] : nil;
        NSError *rerr = nil;
        if (count == 0) {
            rerr = firstError ?: RPError(@"Nessun file copiato.");
        }

        if (count > 0) {
            /* La dimensione mostrata in libreria va aggiornata. */
            unsigned long long size = 0;
            [RPStore analyzeDirectory:game.directory analysis:&(rp_analysis){ 0 } files:NULL totalSize:&size];
            game.sizeBytes = size;
            [game saveMetadata:nil];
        }

        NSError *partial = (count > 0) ? firstError : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (partial) {
                completion(count, backupRel, RPError([NSString stringWithFormat:@"Copiati %lu file, ma qualcosa non è andato: %@",
                                                      (unsigned long) count, partial.localizedDescription]));
            } else {
                completion(count, backupRel, rerr);
            }
        });
    });
}

@end
