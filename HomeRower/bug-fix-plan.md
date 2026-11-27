# HomeRower Bug-Fix Plan

## Objective

Fix the permission-removal failure so HomeRower reliably returns to its
permission screen when its required macOS permission is disabled or its
entry is removed from **System Settings → Privacy & Security**.

The higher-priority safety requirement is that a failed or unresponsive
event tap must not leave keyboard input blocked. Normal keyboard input
must be restored even if permission-state detection or UI recovery
fails.

This plan is based on the supplied `EventTap` implementation and the
related SwiftUI lifecycle code. The exact behavior of macOS after
deleting a TCC entry still needs to be verified; the current code
suggests a failure path but does not prove which macOS API behavior
causes it.

## Current findings

### 1. Permission recovery relies on preflight checks

`hasRequiredAccess` checks `AXIsProcessTrusted()` and, in one case,
`CGPreflightListenEventAccess()`. `accessMonitor()` polls this result
once per second.

When either check reports that access is gone, `accessWasRevoked()`
stops the tap and attempts to start again. If that attempt fails, it
calls `waitForPermission()`.

The weakness is that these permission checks are not a direct health
check of the already-installed event tap. If macOS invalidates or
disables the tap while the preflight APIs continue to report access, the
monitor will not initiate recovery.

**Required fix:** Treat permission state, event-tap existence, and
event-tap enabled state as separate signals. Record and test all three
rather than assuming one proves the others.

### 2. A disabled tap can be re-enabled without sufficient diagnosis

In `handle()`, both `.tapDisabledByTimeout` and
`.tapDisabledByUserInput` enter the same branch. If `hasRequiredAccess`
returns `true`, the code immediately re-enables the tap.

That may be appropriate for a recoverable timeout, but it is not a safe
universal response to every disabled-tap notification. The code should
distinguish recoverable tap timeouts from permission-loss or other
failure conditions, using documented behavior and observed diagnostics.

**Required fix:** Add a deliberate recovery policy. Do not blindly
re-enable the tap when its state or permission status is uncertain.

### 3. The watchdog exists but is not integrated

`TapWatchdog` is defined, but the supplied `EventTap` code does not
create one, register the tap with it, send heartbeats, or react to
`takeDidTrip()`.

As a result, the watchdog currently provides no protection. Since the
event tap callback executes on the main run loop, a blocked main thread
can prevent the callback from returning and interfere with keyboard
input.

**Required fix:** Integrate the watchdog into the tap lifecycle and
verify that it can disable the tap from its background queue when the
main thread stops responding.

### 4. The UI already has a permission-screen state

`RootView` displays `PermissionView` when
`eventTap.status == .waitingForPermission`. The menu-bar UI opens the
permission window when it observes a transition to that state.

The UI therefore appears to have the necessary destination state. The
primary investigation should focus on why the event-tap lifecycle does
not reliably transition into it. Also verify that the window is
presented when recovery is initiated outside the normal menu
interaction.

## Implementation plan

### Phase 1 --- Make input recovery the first priority

-   [ ] Define a single, idempotent failure path that disables the event
    tap, removes its run-loop source, resets the hold-tap engine, and
    releases any modifiers emitted by HomeRower.
-   [ ] Ensure cleanup is safe when called repeatedly or while a tap
    callback is in progress.
-   [ ] Ensure that a failed tap is not left installed in a state where
    it can continue intercepting keyboard events.
-   [ ] Keep the cleanup path independent of successful
    permission-screen presentation.
-   [ ] Review `stop()` and `resetEngine()` for reentrancy and lifecycle
    races.

**Acceptance criteria**

-   When the tap is stopped or fails, ordinary keyboard input reaches
    other applications.
-   Any modifiers held or synthesized by HomeRower are released.
-   Repeated recovery attempts do not leave duplicate run-loop sources
    or event taps.

### Phase 2 --- Integrate and test `TapWatchdog`

-   [ ] Add a `TapWatchdog` instance to `EventTap`.
-   [ ] Call `watch(tap)` after successfully installing the tap.
-   [ ] Call `watch(nil)` whenever the tap is stopped or removed.
-   [ ] Send heartbeats regularly from the main thread while the app is
    responsive. Ensure the heartbeat mechanism itself does not depend on
    the event-tap callback.
-   [ ] Detect `takeDidTrip()` on the main thread and reconcile the
    app's state with the fact that the watchdog disabled the tap.
-   [ ] After a watchdog trip, do not automatically assume the tap is
    healthy merely because the app's status still says `.running`.
-   [ ] Verify that watchdog state cannot accidentally refer to an old
    tap after a stop/restart cycle.

**Acceptance criteria**

-   Deliberately block the main thread in a test build for longer than
    the watchdog threshold.
-   Confirm the watchdog disables the tap from its background queue.
-   Confirm keyboard input becomes available again.
-   Confirm the app exits the stale `.running` state and can recover
    after the main thread resumes.

### Phase 3 --- Improve disabled-tap handling

-   [ ] Separate `.tapDisabledByTimeout` from `.tapDisabledByUserInput`
    in logs and recovery logic.
