# Backseat

Personal Android app (Flutter) that transcribes a work meeting on-device and, on demand,
sends the transcript to the Claude API for expert feedback (issues, risks, questions, ideas).

Full product brief: `docs/PROJECT_BRIEF.md`: read it before starting any phase. It is the
source of truth for scope, schema, prompts and screens; §9 records where the implementation
deliberately differs. Setup, build and install steps: `README.md`.

## Status (2026-10-14)

All five phases are implemented, analyze-clean and tested (50 tests). Installed on a Pixel 8
Pro but **not yet verified end-to-end on device**. The on-device checklist is at the end of
`README.md`. Treat device findings as the next work.

## Key decisions

- Target phone tier: flagship (Pixel 8/9 Pro, Galaxy S24/25 class): default to larger,
  more accurate ASR models, not the most battery-conservative ones.
- English only for v1.
- Audio is deleted immediately once the final transcript exists (not kept 7 days). The
  retention choice is still exposed in Settings.
- Models download file-by-file from the sherpa-onnx author's Hugging Face repos
  (`huggingface.co/csukuangfj/<repo>`), not the GitHub release tarballs: smaller, and
  nothing to unpack. Specs and sizes are in `model_download_service.dart`.
- The live Zipformer model has no `bpe.vocab`, so it is generated from `tokens.txt` after
  download (needed for hotwords). Not yet verified on device. Boost 0 disables it.
- Analysis requests send `fallbacks: "default"` with beta `server-side-fallback-2026-07-01`,
  and `output_config.effort: "medium"`.

## Stack

- Flutter (latest stable), Dart, Material 3, Android only, min SDK 26.
- State/nav: Riverpod + go_router, feature-first folders.
- Audio: `record` (PCM 16 kHz mono, also written to a WAV) + foreground service
  (`flutter_foreground_task`) for background recording with a persistent notification.
- ASR: sherpa-onnx streaming Zipformer (live, background isolate, custom vocabulary as
  per-stream hotwords) and Whisper `small.en` / `base.en` via sherpa-onnx for the final pass
  after Stop (background isolate, re-transcribes the WAV in windows of up to 25 s). Every
  isolate that uses sherpa-onnx must call `sherpa.initBindings()`.
- Storage: Drift (SQLite), schema v2: meetings (+ `extraTerms`), segments, analyses,
  key-value settings (settings JSON, onboarding, theme, privacy notice).
- Secrets: `flutter_secure_storage` for the Claude API key (behind `ApiKeyStore`). Never
  hard-coded or committed.
- Also approved (2026-10-14): `share_plus` (share sheet), `url_launcher` (docs links in
  in-app browser tabs), `file_picker` (vocabulary import). Battery/thermal state comes from
  a small `backseat/device` MethodChannel in `MainActivity.kt`, not a plugin.
- `permission_handler` is pinned to 12.x: 13.x needs compileSdk 37, which the current
  AGP 8.11 can't build. Revisit when upgrading AGP/Gradle/Kotlin; Flutter warns that these
  will soon be unsupported.
- Network: raw HTTP + SSE via `dio` to the Anthropic Messages API (there is no Dart SDK),
  default `claude-sonnet-5-5`, optional `claude-opus-5-5`. "Check against docs" adds
  `web_search_20260209` / `web_fetch_20260209` restricted to the approved domains
  (default `learn.microsoft.com`, `docs.databricks.com`), with `pause_turn` continuation.

## Structure

```
lib/
  core/          theme, router, db (Drift), providers, storage (API key), models
  features/
    recording/   mic capture, foreground service, sherpa-onnx engine, model downloads,
                 live meeting screen, device status
    transcript/  Whisper final pass
    analysis/    prompt builder, Claude SSE client, JSON parser, analysis service + flow,
                 results sheet
    history/     meeting detail
    home/        meeting list, start sheet
    onboarding/
    settings/
  shared/        widgets (cards, transcript view, motion), formatting
assets/prompts/  analysis_system.md + analysis_docs.md (tunable without code changes)
test/            widget tests + fixtures.dart; test/unit/ for builder, parser, SSE, service, DB
docs/PROJECT_BRIEF.md
```

## Working conventions

- Keep ASR behind the `TranscriptionEngine` interface. `FakeTranscriptionEngine` replays
  `assets/sample_transcript.txt` for dev and tests.
- Tests override every platform-backed provider via `baseTestOverrides()` in
  `test/test_utils.dart` (in-memory DB, fake key store, fake downloads, fake analysis
  service). Call `disableAnimations(tester)` before pumping, because looping animations
  otherwise keep `pumpAndSettle` busy. Use `settleAsync()` when awaiting DB writes or stream
  cancels that schedule no frames.
- Segment ids are scoped per meeting (`<meetingId>_seg-N`, `<meetingId>_final_N`). Only final
  segments are persisted; partials stay in memory.
- Verify current versions/APIs of `sherpa_onnx`, `record`, the foreground-service package and
  the Anthropic Messages API before using them. Read the installed package source in the pub
  cache rather than relying on memory.
- Ask before adding a dependency not listed above, and before changing the Drift data model
  (bump `schemaVersion` + add a migration, then run build_runner).
- No analytics, no third-party crash reporting, never log transcript text or request bodies.

## Commands

```
flutter pub get
flutter analyze
dart format lib test
flutter test
dart run build_runner build --delete-conflicting-outputs   # after editing Drift tables
flutter run                                    # debug, USB or wireless debugging
flutter build apk --release --split-per-abi    # release; signs with android/key.properties
flutter install --use-application-binary build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Android SDK licenses must be accepted once per machine: `flutter doctor --android-licenses`.
Release builds fall back to the debug key until `android/key.properties` exists. An install
signed with the debug key must be uninstalled (data lost) before installing a keystore-signed
build.
