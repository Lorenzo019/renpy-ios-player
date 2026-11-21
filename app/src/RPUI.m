/*
 * RenPlayer - interfaccia nativa (libreria dei giochi, dettagli, salvataggi).
 */

#import "RPCommon.h"

@import UniformTypeIdentifiers;

static NSString *const RPPendingURLsNotification = @"RPPendingURLsNotification";

static void RPAlert(UIViewController *vc, NSString *title, NSString *message) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

static UIViewController *RPTopViewController(UIViewController *vc) {
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

/* ======================================================================== */
/* Avanzamento                                                               */
/* ======================================================================== */

@interface RPProgressViewController : UIViewController
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *bar;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, copy, nullable) void (^onCancel)(void);
@end

@implementation RPProgressViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];

    UIView *box = [[UIView alloc] init];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = [UIColor secondarySystemBackgroundColor];
    box.layer.cornerRadius = 16;
    [self.view addSubview:box];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.titleLabel.text = @"Importazione";
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = @"…";

    self.bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelButton setTitle:@"Annulla" forState:UIControlStateNormal];
    [self.cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ self.titleLabel, self.statusLabel, self.bar, self.cancelButton ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [box.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [box.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [box.widthAnchor constraintEqualToConstant:360],
        [stack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:box.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-14],
    ]];
}

- (void)cancelTapped {
    self.cancelButton.enabled = NO;
    self.statusLabel.text = @"Annullamento…";
    if (self.onCancel) {
        self.onCancel();
    }
}

- (void)setFraction:(double)f status:(NSString *)status {
    [self loadViewIfNeeded];
    [self.bar setProgress:(float) f animated:NO];
    self.statusLabel.text = status;
}

@end

/* ======================================================================== */
/* Visualizzatore di testo (log)                                             */
/* ======================================================================== */

@interface RPTextViewController : UIViewController
@property (nonatomic, copy) NSArray<NSURL *> *files;
@property (nonatomic, copy, nullable) NSString *staticText;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISegmentedControl *picker;
@end

@implementation RPTextViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.textView.alwaysBounceVertical = YES;
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.view addSubview:self.textView];

    if (self.staticText) {
        self.textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        self.textView.text = self.staticText;
        return;
    }

    NSMutableArray *names = [NSMutableArray array];
    for (NSURL *u in self.files) {
        [names addObject:u.lastPathComponent];
    }

    if (self.files.count > 1) {
        self.picker = [[UISegmentedControl alloc] initWithItems:names];
        self.picker.selectedSegmentIndex = 0;
        [self.picker addTarget:self action:@selector(showSelected) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView = self.picker;
    } else {
        self.title = names.firstObject ?: @"Log";
    }

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                           target:self
                                                                                           action:@selector(share:)];
    [self showSelected];
}

- (NSURL *)currentFile {
    NSInteger i = self.picker ? self.picker.selectedSegmentIndex : 0;
    if (i < 0 || i >= (NSInteger) self.files.count) {
        return nil;
    }
    return self.files[i];
}

- (void)showSelected {
    NSURL *u = [self currentFile];
    if (!u) {
        self.textView.text = @"Nessun log.";
        return;
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:u error:nil];
    unsigned long long size = [fh seekToEndOfFile];
    unsigned long long maxLen = 2 * 1024 * 1024;
    unsigned long long start = size > maxLen ? size - maxLen : 0;
    [fh seekToFileOffset:start];
    NSData *d = [fh readDataToEndOfFile];
    [fh closeFile];

    /* Se abbiamo tagliato l'inizio, salta i byte a metà di un carattere UTF-8. */
    if (start > 0) {
        const unsigned char *b = d.bytes;
        NSUInteger skip = 0;
        while (skip < d.length && skip < 4 && (b[skip] & 0xC0) == 0x80) {
            skip++;
        }
        d = [d subdataWithRange:NSMakeRange(skip, d.length - skip)];
    }

    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!s) {
        s = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    }
    if (start > 0) {
        s = [@"[… inizio del file omesso …]\n\n" stringByAppendingString:s ?: @""];
    }
    self.textView.text = s.length ? s : @"(file vuoto)";

    dispatch_async(dispatch_get_main_queue(), ^{
        NSRange end = NSMakeRange(self.textView.text.length, 0);
        [self.textView scrollRangeToVisible:end];
    });
}

- (void)share:(UIBarButtonItem *)sender {
    NSURL *u = [self currentFile];
    if (!u) {
        return;
    }
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[ u ] applicationActivities:nil];
    av.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:av animated:YES completion:nil];
}