-   [ ] Check the current enabled state with
    `CGEvent.tapIsEnabled(tap:)` where appropriate, but do not treat
    that check as a permission check.
-   [ ] Determine from documentation and controlled tests which
    disabled-tap conditions should be re-enabled and which should
    trigger teardown and permission re-evaluation.
-   [ ] Avoid repeatedly re-enabling a tap when macOS continues to
    reject or disable it.
-   [ ] Add bounded retries and useful log messages for repeated
    failures.
-   [ ] Ensure recovery work is scheduled outside the event-tap callback
    where necessary.

**Acceptance criteria**

-   A normal tap timeout can recover without creating duplicate taps.
-   A permission-related failure does not enter an endless re-enable
    loop.
-   Logs identify the notification type, permission-check results,
    tap-enabled state, and recovery decision.

### Phase 4 --- Make permission detection and recovery observable

-   [ ] Log the results of `AXIsProcessTrusted()` and
    `CGPreflightListenEventAccess()` separately.
-   [ ] Log whether the tap exists and whether macOS reports it enabled.
-   [ ] Log each transition among `.stopped`, `.waitingForPermission`,
    and `.running`.
-   [ ] Log whether recovery was triggered by the access monitor, a
    disabled-tap callback, or the watchdog.
-   [ ] When access is detected as revoked, tear down the old tap before
    attempting to create another.
-   [ ] If a new tap cannot be created, set the appropriate
    `neededPermission` and transition to `.waitingForPermission`.
-   [ ] Verify that the menu-bar observer presents the permission window
    for every relevant transition, including recovery after a permission
    entry is deleted.
-   [ ] Avoid resetting TCC entries automatically. Keep
    `resetPermission()` as an explicit user-initiated repair action.

**Important investigation:** Reproduce permission *disable* and
permission *entry deletion* separately. Capture the preflight API
results, tap notifications, tap-enabled state, and status transitions
immediately before and after each action. Do not assume that deleting an
entry necessarily makes either preflight API return `false`.

**Acceptance criteria**

-   Both disabling and deleting the required permission lead to a
    recoverable state.
-   The app does not remain indefinitely in `.running` with a
    nonfunctional tap.
-   The permission screen appears without requiring the user to quit and
    relaunch HomeRower.

### Phase 5 --- Verify permission acquisition and restart behavior

-   [ ] Test first-time Accessibility authorization.
-   [ ] Test the case where Accessibility is enabled but tap creation
    fails and Input Monitoring is required.
-   [ ] Test granting permission while HomeRower is already open.
-   [ ] Test removing and re-adding the app's permission entry.
-   [ ] Test the explicit `resetPermission()` flow and its `tccutil`
    exit-code handling.
-   [ ] Test quitting and relaunching after each permission state.
-   [ ] Verify `neededPermission` is reset or retained correctly when
    transitioning between permission states.
-   [ ] Verify the `permissionWatcher` and `accessMonitor` tasks are
    cancelled and restarted without stale tasks.

**Acceptance criteria**

-   HomeRower starts when the required permission is granted.
-   HomeRower waits without intercepting input when permission is
    missing.
-   Permission changes are detected without requiring an app restart, to
    the extent macOS exposes those changes to the app.

## Regression test matrix

  -----------------------------------------------------------------------
  Scenario                            Expected result
  ----------------------------------- -----------------------------------
  Launch with required permissions    Tap starts; status becomes
  already granted                     `.running`

  Launch without Accessibility        No active tap; permission screen is
                                      shown

  Grant Accessibility while app is    Tap starts if creation succeeds
  open                                

  Accessibility is granted but tap    App requests or directs the user to
  creation fails and Input Monitoring the correct permission
  is needed                           

  Switch off required permission      Tap is torn down; normal input
  while running                       works; permission screen appears

  Delete required permission entry    Tap is safely torn down; normal
  while running                       input works; app enters permission
                                      recovery

  Tap is disabled by timeout          Recovery follows the timeout
                                      policy; no duplicate tap

  Main thread is blocked beyond       Watchdog disables tap; normal input
  watchdog threshold                  is restored

  Disable and re-enable HomeRower's   Events pass through while disabled;
  remapping                           remapping resumes when enabled

  Quit while a modifier is held       Synthesized modifiers are released
                                      and tap is removed

  Repeated permission changes         No stuck tasks, duplicate sources,
                                      or stale `.running` state
  -----------------------------------------------------------------------

## Suggested implementation order

1.  Integrate and validate the watchdog.
2.  Make teardown/fail-open behavior idempotent and reliable.
3.  Instrument permission checks and tap state.
4.  Correct disabled-tap recovery based on the observed macOS behavior.
5.  Verify state transitions and permission-window presentation.
6.  Run the full regression matrix.

Do not begin by rewriting the permission UI. The supplied UI already
responds to `.waitingForPermission`; first make the event-tap lifecycle
reliably reach that state while guaranteeing that keyboard input is not
trapped.

## Out of scope for this fix

-   Persisting `logLines` to disk. The supplied implementation
    explicitly keeps them in memory only.
-   Redesigning the permission screen.
-   Changing the hold-tap engine's key-mapping behavior, unless
    regression testing reveals an interaction with cleanup or event
    pass-through.
