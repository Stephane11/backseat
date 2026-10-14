# Backseat — Project Brief

Oct 13, 2026 · @Stéphane Nichanian

## 1. Overview

Build **Backseat**, a personal Android app (Flutter) that listens to a work meeting through the phone's microphone, transcribes it on-device, and, when the user taps **Analyse**, sends the transcript to the Claude API for an expert review: issues, risks, questions to ask, and better or new ideas.

**Context of use**

- The meeting runs on a separate work laptop (Teams, Zoom, Meet, any platform). All participants come out of the laptop speakers.
- The phone sits next to the laptop and records the room audio with its own mic. No integration with the meeting software.
- The single user is a data scientist. Meetings cover data science, data engineering, ML and AI engineering, analytics and product discussions.
- Single user only: no accounts, no sign-in, no multi-user backend.

**Product goal:** after (or during) a meeting, the user gets sharp, specific, technically credible feedback in under 30 seconds, as if a senior colleague had been listening.

## 2. User flow and features

**Core flow**

1. Open the app → Home shows past meetings and a large **Start listening** button.
2. Tap Start → optional meeting title and optional context note (e.g. "Churn model v2 review, stakeholders from marketing").
3. Live screen: the transcript streams in, with a recording timer and a level meter showing the mic is picking up audio.
4. At any point, tap **Analyse** → the full transcript so far goes to Claude → feedback cards appear in a bottom sheet / results screen.
5. Tap **Stop** → meeting is saved locally with transcript and any analyses.
6. Later, open a past meeting → re-read the transcript, re-run analysis, copy or share results.

**MVP features**

- [ ] Continuous on-device transcription for meetings of up to 2 hours.
- [ ] Live transcript view with auto-scroll (pauses when the user scrolls up, with a "jump to latest" chip).
- [ ] Analyse button usable during and after the meeting; multiple analyses per meeting, timestamped.
- [ ] Feedback cards in two families: **Issues & suggestions** and **New ideas & better solutions** (see section 4).
- [ ] Optional per-meeting context note, plus a global "About me / my projects" note in Settings, both sent with the analysis.
- [ ] Meeting history stored locally; rename, delete, search by title.
- [ ] Copy a card, copy all results as Markdown, share via Android share sheet.
- [ ] Settings: Claude API key (stored securely), model choice, transcription model choice, global context note, custom vocabulary, theme (dark default).

**Out of scope for v1**

- Live automatic hints, cloud transcription, speaker identification by name, accounts or sync, iOS, integration with meeting platforms, chat with the transcript. Keep the code structured so speaker diarisation and transcript chat can be added later.

## 3. Tech stack and architecture

Flutter app, Android only, no custom backend: audio and transcription stay on the phone; only transcript text goes to the Claude API when the user taps Analyse.

| Layer | Choice | Notes |
| --- | --- | --- |
| Framework | Flutter (latest stable), Dart, Material 3 | Android min SDK 26; target the latest SDK |
| State / navigation | Riverpod, go\_router | Feature-first folder structure |
| Audio capture | `record` package, PCM 16 kHz mono stream | Also write the raw audio to a local WAV/FLAC file per meeting |
| Background recording | Foreground service with `microphone` type (e.g. `flutter_foreground_task`) | Persistent notification with timer + Stop action; wakelock while recording |
| Live transcription | **sherpa-onnx** Flutter package, streaming English Zipformer/Paraformer model | Fully on-device, real-time, low latency; includes endpointing to split into utterances |
| Accurate final pass (phase 4) | Whisper via sherpa-onnx or whisper.cpp bindings, `small.en` or `base.en` | Re-transcribes saved audio after Stop for higher accuracy; replaces the live draft |
| Storage | Drift (SQLite) | Meetings, segments, analyses |
| Secrets | `flutter_secure_storage` | API key entered in Settings, never hard-coded or committed |
| HTTP | `dio` or `http`, direct calls to the Anthropic Messages API with streaming (SSE) | Default model `claude-sonnet-5-5`, option for `claude-opus-5-5` |

**Pipeline**