@end

/* ======================================================================== */
/* Dettagli di un gioco                                                      */
/* ======================================================================== */

typedef NS_ENUM(NSInteger, RPGameSection) {
    RPSecPlay = 0,
    RPSecInfo,
    RPSecSaves,
    RPSecTools,
    RPSecDelete,
    RPSecCount,
};

@interface RPGameViewController : UITableViewController <UIDocumentPickerDelegate>
@property (nonatomic, strong) RPGame *game;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *infoRows;
@end

@implementation RPGameViewController

- (instancetype)initWithGame:(RPGame *)game {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _game = game;
        self.title = game.title;
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@[ @"Rilevato", [self.game versionDescription] ]];
    [rows addObject:@[ @"Python", self.game.pythonTag.length ? self.game.pythonTag : @"?" ]];
    [rows addObject:@[ @"Runtime", @"" ]];
    if (self.game.gameVersion.length) {
        [rows addObject:@[ @"Versione del gioco", self.game.gameVersion ]];
    }
    [rows addObject:@[ @"Dimensione", self.game.sizeBytes ? [RPStore formatBytes:self.game.sizeBytes] : @"?" ]];
    [rows addObject:@[ @"Cartella (app File)", [@"Games/" stringByAppendingString:self.game.folderName] ]];
    self.infoRows = rows;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return RPSecCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case RPSecPlay: return 1;
        case RPSecInfo: return (NSInteger) self.infoRows.count;
        case RPSecSaves: return 3;
        case RPSecTools: return 1;
        case RPSecDelete: return 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case RPSecInfo: return @"Motore";
        case RPSecSaves: return @"Salvataggi";
        case RPSecTools: return @"Diagnostica";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    RPGame *g = self.game;
    switch (section) {
        case RPSecPlay: {
            NSMutableString *s = [NSMutableString string];
            if (g.newerThanRuntime && g.runtime == g.detectedRuntime) {
                [s appendFormat:@"⚠️ Il gioco è stato creato con un Ren'Py più recente del runtime incluso (%@): potrebbe non partire o dare errori.\n\n", g.runtimeVersion];
            }
            [s appendString:@"Per tornare a questa schermata durante il gioco, chiudi l'app dal multitasking e riaprila."];
            return s;
        }
        case RPSecInfo: {
            NSMutableString *s = [NSMutableString stringWithString:g.evidence ?: @""];
            if (!g.confident) {
                [s appendString:@"\nSe il gioco non parte, prova l'altro runtime."];
            }
            return s;
        }
        case RPSecSaves:
            return @"Su Windows i salvataggi sono in %APPDATA%\\RenPy\\<nome del gioco> e nella cartella game\\saves del gioco; su Mac in ~/Library/RenPy. Puoi scegliere i file .save e \"persistent\", una cartella o uno zip. I file sostituiti vengono spostati in renplayer-backup.";
        case RPSecTools:
            return @"traceback.txt e log.txt sono scritti da Ren'Py; renplayer-log.txt contiene l'output di Python.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    RPGame *g = self.game;

    switch (indexPath.section) {
        case RPSecPlay:
            cell.textLabel.text = [NSString stringWithFormat:@"Gioca  (Ren'Py %@)", g.runtimeVersion];
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
            cell.imageView.image = [UIImage systemImageNamed:@"play.fill"];
            break;

        case RPSecInfo: {
            NSArray *row = self.infoRows[indexPath.row];
            cell.textLabel.text = row[0];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if ([row[0] isEqualToString:@"Runtime"]) {
                NSString *autoTitle = [NSString stringWithFormat:@"Auto (%ld)", (long) g.detectedRuntime];
                UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[ autoTitle, @"Ren'Py 7", @"Ren'Py 8" ]];
                seg.selectedSegmentIndex = g.runtimeOverride == 7 ? 1 : (g.runtimeOverride == 8 ? 2 : 0);
                [seg addTarget:self action:@selector(runtimeChanged:) forControlEvents:UIControlEventValueChanged];
                [seg sizeToFit];
                cell.accessoryView = seg;
            } else {
                cell.detailTextLabel.text = row[1];
                cell.detailTextLabel.numberOfLines = 2;
            }
            break;
        }

        case RPSecSaves:
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Salvataggi nel gioco";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long) [g saveFiles].count];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Importa salvataggi…";
                cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
                cell.textLabel.textColor = self.view.tintColor;
            } else {
                cell.textLabel.text = @"Esporta salvataggi…";
                cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
                cell.textLabel.textColor = self.view.tintColor;
            }
            break;

        case RPSecTools: {
            NSUInteger n = [g logFiles].count;
            cell.textLabel.text = @"Log ed errori";
            cell.detailTextLabel.text = n ? [NSString stringWithFormat:@"%lu file", (unsigned long) n] : @"nessuno";
            cell.accessoryType = n ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
            cell.imageView.image = [UIImage systemImageNamed:@"doc.text.magnifyingglass"];
            break;
        }

        case RPSecDelete:
            cell.textLabel.text = @"Elimina gioco";
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.imageView.image = [UIImage systemImageNamed:@"trash"];
            cell.imageView.tintColor = [UIColor systemRedColor];
            break;
    }

    return cell;
}

