/*
 * RenPlayer - modello dei giochi e archivio su disco.
 *
 * Struttura:
 *   Documents/Games/<cartella>/            config.basedir (visibile nell'app File)
 *   Documents/Games/<cartella>/game/saves  salvataggi
 *   Documents/Games/<cartella>/.renplayer.json
 *   Library/Application Support/RenPlayer  dati condivisi (token, backup di Ren'Py)
 */

#import "RPCommon.h"

NSString *const RPErrorDomain = @"RenPlayer";

static NSString *const kMetaName = @".renplayer.json";

NSError *RPError(NSString *message) {
    return [NSError errorWithDomain:RPErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey : message }];
}

@implementation RPGame

- (instancetype)init {
    self = [super init];
    if (self) {
        _folderName = @"";
        _baseSubpath = @"";
        _title = @"";
        _renpyVersion = @"";
        _pythonTag = @"";
        _detectedRuntime = 8;
        _evidence = @"";
        _gameVersion = @"";
        _sourceName = @"";
    }
    return self;
}

- (NSInteger)runtime {
    if (self.runtimeOverride == 7 || self.runtimeOverride == 8) {
        return self.runtimeOverride;
    }
    return self.detectedRuntime == 7 ? 7 : 8;
}

- (NSString *)runtimeVersion {
    return self.runtime == 7 ? @RP_RUNTIME7_VERSION : @RP_RUNTIME8_VERSION;
}

- (NSURL *)directory {
    return [[RPStore gamesURL] URLByAppendingPathComponent:self.folderName isDirectory:YES];
}

- (NSURL *)baseDirectory {
    NSString *sub = self.baseSubpath;
    while ([sub hasSuffix:@"/"]) {
        sub = [sub substringToIndex:sub.length - 1];
    }
    if (sub.length == 0) {
        return self.directory;
    }
    return [self.directory URLByAppendingPathComponent:sub isDirectory:YES];
}

- (NSURL *)saveDirectory {
    return [[self.baseDirectory URLByAppendingPathComponent:@"game" isDirectory:YES]
            URLByAppendingPathComponent:@"saves" isDirectory:YES];
}

- (NSURL *)logFile {
    return [self.directory URLByAppendingPathComponent:@"renplayer-log.txt"];
}

- (NSURL *)stderrFile {
    return [self.directory URLByAppendingPathComponent:@"renplayer-stderr.txt"];
}

- (NSString *)versionDescription {
    if (self.renpyVersion.length) {
        NSArray *parts = [self.renpyVersion componentsSeparatedByString:@"."];
        if (parts.count >= 3) {
            return [NSString stringWithFormat:@"Ren'Py %@.%@.%@", parts[0], parts[1], parts[2]];
        }
        return [@"Ren'Py " stringByAppendingString:self.renpyVersion];
    }
    if (self.pythonTag.length) {
        return [NSString stringWithFormat:@"Ren'Py %@ (Python %@)", self.detectedRuntime == 7 ? @"6/7" : @"8", self.pythonTag];
    }
    return @"Ren'Py (versione sconosciuta)";
}

- (void)fillFromAnalysis:(const rp_analysis *)a {
    self.baseSubpath = [NSString stringWithUTF8String:a->root] ?: @"";
    self.renpyVersion = [NSString stringWithUTF8String:a->version] ?: @"";
    self.pythonTag = [NSString stringWithUTF8String:a->py_tag] ?: @"";
    self.detectedRuntime = a->runtime;
    self.confident = a->confident != 0;
    self.newerThanRuntime = a->newer_than_runtime != 0;
    self.evidence = [NSString stringWithUTF8String:a->evidence] ?: @"";
    self.gameVersion = [NSString stringWithUTF8String:a->game_version] ?: @"";
}

