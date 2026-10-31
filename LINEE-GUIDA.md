# Studio 54 – Linee guida: versioni, gestionale e architettura

Aggiornato al 29 ottobre 2026. È una guida: niente di quanto descritto qui è ancora stato modificato nel codice.

**In breve.**
- Il dominio porta i visitatori al sito su Hostinger.
- Dati, foto, video e accessi stanno su Cloudflare: sito, gestionale e app li leggono dalla stessa API.
- Il gestionale si apre solo scrivendo `tuodominio.it/admin`, con le credenziali che sceglierai tu.
- Ogni nuova versione dell'app ha un numero di build più alto della precedente: è così che Play Store e App Store riconoscono l'aggiornamento.

---

## 1. Come si collegano i pezzi

```
                         ┌──────────────────────────────┐
  visitatore ──────────► │  DOMINIO  (es. studio54.it)  │  comprato presso un sito di domini
                         └──────────────┬───────────────┘
                                        │ i "nameserver" del dominio puntano a Cloudflare (DNS)
                ┌───────────────────────┼─────────────────────────────┐
                ▼                       ▼                             ▼
   studio54.it / www           api.studio54.it               media.studio54.it
 ┌─────────────────────┐   ┌─────────────────────────┐   ┌─────────────────────────┐
 │ HOSTINGER           │   │ CLOUDFLARE WORKER (API) │   │ CLOUDFLARE R2           │
 │ sito + gestionale   │──►│ controlla gli accessi,  │──►│ foto, video, PDF        │
 │ HTML CSS JS PHP     │   │ legge e scrive i dati   │   └─────────────────────────┘
 │ /admin = gestionale │   │                         │   ┌─────────────────────────┐
 └─────────────────────┘   │                         │──►│ CLOUDFLARE D1           │
            ▲              └─────────────────────────┘   │ database: testi, lavori,│
            │                         ▲                  │ richieste, clienti ...  │
            │                         │                  └─────────────────────────┘
   browser (PC, telefono)     APP FLUTTER (Android e iPhone)
```

| Pezzo | Dove sta | Cosa fa | Chi lo modifica |
|---|---|---|---|
| Dominio | Sito di domini (Aruba, Register.it, OVH…) | Il nome `studio54.it`; rinnovo annuale | Tu, una volta l'anno |
| DNS | Cloudflare (gratis) | Dice dove va ogni indirizzo: sito → Hostinger, api → Worker, media → R2 | Una volta, all'inizio |
| Sito e gestionale | Hostinger | Le pagine (PHP, HTML, CSS, JavaScript) | Noi, quando cambia la grafica o le funzioni |
| Database | Cloudflare D1 | Testi, lavori, modulo preventivo, richieste, appuntamenti, clienti, accessi | Tu, dal gestionale (sito o app) |
| Foto, video, PDF | Cloudflare R2 | I file caricati dal gestionale | Tu, dal gestionale |
| API | Cloudflare Worker | L'unica porta verso dati e file: controlla chi può leggere e scrivere | Noi |
| App | Play Store e App Store | Le stesse pagine del sito, l'area clienti e il gestionale | Noi (nuove versioni); i contenuti li cambi tu |

**Regola d'oro:** i contenuti (testi, lavori, foto, clienti) si cambiano dal gestionale e arrivano subito a sito e app, senza pubblicare niente. Si pubblica una nuova versione del sito o dell'app solo quando cambiano grafica o funzioni.

---

## 2. Il dominio

1. Si compra il dominio su un sito di domini (es. `studio54.it`). Lì si paga solo il rinnovo annuale.
2. Nel pannello del sito di domini si cambiano i **nameserver** con i due che dà Cloudflare. Da quel momento il DNS si gestisce da Cloudflare: è gratis, più veloce e serve per collegare API e foto allo stesso dominio.
3. In Cloudflare si creano questi record:

