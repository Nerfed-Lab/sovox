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
