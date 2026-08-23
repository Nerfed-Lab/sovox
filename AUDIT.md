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

**The consent reminder only existed on the record button.** Siri, the Control
Centre control and the Shortcuts app all reached `start()` directly, so a user
who switched on Announce consent still got a silent start from three of the four
ways to begin a recording. Both intents that can start one already bring the app
forward, so `commandStart` now raises the reminder there and returns
`awaitingConsent` rather than reporting a recording that has not begun. The
recording starts when the user confirms.

**The Ask context guard counted the wrong thing.** The bridge is stateless, so
every prior turn is resent with every question, and nothing bounded the thread.
The guard measured transcripts only, so a long thread showed green while the
prompt it was guarding had grown past the block threshold on history alone,
which is exactly the silent truncation it exists to prevent. History is now
capped at 12,000 characters, oldest dropped first, the prompt says how many
exchanges were left out, and the guard counts transcripts plus the history that
actually survives. A single oversized turn is still sent whole, since a follow
up without the question it follows is useless.

**The recovery screen taught a Shortcut that could never call back.** The setup
wizard listed five actions including Open URL; the screen shown when the bridge
Shortcut is missing listed four and left the callback out. A user following that
screen built a Shortcut that read the prompt, asked the model and saved the
answer, and Sovox waited forever for a callback that was never going to come.
Both lists now come with the callback step spelled out, and the file names come
from `RecordingPaths` rather than being typed twice. On top of that, becoming
active now collects a result that is already sitting in the file: only when it
exists and belongs to the current request, so returning to the app while the
model is still thinking cannot cancel a request that is still alive.

**The AI subject was stored raw and became the title everywhere.** It is model
output shaped by whatever was said in the meeting, and it is printed outside the
fenced transcript in the Ask and to-do prompt headers. A topic carrying a
newline and a run of dashes could therefore read as the end of a fence, letting
the rest of the header line pose as instruction, and a paragraph long topic
broke list rows. `RecordingSession.cleanTitle` collapses whitespace, strips the
subject separator, flattens dash and equals runs and clips to the subject limit.
It runs when the subject is stored and when the user renames, and
`promptSafeTitle` cleans whatever an older build already wrote.

**The custom action sanitiser only caught a fence at the start of a line.** It
dropped lines matching `^\s*---` and left a marker sitting mid line alone, but a
model reads a marker wherever it sits. A forged `--- TRANSCRIPT BEGINS ---`
inside an instruction, which is assembled after the real transcript, would have
made everything below it look like transcript, precedence reassertion included.
Dash runs are now flattened anywhere in the instruction and in the name, which
also protects the wrapper's own `--- IF "name" REQUESTED ---` line, and the
report tells the user what changed rather than rewriting their text silently.

**The transcript could close its own fence.** Phase 12 hardened custom actions
and the response parsing, and trusted the markers around the transcript. Nothing
stopped the transcript from containing them: paste in accepts whatever is on the
clipboard, so an email pasted in as a transcript can carry
`--- TRANSCRIPT ENDS ---` followed by instructions, and everything after that
line reads as instruction. `PromptBuilder.fenced` now flattens dash runs in the
body before fencing it, so nothing inside can pose as a marker while the words
themselves survive for summarising. The stored transcript is untouched: this
applies only to the copy that goes into a prompt, and all three builders share
the choke point.

**Self Test could come back all green next to a broken app.** It never checked
the two things most likely to be wrong and least likely to announce themselves:
whether the bridge Shortcut has ever worked end to end, and whether
notifications are allowed. A bridge that was never built has no symptom until a
recording is already waiting on it, and with the phone locked a notification is
the only way the app can say anything at all, including that recording stopped
for lack of space. Both are rows now, the bridge row offers Setup as its fix,
and the checks come from one enum so a check cannot quietly drop out of the run.