- (void)runtimeChanged:(UISegmentedControl *)seg {
    NSInteger idx = seg.selectedSegmentIndex;
    self.game.runtimeOverride = idx == 1 ? 7 : (idx == 2 ? 8 : 0);
    [self.game saveMetadata:nil];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:RPSecPlay] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

    switch (indexPath.section) {
        case RPSecPlay:
            [self play];
            break;

        case RPSecSaves:
            if (indexPath.row == 1) {
                [self pickSaves];
            } else if (indexPath.row == 2) {
                [self exportSaves:cell];
            }
            break;

        case RPSecTools: {
            NSArray *files = [self.game logFiles];
            if (files.count) {
                RPTextViewController *tv = [[RPTextViewController alloc] init];
                tv.files = files;
                [self.navigationController pushViewController:tv animated:YES];
            }
            break;
        }

        case RPSecDelete:
            [self confirmDelete:cell];
            break;
    }
}

- (void)play {
    RPGame *g = self.game;

    void (^go)(void) = ^{
        [RPLauncher shared].gameToLaunch = g;
    };

    if (g.newerThanRuntime && g.runtime == g.detectedRuntime) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Ren'Py più recente"
                                                                   message:[NSString stringWithFormat:@"Questo gioco usa %@, il runtime incluso è Ren'Py %@. Potrebbe non funzionare. Avviare comunque?", [g versionDescription], g.runtimeVersion]
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Avvia" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            go();
        }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    go();
}

- (void)pickSaves {
    NSArray *types = @[ UTTypeItem, UTTypeFolder ];
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    p.allowsMultipleSelection = YES;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    RPProgressViewController *pv = [[RPProgressViewController alloc] init];
    [pv loadViewIfNeeded];
    [self presentViewController:pv animated:YES completion:nil];
    pv.titleLabel.text = @"Importazione salvataggi";
    [pv setFraction:0.5 status:@"Copia dei file…"];
    pv.cancelButton.hidden = YES;

    [RPImporter importSaves:urls intoGame:self.game completion:^(NSUInteger count, NSString *backup, NSError *error) {
        [pv dismissViewControllerAnimated:YES completion:^{
            if (error) {
                RPAlert(self, @"Salvataggi non importati", error.localizedDescription);
            } else {
                NSMutableString *m = [NSMutableString stringWithFormat:@"Importati %lu file.", (unsigned long) count];
                if (backup) {
                    [m appendFormat:@"\n\nI file sostituiti sono stati spostati in %@.", backup];
                }
                [m appendString:@"\n\nRen'Py 8 potrebbe chiederti conferma la prima volta che carichi un salvataggio creato su un altro dispositivo."];
                RPAlert(self, @"Fatto", m);
            }
            [self.tableView reloadData];
        }];
    }];
}

- (void)exportSaves:(UITableViewCell *)cell {
    NSError *error = nil;
    NSURL *zip = [RPImporter exportSavesOfGame:self.game error:&error];
    if (!zip) {
        RPAlert(self, @"Esportazione", error.localizedDescription);
        return;
    }
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[ zip ] applicationActivities:nil];
    av.popoverPresentationController.sourceView = cell;
    av.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:av animated:YES completion:nil];
}

