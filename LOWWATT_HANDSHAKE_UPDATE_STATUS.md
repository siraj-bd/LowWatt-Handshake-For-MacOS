# LOWWATT_HANDSHAKE_UPDATE_STATUS.md
## Feature & Button Functional Ledger

---

### Item 1: Menu Bar Status Item (NSStatusItem)
- **Purpose & Logic**: Displays current battery percentage, charging state, and watt telemetry directly in macOS menu bar.
- **Trigger / Event**: Native macOS render event; updates on kernel power change or 2.5s AC timer tick (dirty-checked).
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#updateStatus`
- **UI/UX Note**: Renders dynamic icon with battery percentage badge; zero redrawing when telemetry is unchanged.

### Item 2: Force Handshake Kickstart Menu Item
- **Purpose & Logic**: Manually triggers on-demand one-shot PD handshake pulse for stubborn chargers without recurring polling, with atomic debounce guard (`isHandshakeInProgress`) preventing race conditions.
- **Trigger / Event**: User clicks "Force Handshake Kickstart" or presses shortcut `Cmd+K`.
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#manualKickstart` -> `executeHandshakePulseAsyncWithCompletion:`
- **UI/UX Note**: Dispatches asynchronously to background queue with tactile audio/sound confirmation; leaves main thread 100% fluid.

### Item 3: Kernel Power Source Push Listener
- **Purpose & Logic**: Wakes application immediately upon physical power cable insertion/removal without background polling; enforces strict one-shot latch (`hasExecutedHandshakeOnThisConnection`) on plug-in.
- **Trigger / Event**: Hardware power state transition via `IOPSNotificationCreateRunLoopSource`.
- **Code Mapping**: `menubar_app.m` -> `powerSourceNotificationCallback` -> `AppDelegate#handlePowerChangeNotification`
- **UI/UX Note**: Invisible background kernel event; activates AC timer on plug-in, invalidates timer to 0% CPU on unplug.

### Item 4: AC Passive Telemetry Refresh Timer
- **Purpose & Logic**: Provides relaxed passive visual refresh on AC (15.0s interval + 5.0s deep sleep timer coalescing tolerance). Zero handshake calls; purely updates visual watt display numbers without waking idle CPU cores.
- **Trigger / Event**: Scheduled NSTimer tick managed by `AppDelegate#startChargingTimer`.
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#startChargingTimer` -> `AppDelegate#updatePowerStateAndCheck`
- **UI/UX Note**: Only active when `ExternalConnected == YES`; destroyed immediately on battery power (0.0% CPU).

### Item 5: Purchase License Key
- **Purpose & Logic**: Launches user's default browser to access the secure licensing portal.
- **Trigger / Event**: User clicks "🛒 Purchase License Key..." or "🛒 Buy License (Unlock Pro)...".
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#openPurchasePage`
- **UI/UX Note**: Invokes `[[NSWorkspace sharedWorkspace] openURL:]` targeting Telegram/Stripe portal.

### Item 6: Enter License Key
- **Purpose & Logic**: Presents native modal dialog to input and validate machine-locked license credentials.
- **Trigger / Event**: User clicks "🔑 Enter License Key...".
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#openLicenseDialog`
- **UI/UX Note**: Native `NSAlert` modal sheet with secure text input and hardware UUID verification.

### Item 7: Manage License
- **Purpose & Logic**: Displays active tier, hardware ID, activation date, and deactivation options.
- **Trigger / Event**: User clicks "Manage License...".
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#manageLicense`
- **UI/UX Note**: Informational `NSAlert` with one-click "Deactivate" button.

### Item 8: Check for Updates
- **Purpose & Logic**: Queries GitHub releases / distribution endpoint for newer application versions.
- **Trigger / Event**: User clicks "Check for Updates...".
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#checkForUpdates`
- **UI/UX Note**: Asynchronous network fetch with alert popup if a new version or current version is confirmed.

### Item 9: Toggle Automatic Update Check
- **Purpose & Logic**: Enables or disables background startup check for newer releases.
- **Trigger / Event**: User toggles "Automatically Check for Updates" checkbox.
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#toggleAutoCheckUpdates:`
- **UI/UX Note**: Checkmark state stored persistently in `NSUserDefaults`.

### Item 10: About LowWatt Handshake
- **Purpose & Logic**: Displays application version, author credits, and hardware architecture notice.
- **Trigger / Event**: User clicks "About LowWatt Handshake".
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#openAbout`
- **UI/UX Note**: Native `NSAlert` modal featuring application icon and build version.

### Item 11: Quit Application
- **Purpose & Logic**: Safely terminates application, releasing all power assertions and runloop observers.
- **Trigger / Event**: User clicks "Quit LowWatt Handshake" or presses shortcut `Cmd+Q`.
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#quitApp` -> `[NSApp terminate:nil]`
- **UI/UX Note**: Instant termination with zero orphaned threads or lingering background workers.

### Item 12: LaunchAgent Auto-Start Service
- **Purpose & Logic**: Automatically launches the menu bar application at login with crash protection and zero spin-loop guarantee.
- **Trigger / Event**: macOS user login or `make install-launchagent`.
- **Code Mapping**: `com.siraj.lowwatthandshake.plist` -> `SuccessfulExit: false` & `ThrottleInterval: 30`
- **UI/UX Note**: Non-intrusive background registration; respects normal user exit without forced restarts.

### Item 13: Sound Feedback Toggle (CoreAudio Sleep Preservation)
- **Purpose & Logic**: Toggles tactile audio alert on handshake connect and kickstart; keeps audio DAC and amplifiers in deep sleep when disabled.
- **Trigger / Event**: User clicks "🔊 Sound Feedback on Handshake" menu item.
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#toggleAudioFeedback:` -> `AudioFeedbackEnabled` in `NSUserDefaults`
- **UI/UX Note**: Checkmark state; defaults to disabled (silent) for maximum standby battery life.

### Item 14: Developer Account Automatic Lifetime License Authorization
- **Purpose & Logic**: Automatically authorizes the local developer/author machine (`siraj`) with permanent Pro access (`DEV-PRO-LIFETIME`), ensuring developers and contributors are never locked out by trial expiration or licensing checks.
- **Trigger / Event**: Application startup, `isProLicensed` check, or manual key entry with prefix `DEV-`.
- **Code Mapping**: `menubar_app.m` -> `AppDelegate#isProLicensed` & `AppDelegate#applicationDidFinishLaunching`
- **UI/UX Note**: Menu shows "👑 Pro License Active (Dev Account)", unblocking all manual and automatic handshake pulses indefinitely.