**Notes could be generated from a transcript of nothing.** When every segment
fails, the stitched transcript is a run of `[segment N could not be
transcribed]` placeholders, which is not empty, so `generate` passed it
straight to the model. The model would then write notes for a meeting nobody
heard and the app would open a draft addressed to the user's real work address.
`hasTranscribedContent` strips the app's own markers and placeholders and asks
whether anything a person said is left. Generation refuses without it and names
retry as the way out, and the to-do refresh no longer treats a placeholder only
session as a source. The placeholders themselves stay in the transcript the user
reads: a stated gap is the point.

**Share offered files that were not there.** The Audio section rendered a
ShareLink per segment behind the session level `hasAudio` flag, so after the
pruning fix a session could keep a segment record whose .m4a had been deleted in
Files and still offer to share it, and the segment currently being written was
offered too, which is not a playable file until the engine closes it.
`shareableAudioURLs(isRecording:)` filters on the file actually existing and
drops the open segment.

**A missing language asset failed every recording, permanently.** Phase 14a
made the locale a setting and defaulted it to en_IN, but a supported language is
not an installed one: `resolved` handed the asked for identifier straight to the
recogniser, which threw `onDeviceModelMissing` for every segment of every
recording on a device that had never downloaded that asset, while holding a
working en_US asset the whole time. `TranscriptionLocale.usable` now walks a
chain of asked for, phone language, en_US, and takes the first that is actually
installed.

The old Settings copy promised Sovox would never fall back. That promise is now
kept differently: it does fall back, and it says so, naming the language it will
transcribe with and that accuracy suffers. Self Test names both the asked for
and the used locale, and still fails the row, because a fallback is a problem to
fix rather than a state to accept. With nothing installed at all, the error
still names the language the user chose.

**Two pastes in the same minute overwrote each other.** `addPasted` built its
id as `uniqueSessionID(for:) + "-pasted"`, so uniqueness was checked on the bare
timestamp while the id actually used carried a suffix. The check said free both
times, `upsert` replaced the first session in the store and its manifest on
disk, and the first transcript was gone with nothing said. Uniqueness is now
checked on the whole id, and the paste path also checks what is already in
memory, so a failed manifest write cannot make an id look free.

**Generate enabled itself for a case it then refused.** The button unlocks when
either a built in output or a custom action is ticked, but the coordinator
guarded on `modes` alone, so ticking only a custom action produced an enabled
button whose only possible outcome was "Pick at least one output type". A custom
action is an output: `hasRequestedOutput` accepts either, and the assembled
prompt still carries the two header lines and the precedence reassertion with no
built in sections at all.

**Every callback landed on the Record tab.** Ask, to-dos and Verify all return
through the same `sovox://done`, and the handler switched to Record regardless.
An answer to a question was therefore delivered to a screen that does not show
it: not lost, since the Ask tab drains the stranded pair when it next appears,
but invisible until the user happened to go looking. The purpose is read from
the persisted record before collecting clears it, so the flow the user started
is the flow they come back to, and it survives a relaunch.

**The hard constraints were checked by their existence, not their content.**
`verify.sh` asserted that `NSAppTransportSecurity` was present, which says
nothing about whether it blocks anything: flipping `NSAllowsArbitraryLoads` to
true would have passed. Four checks were added, and each was confirmed to fail
when violated rather than merely to pass today: every ATS flag reads false with
no exception domains; none of the permission keys whose mere presence triggers
the corporate review is in either Info.plist, and no push entitlement is either;
the URL scheme is exactly `sovox` with `shortcuts` and `ms-outlook` queryable,
which is the string set the rename broke once; and every
`PRODUCT_BUNDLE_IDENTIFIER` still sits under `com.rishabh.capturenotes`.

**A retried verify never recorded itself.** The wizard marked the bridge
verified from the outcome label's `onAppear`. That runs when the label is
inserted, so it fired on the first failure, and the retry that succeeded updated
the same label without running it again. The ordinary path, get it wrong, fix
the Shortcut, verify again, therefore left a working bridge recorded as
unverified forever, which the new Self Test row would then report as broken.
Marking moved into the coordinator, at the point where the reply is actually
read as OK, so it does not depend on any view being on screen.

