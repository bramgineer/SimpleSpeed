# SimpleSpeed

SimpleSpeed is a minimal SwiftUI app that recreates a **Simple Reaction Time / Go-No-Go** listening task. It teaches users to recognize a target tone (one of the white keys between C4–B4) and tap when they hear it inside a 16-note stream. The app ships with an in-house sine-wave synth (`SineEngine`) so it does not rely on sample files or external audio frameworks.

## Gameplay At A Glance
- Tap **Start** to preview the target tone for 1.5 s.
- Listen to 16 evenly spaced notes (`interOnsetMs = 2250`), then tap **Heard it!** whenever the target reappears.
- The response window closes 1.75 s after each tone; taps outside the window are ignored.
- Results show hits, misses, false alarms, correct rejections, and the computed signal-detection score **d′**.

## Key Features
- **Fixed or Random Target** – Lock the target pitch or let the app draw a random white-key MIDI value each run.
- **Immediate Repeat Guard** – Optionally prevent back-to-back identical tones (targets or distractors) for cleaner perception experiments.
- **Deterministic Tone Bank** – `SineEngine` generates and caches 1 s sine buffers for MIDI 60–71 at runtime.
- **Session Summaries** – The `QuizVM` calculates hit/miss/FA/CR counts and uses a log-linear correction before computing d′.
- **SwiftUI-first** – All state lives in `QuizVM` with a single screen (`ContentView`) that swaps between idle, showing target, running, and finished states.

## Requirements
- macOS with Xcode 16 (or newer) and the iOS 18.5 SDK (deployment target is set to **iOS 18.5** in the project settings).
- An iOS device or simulator running iOS 18.5+ with audio output. (Headphones recommended for precise listening.)

## Getting Started
1. `git clone` or copy this project to your machine.
2. Open `SimpleSpeed.xcodeproj` in Xcode.
3. Choose the **SimpleSpeed** scheme and select an iPhone simulator/device running iOS 18.5 or higher.
4. Press **Run** (`⌘R`). You should hear the synthesized tones automatically; no additional assets are required.

### Command-line build
```bash
xcodebuild \
  -project SimpleSpeed.xcodeproj \
  -scheme SimpleSpeed \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

## How To Play
1. Read the short instructions on the Idle screen.
2. Decide whether to keep the target fixed (tap a row in the note list) or enable **Random target each run**.
3. Choose whether to **Allow same pitch twice in a row**. Turning this off enforces spacing between identical tones.
4. Tap **Start**. Watch the target name during the 1.5 s preview and listen carefully during the 16-note stream.
5. Tap **Heard it!** whenever the target tone returns. Taps are only collected inside the 1.75 s response window after each onset.
6. Review the performance metrics and either **Run Again** (keeps the previous configuration) or **Reset** to go back to Idle.

## Customizing The Session
All tunable parameters live in `SimpleSpeed/ContentView.swift` inside `QuizVM`:

| Property | Default | Purpose |
| --- | --- | --- |
| `interOnsetMs` | 2250 | Gap between note onsets (ms). |
| `responseWindowMs` | 1750 | How long taps are accepted after each note. |
| `targetLabelMs` | 1500 | Duration of the pre-run target preview. |
| `totalTrials` | 16 | Notes per run. |
| `numTargets` | 4 | Number of target iterations inside the run. |
| `noteDurationSec` | 1.0 | Playback duration scheduled in the audio engine. |

Feel free to expose these values via new UI controls or keep them hard-coded for experimental consistency.

## Audio Notes
- `SineEngine` keeps an `AVAudioEngine` alive for the entire session and pre-renders a 1 s buffer per MIDI pitch.
- Each buffer applies 10 ms fade in/out and uses a conservative gain (`0.2`) to avoid clipping when multiple notes overlap.
- If you hear clicks, ensure the simulator/device is not throttled and consider extending `interOnsetMs` to give the engine more headroom.

## Testing
- **Unit tests**: `⌘U` in Xcode or run `xcodebuild test` with the `SimpleSpeedTests` target.
- **UI tests**: `SimpleSpeedUITests` currently contains the template scaffold; extend it with interactions for the Idle → Finished flow.
- Suggested quick regression: run the app, toggle each option, and complete a session to ensure scoring still updates.

## Project Layout
- `SimpleSpeed/ContentView.swift` – SwiftUI UI + `QuizVM` session logic.
- `SimpleSpeed/SineEngine.swift` – Lightweight sine-wave audio generator.
- `SimpleSpeedApp.swift` – Entry point that launches `ContentView`.
- `SimpleSpeedTests` / `SimpleSpeedUITests` – XCTest targets (templates).

## Troubleshooting
- **No audio**: Make sure the simulator volume is up and not muted. On device, confirm the mute switch is off.
- **Playback stutters**: Close other audio-heavy apps. The engine pre-renders buffers, so stutters usually indicate system load.
- **Tone selection disabled**: When **Random target each run** is toggled on, manual target selection is intentionally disabled.

Have ideas for additional metrics, different tone sets, or more adaptive pacing? Open an issue or experiment directly in `QuizVM`—the code is intentionally small and approachable.
