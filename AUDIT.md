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

# Post phase 14 adversarial rounds

Two further rounds of refute first review. Round A raised 5 and confirmed 5,
round B audited round A's own fixes and confirmed 2 more, both of which were
cases where the first fix was incomplete.

**canDeleteAudio counted a failed segment as transcribed.** `isTranscribed` is
`allSatisfy { $0.state.isTerminal }` and `.failed` is terminal, so Delete audio
only was fully enabled on a recording whose segment had permanently failed. That
destroys the only copy of those minutes. Split out `isFullyTranscribed`, which
requires `.done`, and gated deletion on it.

**Retry was offered after the audio was deleted.** Retry reads the .m4a, so on a
transcript only session the button could never succeed. Both retry affordances
now require `session.hasAudio`, and the disabled caption names the real blocker
instead of always claiming transcription is still running.

**restoreInFlightRequest bailed on a nil sessionID.** Only the notes flow stores
one, so ask, todos, verify and safety left `requestStartedAt` at `.distantPast`,
`isFresh` rejected every result and the stranded answer was never written. The
durability fix therefore only worked in process, which is exactly when it was
not needed. Reads moved above the guard, and a dead flight now clears its keys
and its plaintext prompt file rather than leaving both on disk.

**The bridge lock had no user reachable escape.** `cancelInFlight` and
`busyNotice` existed with zero call sites. A wedged flight is now visible on the
record screen with a Cancel and unlock button, and a refused start says why.

**AI to-dos bound to their source by title.** `sourceRecordingId` was never
assigned, so the link resolved by `displayTitle`, which the user can edit and
which two meetings can share. `apply` now takes the candidate sessions and
stores the id.

**The busy notice outlived its flight.** Nothing cleared it, so once shown it
would have claimed a request was still running forever. It is now derived from
`isInFlight` rather than stored on screen, and the waiting banner names
`inFlightDestination` rather than `settings.destination`, which is only the
default and is overridable per recording.

**Binding to-dos by id broke every to-do already on disk.** Those carry a nil
id, so the strict id lookup left their source link dead. Resolution is now id
first, with a title fallback used only when there is no id and only when exactly
one recording matches. An id that is set and does not resolve still refuses to
rebind, because that means the recording was deleted.

**A transcript could be erased by deleting a file in Files.** Documents is user
visible, which the spec requires, so a .m4a can disappear without the app
hearing about it. `reconcile` dropped any segment whose audio was missing, took
its transcript with it, and the next persist made that permanent. Notes would
then have been generated from half a meeting with nothing on screen to say so.
Pruning now keeps any segment that produced text, discards only the ones with no
audio and no text, and marks the session audio removed once nothing playable is
left. Per segment retry is gated on that segment's own file rather than the
session, since a session can lose some of its audio and keep the rest.

**An unreadable volume looked like a full one.** `StorageGuard.freeBytes`
returned 0 when both probes failed, so a transient measurement failure read as
zero bytes free: the engine would stop a live meeting and claim free space had
fallen below 300 MB, and a start would be refused for the same reason. It now
returns nil for unknown. The engine skips that round and keeps recording, the
start is allowed, the remaining minutes figure keeps its last known value, and
Self Test says the space could not be read rather than printing 0 bytes. A disk
that is genuinely full still fails loudly on the next write.

**The long notes path told the user to attach a file it never checked existed.**
The overflow branch wrote the notes with `try?` and then said, in the draft
itself, to attach that file. A failed write, which is most likely on the full
disk that makes notes worth keeping, left the user attaching nothing and the
notes gone. The write is checked now, and on failure the draft carries as much
of the notes as fits with a line saying it is cut short. The prefix is measured
after percent encoding, since encoding expands by up to three characters per
byte.

**Nothing capped the subject line.** The model is asked for a three to five
word topic and will sometimes return a paragraph. That produced an unreadable
Outlook subject and pushed the ms-outlook URL toward the length where the tail,
which is the body, starts getting dropped. Topic is clipped to 80 characters and
each name to 40, both at a word boundary. Only the count changed: the shape of
the line, and the rule that empty components collapse with their separator, are
untouched.

**A crash recovered recording reported itself as 0m.** `reconcile` adopts
segment files that never made it into the manifest, which is exactly what a
force quit leaves behind, and gives them `duration: 0` because the engine that
would have timed them died with the app. Nothing ever filled that in, so
History and the ready notification both described a three hour meeting as 0m.
The transcription pipeline already opens the file, so it now reads the duration
there and reports it back. `applyMeasuredDuration` only ever writes over a zero,
and never shortens a recorded session's own figure, which comes from the elapsed
clock and legitimately includes paused time.

**Stop could park the app on the Transcribing screen forever.** The state moved
to transcribing whenever a session had segments, but the way back to ready comes
only from the queue draining. If every segment was already terminal and the
engine had no open segment to close, which happens when an interruption closed
the last one and it finished while the user was still paused, nothing was queued
and no drain callback was ever coming. `enqueueSegments` reports whether it
queued anything now, and Stop finishes the session directly when it did not.

**Only the notes prompt fenced its transcript.** Phase 12 hardened the master
prompt and left the other two builders alone. The Ask prompt pasted transcripts
in raw, and the to-do prompt did the same while asking the model for line shaped
ADD, MERGE and DONE operations, which a transcript can contain verbatim: paste
in accepts any text from the clipboard, so a forged `DONE | <uuid>` line is one
paste away from a to-do being marked complete. All three builders now use the
same `PromptBuilder.fenced` markers and the same notice saying the fenced text
is data, with the to-do prompt adding that an operation shaped line inside a
transcript is somebody talking. Instructions still come after the untrusted
text in every case, so the last word is the app's.

**The callback host was matched exactly, and a miss did nothing at all.** The
user types the callback URL into the bridge Shortcut by hand, and the one time
this handler stopped matching, during the rename, every result was silently
dropped. Routing moved out of the App struct into `SovoxURL.route`, which
lowercases the scheme and host and, for an unrecognised host arriving while a
request is in flight, still collects the result. Nothing else opens this scheme,
so the alternative to guessing is an indefinite wait on a result already sitting
in the file.

**The recording in progress could be deleted out from under the engine.** It
appears in History as soon as its first segment closes, and nothing stopped a
swipe delete, a Delete everything, or Settings bulk delete from removing its
directory while AVAudioFile was still writing into it. An unlinked file keeps a
valid write handle on iOS, so the audio would have gone nowhere with no error
raised until the session was already lost. `RecordingStore.protectedSessionID`
is set when recording starts and cleared on stop, every delete path checks it,
and the two affordances are simply absent for that session rather than present
and refusing.

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