**The to-do refresh had the durability bug the Ask tab already had fixed.** The
list of recordings sent to the model lived in `@State` on the To-dos tab, and
the reply was delivered only through an `onChange`. The round trip leaves the
app entirely, so a jetsam meant the reply arrived with an empty source list: the
watermark could not advance, every one of those recordings would be proposed
again on the next refresh as duplicates, and the accepted to-dos were created
with no source id. If the tab had not been created yet, the `onChange` could not
fire at all and the reply sat unread. Both halves now persist with the in flight
record, `consumeTodoResponse` returns the reply together with its source ids,
and the tab drains from a `task` as well as an `onChange`.

# Phase 15, bridge setup corrected

A real setup attempt on device produced four defects, every one of them caused
by how the instructions were presented rather than by the user.

**15a. Names are letters only.** `SovoxChatGPT` and `SovoxClaude`. The old names
carried a space and a hyphen, iOS smart punctuation turned the typed hyphen into
an en dash, the lookup matched nothing, and the app asserted the shortcut did not
exist. A name with no punctuation at all cannot be mangled. The encoder still
percent encodes it, and a test asserts the encoded form equals the name: a name
that needs encoding is a name that can be mistyped.

**15b. Literal strings render as literal ASCII.** Every value the user must
reproduce is drawn monospaced and selectable, so a hyphen cannot be mistaken for
a dash and the bytes can be checked by hand. A test walks every displayed
literal, every copyable value, both file names and both callback URLs, and fails
on U+2013, U+2014 or any curly quote. `verify.sh` scans the whole Swift tree for
the same six code points.

**15c. Both bridge files exist from first launch and stay.** Written to the
Documents root, which is what surfaces as the app's folder in Files, never to a
subfolder. `sovox-pending.txt` holds the single line `ready` and
`sovox-result.txt` is empty. Cleanup rewrites the placeholder instead of
deleting the file: the transcript still has to go, but the file's presence is the
user's only visible proof that the app writes where the Shortcut reads. A user
who opened that folder and found only Recordings had no way to tell which end was
broken.

**15d. Three actions.** The callback is carried by x-success in the URL the app
opens, so the fourth action is gone, and with it the step where "Open" and "Open
URLs" sit adjacent in search under nearly identical names. The fallback for
x-success never firing already existed and is now backed by an explicit
baseline: the result file's modification date is captured at the moment the
bridge is invoked, and becoming active collects anything newer.

**15e. One control per sub step.** The row per action table is gone. Fourteen
numbered sub steps, each exactly one of a literal value, a toggle with its exact
label and state, a folder to navigate into, a variable to tap, or plain guidance.
A Copy button is attached to `.copyValue` and to nothing else, and that is
enforced in the model rather than in the view, which is what makes defect 1
structurally impossible rather than merely fixed. Each sub step carries a
checkbox that persists, so setup can be stopped and resumed. Every named field
also states its position, because field labels move between iOS versions. Two
things that look like faults and are not are stated outright: folder pickers grey
out files, and path fields are typed text whose target need not exist.

**15f. Prepare a manual test.** Writes the probe prompt and stops, without
invoking anything. Running the Shortcut by hand is the only way to tell a wrong
Shortcut from an app invoking it wrongly, and the user could not previously make
that distinction at all.

**15g. Five outcomes, no raw codes.** Shortcuts returns x-error both for a
missing shortcut and for one that exists and fails partway, so the old message,
which asserted the first, sent the user hunting in the wrong place. The result
file's modification date separates them. Each outcome names what to check next,
and a sixty second timeout produces a verdict rather than a spinner.

**15h. Migration, not rebuild.** Renaming the Shortcuts makes any earlier
verification meaningless, so it is cleared once for users who had got that far,
and a card names the three edits. A fresh install has nothing to migrate and
never sees it.

# Phase 15, what the adversarial audit found

Six independent auditors, every finding attacked by a separate skeptic before it
counted. Nineteen raised, two survived. Both were in the new code.

