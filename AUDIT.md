# Sovox self audit

Evidence: 81 Swift files parse, 6 plists lint, the pbxproj resolves three
targets, all three build against the iOS 26.5 device SDK with zero warnings, and
180 XCTest cases pass on an iPhone 17 Pro simulator with zero failures across two
independent runs.

# Phase 13, E1 to E42

| # | Item | Result |
|---|------|--------|
| E1 | TranscriptionService is a long lived actor, not view owned | PASS, `TranscriptionService` is `actor` with a `shared` singleton |
| E2 | Serial queue, concurrency exactly 1 | PASS, `drain()` pops one job and holds `activeKey` until it settles |
| E3 | QoS utility | PASS, `Task(priority: .utility)` |
| E4 | Finalisation verified before enqueueing | PASS, `SegmentFinalisation.verify` checks exists, non zero, duration greater than zero |
| E5 | Survives backgrounding and view dismissal | PASS, no view constructs the service; the controller holds only Sendable closures |
| E6 | No `try?` in the pipeline | PASS, none in the three transcription files |
| E7 | Thermal guard defers transcription, never recording | PASS, `thermalStateBlocksWork` lives only in the service; the engine has no thermal code |
| E8 | Stitching tolerates an empty or failed segment | PASS, `stitch(records:)` inserts `[segment N could not be transcribed]` |
| E9 | Live Activity still renders after re-theming | NOT VERIFIED HERE, ActivityKit does not render in this environment |
| E10 | No hardcoded colour outside the token file | PASS, zero hex outside `Theme.swift` and `WidgetPalette.swift` |
| E11 | Red only for record, stop, REC dot, destructive | PASS by reading every call site. Failure indicators use `destructive`, which is an interpretation worth stating |
| E12 | Background gradients removed | PASS, `SovoxBackdrop` is a flat `bg` fill |
| E13 | Live Activity legible in dimmed Always On | NOT VERIFIED HERE. `WidgetPalette.subdued` is deliberately far brighter than the app's `textSecondary`, asserted by a luminance test |
| E14 | Title precedence userTitle, aiSubject, date | PASS, `RecordingSession.displayTitle` |
| E15 | Regeneration cannot overwrite a userTitle | PASS, the coordinator writes only `aiSubject` |
| E16 | Subject never emits a trailing or doubled separator | PASS, matrix test over 20 combinations |
| E17 | Prefix present in every combination | PASS, six combinations asserted |
| E18 | Prefix from CFBundleDisplayName, not hardcoded | PASS, `SubjectBuilder.appPrefix` |
| E19 | Model's SUBJECT never carries the prefix | PASS, instructed in the prompt and asserted by the Layer 2 verdict logic |
| E20 | All nine Phase 12 unit tests pass | PASS, T1 to T9 in `PromptInjectionTests` |
| E21 | Sanitiser strips and reports | PASS, `SanitisationReport` shown before the editor closes |
| E22 | Precedence reassertion after all custom blocks | PASS, appended last and asserted with `hasSuffix` |
| E23 | Conversation type persisted per recording | PASS, stored on `RecordingSession`, editable on regeneration |
| E24 | Delete audio only preserves the rest | PASS, and `reconcile` returns early on `audioRemoved` so the transcript is not stripped |
| E25 | Ask blocks above 100,000 rather than truncating | PASS, exact boundary tested |
| E26 | Ask attributes claims to sources | PASS, prompt requires `(Source: <recording title>)` |
| E27 | To-do refresh changes nothing without approval | PASS, `apply` runs only from the review sheet |
| E28 | Manual to-dos never displaced, merged or auto completed | PASS, filtered before the sheet and again inside `apply` |
| E29 | Watermark advances only after review completes | PASS, `advanceWatermark` called in the accept handler |
| E30 | 10 item cap without silent dropping | PASS, overflow shown and Apply disabled |
| E31 | Verify distinguishes the three failure modes | PASS, three distinct outcomes with distinct messages |
| E32 | No remaining user visible or callback string says Capture | PASS, two deliberate exceptions: the migration notice and the migration flag key |
| E33 | Wizard copy matches the live names and paths | PASS, generated from `RecordingPaths` and `SovoxURL`, asserted by test |
| E34 | Nothing in Phase 0 modified outside the carve outs | PASS, engine changes limited to the named carve outs |
| E35 | Zero network code, zero dependencies | PASS |
| E36 | No EventKit, no Contacts | PASS |
| E37 | Voice processing disabled everywhere | PASS. **Explicit statement: none was found, so nothing was removed.** Mode is `.default`. Locked by `CapturePathGuardTests` |
| E38 | Locale user selectable, defaults to en-IN | PASS, list queried at runtime from `SFSpeechRecognizer.supportedLocales()` |
| E39 | Locale stored per recording | PASS, `RecordingSession.localeIdentifier` |
| E40 | ASR paragraph does not weaken the ban on adding facts | PASS, both rules kept, asserted by test |
| E41 | No Whisper or third party speech model | PASS, no model files anywhere |
| E42 | No glossary, term store, custom vocabulary or known names list | PASS, no `contextualStrings` in shipping code |

The only two E37 and E42 grep hits in the whole tree are string literals inside
`CapturePathGuardTests`, which exist precisely to assert their absence.

# Deviations from the spec, stated rather than buried

**Phase 2 asks for SpeechAnalyzer / SpeechTranscriber. The shipping path is
SFSpeechRecognizer with `requiresOnDeviceRecognition`.** The SpeechAnalyzer
implementation exists at `Sovox/Transcription/SpeechAnalyzerTranscriber.swift`
behind the `SOVOX_SPEECHANALYZER` compilation condition, because its initialiser
signatures could not be verified against a compiler here and a drift would take
the whole app down. Both are equally on device. To switch: add
`-D SOVOX_SPEECHANALYZER` to Other Swift Flags on the Sovox target.

**Phase 1a asked for a new bundle identifier.** Kept at
`com.rishabh.capturenotes` on explicit instruction, so no new App Store Connect
record is needed. Because the container therefore survives, a one time
UserDefaults migration copies the old `capture.*` keys.

**E11.** Red is used for failure indicators as well as the four listed cases,
through the `destructive` token. Errors that are invisible are worse than a
slightly wider red.

# iOS 26 APIs I am not certain of

Everything else compiled against the iOS 26.5 SDK, so it is confirmed rather
than guessed.

1. The whole SpeechAnalyzer surface: `SpeechTranscriber(locale:preset:)`, the
   `.offlineTranscription` preset, `AssetInventory.assetInstallationRequest(supporting:)`,
   `downloadAndInstall()`, `SpeechTranscriber.installedLocales`,
   `SpeechAnalyzer(modules:)`, `analyzeSequence(from:)`,
   `finalizeAndFinish(through:)`, `cancelAndFinishNow()`, and whether
   `transcriber.results` yields an element with a `.text` of `AttributedString`.
   Not compiled, which is why it is behind a flag.
2. Whether `shortcuts://create-shortcut` opens a new empty shortcut. It compiles
   as a URL and the wizard also offers plain `shortcuts://` behaviour, but the
   exact landing screen is unverified.
3. Whether a Control Centre control honours `LiveActivityIntent` app process
   execution the way a Live Activity button does.
4. Whether `.symbolEffect(.pulse, options: .repeating)` animates inside a Live
   Activity, which renders as a snapshot.
5. ActivityKit's exact update throttling thresholds.