- (void)confirmDelete:(UITableViewCell *)cell {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Eliminare %@?", self.game.title]
                                                               message:@"Vengono cancellati il gioco e i suoi salvataggi. Se ti servono, esportali prima."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Elimina" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSError *e = nil;
        if (![RPStore deleteGame:self.game error:&e]) {
            RPAlert(self, @"Errore", e.localizedDescription);
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

/* ======================================================================== */
/* Aiuto                                                                     */
/* ======================================================================== */

static NSString *RPHelpText(void) {
    return [NSString stringWithFormat:
        @"RenPlayer avvia i giochi Ren'Py per PC/Mac/Linux su iPhone e iPad.\n\n"
        @"IMPORTARE UN GIOCO\n"
        @"1. Scarica lo zip della versione PC (o Mac/Linux) dal sito ufficiale del gioco.\n"
        @"2. Tocca + e scegli \"Importa gioco da zip…\". In alternativa, dall'app File tieni premuto lo zip › Condividi › RenPlayer.\n"
        @"3. RenPlayer copia solo la cartella game/ (le parti per Windows non servono) e capisce da solo quale versione di Ren'Py serve.\n\n"
        @"RUNTIME INCLUSI\n"
        @"• Ren'Py %s (Python 2) per i giochi Ren'Py 6 e 7\n"
        @"• Ren'Py %s (Python 3) per i giochi Ren'Py 8\n"
        @"Se il rilevamento sbaglia, puoi cambiare runtime nella scheda del gioco.\n\n"
        @"SALVATAGGI\n"
        @"Nella scheda del gioco puoi importare i salvataggi dal PC (file .save e persistent) ed esportarli in uno zip.\n\n"
        @"FILE\n"
        @"I giochi sono nell'app File › Sul mio iPhone › RenPlayer › Games. Puoi anche copiarci a mano la cartella di un gioco già estratto.\n\n"
        @"TORNARE ALLA LIBRERIA\n"
        @"Mentre un gioco è aperto, chiudi l'app dal multitasking e riaprila.\n\n"
        @"PROBLEMI\n"
        @"Se un gioco non parte, apri la sua scheda › Log ed errori: traceback.txt spiega quasi sempre il motivo.\n\n"
        @"LICENZE\n"
        @"RenPlayer include Ren'Py (licenza MIT) e librerie distribuite sotto GNU LGPL (tra cui SDL2 e FFmpeg) e altre licenze libere: www.renpy.org/doc/html/license.html",
        RP_RUNTIME7_VERSION, RP_RUNTIME8_VERSION];
}

/* ======================================================================== */
/* Libreria                                                                  */
/* ======================================================================== */

typedef NS_ENUM(NSInteger, RPPickMode) {
    RPPickZip,
    RPPickFolder,
};

@interface RPLibraryViewController : UITableViewController <UIDocumentPickerDelegate>
@property (nonatomic, copy) NSArray<RPGame *> *games;
@property (nonatomic) RPPickMode pickMode;
@property (nonatomic) BOOL importing;
@property (nonatomic) BOOL checkedCrash;
@end

@implementation RPLibraryViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"RenPlayer";
        _games = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                           target:self
                                                                                           action:@selector(addTapped:)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"questionmark.circle"]
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(helpTapped)];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.rowHeight = 64;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(processPending)
                                                 name:RPPendingURLsNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (!self.checkedCrash) {
        self.checkedCrash = YES;
        NSString *folder = [RPLauncher crashedGameFolder];
        if (folder) {
            RPGame *g = [RPStore loadGameInFolder:folder];
            if (g) {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Il gioco si è chiuso"
                                                                           message:[NSString stringWithFormat:@"L'ultima partita a %@ si è chiusa in modo inatteso. Vuoi vedere i log?", g.title]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleCancel handler:nil]];
                [a addAction:[UIAlertAction actionWithTitle:@"Mostra" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                    RPGameViewController *gv = [[RPGameViewController alloc] initWithGame:g];
                    [self.navigationController pushViewController:gv animated:NO];
                    NSArray *files = [g logFiles];
                    if (files.count) {
                        RPTextViewController *tv = [[RPTextViewController alloc] init];
                        tv.files = files;
                        [self.navigationController pushViewController:tv animated:YES];
                    }
                }]];
                [self presentViewController:a animated:YES completion:nil];
                return;
            }
        }
    }

    [self processPending];
}

- (void)reload {
    self.games = [RPStore loadGames];
    [self.tableView reloadData];
}

- (void)refresh {
    [self reload];
    [self.refreshControl endRefreshing];
}

- (void)helpTapped {
    RPTextViewController *tv = [[RPTextViewController alloc] init];
    tv.files = @[];
    tv.title = @"Guida";
    tv.staticText = RPHelpText();
    [self.navigationController pushViewController:tv animated:YES];
}

