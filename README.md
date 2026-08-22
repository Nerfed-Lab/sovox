# Sovox

A local voice recorder for meetings, for iOS 26.

It records in the background, transcribes on device, hands the transcript to
your own ChatGPT or Claude app through a Shortcut you build once, and opens a
prefilled Outlook draft. You press Send.

**Nothing leaves the phone except through that hand off, which you trigger.**
There is no networking code in the app at all: no URLSession, no analytics, no
crash reporting, no SDKs, no package dependencies. App Transport Security is
configured to refuse every outbound connection. No EventKit, no Contacts, no App
Groups, no push.

## What it does

- **Records through interruptions.** AVAudioEngine with a tap, gapless segment
  rollover, and recovery from phone calls, Bluetooth route changes and media
  services resets. Survives backgrounding, a locked screen and three hour
  meetings.
- **Transcribes while it records.** A long lived serial actor at `.utility`
  transcribes each segment as it closes, with a thermal guard that defers
  transcription and never recording.
- **Live Activity.** Elapsed time on the Lock Screen and in the Dynamic Island,
  with Pause and Stop that work without unlocking.
- **Hands off to your AI app.** A file in, file out bridge through Shortcuts.
  The app never talks to any model directly.
- **Ask.** Question several transcripts at once, with every claim attributed to
  its source recording.
- **To-dos.** Proposed from transcripts, applied only after you approve each one.

## Requirements

Xcode 26, iOS 26. Zero dependencies, so there is nothing to install.

## Building it

1. Open `Sovox.xcodeproj`
2. Set your team on the **Sovox** and **SovoxWidget** targets under Signing and
   Capabilities
3. Change both bundle identifiers to your own. The widget must be the app
   identifier plus exactly one suffix
4. Run

`./verify.sh` runs the source level checks: parse, plists, project integrity,
and the invariants that cannot be expressed as unit tests.

## Design notes

Three constraints shaped most of this:

**The audio thread always wins.** Transcription is compute over a closed file
and must never contend with a real time capture path, so it is strictly serial,
runs at `.utility`, and backs off when the device gets warm.

**A silent failure is worse than a loud one.** Every transcription error is
captured, persisted with its segment and shown with a reason. Stitching inserts
`[segment N could not be transcribed]` rather than quietly returning a shorter
transcript. The Ask tab refuses above 100,000 characters instead of letting the
model truncate and answer confidently from a partial context.

**Free user text is untrusted.** Custom actions are the only place it enters the
prompt. It is sanitised on save, wrapped in markers, and followed by a precedence
paragraph. Nine adversarial cases are unit tested against the assembled prompt,
and a debug only harness runs four of them through the real bridge.

## Layout

```
Sovox/            app target
SovoxShared/      compiled into both the app and the widget
SovoxWidget/      Live Activity, Dynamic Island, Control Centre control
SovoxTests/       209 tests
```

See `AUDIT.md` for the self audit and the list of APIs that are not compiler
verified, `RELEASES.md` for version history, and `TESTFLIGHT.md` for
distribution.

## Licence

No licence granted. All rights reserved.
