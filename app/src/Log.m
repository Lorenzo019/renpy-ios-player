/*
 * Sostituisce il Log.m del prototipo di Ren'Py: oltre a NSLog scrive anche
 * nel file indicato da RENPLAYER_LOGFILE, così l'output di Python (print,
 * traceback) si può leggere dalla scheda del gioco.
 *
 * Ren'Py lo usa tramite pyobjus: Log.log_(riga).
 */

@import Foundation;

#include <stdio.h>
#include <stdlib.h>

@interface Log : NSObject
+ (void)log:(char *)s;
@end

@implementation Log

+ (void)log:(char *)s {
    static FILE *f = NULL;
    static BOOL tried = NO;

    if (!s) {
        return;
    }

    NSLog(@"%s", s);

    @synchronized(self) {
        if (!tried) {
            tried = YES;
            const char *path = getenv("RENPLAYER_LOGFILE");
            if (path) {
                f = fopen(path, "a");
            }
        }
        if (f) {
            fputs(s, f);
            fputc('\n', f);
            fflush(f);
        }
    }
}

@end
