# TestFlight internal testing

No cable at any point. No App Store listing, no review, nobody sees it but the
people you invite. Builds last 90 days, not the 7 days free provisioning gives.

## What it costs

Apple Developer Program, 99 USD a year. Enrolment is at developer.apple.com and
can take anywhere from minutes to a couple of days if Apple asks for ID.

## Before you pay, know these two things

**The app is now called Sovox Notes.** Use exactly that as the App Store
Connect app name. The Home Screen name is Sovox Notes too, and Siri accepts
both "Start Sovox Notes" and the shorter "Start capture", because Info.plist
declares Sovox as an alternative app name.

**The bundle identifier must be globally unique.** The project uses
`com.rishabh.capturenotes`, with `com.rishabh.capturenotes.CaptureWidget` for the
extension. If App Store Connect says it is taken, change both together and keep
the widget as the app ID plus exactly one suffix.

## Steps

Your team has no registered devices, and Apple will not issue a Development
provisioning profile to a team with none. Both a device build and an archive ask
for one, which is why Xcode could not register the identifiers and why the bundle
ID never appeared in App Store Connect. Distribution profiles have no such
requirement, so the whole flow below is manual distribution signing and never
touches a device.

### 1. Register the two App IDs

developer.apple.com/account, Certificates Identifiers and Profiles, Identifiers,
the blue `+`.

- App IDs, Continue, App, Continue.
- Description `Sovox Notes`, Bundle ID **Explicit**, `com.rishabh.capturenotes`.
- Capabilities: leave everything off. This app needs none.
- Continue, Register.

Repeat for the widget: Description `Sovox Notes Widget`, Bundle ID **Explicit**,
`com.rishabh.capturenotes.CaptureWidget`, no capabilities.

The bundle ID appears in App Store Connect the moment this is done.

### 2. Archive and upload

```
./upload-testflight.sh
```

That is the whole of it. The script archives unsigned, then exports with
`-allowProvisioningUpdates`, which makes Xcode create the Apple Distribution
certificate and the App Store provisioning profiles on demand and sign with
them. None of that needs a registered device, so no manual certificate or
profile creation is required.

Do not use Product, Archive from the Xcode GUI on a team with no devices. The
GUI archive signs with Apple Development first, which needs a device, and it
fails before it gets anywhere near distribution signing.

`./set-signing.py manual` exists for the case where you would rather pin
specific profiles by name, but it is not needed for the flow above.

### 3. Create the App Store Connect record

appstoreconnect.apple.com, My Apps, `+`, New App.

- Platform iOS, Name `Sovox Notes`, Primary Language English

If App Store Connect says the name is already used, that is only the record
name and it is unique across the whole App Store. It is not tied to the bundle
ID or to what the phone shows. Pick any free variant, for example
`Sovox Notes RS`, and change nothing in the project. The Home Screen name
comes from CFBundleDisplayName and stays `Sovox Notes` regardless.

- Bundle ID `com.rishabh.capturenotes`, now present because of step 1
- SKU `capturenotes-1`, User Access Full Access

### 4. Add yourself as an internal tester

Processing email in five to fifteen minutes. App Store Connect, Sovox Notes,
TestFlight tab, Internal Testing, add yourself, attach the build. Then install
from the TestFlight app on the phone with the same Apple ID.

## App Privacy questionnaire

App Store Connect asks this once, under your app, App Privacy. The honest answer
for this app is **Data Not Collected** across the board. Nothing is transmitted,
there is no networking code, and `PrivacyInfo.xcprivacy` already declares the
three required reason API categories the app touches: file timestamp, disk space
and user defaults.

## Every later build

Bump `CURRENT_PROJECT_VERSION` in the Sovox target, an upload with a build
number App Store Connect has already seen is rejected. `MARKETING_VERSION` only
needs to change when you want the version string to change.

## What is already done in this project

- `PrivacyInfo.xcprivacy` with the three required reason declarations.
- `CFBundleIconName` set, which is the ITMS-90713 rejection.
- `ITSAppUsesNonExemptEncryption` false, which skips the export compliance prompt.
- A 1024 icon with no alpha channel, which is the ITMS-90717 rejection.
- The widget nested correctly, no test bundle embedded, `SKIP_INSTALL` set on the
  extension.
- An unsigned archive was produced and its merged Info.plist and bundle layout
  were checked against the above. The only thing not verifiable here is signing,
  which needs your account.