- (NSDictionary *)metadataDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"formatVersion"] = @1;
    d[@"title"] = self.title;
    d[@"baseSubpath"] = self.baseSubpath;
    d[@"renpyVersion"] = self.renpyVersion;
    d[@"pythonTag"] = self.pythonTag;
    d[@"detectedRuntime"] = @(self.detectedRuntime);
    d[@"runtimeOverride"] = @(self.runtimeOverride);
    d[@"confident"] = @(self.confident);
    d[@"newerThanRuntime"] = @(self.newerThanRuntime);
    d[@"evidence"] = self.evidence;
    d[@"gameVersion"] = self.gameVersion;
    d[@"sourceName"] = self.sourceName;
    d[@"sizeBytes"] = @(self.sizeBytes);
    if (self.importedAt) {
        d[@"importedAt"] = @(self.importedAt.timeIntervalSince1970);
    }
    if (self.lastPlayed) {
        d[@"lastPlayed"] = @(self.lastPlayed.timeIntervalSince1970);
    }
    return d;
}

static NSString *str(NSDictionary *d, NSString *k) {
    id v = d[k];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

static NSInteger num(NSDictionary *d, NSString *k) {
    id v = d[k];
    return [v isKindOfClass:[NSNumber class]] ? [v integerValue] : 0;
}

- (void)applyMetadata:(NSDictionary *)d {
    self.title = str(d, @"title");
    self.baseSubpath = str(d, @"baseSubpath");
    self.renpyVersion = str(d, @"renpyVersion");
    self.pythonTag = str(d, @"pythonTag");
    self.detectedRuntime = num(d, @"detectedRuntime") == 7 ? 7 : 8;
    self.runtimeOverride = num(d, @"runtimeOverride");
    self.confident = num(d, @"confident") != 0;
    self.newerThanRuntime = num(d, @"newerThanRuntime") != 0;
    self.evidence = str(d, @"evidence");
    self.gameVersion = str(d, @"gameVersion");
    self.sourceName = str(d, @"sourceName");
    id size = d[@"sizeBytes"];
    self.sizeBytes = [size isKindOfClass:[NSNumber class]] ? [size unsignedLongLongValue] : 0;
    id imp = d[@"importedAt"];
    self.importedAt = [imp isKindOfClass:[NSNumber class]] ? [NSDate dateWithTimeIntervalSince1970:[imp doubleValue]] : nil;
    id lp = d[@"lastPlayed"];
    self.lastPlayed = [lp isKindOfClass:[NSNumber class]] ? [NSDate dateWithTimeIntervalSince1970:[lp doubleValue]] : nil;
}

- (BOOL)saveMetadata:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self metadataDictionary]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!data) {
        return NO;
    }
    NSURL *url = [self.directory URLByAppendingPathComponent:kMetaName];
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (nullable UIImage *)icon {
    NSArray *candidates = @[ @"game/gui/window_icon.png", @"game/window_icon.png", @"game/icon.png",
                             @"game/gui/icon.png", @"game/images/icon.png" ];
    for (NSString *c in candidates) {
        NSURL *u = [self.baseDirectory URLByAppendingPathComponent:c];
        UIImage *img = [UIImage imageWithContentsOfFile:u.path];
        if (img) {
            return img;
        }
    }
    return nil;
}

- (NSArray<NSURL *> *)saveFiles {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.saveDirectory
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:nil];
    NSMutableArray *rv = [NSMutableArray array];
    for (NSURL *u in items) {
        if (rp_is_save_file(u.lastPathComponent.fileSystemRepresentation)) {
            [rv addObject:u];
        }
    }
    [rv sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];
    return rv;
}

- (NSArray<NSURL *> *)logFiles {
    NSMutableArray *rv = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = @[ @"traceback.txt", @"errors.txt", @"log.txt" ];
    for (NSString *n in names) {
        NSURL *u = [self.baseDirectory URLByAppendingPathComponent:n];
        if ([fm fileExistsAtPath:u.path]) {
            [rv addObject:u];
        }
    }
    for (NSURL *u in @[ self.logFile, self.stderrFile ]) {
        if ([fm fileExistsAtPath:u.path]) {
            [rv addObject:u];
        }
    }
    return rv;
}

