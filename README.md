# SpeakSel

A macOS menu-bar app: **highlight text in any app, press a hotkey, hear it in an ElevenLabs voice.**

Works in Terminal, browsers, Slack, Xcode, and other apps. Select text, press **⌃⌥R** (Control-Option-R) to read. Press **⌃⌥S** (Control-Option-S) to stop. The speak hotkey also stops if something is already playing.

## Install (no Xcode)

Requires macOS 14 or later.

1. Download **SpeakSel.zip** from the [latest GitHub release](https://github.com/dnikolsk/SpeakSel/releases/latest), or use a zip someone sent you.
2. Unzip and drag **SpeakSel.app** into **Applications**.
3. Open it (right-click → **Open** if macOS warns the first time).
4. Paste an [ElevenLabs API key](https://elevenlabs.io/app/settings/api-keys) in Settings.
5. Enable **Accessibility**: System Settings → Privacy & Security → Accessibility. If SpeakSel is missing, click **+**, choose `/Applications/SpeakSel.app`, turn the switch on, then quit SpeakSel from the menu bar and open it again. Use that Applications copy only — Xcode/DerivedData rows will not grant the installed app.

The API key needs **text_to_speech** and **voices_read** (or an unrestricted key). There is no ElevenLabs CLI.

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

## Privacy

- The API key never leaves the Keychain except as the `xi-api-key` header to `api.elevenlabs.io`.
- Selected text is sent to ElevenLabs to generate audio. It is not stored by SpeakSel.
- The app is not sandboxed, because a sandboxed agent cannot read other apps' selections. It is distributed as a notarized Developer ID build, not on the Mac App Store.

## Build from source

Xcode 15 or later.

1. Open `SpeakSel.xcodeproj`.
2. Select the **SpeakSel** scheme and **My Mac**.
3. Debug uses Apple Development signing. Release uses Developer ID (team `MHCFHR9BB2`) so it can be notarized. App Sandbox stays off on purpose.
4. Run. SpeakSel appears in the menu bar (waveform extra). There is no Dock icon.

```bash
xcodebuild -scheme SpeakSel -destination 'platform=macOS' test
```
