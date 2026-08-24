# Version naming

`MARKETING_VERSION` says what changed. `CURRENT_PROJECT_VERSION` only ever goes
up, and App Store Connect rejects a build number it has already seen.

Rule: **1.<highest phase completed>**.

The minor component is the build phase number, so 1.14 means phases 1 through 14
are in. A build that only fixes something keeps the phase it was cut from and
takes a new build number.

`AppVersion.phase` parses the phase back out of the version rather than tracking
it separately, so the two cannot drift apart.

Both live in the project, and `Info.plist` reads them through
`$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`. Never hardcode either
into the plist. That was done once and it silently ignored a build number bump,
so an upload was rejected as a duplicate.

The running version is shown in Settings, About, so the phone can always be
matched to a build.

# History

| Version | Build | What it was |
|---|---|---|
| 1.0 | 1 | Pre phase. First working build. Capture Notes. Background recording, segmenting, on device transcription, Live Activity, Shortcuts bridge, Outlook draft. |
| 1.0 | 2 | Pre phase. Fixed OSStatus -50 on a real device. `allowBluetoothA2DP` and `defaultToSpeaker` are invalid with the `.record` category and the fallback carried A2DP too, so recording could not start at all. Replaced with a four rung ladder. |
| 1.0 | 3 | Pre phase. Fixed the Files folder name. Every instruction said "On My iPhone, Capture" while iOS names the folder from CFBundleDisplayName. Now derived at runtime. |
| 1.14 | 4 | **Sovox.** Renamed throughout. Transcription rebuilt as a long lived serial actor with a finalisation gate and a thermal guard. New theme with light and dark. Titles and a prefixed email subject. Custom actions. Conversation type. Audio only deletion. Ask tab. To-dos tab. Setup wizard with a bridge verifier. Prompt injection hardening. |

Builds 1 to 3 predate the phase plan and stay at 1.0.

# What to Test, paste into App Store Connect for build 4

Sovox is the old Capture, renamed. Your existing bridge Shortcuts will not work
until you rebuild them: the Shortcut names, both file names and the callback URL
all changed. Settings, Setup walks through it with a Copy button per value and a
Verify that tells you which step is wrong.

Worth exercising:
- Record, lock the phone, use other apps, come back. Stop from the Lock Screen.
- Settings, Self Test, Run smoke test.
- Generate notes on a recording, then try the Ask tab and the To-dos tab.
- Delete audio only on a finished recording and confirm the transcript survives.

# 1.15, build 5

Phase 15, bridge setup corrected after a real attempt on device failed.

- Shortcut names are letters only: SovoxChatGPT, SovoxClaude
- The bridge is three actions. Delete the fourth if you already built it
- sovox-pending.txt and sovox-result.txt exist from first launch and stay there
- The wizard is one control per sub step, with a checkbox on each and Copy
  buttons only on values you must reproduce
- Prepare a manual test, run the Shortcut yourself, then Check result
- Verify tells five failures apart instead of always blaming the name

# What to Test, paste into App Store Connect for build 5

Your existing bridge Shortcut will not run: the names changed. A card on first
launch names the three edits, or Settings, Setup rebuilds it from scratch.

Worth exercising:
- Settings, Setup, and follow the ticked sub steps end to end
- Prepare a manual test, run SovoxClaude by hand in Shortcuts, tap Check result
- Verify, and confirm the failure it reports matches what is actually wrong
- Open Files, On My iPhone, Sovox, and confirm both txt files are there before
  and after a Verify run

# 1.19, build 7

Phases 15 to 18. Phase 19 is not built: the capability probe reports Tier 3 on
an iPhone 14 Pro, and a re-probe is needed now that Hindi dictation is
installed.

- The wizard asks which model app you have, and walks you through that one only
- Settings, Hand off shows whether each model is installed and set up, and will
  not let you select one that is not
- Generate says so plainly when the selected bridge is not set up
- Transcript Ready no longer duplicates the model choice
- Recordings that caught nothing are discarded automatically. Anything with a
  failed segment, or any silence over a minute, is kept

# What to Test, paste into App Store Connect for build 7

Worth exercising:
- Settings, Setup. It should offer only the model app you actually have
- Settings, Hand off. Selecting a model you have not set up should not be
  possible, and Set up should open the walkthrough
- Tap the Action Button twice quickly to make a one second recording. It should
  vanish with a brief note rather than leaving a row
- Record a minute of silence. It should stay, labelled No speech detected
- Settings, Diagnostics, Speech capability, then send me the report

# 1.19, build 9

Fixes recordings coming back as No speech detected.

- Languages that need a network are shown as Not usable and cannot be selected
- A segment that transcribes to nothing is retried once on a language known to
  work on this device
- The empty label names the language that produced it
- The smoke test uses the language a real recording would use, reports the peak
  input level, and tells you whether the microphone or the recogniser is at fault

# What to Test, paste into App Store Connect for build 9

- Settings, Transcription, Language. Check which section your language sits in
- Settings, Self Test, Run smoke test, and speak for the full minute
- Record thirty seconds of speech and confirm a transcript appears

# 1.19, build 10

Phase 19, dual language transcription. The project is now complete against every
phase in the spec.

- Settings, Transcription: primary language, Also transcribe in, secondary
  language. Off gives exactly the behaviour and the prompt you had before
- The same audio is transcribed twice and both readings are handed to the model,
  interleaved by pause, for it to reconcile
- A language that needs a network can never be selected
- Recordings over 80,000 merged characters resolve segment by segment, then
  synthesise once over the whole conversation
- Settings, Developer, Merge preview shows the windows and the real sizes

# What to Test, paste into App Store Connect for build 10

- Settings, Transcription. Turn on Also transcribe in and check which section
  Hindi sits in
- Record two minutes switching between English and Hindi, then Generate
- Settings, Developer, Merge preview to see the windows and both readings
- With the toggle off, everything should behave exactly as it did in build 9