1. Mic → PCM stream → (a) on-disk audio file, (b) streaming recogniser.
2. Recogniser emits partial text (shown greyed) and final segments (saved to DB with start/end timestamps).
3. Analyse → build prompt from segments + context notes → stream Claude's response → parse JSON → render cards → save analysis.

**Models on device:** ASR model files are tens to a few hundred MB. Download them on first launch from the official sherpa-onnx releases with a progress screen, rather than bundling them in the APK. Verify current package and model versions before adding dependencies.

**Custom vocabulary**

- Settings screen to add, edit and delete terms (one per row), pre-filled with a starter list: Databricks, Unity Catalog, Delta Lake, Delta Live Tables, Lakeflow, Auto Loader, MLflow, Spark, PySpark, dbt, Azure Data Factory, Synapse, Fabric, ADLS, Key Vault, AKS, XGBoost, LightGBM, scikit-learn, PyTorch, LLM, RAG, embeddings, feature store, CI/CD.
- Optional per-meeting extra terms in the start sheet (project names, product names, acronyms).
- Recognition: pass the list as hotwords / contextual biasing to the sherpa-onnx recogniser (supported for transducer models; confirm the current API and pick a model that supports it), with a boost-strength slider in Settings.
- Analysis: always send the list to Claude so it can correct mistranscriptions it still sees.
- Import/export the list as a plain text file.

**Suggested structure**

```
lib/
  core/        theme, router, db, secure storage, api client
  features/
    recording/ audio capture, foreground service, ASR engine
    transcript/ live view, segment models
    analysis/  prompt builder, Claude client, card UI
    history/   meeting list, meeting detail
    settings/
  shared/      widgets, utils
```

## 4. Analysis engine

One Claude call per Analyse tap, returning strict JSON that the app renders as cards. Keep the system prompt in `assets/prompts/analysis_system.md` so it can be tuned without code changes.

**System prompt (starting draft)**

```
You are a senior data scientist and ML/data engineering lead silently attending a work
meeting alongside the user, who is a data scientist. You receive an automatic
transcript (it contains recognition errors and no speaker names) plus optional context.

Review the discussion and produce two kinds of feedback:

1. ISSUES & SUGGESTIONS: problems, risks or gaps in what was said. Look especially for:
   - Statistics & experimentation: leakage, sampling bias, wrong metric for the goal,
     underpowered tests, p-hacking, confounders, train/test contamination.
   - ML & AI engineering: missing evaluation plan or baseline, offline/online mismatch,
     drift and monitoring, LLM evals, hallucination risk, cost and latency.
   - Data engineering: data quality, schema changes, lineage, freshness/SLAs,
     scalability, idempotency, backfills, PII and governance.
   - Delivery: vague requirements, unstated assumptions, undefined success criteria,
     missing owners or deadlines, scope creep.
   - Questions the user should ask before the meeting ends.
2. IDEAS & BETTER SOLUTIONS: simpler, cheaper, faster or more robust alternatives to
   what was proposed, and genuinely new ideas worth exploring.

Rules:
- Be specific to THIS conversation. Quote or paraphrase the moment you refer to.
- No generic advice. If nothing important applies to a category, omit it.
- Prefer 5–10 high-value items over many weak ones; rank by importance.
- If the transcript is ambiguous or garbled, say what you are assuming.
- The transcript has no speaker labels and is an imperfect, automatic record of one
  meeting. Never attribute statements to a person or role, and never blame or judge
  individuals. Discuss ideas, decisions and risks, not people.
- You only see this one conversation: earlier discussions, documents or decisions may
  already cover a point. Frame items as "worth checking" or "worth raising" rather than
  as definite failures, unless the transcript clearly shows the problem.
- Words from the custom vocabulary list may be mistranscribed (e.g. "unity cat a log");
  silently read them as the intended term.
- Return ONLY valid JSON matching the schema.
```

**User message** = global context note + meeting context note + custom vocabulary list + transcript as timestamped lines (`[00:12:34] text`).

**Output schema**

```json
{
  "summary": "2-3 sentence recap of what the meeting is about so far",
  "items": [
    {
      "type": "issue | suggestion | question | idea | better_solution",
      "category": "statistics | ml | ai_engineering | data_engineering | delivery | other",
      "severity": "high | medium | low",
      "title": "short headline, max 10 words",
      "detail": "2-4 sentences: what, why it matters, what to do",
      "evidence": "short quote or paraphrase from the transcript",
      "timestamp": "00:12:34 or null"
    }
  ]
}
```

