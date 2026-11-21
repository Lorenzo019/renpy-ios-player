# RenPlayer

App per iPhone e iPad che avvia i giochi **Ren'Py** distribuiti per PC/Mac/Linux.
È un "player" come JoiPlay su Android: importi lo zip del gioco, l'app capisce quale
versione di Ren'Py serve e lo fa partire.

- **Rilevamento automatico** della versione di Ren'Py e di Python (Ren'Py 6/7 → Python 2, Ren'Py 8 → Python 3)
- **Due runtime in una sola app**: Ren'Py 7.8.7 e Ren'Py 8.3.7
- **Import diretto degli zip** (anche oltre 4 GB, Zip64), dall'app File, da iCloud o con "Condividi › RenPlayer"
- **Salvataggi**: importa i `.save` e `persistent` dal PC (file, cartella o zip) ed esportali in uno zip
- Log e `traceback.txt` consultabili dalla scheda del gioco

L'app **non contiene giochi**: usa le versioni PC che scarichi tu dai siti ufficiali.

---

## 1. Compilare l'app (senza Mac)

La compilazione avviene su GitHub Actions, su un Mac in cloud.

1. Metti questo progetto in un repository GitHub (meglio **pubblico**: i minuti macOS sono gratuiti).
2. Ogni push sul ramo `main` avvia il workflow **Build RenPlayer** (oppure: scheda *Actions* › *Build RenPlayer* › *Run workflow*).
3. A fine build (circa 10–15 minuti) apri l'esecuzione e scarica l'artifact **RenPlayer-ipa**:
   è uno zip che contiene `RenPlayer.ipa`.
4. Facoltativo: se crei un tag `v1.0`, l'IPA viene pubblicato anche nelle *Releases*.

Il workflow scarica da renpy.org l'SDK e il pacchetto iOS ("renios") di entrambe le versioni,
ne verifica i checksum e costruisce il progetto Xcode con `tools/assemble.py`.

## 2. Installare sull'iPhone con Sideloadly (Windows)

1. Installa **iTunes e iCloud dal sito Apple** (non dal Microsoft Store: con quelle versioni Sideloadly non funziona).
2. Installa [Sideloadly](https://sideloadly.io), collega l'iPhone con il cavo e autorizza il computer.
3. Trascina `RenPlayer.ipa` in Sideloadly, inserisci il tuo Apple ID e premi **Start**.
   Se l'Apple ID ha l'autenticazione a due fattori, Sideloadly chiede il codice.
4. Sull'iPhone:
   - *Impostazioni › Privacy e sicurezza › Modalità sviluppatore* → attiva (iOS 16 e successivi, richiede riavvio);
   - *Impostazioni › Generali › VPN e gestione dispositivi* → tocca il tuo Apple ID → *Autorizza*.

Con un Apple ID gratuito l'app **scade dopo 7 giorni**: rifai il sideload con lo stesso IPA e lo stesso
Apple ID (oppure attiva l'aggiornamento automatico di Sideloadly). **Non cancellare l'app** prima di
rifirmarla: perderesti giochi e salvataggi. Con l'account gratuito si possono avere al massimo 3 app
installate così.

## 3. Usare l'app

1. Scarica lo **zip della versione PC** del gioco (va bene anche Mac o Linux; gli APK Android no).
2. In RenPlayer tocca **+ › Importa gioco da zip…** e scegli il file. In alternativa, nell'app File tieni
   premuto lo zip › *Condividi* › *RenPlayer*.
3. RenPlayer copia solo ciò che serve (la cartella `game/`, senza i file per Windows/Linux),
   rileva la versione e mostra il runtime scelto.
4. Apri la scheda del gioco e tocca **Gioca**.

Per tornare alla libreria mentre un gioco è aperto: chiudi l'app dal multitasking e riaprila.

### Salvataggi dal PC

Su Windows i salvataggi di Ren'Py sono in `%APPDATA%\RenPy\<nome del gioco>` e spesso anche in
`game\saves` dentro la cartella del gioco (su Mac: `~/Library/RenPy/<nome del gioco>`).
Copia sull'iPhone i file `*.save` e `persistent` (anche zippati), poi nella scheda del gioco:
**Importa salvataggi…**. I file sostituiti vengono spostati in `renplayer-backup/`.
Ren'Py 8 chiede una conferma la prima volta che carichi un salvataggio creato su un altro dispositivo.

### Dove sono i file

App File › *Sul mio iPhone* › *RenPlayer* › `Games/<nome del gioco>`. Puoi anche copiare lì a mano
la cartella di un gioco già estratto: viene riconosciuta al successivo avvio.

### Se un gioco non parte

Scheda del gioco › **Log ed errori**: `traceback.txt` (scritto da Ren'Py) spiega quasi sempre il motivo,
`renplayer-log.txt` contiene l'output di Python. Se il rilevamento ha sbagliato, scegli a mano
*Ren'Py 7* o *Ren'Py 8* nella riga **Runtime**.

## Limiti noti

- I giochi creati con Ren'Py **più recente di 8.3.7** (8.4, 8.5…) vengono segnalati con ⚠️ e possono non funzionare.
- Giochi molto grandi possono richiedere più memoria di quella che iOS concede a un'app.
- I giochi che modificano il motore (cartella `renpy/` personalizzata) usano comunque il motore incluso.
- Gli zip cifrati o compressi con metodi diversi da Deflate (es. Deflate64 di Windows per file > 2 GB) non sono supportati: ricomprimi con 7-Zip in formato zip standard.

## Come funziona

- `app/core/` — C puro: lettore zip in streaming (Zip64, CRC), scrittore zip per i salvataggi,
  analisi della distribuzione (radice del gioco, versione di Ren'Py da `renpy/vc_version.*`,
  versione di Python da `lib/`, `__pycache__`, `.pyo`).
- `app/src/` — interfaccia UIKit (libreria, scheda del gioco, importazione, salvataggi) e `main.m`.
- `tools/assemble.py` — parte dal progetto Xcode ufficiale di Ren'Py 8 (renios) e:
  - prepara `runtimes/rt7/base` e `runtimes/rt8/base` (main.py, `renpy/` compilato, libreria standard);
  - collega Ren'Py 8 normalmente e **prelinka Ren'Py 7** in un unico oggetto (`rt7/rp7.o`) con tutti i
    simboli nascosti tranne il punto di ingresso, così Python 2 e Python 3 convivono nello stesso eseguibile;
  - le librerie C (SDL2, FFmpeg, …) sono le stesse per i due runtime (stessa build di renpy-build).
- All'avvio SDL esegue `player_main`: mostra la libreria in un run loop annidato, poi chiude la finestra e
  chiama il runtime giusto con `basedir` = cartella del gioco e `--savedir` = `game/saves` del gioco.

## Sviluppo

```bash
python3 tests/test_core.py          # test del codice C (zip, Zip64, rilevamento)
python3 tests/test_core.py --big    # include zip da oltre 4 GB
bash tests/objc_syntax_check.sh     # controllo di sintassi Objective-C su Linux (clang + GNUstep + stub)
```

Le versioni dei runtime si cambiano in `.github/workflows/build.yml` (`RENPY7`, `RENPY8`).
Devono provenire dalla stessa build di renpy-build (es. 7.8.7 e 8.3.7), perché condividono le librerie C.

## Licenze

RenPlayer include Ren'Py (licenza MIT) e librerie distribuite sotto licenza GNU LGPL
(tra cui SDL2 e FFmpeg) e altre licenze libere; vedi <https://www.renpy.org/doc/html/license.html>.
I giochi appartengono ai rispettivi autori.
