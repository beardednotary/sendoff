# App Store listing

What the App Store product page says, kept here so it stays in step with the website
(web/app/src/site/content.ts) and docs/PRODUCT.md. App Store Connect is where it is published;
change both together.

## App information

| Field | Value |
|---|---|
| Name (30) | Sendoff - Group Memory Book |
| Subtitle (30) | Farewell & retirement cards |
| Categories | Lifestyle, Social Networking |
| Privacy policy | https://sendoffapp.com/privacy |

## Version 1.0

**Keywords (100).** Comma-separated, no spaces. Words already in the name or subtitle are left out,
because search combines the fields.

```
graduation,goodbye,leaving,coworker,colleague,teacher,coach,military,keepsake,ecard,gift,boss,thank
```

**Promotional text (170).** Not searched; can change at any time without review.

> Everyone adds a note, photos, a voice note or a video, privately. It stays sealed until the day, then opens one entry at a time.

**Support URL:** https://sendoffapp.com/support
**Marketing URL:** https://sendoffapp.com
**Copyright:** 2026 Dahvio Studios

**Description (4000).** No prices: they differ by country, and the App Store shows the real ones.

```
Sendoff is a group card and memory book for someone's big day. Everyone adds a note, photos, a voice note or a video, privately. It stays sealed until the day, and then the person it's for opens it, one entry at a time.

How it works
1. Start one in the app: who it's for, a photo if you like, and when it opens, on a date or when you say.
2. Share one link or QR code wherever your group talks. Nobody needs the app or an account to add to it.
3. Everyone adds privately: a note, up to six photos, a voice note or a minute of video, from any phone or computer.
4. They open it on the day. They press and hold the seal, and the entries open one at a time.

Why groups choose Sendoff
- Private by design: only the person it's for and the organizer read the entries, so people write what they mean, not what reads well to the room.
- Sealed until the day: it's an envelope, not a board everyone scrolls.
- Voices, not just signatures: a voice note or a minute of video carries what a signature can't.
- Nothing to install: everyone adds from one link or a QR code, in any browser.
- Opened like a letter: one entry at a time, with music.
- You stay in charge: see entries as they arrive, approve them first if you like, hide anything that doesn't belong, and choose the order they open in.
- Theirs to keep: they can come back to it, and save it as a PDF, on every plan.

Perfect for
- Retirements
- A coworker leaving or starting a new job
- Graduations
- Teacher appreciation and the last day of school
- Military farewells, PCS moves and changes of command
- The end of a season, for a coach
- Any goodbye worth doing properly

Free to start
Starting one and collecting up to 10 entries is free. When more people want in, the organizer pays once for that Sendoff, in the app. Sendoff Plus has no entry limit, every Plus look, and a song from Apple Music, which plays in full for Apple Music subscribers and as a 30-second preview for everyone else. Nobody who adds to it or opens it pays.

Private by default
Only the person it's for and the organizer can read what people write. No advertising, no tracking, no selling your data. Privacy policy: sendoffapp.com/privacy

Support
Questions or feedback? Write to support@sendoffapp.com.
```

## Screenshots

Made by `ios/SendoffTests/StoreScreens.swift` from the app's own screens and demo data (photos
from Unsplash): one line of serif over the real screen, on Evening black, after Once's listing.
Two sets go up, each into its own folder: 6.3" (1206 x 2622) for "iPhone with Dynamic Island
(medium display)", which the version page requires, and 6.9" (1320 x 2868) for the optional
"(large display)" slot in the Media Manager. Apple scales them for the other iPhones. To make them
again, on an iPhone Pro Max simulator:

```
cd ios && TEST_RUNNER_STORE_SCREENS_DIR="$PWD/build/store-screens" xcodebuild test -project Sendoff.xcodeproj \
  -scheme Sendoff -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:SendoffTests/StoreScreens
```

| # | Eyebrow | Headline | Screen |
|---|---|---|---|
| 1 | Sendoff | Everyone's words, sealed until the day. | The sealed reveal |
| 2 | On the day | Their photo, their name, then everyone's words. | The cover |
| 3 | Everyone adds | A note, photos, a voice, a video. | Writing an entry |
| 4 | On the day | Opened one at a time, like letters. | A note |
| 5 | Voice notes | The part they'll play again. | A voice note |
| 6 | Photos and video | Everyone who was there, in one place. | A photo entry |
| 7 | One link | No app to install, no account to make. | Share link and QR code |
| 8 | For the organizer | See each one arrive, and set the order. | The organizer's view |
| 9 | Theirs to keep | Come back to it, or save it as a PDF. | Kept |

## App Clip card

What an iPhone shows when someone opens a Sendoff link without the app. Set on the 1.0 page's
App Clip section (the default App Clip experience).

| Field | Value |
|---|---|
| Header image | 1800 x 1200, no text: the Wednesday lunch crew photo from the demo (Unsplash) |
| Subtitle (56) | Add a note, photos or a voice note to their Sendoff |
| Action | Open |

## App Review

**Sign-in required:** off. Only organizers sign in, with Sign in with Apple, so the reviewer uses
their own Apple ID. **App Clip URL:** the review Sendoff's contribute link. **Notes:**