**Implementation notes**

- Stream the response and show a polished loading state; render cards once JSON parses. On parse failure, retry once with a "return valid JSON only" reminder, then show the raw text.
- Long meetings: a 2-hour transcript fits in context; still cap input and trim the oldest segments if needed, telling the user.
- Use prompt caching on the system prompt and transcript prefix so repeated Analyse taps during one meeting are cheaper and faster.
- Tapping a card's timestamp jumps to that point in the transcript.
- Errors (no key, no network, rate limit) show a friendly inline message with a retry button.

## 4b. Documentation lookup (Azure & Databricks)

During analysis, Claude can search and read the official Azure and Databricks docs, using the Claude API's built-in server tools restricted to approved domains. No backend or document index is needed.

**Tools added to the Analyse request**

- `web_search` with `allowed_domains` = the approved list and `max_uses` = 5 (configurable).
- `web_fetch` with the same `allowed_domains`, so Claude can open the full page a search returns.
- Default approved domains: `learn.microsoft.com` (all Azure docs, **including Azure Databricks**, the primary source since the user's company runs Databricks on Azure) and `docs.databricks.com` (general Databricks reference, AWS/GCP-flavoured; use when the Azure page lacks detail).
- Use the latest web search / web fetch tool versions listed in the Claude API docs; check the exact tool type strings and any beta headers before implementing.

**Prompt addition** (append to the system prompt):

```
When a point depends on Azure or Databricks features, limits, pricing tiers, defaults
or best practice, check the official documentation before stating it. Prefer Azure
Databricks pages on learn.microsoft.com. Do not search for things you can judge from
first principles (statistics, general ML design). For each item backed by the docs,
fill "sources" with the page title and URL.
```

**Schema change:** each item gains `"sources": [{"title": "...", "url": "..."}]` (empty when not docs-backed).

**App behaviour**

- Analyse button gets a "Check against docs" toggle, on by default; off = faster, cheaper analysis with no tools.
- Cards with sources show a "Verified in docs" chip; tapping it opens the page in an in-app browser tab.
- While searching, the loading state shows what Claude is checking (from the streamed tool-use events), e.g. "Checking Unity Catalog docs…".
- Settings: editable list of approved doc domains (add dbt, MLflow, PyPI docs later) and max lookups per analysis.
- Web search must be enabled for the organisation in the Claude Console before it works; show a clear error if the API reports it is disabled.

**Cost and speed:** each search adds a per-search fee plus the tokens of the results read; expect analyses with lookups to take roughly 30–60 s. Prompt caching still applies to the system prompt and transcript.

**Build in phase 3**, after basic analysis works. Smoke test: a transcript mentioning Auto Loader and Unity Catalog must produce at least one card citing a learn.microsoft.com page.

## 5. Data storage and privacy

Everything lives on the phone; the only network call is the Analyse request (plus the one-time model download).

**Data model (Drift)**

- `meetings`: id, title, contextNote, startedAt, endedAt, durationSec, audioPath, transcriptSource (`live` | `final`).
- `segments`: id, meetingId, startMs, endMs, text, isFinal.
- `analyses`: id, meetingId, createdAt, model, transcriptUpToMs, rawJson, summary.
- `settings`: key-value (model, ASR model, global context note, keep-audio flag).

**Privacy rules**

- Audio never leaves the device. Option in Settings to auto-delete audio after the final transcript is created (default: keep 7 days).
- Before the first Analyse, show a one-time notice that transcript text is sent to Anthropic's API.
- A small, clear "Recording" indicator is always visible while listening; remind the user in the start sheet to let participants know they are being recorded.
- No analytics, no crash reporting to third parties, no logging of transcript text.

## 6. Design system and screens

Calm, warm, editorial dark UI in the style of modern AI chat apps: near-black warm background, generous spacing, serif type for content, one warm accent colour, soft rounded surfaces and smooth motion. Use original assets only: no third-party logos, names or brand artwork.

**Tokens**

| Token | Dark (default) | Light |
| --- | --- | --- |
| background | `#1C1B1A` | `#FAF9F5` |
| surface (cards, composer) | `#262624` | `#FFFFFF` |
| surface-raised (chips, sheets) | `#30302E` | `#F0EEE6` |
| border | `#3A3936` | `#E5E2D9` |
| text-primary | `#ECEAE4` | `#1F1E1D` |
| text-secondary | `#A3A09A` | `#6B6862` |
| accent (primary actions, recording) | `#E07A5F` | `#C9603F` |
| severity high / medium / low | `#E5674F` / `#E0A458` / `#7FA88A` | same |

**Typography**

- Content (transcript, cards, headings): a serif, e.g. **Source Serif 4** (Google Fonts). Headings semibold 22–28 sp, body 17 sp, line height 1.5.
- UI chrome (buttons, labels, chips, timestamps): a clean sans, e.g. **Inter**, 13–15 sp.

**Shape, spacing, motion**

- Radius: 24 for the bottom action bar (pill), 16 for cards, 12 for chips, full circle for the main action button.
- 8-pt spacing grid; screen side padding 20.
- Motion: 200–300 ms ease-out; cards fade + slide up with a 40 ms stagger; the transcript's new lines fade in; record button gently pulses while listening. Haptic tick on Start, Stop and Analyse.
- Respect system "reduce motion" and dynamic text size. 60 fps target, no jank while transcribing.

**Screens**

1. **Home**: top bar with menu icon (left) and settings (right); serif greeting ("Good evening"); list of past meetings as quiet rows (title, date, duration); bottom pill bar with a large round accent **Start listening** button.
2. **Start sheet**: bottom sheet with title field, context-note field, recording-consent reminder, Start button.
3. **Live meeting**: header with title, red-dot timer and a thin animated level meter; transcript in serif, partial text in text-secondary; bottom pill bar mirroring a chat composer: Stop (left), **Analyse** (accent, right) with a small badge showing new minutes since the last analysis.
4. **Analysis results**: draggable full-height bottom sheet; summary paragraph at top; segmented control *Issues & suggestions* / *Ideas*; cards with severity dot, category chip, serif title, detail, evidence quote in a left-bordered block, tappable timestamp; per-card copy icon row like a chat message's action row.
5. **Meeting detail**: transcript + list of past analyses; actions: re-analyse, share, rename, delete.
6. **Settings**: API key, model, ASR model (with download state), global context note, audio retention, theme.
7. **First-run**: 3 short onboarding screens, mic permission, notification permission, model download with progress.

## 7. Non-functional requirements

- **Reliability:** a 2-hour recording must survive the screen turning off, switching apps and incoming notifications. Segments are written to the DB as they finalise, so a crash loses at most a few seconds.
- **Performance:** live transcript lag under 2 s on a mid-range Android phone; ASR runs in a background isolate, never on the UI thread.
- **Battery and heat:** target under 15% battery per hour of recording; show a warning if the device gets hot or the battery is under 15%.
- **Audio quality:** guide the user to place the phone near the laptop speakers; show a "low audio" hint if the level stays low for 10+ seconds.
- **Permissions:** request mic and notification permissions with clear rationale screens; handle denial gracefully.
- **Testing:** unit tests for the prompt builder, JSON parsing and DB layer; widget tests for the main screens; a fake ASR engine that replays a sample transcript so the UI can be developed and tested without speaking.
- **Code quality:** `flutter analyze` clean, `dart format`, null-safe, no hard-coded secrets, README with setup steps.

## 8. Build phases and instructions for Claude Code

Build in five phases. Finish and demo each phase on a real Android device before starting the next.

| Phase | Scope | Done when |
| --- | --- | --- |
| 1. Skeleton & design | Project setup, theme tokens, fonts, router, all screens with mock data, fake ASR replaying a sample transcript | App runs on device; all screens navigable; looks polished in dark and light |
| 2. Live transcription | Mic capture, foreground service, sherpa-onnx streaming ASR, model download, segments saved to DB | 30-minute real meeting transcribed with screen off; transcript readable and saved |
| 3. Analysis | Settings + secure API key, prompt builder, streaming Claude call, JSON parsing, results sheet with cards | Analyse on a real transcript returns specific, well-formatted cards in under 30 s |
| 4. History & accuracy | Meeting detail, re-analyse, share/copy, rename/delete, Whisper final pass after Stop | Past meetings fully usable; final transcript visibly more accurate than live |
| 5. Polish | Motion, haptics, empty/error states, onboarding, battery and audio-level warnings, tests | `flutter analyze` clean, tests pass, no jank in a 1-hour session |

**How to work on this project**

- Save this brief as `docs/PROJECT_BRIEF.md` and create a concise `CLAUDE.md` summarising stack, structure, commands and conventions.
- Start each phase in plan mode: propose the plan, list new dependencies with reasons, then implement.
- Check current versions and docs of `sherpa_onnx`, `record`, the foreground-service package and the Anthropic Messages API before using them; do not rely on memory.
- Ask before adding any dependency not listed here, and before any change to the data model after phase 2.
- Keep the ASR engine behind an interface (`TranscriptionEngine`) so the fake, streaming and Whisper engines are swappable.
- After each phase: run analyze and tests, summarise what was built, and list anything the user must test by hand on the phone.

**Build and install (no Play Store)**

- Development happens on the user's Windows PC with Android Studio and the Flutter SDK; Claude Code runs on the same PC in the project folder.
- During development: run debug builds straight to the phone over USB or wireless debugging (`flutter run`).
- For daily use: create a personal release keystore (kept outside the repo, path in a git-ignored `key.properties`), then `flutter build apk --release --split-per-abi` and install the `arm64-v8a` APK on the phone (USB, `adb install`, or copy the file and allow "Install unknown apps").
- Always sign updates with the same keystore so new APKs install over the old one without losing data.
- Keep ASR models out of the APK (downloaded on first launch) so builds stay small.
- Document all of this in the README.

**Open questions for the user — resolved 2026-10-13**

- Phone tier: **flagship** (e.g. Pixel 8/9 Pro, Galaxy S24/S25) → default to a larger, more accurate streaming ASR model; no need to optimise first for low-end hardware.
- Language: **English only** for v1. Keep `TranscriptionEngine` model selection generic enough that another language model could be swapped in later, but no multilingual UI/logic now.
- Audio retention: **delete immediately** once the final transcript exists (overrides the "keep 7 days" default suggested in section 5 — treat that as superseded; Settings should still default the toggle to "delete immediately" rather than a 7-day window, but a user-adjustable retention setting is still worth keeping for flexibility).

## 9. Implementation notes (2026-10-14)

All five phases are implemented. On-device verification is pending (checklist in `README.md`).
Deliberate differences from the sections above:

- **Model source (§3):** models are fetched file-by-file from the sherpa-onnx author's Hugging Face repos (`csukuangfj/…`), the same artifacts the GitHub release archives contain. This means a smaller download (int8 weights only) with no on-phone extraction. Live: `sherpa-onnx-streaming-zipformer-en-2023-06-21` (~190 MB). Final pass: Whisper `small.en` (~375 MB, default) or `base.en` (~160 MB), or off.
- **Hotwords (§3):** the live model ships no `bpe.vocab`, so the app generates one from `tokens.txt` after download. Hotwords use modified beam search. Boost strength 0 disables biasing.
- **Final pass (§3, phase 4):** Whisper re-transcribes the saved WAV in windows of up to 25 s built from the live segment boundaries (silences skipped). If Whisper returns nothing for a window, that window keeps its live text.
- **Data model (§5):** `meetings` gained `extraTerms` (schema v2). `analyses` stores parsed items as `itemsJson` rather than raw response JSON. Unparseable responses are shown as raw text and not saved.
- **Analysis requests (§4):** effort `medium`. Server-side refusal fallback (`fallbacks: "default"`) is on. The transcript is split into 10-minute blocks so repeated Analyse taps hit the prompt cache. The input cap is ~400k characters, with the oldest lines dropped and the user told.
- **Dependencies:** added `share_plus`, `url_launcher` and `file_picker`. `permission_handler` is pinned to 12.x until the Android toolchain supports compileSdk 37.
