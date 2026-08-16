# Reproduction manual — Glasses2Car

Complete guide for reproducing the environment, running the app and testing it
with physical Ray-Ban Meta glasses. Written from a real setup (macOS + iPhone +
Ray-Ban Meta Wayfarer, firmware 127, Meta Wearables DAT SDK 0.8.0).

## 1. What the app does

- Queries the [Conect2AI platform API](https://dashboard.conect2ai.dca.ufrn.br:8000/docs)
  (OAuth2 login + Smart Glass endpoints) and **speaks the answers** through the
  glasses (driving behavior, CO₂ emissions, trip summary), in English or pt-BR;
- Hands-free voice trigger: wake word **"Hey Conecta"** → the app answers
  "Yes?" → command ("how am I driving?", "how am I emitting?", "trip summary").
  Listening starts automatically after login. ("Hey Meta" is reserved by Meta —
  the glasses' native wake-word engine is closed to third parties, so ours runs
  on the iPhone over HFP audio.) Photo capture on the glasses and on-screen
  buttons are alternative triggers;
- Lens dashboard prototype (`MWDATDisplay`) ready for the Meta Ray-Ban Display
  model (audio-only glasses have no display).

## 2. Prerequisites

| Item | Details |
|---|---|
| Mac | Full Xcode installed (Command Line Tools alone are not enough) + iOS platform (`xcodebuild -downloadPlatform iOS`) |
| XcodeGen | `brew install xcodegen` |
| iPhone | iOS 16+, USB cable, Developer Mode enabled |
| Apple account | A free account works (the installed app expires after 7 days and must be reinstalled) |
| Meta account | The same account signed into the **Meta AI** app on the iPhone |
| Glasses | Ray-Ban Meta paired in Meta AI, firmware **125+** |
| Meta AI app | v272+ with **Developer Mode** enabled (Settings → App Info → tap "App version" 5×) |
| Platform account | Valid username/password for the Conect2AI API |

## 3. Meta platform — detailed walkthrough

### 3.1 Prepare the Meta AI app and the glasses (on the iPhone)

1. Install **Meta AI** (App Store) and sign in with your Meta account —
   **remember which account**: the same one must be used on the developer site;
2. Pair the glasses in Meta AI (Devices tab, glasses icon);
3. Check the firmware: Devices → your glasses → gear icon → **General →
   About → Version**. It must be **125 or newer** (tested with 127). Update
   from that screen if needed;
4. Enable **Developer Mode**: Meta AI → **Settings → App Info** → tap
   **"App version" 5 times** → the **Developer Mode** toggle appears → enable
   and confirm. Without this, unpublished apps cannot register.

### 3.2 Wearables Developer Center (in the browser)

Site: **https://wearables.developer.meta.com**

1. Sign in with the **same Meta account used in Meta AI**. Tip from Meta's own
   docs: if you are signed into `developers.meta.com` (Meta Horizon), **sign
   out there first** — the domains conflict and the link fails;
2. On first use the site asks you to create an **organization** (free-form
   name, e.g. "Conect2AI UFRN");
3. On the **Projects** page, click **"New project"**. A dialog asks for:
   - **Name**: e.g. `Conect2AI Glasses`
   - **Description** (optional): visible only to your team
   - Click **"Create project"**;
4. Inside the project, open the **iOS** tab → **"Mobile app configuration"**
   section. Fill in the three fields:
   - **Team ID**: your Apple team ID (see Section 4 below — shown in Xcode
     under Signing & Capabilities; format example: `XXXXXXXXXX`)
   - **Bundle ID**: `br.ufrn.conect2ai.RayBanTripApp` — exactly this; Meta
     **rejects hyphens** in iOS bundle IDs
   - **Universal link**: required field, but in Developer Mode the return
     trip uses the app's URL scheme — fill in a plausible address under a
     domain you control: `https://conect2ai.dca.ufrn.br/glasses`
   - **Save changes**;
5. Still in the project, **Permissions** section ("Add rationales for the
   device permissions your app requires") → enable **Camera access** and write
   the rationale (only Meta's reviewer sees it). Example used:
   > Research app (Conecta.ai/UFRN): streams the glasses camera and
   > captures photos so drivers can hands-free trigger trip summaries
   > from our research API. No media is shared publicly.
6. Note down the app's **Meta App ID** and **Client Token** (the platform
   shows both as a ready-to-copy plist/manifest snippet — format example:
   numeric `MetaAppID` and `ClientToken` in the `AR|<app id>|<hash>`
   pattern). They go into your `Local.xcconfig`.

> Notes: Team ID, Universal link and permissions can be edited later (if the
> app was already registered in Meta AI, unregister and register again after
> changes). The **Bundle ID** should not change. In Developer Mode, **only 1
> third-party app** can be registered at a time in Meta AI.

## 4. Per-developer configuration (Apple + project)

1. **Xcode**: Settings → Accounts → "+" → Apple ID (a free account works) →
   select the team → **Manage Certificates…** → "+" → **Apple Development**.
   The **Team ID** appears next to the team name (or under Signing &
   Capabilities of any project);
2. **Local credentials**: `cp Local.xcconfig.example Local.xcconfig` and fill
   in `DEVELOPMENT_TEAM`, `META_APP_ID` and `CLIENT_TOKEN` with your values
   (the file stays out of git);
3. Generate and open the project:

   ```bash
   xcodegen generate
   open RayBanTripApp.xcodeproj
   ```

## 5. Automated tests (no hardware)

```bash
make test-core   # API client tests (runs even without Xcode, CLT only)
make test-ios    # Simulator: Mock Device Kit + lens dashboard tests
```

The Mock Device Kit simulates the glasses entirely (pairing, permissions,
camera). To run the app in the simulator without hardware: launch argument
`--mock-glasses` (Scheme → Run → Arguments).

## 6. Running on iPhone + glasses

1. iPhone on the cable → select it as destination in Xcode → Run
   (or: `xcodebuild build -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates`
   and install with `xcrun devicectl device install app ...`);
2. First time: the iPhone asks for **Developer Mode** (Settings → Privacy &
   Security) and, sometimes, to trust the certificate (Settings → General →
   VPN & Device Management);
3. In the app, in this order:
   1. **Register with Meta AI** → confirm in Meta AI → it returns on its own;
   2. **Log in** with the platform credentials;
   3. Voice listening starts automatically (first time asks for microphone +
      speech permissions). Say **"Hey Conecta"** → hear "Yes?" → say
      **"how am I driving?"** (or all at once: "Hey Conecta, trip summary").
      Command window: ~10 s; with no command it goes back to waiting for the
      wake word. The Voice toggle disables/re-enables listening;
   4. Optional camera flow: **Connect and stream** → first time confirms the
      camera permission in Meta AI (glasses must be **worn, unfolded and
      connected**) → **Capture photo** → spoken trip summary.

## 7. Known issues and fixes (all hit in practice)

| Symptom | Cause | Fix |
|---|---|---|
| `xcodebuild requires Xcode` | Only CLT installed | Install Xcode; `sudo xcode-select -s /Applications/Xcode.app` |
| Simulator "Unavailable: runtime profile not found" | Runtime not downloaded or duplicated | `xcodebuild -downloadPlatform iOS`; delete duplicates via `xcrun simctl runtime list/delete` |
| `no such module 'MetaWearablesDAT'` | The docs use an umbrella import that does not exist in package 0.8.0 | `import MWDATCore` + `MWDATMockDevice`/`MWDATCamera`/`MWDATDisplay` |
| Test failure: "does not have an Info.plist" | Test target without plist | `GENERATE_INFOPLIST_FILE: YES` (already in project.yml) |
| CodeSign fails right after creating the certificate | Keychain still settling | Run the build again |
| **`noEligibleDevice` when connecting** | Glasses off the face/folded/asleep, or the automatic selector resolving late | Glasses on the face + connected in Meta AI; the app already uses `SpecificDeviceSelector` when it sees a device with `linkState == .connected` |
| API decoding error with a real trip | `location` carries `null` GPS points before the first fix | Model already accepts `[[Double?]]` |
| Voice audio sounds low quality | HFP (glasses mic) is 8 kHz mono by protocol | Expected; narration without active listening uses A2DP (full quality) |
| App stops opening after days | Free Apple account expires in 7 days | Reinstall from the Mac |
| Request GPS frozen at one coordinate | While-Using permission stops updating in background | App uses the `location` background mode + `allowsBackgroundLocationUpdates` (fixed after the first field sessions) |
| Wake word misheard | 8 kHz HFP audio degrades ASR | Token matching is deliberately loose (en-US hears "Conecta" as *connected/connector*; "emitting" as *meeting/mission* — all accepted) |

### Debugging with the iPhone on the cable

```bash
xcrun devicectl list devices
xcrun devicectl device process launch --console --terminate-existing \
  --device <UDID> br.ufrn.conect2ai.RayBanTripApp
```

The app prints `MWDAT ...` lines (registration state, devices with
`linkState`/`compatibility`, permissions, stream) and `VOICE ...` lines
(listening pipeline, live transcripts).

## 8. Platform limitations (Meta, as of today)

- **App Store publishing is not allowed** (the SDK uses ExternalAccessory);
  distribution to testers = Developer Center release channels
  (+ TestFlight/Ad Hoc, which require a paid Apple account);
- In Developer Mode, **only 1 third-party app** registered at a time in Meta AI;
- Custom "Hey Meta" phrases are **not available** to third parties in SDK 0.8 —
  the app's voice command uses the glasses microphone (HFP) +
  `SFSpeechRecognizer`, with the app in the foreground or background (audio
  background mode);
- DAT sessions require the app running on the iPhone (the glasses are a
  peripheral; they do not run apps);
- Lens widgets only on the **Meta Ray-Ban Display** model (`MWDATDisplay`).

## 9. Sources

- Docs: https://wearables.developer.meta.com/docs/ (iOS MDK testing at
  `/docs/develop/dat/testing-mdk-ios/`);
- Meta's documentation MCP server (no auth):
  `https://mcp.developer.meta.com/wearables`, tool `search_dat_docs`;
- SDK: https://github.com/facebook/meta-wearables-dat-ios (0.8.0);
- Conect2AI API: https://dashboard.conect2ai.dca.ufrn.br:8000/docs