@end

/* ------------------------------------------------------------------------ */

@implementation RPStore

+ (NSURL *)documentsURL {
    return [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}

+ (NSURL *)gamesURL {
    NSURL *u = [[self documentsURL] URLByAppendingPathComponent:@"Games" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:nil];
    return u;
}

+ (NSURL *)dataURL {
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *u = [base URLByAppendingPathComponent:@"RenPlayer" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:nil];
    return u;
}

+ (NSURL *)inboxURL {
    return [[self documentsURL] URLByAppendingPathComponent:@"Inbox" isDirectory:YES];
}

+ (nullable RPGame *)loadGameInFolder:(NSString *)folder {
    NSURL *dir = [[self gamesURL] URLByAppendingPathComponent:folder isDirectory:YES];
    NSURL *meta = [dir URLByAppendingPathComponent:kMetaName];

    RPGame *g = [[RPGame alloc] init];
    g.folderName = folder;

    NSData *data = [NSData dataWithContentsOfURL:meta];
    NSDictionary *d = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;

    if ([d isKindOfClass:[NSDictionary class]]) {
        [g applyMetadata:d];
        if (g.title.length == 0) {
            g.title = folder;
        }
        return g;
    }

    /* Cartella copiata a mano con l'app File: la analizziamo adesso. */
    rp_analysis a;
    unsigned long long size = 0;
    if (![self analyzeDirectory:dir analysis:&a files:NULL totalSize:&size]) {
        return nil;
    }

    [g fillFromAnalysis:&a];
    g.title = a.title[0] ? ([NSString stringWithUTF8String:a.title] ?: folder) : folder;
    g.sourceName = folder;
    g.sizeBytes = size;
    g.importedAt = [NSDate date];
    [[NSFileManager defaultManager] createDirectoryAtURL:g.saveDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [g saveMetadata:nil];
    return g;
}

+ (NSArray<RPGame *> *)loadGames {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self gamesURL]
                                                   includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:nil];
    NSMutableArray *games = [NSMutableArray array];
    for (NSURL *u in items) {
        NSNumber *isDir = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (!isDir.boolValue) {
            continue;
        }
        RPGame *g = [self loadGameInFolder:u.lastPathComponent];
        if (g) {
            [games addObject:g];
        }
    }

    [games sortUsingComparator:^NSComparisonResult(RPGame *a, RPGame *b) {
        NSDate *da = a.lastPlayed ?: a.importedAt ?: [NSDate distantPast];
        NSDate *db = b.lastPlayed ?: b.importedAt ?: [NSDate distantPast];
        NSComparisonResult r = [db compare:da];
        if (r != NSOrderedSame) {
            return r;
        }
        return [a.title localizedStandardCompare:b.title];
    }];

    return games;
}

+ (NSString *)uniqueFolderNameFor:(NSString *)title {
    NSMutableString *s = [NSMutableString string];
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    for (NSUInteger i = 0; i < title.length; i++) {
        unichar c = [title characterAtIndex:i];
        if ([bad characterIsMember:c] || c < 0x20) {
            [s appendString:@"-"];
        } else {
            [s appendFormat:@"%C", c];
        }
    }

    NSString *base = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([base hasPrefix:@"."]) {
        base = [base substringFromIndex:1];
    }
    if (base.length > 60) {
        base = [base substringToIndex:60];
    }
    if (base.length == 0) {
        base = @"Gioco";
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *name = base;
    int n = 2;
    while ([fm fileExistsAtPath:[[self gamesURL] URLByAppendingPathComponent:name].path]) {
        name = [NSString stringWithFormat:@"%@ %d", base, n++];
    }
    return name;
}

+ (BOOL)deleteGame:(RPGame *)game error:(NSError **)error {
    if (game.folderName.length == 0) {
        if (error) {
            *error = RPError(@"Cartella del gioco non valida.");
        }
        return NO;
    }
    return [[NSFileManager defaultManager] removeItemAtURL:game.directory error:error];
}

+ (NSString *)formatBytes:(unsigned long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long) bytes countStyle:NSByteCountFormatterCountStyleFile];
}