- (void)addTapped:(UIBarButtonItem *)sender {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil
                                                               message:@"Importa la versione PC/Mac/Linux del gioco."
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Importa gioco da zip…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self pick:RPPickZip];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Importa cartella già estratta…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self pick:RPPickFolder];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pick:(RPPickMode)mode {
    self.pickMode = mode;
    NSArray *types = mode == RPPickZip ? @[ UTTypeZIP ] : @[ UTTypeFolder ];
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    p.allowsMultipleSelection = NO;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) {
        return;
    }
    [[RPLauncher shared].pendingURLs addObject:@{
        @"url" : u,
        @"scoped" : @YES,
        @"delete" : @NO,
        @"folder" : @(self.pickMode == RPPickFolder),
    }];
    /* Aspetta che il selettore si chiuda prima di mostrare l'avanzamento. */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self processPending];
    });
}

- (void)processPending {
    /* La libreria può essere sotto altre schermate: presentiamo dal navigation controller. */
    UIViewController *host = self.navigationController ?: self;

    if (self.importing || host.presentedViewController) {
        return;
    }

    NSMutableArray *pending = [RPLauncher shared].pendingURLs;
    if (pending.count == 0) {
        return;
    }

    NSDictionary *item = pending.firstObject;
    [pending removeObjectAtIndex:0];

    NSURL *url = item[@"url"];
    BOOL scoped = [item[@"scoped"] boolValue];
    BOOL del = [item[@"delete"] boolValue];
    BOOL folder = [item[@"folder"] boolValue];

    self.importing = YES;

    RPProgressViewController *pv = [[RPProgressViewController alloc] init];
    [pv loadViewIfNeeded];
    [host presentViewController:pv animated:YES completion:nil];
    pv.titleLabel.text = [NSString stringWithFormat:@"Importazione di %@", url.lastPathComponent];

    RPProgressBlock progress = ^(double f, NSString *status) {
        [pv setFraction:f status:status];
    };

    RPImportCompletion done = ^(RPGame *game, NSError *error) {
        [pv dismissViewControllerAnimated:YES completion:^{
            self.importing = NO;
            [self reload];

            if (error) {
                RPAlert(host, @"Importazione non riuscita", error.localizedDescription);
            } else if (game) {
                NSString *msg = [NSString stringWithFormat:@"%@\nRuntime: Ren'Py %@\n\n%@", [game versionDescription], game.runtimeVersion, game.evidence];
                if (game.newerThanRuntime) {
                    msg = [msg stringByAppendingFormat:@"\n\n⚠️ Il gioco usa un Ren'Py più recente del runtime incluso: potrebbe non funzionare."];
                }
                UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ importato", game.title]
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"Chiudi" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
                    [self processPending];
                }]];
                [a addAction:[UIAlertAction actionWithTitle:@"Apri scheda" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                    RPGameViewController *gv = [[RPGameViewController alloc] initWithGame:game];
                    [self.navigationController pushViewController:gv animated:YES];
                }]];
                [host presentViewController:a animated:YES completion:nil];
                return;
            }

            [self processPending];
        }];
    };

    RPImportTask *task;
    if (folder) {
        task = [RPImporter importFolder:url securityScoped:scoped progress:progress completion:done];
    } else {
        task = [RPImporter importArchive:url securityScoped:scoped deleteWhenDone:del progress:progress completion:done];
    }

    __weak RPImportTask *weakTask = task;
    pv.onCancel = ^{
        weakTask.cancelled = YES;
    };
}

/* --- Tabella --------------------------------------------------------------- */

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger) self.games.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *space = [NSString stringWithFormat:@"Spazio libero: %@", [RPStore formatBytes:[RPStore availableBytes]]];
    if (self.games.count == 0) {
        return [NSString stringWithFormat:@"Nessun gioco. Tocca + per importare lo zip della versione PC di un gioco Ren'Py.\n\n%@", space];
    }
    return [NSString stringWithFormat:@"Scorri a sinistra per eliminare. I file sono nell'app File › RenPlayer › Games.\n%@", space];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"game"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"game"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    RPGame *g = self.games[indexPath.row];
    cell.textLabel.text = g.title;

    NSMutableArray *parts = [NSMutableArray arrayWithObject:[g versionDescription]];
    [parts addObject:[NSString stringWithFormat:@"runtime %ld", (long) g.runtime]];
    if (g.sizeBytes) {
        [parts addObject:[RPStore formatBytes:g.sizeBytes]];
    }
    if (g.newerThanRuntime) {
        [parts addObject:@"⚠️"];
    }
    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    UIImage *icon = [g icon];
    if (icon) {
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(44, 44)];
        cell.imageView.image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 44, 44) cornerRadius:9] addClip];
            [icon drawInRect:CGRectMake(0, 0, 44, 44)];
        }];
        cell.imageView.tintColor = nil;
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"gamecontroller.fill"];
        cell.imageView.tintColor = self.view.tintColor;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RPGameViewController *gv = [[RPGameViewController alloc] initWithGame:self.games[indexPath.row]];
    [self.navigationController pushViewController:gv animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    RPGame *g = self.games[indexPath.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:@"Elimina"
                                                                    handler:^(UIContextualAction *action, UIView *view, void (^completionHandler)(BOOL)) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Eliminare %@?", g.title]
                                                                   message:@"Vengono cancellati il gioco e i suoi salvataggi."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
            completionHandler(NO);
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Elimina" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            NSError *e = nil;
            BOOL ok = [RPStore deleteGame:g error:&e];
            completionHandler(ok);
            if (!ok) {
                RPAlert(self, @"Errore", e.localizedDescription);
            }
            [self reload];
        }]];
        [self presentViewController:a animated:YES completion:nil];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[ del ]];
}