| Indirizzo | Tipo | Punta a | Serve per |
|---|---|---|---|
| `studio54.it` | A | IP del piano Hostinger | Il sito |
| `www.studio54.it` | CNAME | `studio54.it` | Il sito con "www" |
| `api.studio54.it` | Dominio personalizzato del Worker | Worker Cloudflare | API per sito, gestionale e app |
| `media.studio54.it` | Dominio personalizzato di R2 | Bucket delle foto pubbliche | Foto e video del sito e dell'app |
| Posta (MX, SPF, DKIM) | MX / TXT | Il servizio email scelto (es. email di Hostinger) | `info@studio54.it` |

Il certificato HTTPS lo fanno Cloudflare e Hostinger in automatico. In Cloudflare va impostato su "Full (strict)".

---

## 3. Hostinger: sito e gestionale

- Su Hostinger va la cartella `sito/` così com'è: pagine PHP, `assets/` (CSS, JavaScript, immagini), `inc/`.
- Le pagine PHP chiedono i contenuti all'API **dal server**, prima di mandare la pagina. Così Google legge testi e lavori, e la pagina si apre già completa. Una piccola cache (es. 5 minuti) evita di chiedere sempre gli stessi dati.
- Il gestionale (oggi `riservata.php`) è una pagina che, una volta entrati, parla direttamente con l'API.
- Un file `.htaccess` sistema gli indirizzi:
  - `studio54.it/admin` apre il gestionale (vedi sezione 6);
  - `studio54.it/lavori` invece di `lavori.php`;
  - un indirizzo inesistente mostra la pagina 404.
- L'anteprima su GitHub Pages resta come area di prova: lì le pagine sono convertite in HTML statico, con i dati d'esempio.

**Pubblicare il sito:** da GitHub una procedura automatica copia i file su Hostinger (via FTP o SSH) a ogni modifica approvata. In alternativa si caricano a mano dal File Manager di Hostinger.

---

## 4. Cloudflare: database, file e API

**D1, il database.** Una tabella per ogni tipo di dato:

| Tabella | Contiene |
|---|---|
| `contenuti` | Nome dello studio, biografia, metodo, contatti, colore |
| `lavori`, `foto_lavori` | Lavori, foto, ordine, in evidenza, Sito/App, pubblicato |
| `caroselli` | Foto del carosello orizzontale e verticale: sito e app usano quello che corrisponde al verso dello schermo |
| `modulo_preventivo` | Tipi di evento, richieste, parti accese |
| `richieste` | Le richieste arrivate da sito e app, con lo stato |
| `appuntamenti` | Calendario |
| `clienti`, `cartelle`, `media_clienti`, `documenti` | Area clienti |
| `titolare`, `sessioni` | Accesso al gestionale (password solo cifrata) e accessi aperti |
| `impostazioni` | Es. la versione minima dell'app (sezione 7) |

**R2, i file.** Due contenitori:
- **pubblico**: foto dei lavori e dei caroselli, servite da `media.studio54.it`;
- **privato**: foto, video e PDF dei clienti. Si aprono solo con un link a tempo, generato dall'API per il cliente che ha fatto l'accesso.

I file non passano più dentro il database come oggi (le foto "incorporate"): il gestionale li carica direttamente su R2. Così non c'è il limite di qualche MB.

**Worker, l'API.** È l'unica porta d'accesso:

| Chi | Cosa può fare |
|---|---|
| Chiunque | Leggere i contenuti pubblici; inviare un preventivo (con un controllo anti-spam, Cloudflare Turnstile) |
| Cliente con accesso | Vedere e scaricare solo i propri file |
| Titolare con accesso | Leggere e modificare tutto |

All'arrivo di una richiesta di preventivo può partire un'email di avviso al titolare.

**Costi indicativi:** il piano gratuito di Cloudflare basta per database e API di uno studio. R2 ha 10 GB gratis, poi un costo di circa 1–2 euro al mese ogni 100 GB, senza costi per i download. I video dei matrimoni sono la voce che pesa di più. I prezzi vanno verificati al momento dell'attivazione.

---

## 5. L'app Flutter