**Verify called a broken bridge working.** The success test was
`raw.uppercased().contains("OK")`, and ordinary conversational replies contain
those two letters: "Okay, here is what I found", "It looks like you want me to
use the file from action 1". That second one is defect 1 from the field report
verbatim, the exact failure Verify exists to catch, and it was being reported as
"Round trip worked" and then persisted as verified, so the wizard stopped
offering any remediation. The probe asks for exactly OK, so the reply must be
exactly OK: `isProbeSuccess` strips surrounding punctuation and quoting, which a
model will add, and rejects a sentence. My own test fixture had hidden the gap by
happening not to contain those letters.

**The x-success fallback was dead in the process it exists for.**
`collectIfResultWaiting` guarded on `isInFlight`, which reads `phase`, which
lives in memory and is never persisted. After the jetsam the fallback was written
for, `phase` is idle, so the guard failed before the durable check on the result
file's date was ever reached, and a finished answer was dropped in silence. It
now keys off `hasPersistedRequest`, which is the record on disk.

Also fixed while there: the recovery screen numbered every step twice, once in a
pill and once inside the step string.

# Phases 15 to 18

**Phase 15a and 15b.** `canOpenURL` answers false both for an app that is not
installed and for a scheme string that is wrong, and those are not the same
thing. Believing the second would tell a user to install what they are already
holding, so a negative is only trusted once some scheme has been seen to return
true on a real device. Until then the wizard treats "nothing detected" as
unknown and offers both with a "Don't see your app?" line. The wizard is four
pages and walks exactly one bridge per run.

**Phase 15k.** Hand off is three states, re-probed on appearance, and Generate
refuses an unverified bridge by name rather than failing somewhere in the middle
of a round trip. Note the interaction with the Phase 15 migration: renaming the
Shortcuts cleared every prior verification, so an existing user has to run
Verify once before Generate works. That is the intended consequence of a rename
that made the old bridge unreachable, not a regression.

**Phase 17.** The per recording model picker is gone. It duplicated Settings and
its only effect was to let a recording disagree with the setting that every
other flow reads.

**Phase 18.** Recognition succeeding and hearing nothing is now `empty`, its own
terminal state, distinct from `failed`. Only a failure leaves a gap marker in
the transcript: labelling silence "could not be transcribed" is what filled
History with junk. Discarding is deliberately asymmetric, because the two
mistakes cost different amounts. Sweeping a silent ten second recording costs
nothing; sweeping a ninety minute meeting whose recogniser hit a thermal defer
costs the meeting. So a failed segment is never swept, and silence over a minute
is kept because it usually means a microphone problem the user needs to see.

One deliberate exception, stated rather than buried: under three seconds
discards whatever the state, including failed, because 18b says "always discard,
whatever the state" and at that length there is no meeting to lose. E70 reads as
an absolute; this is the one place it is not, and it is one line to change if
that trade is wrong.

# Phase 18, the bug the audit caught after build 7 was already uploaded

**The mis-tap rule was deleting real meetings.** `duration < 3` fired whenever
duration was zero, and zero is the persisted default, not a measurement. The
chain, all of it ordinary: the app is force quit during segment one, so the
manifest still holds `duration: 0` because it is only rewritten at a segment
boundary, which with the default thirty minute segment is up to an hour away.
`reconcile` adopts the orphan file with duration zero. `resumeUnfinishedTranscriptions`
marks the session complete and sums the segments to zero. The file was killed
mid write so it has no moov atom, verification throws, the segment is marked
failed, and the measure step, which ran after verification, never happens. The
verdict then reads a thirty minute meeting as a stray tap and deletes the
directory. The retroactive sweep did the same at first launch, and the row's own
"tap to retry" label led the user straight into it.

Fixed three ways: an unmeasured duration is never swept, the duration is
measured before verification can throw so a recovered session stops looking like
a tap, and the tests now cover duration zero, which is the only case that
mattered and the one the original tests skipped.

**A silent segment blocked audio deletion.** `isFullyTranscribed` still required
`.done`, so once silence became its own state any recording with a quiet stretch
could never have its audio deleted. `.empty` counts as finished now, because
transcription ran and there was nothing to hear.

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
