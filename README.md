# Backseat

Personal Android app that transcribes a work meeting on-device and, when you tap
**Analyse**, sends the transcript to the Claude API for expert feedback: issues, risks,
questions to ask, and better ideas. Product brief: [`docs/PROJECT_BRIEF.md`](docs/PROJECT_BRIEF.md).

- Audio never leaves the phone. Only transcript text (plus your context notes and
  custom vocabulary) is sent to Anthropic, and only when you tap Analyse.
- No accounts, no backend, no analytics.

## How it works

| Stage | What runs | Where |
| --- | --- | --- |
| Live transcript | sherpa-onnx streaming Zipformer (English, int8, ~190 MB), custom vocabulary as hotwords | On-device, background isolate |
| Background recording | Foreground service (`microphone` type) with a Stop action, wakelock | On-device |
| Final transcript | Whisper `small.en` (default, ~375 MB) or `base.en` (~160 MB) re-transcribes the saved WAV after Stop | On-device, background isolate |
| Analysis | Claude Messages API, streamed; `claude-sonnet-5-5` (default) or `claude-opus-5-5` | Anthropic API |
| Docs check (optional) | Claude's `web_search` / `web_fetch` server tools restricted to approved domains (default `learn.microsoft.com`, `docs.databricks.com`) | Anthropic API |

Models download on first launch (onboarding) or from **Settings → Transcription**. They are
not bundled in the APK.

Analysis prompts live in [`assets/prompts/`](assets/prompts/), so you can tune them without code changes
(rebuild to pick them up).

## Setup (Windows dev machine)

1. Install the Flutter SDK (stable) and Android Studio, then accept the licences once:
   ```
   flutter doctor --android-licenses
   ```
2. Fetch dependencies and check everything is green:
   ```
   flutter pub get
   flutter analyze
   flutter test
   ```
3. Get a Claude API key from <https://console.anthropic.com> and paste it into the app under
   **Settings → Claude API** (stored encrypted on the phone with the Android Keystore,
   never in the repo).
4. For **Check against docs**, web search and web fetch must be enabled for your
   organisation in the Claude Console. If they aren't, the app shows a clear error. Turn the
   docs toggle off to analyse without lookups.

If you change the Drift tables in `lib/core/db/tables.dart`, regenerate the database code:

```
dart run build_runner build --delete-conflicting-outputs
```

## Run during development

Plug in the phone with USB debugging (or pair wireless debugging), then:

```
flutter run
```

Widget tests and dev builds can use `FakeTranscriptionEngine`, which replays
`assets/sample_transcript.txt` without a microphone (see `test/test_utils.dart`).

## Build and install for daily use (no Play Store)

1. Create a personal release keystore once, **outside the repo**, and back it up. Android only
   installs an update over an existing install if it is signed with the same key:
   ```
   keytool -genkey -v -keystore %USERPROFILE%\keys\backseat.jks -keyalg RSA -keysize 2048 -validity 10000 -alias backseat
   ```
2. Create `android/key.properties` (git-ignored):
   ```
   storeFile=C:\\Users\\<you>\\keys\\backseat.jks
   storePassword=...
   keyAlias=backseat
   keyPassword=...
   ```
   Without this file, release builds fall back to the debug key, which is fine for testing
   but not for an install you want to keep updating.
3. Build:
   ```
   flutter build apk --release --split-per-abi
   ```
4. Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`:
   - `adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`, or
   - copy it to the phone and open it (allow "Install unknown apps" for your file manager).

## Using it

1. Put the phone next to the laptop speakers. Tap **Start listening** and optionally add a
   title, a context note and extra terms (project names, acronyms).
2. Tell the other participants that the meeting is being recorded.
3. Tap **Analyse** at any time. The book icon next to it toggles **Check against docs**.
   Tap a card's timestamp to jump to that moment in the transcript. "Verified in docs"
   opens the cited page.
4. Tap **Stop**. If a Whisper model is downloaded, the transcript is re-transcribed
   on-device (progress shows in the notification and on the meeting page). After that, the
   recording is deleted unless you chose to keep audio in Settings.
5. From a past meeting you can re-analyse, share or copy the transcript and analyses,
   rename, or delete.

## Project layout

```
lib/
  core/          theme, router, Drift db, providers, secure key storage, models
  features/
    recording/   mic capture, foreground service, sherpa-onnx engine, model downloads
    transcript/  Whisper final pass
    analysis/    prompt builder, Claude SSE client, JSON parser, results UI
    history/     meeting detail
    home/        meeting list, start sheet
    onboarding/  first-run flow
    settings/
  shared/        widgets, formatting
assets/prompts/  analysis system prompt + docs addendum
test/            widget tests; test/unit/ for prompt builder, parser, SSE, service, DB
```

## Check on a real phone

These can't be covered by automated tests:

- [ ] Onboarding downloads the live model. Mic and notification permissions are granted.
- [ ] A 30-minute meeting transcribes with the screen off. The notification timer keeps
      ticking and its **Stop** button works.
- [ ] Custom vocabulary terms (e.g. "Unity Catalog") come out correctly in the live
      transcript. If recording fails to start after you change vocabulary, set **Recognition
      boost** to 0 and report it.
- [ ] The low-audio hint appears when the phone is far from the speakers. Battery and heat
      warnings show when relevant.
- [ ] After Stop, "Improving transcript" runs and the final transcript reads better than the
      live one. The WAV in app storage is gone afterwards (with the default retention).
- [ ] Analyse returns cards in under ~30 s without docs, and 30–60 s with docs. A transcript
      mentioning Auto Loader and Unity Catalog yields at least one card citing
      learn.microsoft.com.
- [ ] Wrong API key, airplane mode and docs-disabled each show a friendly inline error with
      Retry.
- [ ] Kill the app mid-recording. On relaunch the meeting appears as a normal past meeting
      with its transcript.