- L'app è già divisa in due: la grafica e lo "scaffale" dei dati (`Repository`). Oggi lo scaffale è il telefono. Con il database si scrive una versione dello scaffale che parla con `api.studio54.it`, e il resto dell'app non cambia.
- L'app si usa online. Senza internet, all'apertura (o tornando nell'app) compare l'avviso "Siete offline"; appena la connessione torna si chiude da solo e le foto si ricaricano. I caratteri stanno dentro l'app.
- Area clienti e gestionale funzionano solo online, con l'accesso.
- Le foto si scaricano da `media.studio54.it` (pubbliche) o con il link a tempo (clienti).

---

## 6. Accesso al gestionale

**Come si entra:**
- **Sito:** non c'è più nessun tasto "Area riservata" nel footer né altrove. Si entra solo scrivendo nella barra degli indirizzi `studio54.it/admin`.
- **App:** dall'Area clienti, con le credenziali del titolare, come oggi.
- **Credenziali:** un nome utente e una password che sceglierai tu. Valgono sia sul sito sia nell'app.

**Come è protetto** (l'indirizzo nascosto da solo non basta: la vera protezione è l'accesso):

| Protezione | Come funziona |
|---|---|
| Password mai in chiaro | Nel database c'è solo una versione cifrata; nessuno, nemmeno noi, può leggerla |
| Niente dati nella pagina | La pagina `/admin` non contiene dati: arrivano dall'API solo dopo l'accesso. Oggi, nell'anteprima, i dati d'esempio sono dentro la pagina: con il database questo sparisce |
| Sessione sicura | Dopo l'accesso il browser riceve un "biglietto" protetto (cookie HttpOnly e Secure), valido 30 giorni con "Ricordami", altrimenti fino alla chiusura del browser |
| Tentativi limitati | Dopo 5 password sbagliate si aspetta 15 minuti |
| Pagina invisibile ai motori di ricerca | `/admin` non compare su Google (noindex) e non è citata da nessuna parte del sito |
| Cambio password | Da Impostazioni; se la dimentichi, la si reimposta dal pannello Cloudflare (in futuro anche via email) |
| In più, facoltativo | Codice di verifica via app (2FA) e avviso email a ogni nuovo accesso |

Le credenziali di prova attuali (`titolare` / `studio54`) spariranno con il database.

---

## 7. Versioni dell'app: nome e numero

**Il formato.** Ogni versione ha due parti, scritte in un solo punto: il file `app/pubspec.yaml`.

```
version: 1.0.0+1
         │ │ │ └── numero di build: intero, sale di 1 a OGNI file caricato sugli store
         │ │ └──── correzione  (1.0.0 → 1.0.1): solo errori sistemati
         │ └────── novità      (1.0.1 → 1.1.0): funzioni o pagine nuove
         └──────── grande cambio (1.4.2 → 2.0.0): app rifatta o cambiamenti importanti
```

| Dove si vede | Nome della versione | Numero di build |
|---|---|---|
| Android (Play Store) | `versionName` = 1.0.0 | `versionCode` = 1 |
| iPhone (App Store) | `CFBundleShortVersionString` = 1.0.0 | `CFBundleVersion` = 1 |
| Chi lo vede | Gli utenti, nella pagina dello store | Solo gli store: decide qual è l'aggiornamento |

**Le regole:**
1. Il numero di build **sale sempre**, anche di 1 solo, a ogni file caricato. Non si riusa mai, nemmeno per una versione scartata o rifiutata.
2. Lo stesso numero di build vale per Android e iPhone nella stessa uscita: `1.2.0+7` su entrambi gli store.
3. Quando sale la parte centrale, l'ultima riparte da 0 (`1.2.3` → `1.3.0`); quando sale la prima, ripartono le altre (`1.9.2` → `2.0.0`). Il numero di build invece non riparte mai.
4. Una correzione urgente subito dopo un'uscita: `1.3.0+12` → `1.3.1+13`.

**Esempio di storia:**

| Data | Versione | Cosa cambia |
|---|---|---|
| Prima uscita | 1.0.0+1 | Pubblicazione sugli store |
| Rifiutata da Apple, corretta | 1.0.0+2 | Stesso nome, build nuova |
| Errore nel download dei video | 1.0.1+3 | Correzione |
| Nuova sezione nell'area clienti | 1.1.0+4 | Novità |
| App collegata a un nuovo database | 2.0.0+5 | Grande cambio |

**Nomi dei file**, uguali per ogni uscita:

| File | Nome | A cosa serve |
|---|---|---|
| Android per il Play Store | `Studio54-1.1.0-4.aab` | Si carica sul Play Store (formato obbligatorio) |
| Android da installare a mano | `Studio54-1.1.0-4.apk` | Prove sui telefoni, cartella `apk/` |
| iPhone per l'App Store | `Studio54-1.1.0-4.ipa` | Si carica su App Store Connect |
| Segnalibro nel codice | `app-v1.1.0-4` | Etichetta su GitHub: si ritrova il codice esatto di ogni versione |

Ogni uscita ha anche due o tre righe di "Novità", in italiano, da scrivere negli store e in un file `app/NOVITA.md`.

**Aggiornamento obbligatorio (consigliato).** Nella tabella `impostazioni` del database si tiene la "versione minima". All'apertura, se l'app è più vecchia, mostra "È disponibile una nuova versione" con il tasto per lo store. Serve quando l'API cambia e le versioni vecchie smetterebbero di funzionare.

**Da sapere:**
- La versione si mostrerà in fondo alle Impostazioni del gestionale (es. "Versione 1.1.0 (4)"), così si capisce subito quale versione ha un telefono.
- L'**ID dell'app** non si potrà mai più cambiare dopo la prima pubblicazione. Oggi è `it.studio54.studio_fotografico`: va deciso quello definitivo prima, di solito il dominio al contrario (es. `it.studio54.app`).
- Il **nome mostrato** sotto l'icona resta "Studio 54".

---

## 8. Pubblicare su Play Store e App Store

| | Google Play Store | Apple App Store |
|---|---|---|
| Account | Google Play Console, 25 dollari una volta sola | Apple Developer Program, 99 dollari l'anno |
| Intestato a | Il titolare dello studio (personale o "organizzazione": per l'organizzazione serve il numero D-U-N-S, gratuito) | Il titolare dello studio (personale o organizzazione, con D-U-N-S) |
| Cosa serve per compilare | Il PC Windows di oggi va bene | Un Mac con Xcode, oppure un servizio di compilazione nel cloud (es. Codemagic) |
| Firma del file | Una "chiave di caricamento" da creare una volta e conservare con due copie di sicurezza: senza, non si possono più pubblicare aggiornamenti | Certificati Apple, gestiti da Xcode o dal servizio cloud |
| Prove prima dell'uscita | Test interno; con un account **personale** nuovo Google chiede un test chiuso con almeno 12 persone per 14 giorni prima della pubblicazione | TestFlight |
| Revisione | Da poche ore a qualche giorno | Di solito 1–3 giorni |
| Materiale | Icona 512×512, immagine 1024×500, almeno 2 schermate del telefono, descrizione | Icona 1024×1024, schermate per iPhone (e iPad, se supportato), descrizione |

**Valgono per entrambi:**
- **Privacy:** una pagina "Privacy" sul sito (es. `studio54.it/privacy`) e il modulo sui dati raccolti (nome, email, telefono del preventivo; foto dei clienti).
- **Account di prova per i revisori:** un cliente d'esempio con qualche foto, perché Apple e Google vogliono provare l'area clienti.
- **Account dei clienti:** li crea lo studio, non il cliente. Nelle note per la revisione va scritto, e va indicato come chiedere la cancellazione dei propri dati (es. un'email allo studio).
- **Parte iPhone:** la cartella `app/ios/` c'è già, con icone, schermata d'avvio e permessi. Va compilata su un Mac o con un servizio cloud, e lì va provata la prima volta.
- **Firma Android:** l'app è pronta a usare la chiave. Basta creare `app/android/key.properties` copiando `key.properties.example`: né quel file né la chiave vanno su GitHub.

---

## 9. Come si fa un aggiornamento

**Contenuti** (testi, lavori, foto, clienti): dal gestionale, sito o app. Arrivano subito ovunque, senza pubblicare niente.

**Sito o gestionale** (grafica o funzioni):
1. Si modifica il codice e si prova sull'anteprima GitHub.
2. Si pubblica: la procedura copia i file su Hostinger.
3. Si controlla il sito vero dal telefono e dal PC.

**Database** (una tabella nuova o un campo in più):
1. Si scrive la modifica come "migrazione", un file numerato, e la si applica su Cloudflare **prima** di pubblicare sito e app che la usano.
2. Si aggiunge senza togliere: le versioni dell'app già installate devono continuare a funzionare. Un campo vecchio si toglie solo quando nessuno usa più le versioni che lo leggono (sezione 7, versione minima).

**App:**
1. Si alza la versione in `pubspec.yaml` (es. `1.1.0+4` → `1.2.0+5`) e si scrivono le Novità.
2. Si fanno i test automatici e si prova l'APK su un telefono.
3. Si creano i file `Studio54-1.2.0-5.aab` e `Studio54-1.2.0-5.ipa`.
4. Si caricano: prima nel test interno o su TestFlight, poi in produzione. Sul Play Store si può uscire per gradi (es. 20% dei telefoni, poi 100%).
5. Si mette l'etichetta `app-v1.2.0-5` su GitHub e si copia l'APK in `apk/`.
6. I telefoni si aggiornano da soli dallo store. Se serve, si alza la versione minima nel database.

---

## 10. Chi fa cosa

| Attività | Chi |
|---|---|
| Pubblicare sito e gestionale su Hostinger, impostare DNS, database, foto e API su Cloudflare | Claude |
| Ogni modifica a sito, gestionale, database e app (codice) | Claude |
| Prima di ogni uscita dell'app: alzare la versione, test, Novità, etichetta su GitHub | Claude |
| Creare i file dell'app per gli store (`.aab`, `.ipa`) con il nome corretto e caricarli su Play Store e App Store | Il titolare |
| Account (dominio, Hostinger, Cloudflare, store) e pagamenti | Il titolare, che poi dà accesso a Claude dove serve |

---

## 11. Cosa manca prima di pubblicare sugli store

Il codice dell'app è adatto a Android, iPhone e tablet, ma **questi punti bloccano una pubblicazione vera**:

| Punto | Perché blocca | Cosa serve |
|---|---|---|
| **Database collegato** | Oggi ogni telefono ha i suoi dati: le richieste di preventivo restano sul telefono del visitatore e non arrivano allo studio. Clienti, foto e modifiche del gestionale non passano da un telefono all'altro | Cloudflare collegato all'app (sezioni 4 e 5) |
| **Credenziali di prova** | `titolare` / `studio54` e i clienti d'esempio sono dentro l'app: chiunque potrebbe entrare | Vanno tolti con il database, usando le credenziali vere |
| **Contenuti d'esempio** | Foto, lavori e testi sono di prova, e i contatti in parte inventati | Quelli veri, dal gestionale |
| **Pagina Privacy** | Entrambi gli store la chiedono, e il consenso del preventivo deve poterla aprire | Il testo della privacy, poi il link nell'app e sul sito |
| **Dominio** | `Vedi il sito` apre ancora l'anteprima su GitHub | Dominio definitivo |
| **ID dell'app** | Oggi Android `it.studio54.studio_fotografico` e iPhone `it.studio54.studioFotografico`; dopo la prima pubblicazione non si cambiano | Sceglierne uno solo (es. `it.studio54.app`) |

---

## 12. Decisioni da prendere prima di partire

- [ ] **Dominio** definitivo (es. `studio54.it`) e su quale sito di domini comprarlo.
- [ ] **ID definitivo dell'app** (es. `it.studio54.app`): dopo la prima pubblicazione non si cambia più.
- [ ] **Credenziali del titolare** per `/admin` e per l'app: me le dirai tu.
- [ ] **Account degli store**: personale o organizzazione (D-U-N-S), e a nome di chi.
- [ ] **iPhone**: un Mac a disposizione, oppure un servizio di compilazione nel cloud.
- [ ] **Email** a cui mandare l'avviso delle nuove richieste di preventivo, e casella `info@` del dominio.
- [ ] **Testo della pagina Privacy** (dati del preventivo e dell'area clienti).
- [ ] **Dove conservare la chiave di firma Android** (due copie, fuori dal PC).
