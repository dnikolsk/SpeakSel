# SpeakSel

A macOS menu-bar app: **highlight text in any app, press a hotkey, hear it in an ElevenLabs voice.**

Works in Terminal, browsers, Slack, Xcode, and other apps. Select text, press **⌃⌥R** (Control-Option-R) to read. Press **⌃⌥S** (Control-Option-S) to stop. The speak hotkey also stops if something is already playing.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later
- An [ElevenLabs](https://elevenlabs.io) account and API key

## Build and run

1. Open `SpeakSel.xcodeproj` in Xcode on your Mac.
2. Select the **SpeakSel** scheme and **My Mac**.
3. In **Signing & Capabilities**, choose your Team. App Sandbox is off on purpose so SpeakSel can read selected text from other apps.
4. Press Run. SpeakSel appears in the menu bar (speaker icon). There is no Dock icon.

## First-run setup

1. Paste your ElevenLabs API key into Settings. Keys are stored in the Keychain, not in the project.
   Get one at [elevenlabs.io/app/settings/api-keys](https://elevenlabs.io/app/settings/api-keys).
2. Grant **Accessibility** when macOS asks, or click **Open Accessibility settings** and enable SpeakSel.
   Without this, macOS will not let the app read a selection in Terminal, Chrome, or other apps.
   Xcode debug builds live in DerivedData, so macOS may ask you to enable SpeakSel again after a clean rebuild. That settles once you copy a Release build to `/Applications`.
3. Click **Refresh voices**, pick a voice, then **Test voice**.

## Use

| Action | How |
| --- | --- |
| Read the current selection | Highlight text, press **⌃⌥R** |
| Stop | Press **⌃⌥S**, or **⌃⌥R** again, or **Stop** in the menu |
| Change the hotkeys | Settings → Speak or Stop → Change, then press a shortcut that includes a modifier |
| Change voice / speed / model | Settings. Flash is fastest; Multilingual v2 is highest quality |

Long selections are split on sentence boundaries so playback can start before the whole article is synthesized.

## How selection works

1. Accessibility `AXSelectedText` (native text views, many apps).
2. If that is empty, SpeakSel briefly sends **⌘C**, reads the clipboard, then restores whatever was there before.

Password fields are skipped.

## Tests

In Xcode: **Product → Test**, or:

```bash
xcodebuild -scheme SpeakSel -destination 'platform=macOS' test
```

## Privacy

- The API key never leaves the Keychain except as the `xi-api-key` header to `api.elevenlabs.io`.
- Selected text is sent to ElevenLabs to generate audio. It is not stored by SpeakSel.
- The app is not sandboxed, because a sandboxed agent cannot read other apps' selections.