@end

/* ======================================================================== */
/* Launcher                                                                  */
/* ======================================================================== */

@implementation RPLauncher {
    UIWindow *_window;
    NSMutableArray<NSDictionary *> *_pending;
}

+ (instancetype)shared {
    static RPLauncher *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[RPLauncher alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pending = [NSMutableArray array];
    }
    return self;
}

- (NSMutableArray<NSDictionary *> *)pendingURLs {
    return _pending;
}

- (BOOL)active {
    return _window != nil;
}

- (void)scanInbox {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[RPStore inboxURL]
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:nil];
    for (NSURL *u in items) {
        if ([u.pathExtension.lowercaseString isEqualToString:@"zip"]) {
            BOOL already = NO;
            for (NSDictionary *d in _pending) {
                if ([[d[@"url"] path] isEqualToString:u.path]) {
                    already = YES;
                }
            }
            if (!already) {
                [_pending addObject:@{ @"url" : u, @"scoped" : @NO, @"delete" : @YES, @"folder" : @NO }];
            }
        }
    }
}

- (void)present {
    [self scanInbox];

    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _window.backgroundColor = [UIColor systemBackgroundColor];
    _window.rootViewController = RPMakeRootViewController();
    [_window makeKeyAndVisible];
}

- (void)dismissWindow {
    UIViewController *root = _window.rootViewController;
    if (root.presentedViewController) {
        [root dismissViewControllerAnimated:NO completion:nil];
    }
    _window.hidden = YES;
    _window.rootViewController = nil;
    _window = nil;
}

- (void)handleOpenURL:(NSURL *)url openInPlace:(BOOL)inPlace {
    NSString *ext = url.pathExtension.lowercaseString;
    if (![ext isEqualToString:@"zip"]) {
        if (_window) {
            RPAlert(RPTopViewController(_window.rootViewController), @"File non supportato",
                    @"RenPlayer importa solo archivi .zip con la versione PC/Mac/Linux di un gioco Ren'Py.");
        }
        return;
    }

    BOOL inInbox = [url.URLByResolvingSymlinksInPath.path hasPrefix:[RPStore inboxURL].URLByResolvingSymlinksInPath.path];
    [_pending addObject:@{
        @"url" : url,
        @"scoped" : @(inPlace),
        @"delete" : @(inInbox),
        @"folder" : @NO,
    }];
    [[NSNotificationCenter defaultCenter] postNotificationName:RPPendingURLsNotification object:nil];
}

+ (NSURL *)launchMarker {
    return [[RPStore dataURL] URLByAppendingPathComponent:@"launching.json"];
}

+ (void)markLaunching:(RPGame *)game {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{ @"folder" : game.folderName } options:0 error:nil];
    [d writeToURL:[self launchMarker] atomically:YES];
}

+ (void)clearLaunching {
    [[NSFileManager defaultManager] removeItemAtURL:[self launchMarker] error:nil];
}

+ (nullable NSString *)crashedGameFolder {
    NSData *d = [NSData dataWithContentsOfURL:[self launchMarker]];
    [self clearLaunching];
    if (!d) {
        return nil;
    }
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    id f = [j isKindOfClass:[NSDictionary class]] ? j[@"folder"] : nil;
    return [f isKindOfClass:[NSString class]] ? f : nil;
}

@end

UIViewController *RPMakeRootViewController(void) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[RPLibraryViewController alloc] init]];
    nav.navigationBar.prefersLargeTitles = YES;
    return nav;
}
