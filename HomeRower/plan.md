# Plan: QMK-style home-row mods for the MacBook keyboard (prototype)

## Goal

A small macOS menu-bar app that gives the built-in keyboard the same home-row mods as the Voyager. It decides tap vs. hold the way QMK does: it **buffers** keys and decides from release order and timing, so fast rolls never drop letters or fire shortcuts.

**Prototype scope:** the 8 home-row mods, permissive hold, the opposite-hand rule, and the typing-speed rule. A settings window, layer holds, device filtering and robustness come in later milestones.

**Assumptions:** macOS input source stays **Dvorak**. The app works only with physical key codes, so the layout is handled by macOS. Karabiner-Elements is **not** running.

---

## Key map (physical keys → behavior)

macOS virtual key codes (`kVK_ANSI_*`). The letter you see is the Dvorak output when tapped.

| Physical | Key code | Tap (Dvorak) | Hold | Hand |
|---|---|---|---|---|
| A | 0 | a | Left Shift | L |
| S | 1 | o | Left Control | L |
| D | 2 | e | Left Option | L |
| F | 3 | u | Left Command | L |
| J | 38 | h | Right Command | R |
| K | 40 | t | Right Option | R |
| L | 37 | n | Right Control | R |
| ; | 41 | s | Right Shift | R |

Layer keys (milestone 7): G (5) and H (4) → Arrows; C (8) and ' (39) → Brkt/Num.