```
Sendoff is a group card and memory book. One person, the organizer, starts it in the app and shares a link. Everyone else adds an entry from that link, in a browser or the App Clip, with no account. The person it is for opens it on the day.

SIGNING IN
Only organizers sign in, with Sign in with Apple, so there is no demo account: please use your own Apple ID. Adding an entry and opening a Sendoff need no sign-in.

TO TRY IT
1. Add an entry (the App Clip): open [CONTRIBUTE LINK] on an iPhone. Write a note, add a photo or a voice note if you like, sign it, and tap Add yours.
2. Open a Sendoff made for someone: open [RECIPIENT LINK]. It is already due, so press and hold the seal for a second. The entries open one at a time.
3. Start your own: in the app, sign in with Apple and tap Start a Sendoff.

IN-APP PURCHASES
Starting a Sendoff and collecting up to 10 entries is free. Once a Sendoff you started has an entry, its page shows "Free holds 10. Make it something they can keep". Tap it for:
- Sendoff and Sendoff Plus: consumables, each upgrading that one Sendoff (up to 100 entries; Plus has no limit, every Plus look and a song from Apple Music).
- Packs of 5 and 10 Sendoffs: consumables, bought ahead.
- Gold Leaf, Darkroom and Field Day: non-consumable looks, kept for every Sendoff.
Picking a Plus look when starting one also leads there. Restore purchases is on the same screen.

APPLE MUSIC
On a Plus Sendoff the organizer can pick a song from Apple Music (MusicKit). It plays in full for Apple Music subscribers and as a 30-second preview for everyone else.

USER-GENERATED CONTENT
Entries are private: only the person a Sendoff is for and its organizer can read them. The organizer can require approval before entries go in and can hide any entry. The person it is for can report an entry from the reveal (Report), which emails support@sendoffapp.com, and we respond within 24 hours.
```

## Spanish (Mexico)

A second localization for ASO. The US App Store also searches the Spanish (Mexico) listing, so its
name, subtitle and keywords add search terms in the US as well as in Mexico. The name and subtitle
are Spanish, since Mexico sees them. The hidden keyword field carries the best Spanish words the
name and subtitle don't, plus English words the English listing has no room for. No word repeats
another field here or in English. The app is English-only, and the description says so.
Screenshots fall back to the English ones.

| Field | Value |
|---|---|
| Name (30) | Sendoff - Tarjeta de despedida |
| Subtitle (30) | Jubilación y graduación |
| App Clip subtitle (56) | Agrega una nota, fotos o una nota de voz a su Sendoff |

**Keywords (100):**

```
recuerdos,libro,regalo,maestra,grupal,memories,scrapbook,guestbook,office,promotion,veteran,nurse
```

**Promotional text (170):**

> Cada quien agrega en privado una nota, fotos, una nota de voz o un video. Queda sellado hasta el día y se abre una entrada a la vez.

**Description:**

```
Sendoff es una tarjeta grupal y libro de recuerdos para el gran día de alguien. Cada quien agrega en privado una nota, fotos, una nota de voz o un video. Todo queda sellado hasta el día, y entonces la persona lo abre, una entrada a la vez.

Cómo funciona
1. Créalo en la app: para quién es, una foto si quieres y cuándo se abre, en una fecha o cuando tú digas.
2. Comparte un enlace o un código QR donde platique tu grupo. Nadie necesita la app ni una cuenta para participar.
3. Cada quien agrega lo suyo en privado: una nota, hasta seis fotos, una nota de voz o un minuto de video, desde cualquier teléfono o computadora.
4. Se abre el día indicado: se mantiene presionado el sello y las entradas aparecen una por una.

Por qué los grupos eligen Sendoff
- Privado: solo la persona a quien va dirigido y quien lo organiza leen las entradas, así que la gente escribe lo que de verdad quiere decir.
- Sellado hasta el día: es un sobre, no un muro que todos ven.
- Voces, no solo firmas: una nota de voz o un minuto de video dicen lo que una firma no puede.
- Nada que instalar: todos participan desde un enlace o un código QR, en cualquier navegador.
- Se abre como una carta: una entrada a la vez, con música.
- Tú tienes el control: ve las entradas conforme llegan, apruébalas antes si quieres, oculta lo que no corresponda y elige el orden.
- Para conservar: puede volver a verlo y guardarlo como PDF, en todos los planes.

Ideal para
- Jubilaciones
- Un compañero que se va o empieza un nuevo trabajo
- Graduaciones
- Agradecer a un maestro y el último día de clases
- Despedidas militares y cambios de base
- El fin de temporada, para un entrenador
- Cualquier despedida que valga la pena

Gratis para empezar
Crear uno y recibir hasta 10 entradas es gratis. Si quieren participar más personas, quien lo organiza paga una sola vez por ese Sendoff, en la app. Sendoff Plus no tiene límite de entradas e incluye todos los estilos Plus y una canción de Apple Music, que suena completa para suscriptores de Apple Music y como vista previa de 30 segundos para los demás. Nadie que participe o lo abra paga.

Privado por defecto
Solo la persona a quien va dirigido y quien lo organiza pueden leer lo que escribe la gente. Sin publicidad, sin rastreo y sin vender tus datos. Aviso de privacidad: sendoffapp.com/privacy

Por ahora, la app está en inglés.

Soporte
¿Preguntas o comentarios? Escríbenos a support@sendoffapp.com.
```