+ (unsigned long long)availableBytes {
    NSURL *docs = [self documentsURL];
    NSDictionary *vals = [docs resourceValuesForKeys:@[ NSURLVolumeAvailableCapacityForImportantUsageKey ] error:nil];
    NSNumber *n = vals[NSURLVolumeAvailableCapacityForImportantUsageKey];
    if (n && n.longLongValue > 0) {
        return n.unsignedLongLongValue;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:docs.path error:nil];
    return [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
}

+ (NSString *)titleFromFileName:(NSString *)name {
    NSString *t = name.stringByDeletingPathExtension;

    /* Toglie i suffissi tipici delle distribuzioni Ren'Py. */
    NSArray *suffixes = @[ @"-pc", @"-PC", @"-win", @"-mac", @"-linux", @"-all", @"-market", @"_pc", @"-Pc" ];
    BOOL changed = YES;
    while (changed) {
        changed = NO;
        for (NSString *suf in suffixes) {
            if ([t hasSuffix:suf] && t.length > suf.length) {
                t = [t substringToIndex:t.length - suf.length];
                changed = YES;
            }
        }
    }

    t = [t stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return t.length ? t : name;
}

/* Lettore per rp_analyze: legge file relativi a una cartella. */
static int dir_reader(void *ctx, const char *path, unsigned char **out, size_t *outlen) {
    NSURL *dir = (__bridge NSURL *) ctx;
    NSString *rel = [NSString stringWithUTF8String:path];
    if (!rel) {
        return -1;
    }
    NSURL *u = [dir URLByAppendingPathComponent:rel];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:u.path error:nil];
    if (!attrs || [attrs fileSize] > (1 << 20)) {
        return -1;
    }
    NSData *d = [NSData dataWithContentsOfURL:u];
    if (!d) {
        return -1;
    }
    unsigned char *buf = malloc(d.length + 1);
    if (!buf) {
        return -1;
    }
    memcpy(buf, d.bytes, d.length);
    buf[d.length] = 0;
    *out = buf;
    *outlen = d.length;
    return 0;
}

+ (BOOL)analyzeDirectory:(NSURL *)dir
                analysis:(rp_analysis *)analysis
                   files:(NSArray<NSString *> *_Nullable *_Nullable)filesOut
               totalSize:(unsigned long long *_Nullable)totalSize {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en = [fm enumeratorAtURL:dir
                         includingPropertiesForKeys:@[ NSURLIsDirectoryKey, NSURLFileSizeKey ]
                                            options:0
                                       errorHandler:nil];

    NSString *basePath = dir.URLByStandardizingPath.URLByResolvingSymlinksInPath.path;
    if (![basePath hasSuffix:@"/"]) {
        basePath = [basePath stringByAppendingString:@"/"];
    }

    NSMutableArray<NSString *> *files = [NSMutableArray array];
    unsigned long long total = 0;

    for (NSURL *u in en) {
        NSNumber *isDir = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            continue;
        }

        NSString *p = u.URLByStandardizingPath.URLByResolvingSymlinksInPath.path;
        if (![p hasPrefix:basePath]) {
            continue;
        }
        NSString *rel = [p substringFromIndex:basePath.length];
        if ([rel isEqualToString:kMetaName]) {
            continue;
        }
        [files addObject:rel];

        NSNumber *size = nil;
        [u getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        total += size.unsignedLongLongValue;
    }

    size_t n = files.count;
    const char **paths = calloc(n ? n : 1, sizeof(char *));
    for (size_t i = 0; i < n; i++) {
        paths[i] = files[i].UTF8String;
    }

    int rv = rp_analyze(paths, n, dir_reader, (__bridge void *) dir, analysis);
    free(paths);

    if (filesOut) {
        *filesOut = files;
    }
    if (totalSize) {
        *totalSize = total;
    }
    return rv == 0;
}

@end