**Hand sets** (for the opposite-hand rule), by physical key:
- **Left:** Q W E R T A S D F G Z X C V B
- **Right:** Y U I O P [ H J K L ; ' N M , . /

---

## Settings (Config.swift)

Defaults below. From milestone 6 these live in `UserDefaults` and can be changed in the Settings window.

```swift
let tappingTerm: TimeInterval = 0.200   // hold if still down after this
let priorIdle: TimeInterval   = 0.150   // typing-speed rule: tap if pressed this soon after the last key
let quickTap: TimeInterval    = 0.175   // tap then hold within this = key repeat (milestone 9)
```

---

## The decision logic (the core)

Each home-row key is in one of three states: **idle**, **pending** (undecided, buffering) or **resolved** (tap or hold).

**When a home-row key goes down:**
1. **Typing-speed rule:** if less than `priorIdle` has passed since the last key event, resolve it as a **tap** right away and pass it through. No buffering.
2. Otherwise it becomes **pending**: swallow the event, record its time, start a `tappingTerm` timer and start buffering.

**While a key is pending, every incoming event is checked in order:**

| Event | Result |
|---|---|
| The pending key goes **up** | **Tap.** Send its key down and up, then replay the buffer. |
| A **same-hand** key goes down (opposite-hand rule) | **Tap.** Send the pending key's tap, then replay the buffer and this key. |
| An opposite-hand key goes down | Swallow it and add it to the buffer. |
| A buffered key goes **up**, and its down is also in the buffer (pressed and released inside the hold) | **Hold** (permissive hold). Send the modifier down, then replay the buffer. |
| The timer fires | **Hold.** Send the modifier down, then replay the buffer. |

**After resolving:**
- **Hold:** the modifier stays active until the physical key goes up, then the modifier is released.
- **Replay:** feed buffered events back through the same handler instead of posting them raw. That way a second home-row key in the buffer becomes pending itself, which allows stacking (Shift+Cmd and so on).

**The flags gotcha:** events that pass straight through the tap carry the *hardware* modifier state, which doesn't include your synthetic modifiers. While any home-row mod is held, add the active modifier flags (`.maskShift`, `.maskCommand` and so on) to **every** event you pass through or post.

---

## Architecture

```
HRMApp (SwiftUI MenuBarExtra)
 ├─ EventTap          CGEventTap setup, callback, re-enable on timeout
 ├─ HoldTapEngine     the state machine above (pure logic, no Apple APIs → unit-testable)
 ├─ Emitter           builds and posts CGEvents, applies active modifier flags, tags its own events
 ├─ Config            timings, key map, hand sets
 └─ (later) DeviceFilter   IOHIDManager: ignore events from the Voyager
```

Keep **HoldTapEngine** free of CoreGraphics. Give it simple inputs like `(keyCode, isDown, timestamp)` and have it return a list of actions (`.post(keyCode, down)`, `.modDown(flag)`, `.swallow`). That lets you unit-test every roll and shortcut sequence without touching the keyboard.

---

## Milestones

### 0. Project setup
- Xcode → new macOS **App**, SwiftUI, named e.g. `HomeRowMods`.
- **Turn off App Sandbox.** An active event tap needs it off.
- Set **Signing → Team** to your Apple ID. With ad-hoc signing, macOS treats every rebuild as a new app and resets its permissions.
- Set `LSUIElement = YES` in Info.plist (Application is agent) so there's no Dock icon by default.
- Menu bar: a `MenuBarExtra` with an icon (e.g. SF Symbol `keyboard`), an on/off toggle, Settings…, Show log, and Quit.

### 1. Pass-through tap with logging
- `CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: keyDown | keyUp | flagsChanged, callback:…)`
- Add it to the main run loop. In the callback, log the key code, down/up, `.keyboardEventAutorepeat` and the timestamp, then return the event unchanged.
- Handle `.tapDisabledByTimeout` / `.tapDisabledByUserInput` by calling `CGEvent.tapEnable(tap:enable: true)`.
- Permissions: `CGRequestListenEventAccess()` and `CGRequestPostEventAccess()`. On macOS 27, also check **Privacy & Security → Device Control and Data Access**.
- **Done when:** every key prints, and typing works normally.

### 2. One key, timeout only
- Physical A only: swallow its down. If it's released before `tappingTerm`, post "a" down/up. If the timer fires first, post Left Shift down, then release Shift when A goes up.
- Pass other keys through, adding `.maskShift` while Shift is held.
- Tag your own posted events with `.eventSourceUserData` (e.g. `0x484D52`) and return them untouched when they come back through the tap.
- **Done when:** a quick tap gives "a", and holding A then pressing S gives "S".

### 3. Buffer + permissive hold
- Move the logic into `HoldTapEngine` and add the buffer and the full pending table above.
- **Done when:** rolling A→S (A released first) gives "ao" every time, and A down, S tap, A up gives Shift+S, even within 200 ms.

### 4. Opposite-hand and typing-speed rules
- Add the hand sets and the `priorIdle` check.
- **Done when:** fast typing of words with same-hand rolls (e.g. "oe", "ue") never produces modifiers.

### 5. All eight home-row mods
- Add the full key map and modifier stacking through replay.
- **Done when:** Cmd+Shift combos work by holding F+A and tapping a right-hand key.

### 6. Settings window
**Window**
- Add a SwiftUI `Window("Home Row Mods Settings", id: "settings")` scene. A plain `Window` is more predictable than the `Settings` scene for a menu-bar-only app.
- The menu bar's **Settings…** item calls `openWindow(id: "settings")`.

**Controls** (`@AppStorage`, values in ms)

| Setting | Key | Default | Range |
|---|---|---|---|
| Tapping term | `tappingTermMs` | 200 | 100–500 |
| Typing-speed rule (prior idle) | `priorIdleMs` | 150 | 0–300 (0 = off) |
| Quick tap | `quickTapMs` | 175 | 0–300 (0 = off) |

- Use a `Slider` paired with a numeric `TextField` (or `Stepper`) for each, with a short line explaining what it does.
- Add a **Reset to defaults** button.
- Changes apply immediately. `HoldTapEngine` reads the current values from a shared settings object each time it starts a decision, so no restart is needed. Keep reading them off the main thread safe (copy into the engine, or read `UserDefaults` directly).

**Dock icon only while Settings is open**
- `LSUIElement = YES` keeps the app out of the Dock by default.
- When the settings window appears (`.onAppear`): `NSApp.setActivationPolicy(.regular)` then `NSApp.activate(ignoringOtherApps: true)`, so the Dock icon shows and the window comes to the front.
- When it closes (`.onDisappear`, or observe `NSWindow.willCloseNotification` for that window): `NSApp.setActivationPolicy(.accessory)`, which hides the Dock icon again. The menu-bar icon stays the whole time.
- Check the edge cases: closing with ⌘W, quitting with ⌘Q while it's open, and opening Settings twice (it should bring the existing window forward, not open a second one).

**Done when:** changing the tapping term changes typing feel right away, the Dock icon appears only while Settings is open, and the menu-bar icon is always there.

### 7. Layer holds
- Treat G/H (Arrows) and C/' (Num) as hold-taps whose "hold" makes a layer active instead of a modifier.
- While a layer is active, remap keys by physical key code (tables below). Same engine: a layer is a hold result.
- G and C use the opposite-hand rule. H and ' don't, because their layer keys are on the same hand.

### 8. Ignore the Voyager
- `IOHIDManager` matching keyboards. Register `IOHIDManagerRegisterInputValueCallback`.
- In the callback, look up the device's `kIOHIDProductKey`. If it's "Voyager", record "the last event for usage X came from the Voyager" with a timestamp.
- In the tap, if the matching key event came from the Voyager within a few ms, pass it through untouched.
- This matching is approximate. `.keyboardEventKeyboardType` may help as an extra hint.

### 9. Robustness
- **Panic switch:** the menu toggle, plus a key combo (e.g. Left Ctrl+Space+Esc held) that disables the app.
- `IsSecureEventInputEnabled()` → pass everything through while a password field is active.
- `NSWorkspace.didWakeNotification` → clear the engine state and release any held modifiers.
- Key repeat: ignore autorepeat events for pending keys. Add `quickTap` (tap then hold = repeat the letter).
- Launch at login: `SMAppService.mainApp.register()`.

---

## Layer tables (milestone 7)

Outputs are listed as the **physical key to post**, because macOS's Dvorak layout translates them. For example, to type `[` you post the QWERTY `-` key.

**Arrows (hold G or H)**

| Physical | Output |
|---|---|
| U | Cmd+Shift+[ (prev tab) → post Cmd+Shift+`-` |
| I | Up |
| O | Cmd+Shift+] (next tab) → post Cmd+Shift+`=` |
| [ | Page Up |
| A / S / D / F | Shift / Control / Option / Command |
| H | Cmd+Left |
| J / K / L | Left / Down / Right |
| ; | Cmd+Right |
| ' | Page Down |
| ` | Esc |

**Brkt/Num (hold C or ')**

| Physical | Types | Post |
|---|---|---|
| Q W E R T | < > ( ) + | Shift+W, Shift+E, Shift+9, Shift+0, Shift+] |
| A S D F G | [ ] { } - | `-`, `=`, Shift+`-`, Shift+`=`, `'` |
| Z X C V B | # $ % & = | Shift+3, Shift+4, Shift+5, Shift+7, `]` |
| Y | + | Shift+] |
| U I O / J K L / M , . | 7 8 9 / 4 5 6 / 1 2 3 | number keys |
| P | / | `[` |
| ; | * | Shift+8 |
| / | . | `e` |
| H | - | `'` |
| N | = | `]` |
| [ / ' | Volume up / down | media keys (`NX_KEYTYPE_SOUND_UP` / `_DOWN` system events) |
| 7 8 9 (number row) | Prev / Play / Next | media keys |
| ` | Esc | Esc |

---

## Testing

- **Unit tests on HoldTapEngine:** feed scripted sequences with timestamps and check the output.

| Sequence | Expected |
|---|---|
| A↓ A↑ (100 ms) | `a` |
| A↓ (250 ms) A↑ | Shift tap, no letter |
| A↓ J↓ A↑ J↑ (fast, after idle) | `ah` |
| A↓ J↓ J↑ A↑ | Shift+J |
| A↓ S↓ S↑ A↑ (same hand) | `ao` |
| X↓ X↑, then A↓ within 150 ms, J↓ J↑ A↑ | `xah` (typing-speed rule) |
| F↓ A↓ (hold) Q↓ Q↑ | Cmd+Shift+Q |

- **Live test:** type a paragraph quickly and compare it against the source text. Practise shortcuts (Cmd+C/V/Z, Cmd+Shift+T) in a text editor.
- **Safety while developing:** run from Xcode so ⌘. stops it, and keep the mouse-accessible Quit item. A bug that swallows every key will lock the keyboard until the app stops.

---

## Known limits of this approach

- **Password fields:** with Secure Input on, macOS hides keys from event taps, so plain typing (no mods) is all you'll have there.
- **Telling keyboards apart:** matching events to devices is approximate. Test it with both keyboards in use at the same time.
- **Lag:** a letter appears only once its key is decided. With the typing-speed rule, that's only noticeable on the first key after a pause, same as QMK.
