/*
 * RenPlayer - dichiarazioni comuni dell'interfaccia nativa.
 */

@import UIKit;

#include "rpcore.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RPErrorDomain;

NSError *RPError(NSString *message);

/* ------------------------------------------------------------------------ */

@interface RPGame : NSObject

@property (nonatomic, copy) NSString *folderName;      /* cartella in Documents/Games */
@property (nonatomic, copy) NSString *baseSubpath;     /* radice del gioco dentro la cartella ("" di solito) */
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *renpyVersion;    /* "" se sconosciuta */
@property (nonatomic, copy) NSString *pythonTag;       /* "2.7", "3.9"... */
@property (nonatomic) NSInteger detectedRuntime;       /* 7 o 8 */
@property (nonatomic) NSInteger runtimeOverride;       /* 0 = automatico */
@property (nonatomic) BOOL confident;
@property (nonatomic) BOOL newerThanRuntime;
@property (nonatomic, copy) NSString *evidence;
@property (nonatomic, copy) NSString *gameVersion;
@property (nonatomic, copy) NSString *sourceName;
@property (nonatomic) unsigned long long sizeBytes;
@property (nonatomic, strong, nullable) NSDate *importedAt;
@property (nonatomic, strong, nullable) NSDate *lastPlayed;

@property (nonatomic, readonly) NSInteger runtime;      /* override o rilevato */
@property (nonatomic, readonly) NSString *runtimeVersion;
@property (nonatomic, readonly) NSURL *directory;       /* Documents/Games/<folderName> */
@property (nonatomic, readonly) NSURL *baseDirectory;   /* directory + baseSubpath = config.basedir */
@property (nonatomic, readonly) NSURL *saveDirectory;   /* baseDirectory/game/saves */
@property (nonatomic, readonly) NSURL *logFile;         /* output di Python */
@property (nonatomic, readonly) NSURL *stderrFile;      /* stderr del processo */

- (void)fillFromAnalysis:(const rp_analysis *)a;
- (BOOL)saveMetadata:(NSError **)error;
- (nullable UIImage *)icon;
- (NSArray<NSURL *> *)saveFiles;
- (NSArray<NSURL *> *)logFiles;                         /* file di log esistenti */
- (NSString *)versionDescription;                       /* es. "Ren'Py 8.3.7" */

@end

/* ------------------------------------------------------------------------ */

@interface RPStore : NSObject

+ (NSURL *)documentsURL;
+ (NSURL *)gamesURL;
+ (NSURL *)dataURL;              /* Library/Application Support/RenPlayer */
+ (NSURL *)inboxURL;             /* Documents/Inbox */

+ (NSArray<RPGame *> *)loadGames;
+ (nullable RPGame *)loadGameInFolder:(NSString *)folder;
+ (NSString *)uniqueFolderNameFor:(NSString *)title;
+ (BOOL)deleteGame:(RPGame *)game error:(NSError **)error;

+ (NSString *)formatBytes:(unsigned long long)bytes;
+ (unsigned long long)availableBytes;
+ (NSString *)titleFromFileName:(NSString *)name;

/* Analizza una cartella già presente sul disco (radice inclusa). */
+ (BOOL)analyzeDirectory:(NSURL *)dir
                analysis:(rp_analysis *)analysis
                   files:(NSArray<NSString *> *_Nullable *_Nullable)files
               totalSize:(unsigned long long *_Nullable)totalSize;

@end

/* ------------------------------------------------------------------------ */

typedef void (^RPProgressBlock)(double fraction, NSString *status);
typedef void (^RPImportCompletion)(RPGame *_Nullable game, NSError *_Nullable error);
typedef void (^RPSavesCompletion)(NSUInteger count, NSString *_Nullable backupFolder, NSError *_Nullable error);

@interface RPImportTask : NSObject
@property (atomic) BOOL cancelled;
@end

@interface RPImporter : NSObject

/* Tutti i blocchi vengono chiamati sul main thread. */
+ (RPImportTask *)importArchive:(NSURL *)url
                 securityScoped:(BOOL)scoped
                deleteWhenDone:(BOOL)deleteWhenDone
                       progress:(RPProgressBlock)progress
                     completion:(RPImportCompletion)completion;

+ (RPImportTask *)importFolder:(NSURL *)url
                securityScoped:(BOOL)scoped
                      progress:(RPProgressBlock)progress
                    completion:(RPImportCompletion)completion;

+ (void)importSaves:(NSArray<NSURL *> *)urls
             intoGame:(RPGame *)game
           completion:(RPSavesCompletion)completion;

+ (nullable NSURL *)exportSavesOfGame:(RPGame *)game error:(NSError **)error;

@end

/* ------------------------------------------------------------------------ */

@interface RPLauncher : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL active;
@property (nonatomic, strong, nullable) RPGame *gameToLaunch;

/* URL arrivati con "Apri con" / condivisione, in attesa di importazione. */
@property (nonatomic, readonly) NSMutableArray<NSDictionary *> *pendingURLs;

- (void)present;
- (void)dismissWindow;
- (void)handleOpenURL:(NSURL *)url openInPlace:(BOOL)inPlace;

/* Gestione del segnale di "avvio in corso" per capire se un gioco si è chiuso male. */
+ (void)markLaunching:(RPGame *)game;
+ (void)clearLaunching;
+ (nullable NSString *)crashedGameFolder;

@end

/* Interfaccia */
UIViewController *RPMakeRootViewController(void);

NS_ASSUME_NONNULL_END
