/*
 * RenPlayer - punto di ingresso.
 *
 * SDL possiede il ciclo dell'applicazione (SDL_UIKitRunApp). Dentro la sua
 * "main" mostriamo prima la libreria nativa in un run loop annidato; quando
 * l'utente sceglie un gioco chiudiamo la finestra e avviamo il runtime giusto:
 *
 *   launcher_main   -> Ren'Py 8 (Python 3), linkato normalmente
 *   rp7_lnch_main   -> Ren'Py 7 (Python 2), prelinkato con i simboli nascosti
 *
 * argv[0] finto (runtimes/rtN/renplayer) fa sì che il runtime trovi la sua
 * cartella "base" (main.py, renpy/, lib/pythonX.Y) dentro il bundle.
 */

#import "RPCommon.h"

#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int launcher_main(int argc, char **argv);
int rp7_lnch_main(int argc, char **argv);
int SDL_UIKitRunApp(int argc, char **argv, int (*mainFunction)(int, char **));

static IMP gOrigOpenURL = NULL;

/* "Apri con" / condivisione verso RenPlayer mentre è aperta la libreria. */
static BOOL rp_open_url(id self, SEL _cmd, UIApplication *app, NSURL *url, NSDictionary *options) {
    RPLauncher *l = [RPLauncher shared];
    if (l.active) {
        BOOL inPlace = [options[UIApplicationOpenURLOptionsOpenInPlaceKey] boolValue];
        [l handleOpenURL:url openInPlace:inPlace];
        return YES;
    }
    if (gOrigOpenURL) {
        return ((BOOL (*)(id, SEL, UIApplication *, NSURL *, NSDictionary *)) gOrigOpenURL)(self, _cmd, app, url, options);
    }
    return NO;
}

static void install_hooks(void) {
    Class cls = NSClassFromString(@"SDLUIKitDelegate");
    if (!cls) {
        NSLog(@"RenPlayer: SDLUIKitDelegate non trovato, 'Apri con' disattivato.");
        return;
    }
    SEL sel = @selector(application:openURL:options:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        gOrigOpenURL = method_setImplementation(m, (IMP) rp_open_url);
    } else {
        class_addMethod(cls, sel, (IMP) rp_open_url, "B@:@@@");
    }
}

static void run_launcher_until_choice(void) {
    RPLauncher *l = [RPLauncher shared];
    [l present];

    /* Run loop annidato, come fa SDL per i suoi message box. */
    while (l.gameToLaunch == nil) {
        @autoreleasepool {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
            CFRunLoopRunInMode((__bridge CFStringRef) UITrackingRunLoopMode, 0, true);
        }
    }
}

static int player_main(int argc, char **argv) {
    RPGame *game = nil;
    char *args[5];
    int runtime = 8;

    @autoreleasepool {
        run_launcher_until_choice();

        RPLauncher *l = [RPLauncher shared];
        game = l.gameToLaunch;
        [l dismissWindow];

        NSFileManager *fm = [NSFileManager defaultManager];

        game.lastPlayed = [NSDate date];
        [game saveMetadata:nil];

        runtime = (int) game.runtime;

        NSString *bundle = [NSBundle mainBundle].bundlePath;
        NSString *exe = [bundle stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"runtimes/rt%d/renplayer", runtime]];
        NSString *base = game.baseDirectory.path;
        NSString *saves = game.saveDirectory.path;
        NSString *data = [RPStore dataURL].path;

        [fm createDirectoryAtPath:saves withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:data withIntermediateDirectories:YES attributes:nil error:nil];

        /* Log: renplayer-log.txt (output di Python, vedi Log.m) e stderr. */
        NSString *log = game.logFile.path;
        [[NSData data] writeToFile:log atomically:NO];

        setenv("RENPLAYER_SAVEDIR", saves.fileSystemRepresentation, 1);
        setenv("RENPLAYER_DATADIR", data.fileSystemRepresentation, 1);
        setenv("RENPLAYER_LOGFILE", log.fileSystemRepresentation, 1);
        setenv("RENPLAYER_GAME", game.title.UTF8String, 1);

        if (!freopen(game.stderrFile.fileSystemRepresentation, "w", stderr)) {
            NSLog(@"RenPlayer: impossibile redirigere stderr.");
        }
        fprintf(stderr, "RenPlayer: avvio di %s con Ren'Py %s\nbasedir: %s\nsavedir: %s\n",
                game.title.UTF8String, game.runtimeVersion.UTF8String,
                base.fileSystemRepresentation, saves.fileSystemRepresentation);

        /* Se il gioco si chiude entro 30 secondi lo consideriamo un crash di avvio. */
        [RPLauncher markLaunching:game];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [RPLauncher clearLaunching];
        });

        args[0] = strdup(exe.fileSystemRepresentation);
        args[1] = strdup(base.fileSystemRepresentation);
        args[2] = strdup("--savedir");
        args[3] = strdup(saves.fileSystemRepresentation);
        args[4] = NULL;
    }

    int rv;
    if (runtime == 7) {
        rv = rp7_lnch_main(4, args);
    } else {
        rv = launcher_main(4, args);
    }

    fprintf(stderr, "RenPlayer: il runtime è terminato con codice %d\n", rv);
    fflush(stderr);

    @autoreleasepool {
        if (rv == 0) {
            [RPLauncher clearLaunching];
        } else {
            [RPLauncher markLaunching:game];
        }
    }

    exit(rv);
    return rv;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        install_hooks();
    }
    return SDL_UIKitRunApp(argc, argv, player_main);
}
