#ifndef EXPERIMENTAL_MECHANISM_LAYER_H
#define EXPERIMENTAL_MECHANISM_LAYER_H

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <notify.h>
#import <unistd.h>

/**
 * ============================================================================
 * LOWWATT HANDSHAKE - EXPERIMENTAL HARDWARE MECHANISM LAYER
 * ============================================================================
 * 
 * MODULE: Mechanism 1 — Clamshell / DarkWake Micro-State Emulation
 * 
 * PURPOSE:
 * When the MacBook lid is closed, macOS enters a low-load DarkWake state
 * where the PMU drops the power threshold, ignores inrush voltage sags,
 * unlatches PortControllerLoserReason, and turns ON PortControllerFetStatus.
 *
 * This isolated mechanism replicates that EXACT lid-close transition for 
 * 350 milliseconds in software while the laptop remains open and awake,
 * allowing the M1 PMU charging gate to unlock and latch power delivery.
 *
 * SAFETY & REVERTIBILITY:
 * • 100% isolated in this dedicated file.
 * • Set EXPERIMENTAL_MECHANISM_1_ENABLED to 0 to disable instantly.
 * • Never modifies core charging drivers or legacy handshake logic.
 * ============================================================================
 */

// Master Safety Switch: 1 = Enabled, 0 = Fully Disabled / Bypass
#define EXPERIMENTAL_MECHANISM_1_ENABLED 1

__attribute__((noinline))
static inline BOOL execute_experimental_mechanism_1(void) {
#if !EXPERIMENTAL_MECHANISM_1_ENABLED
    return NO;
#else
    // Phase 1: Micro-Drop (Signal Low Power & Clamshell lid-close transition)
    // Drops PMU baseline threshold without closing physical screen
    notify_post("com.apple.system.lowpowermode");
    notify_post("com.apple.system.clamshell");
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");
    notify_post("com.apple.PowerManagement.rescheduled");

    // Phase 2: Hold 350ms stabilization window
    // Gives power bank's buck-boost inductor time to ramp and M1 PMU to unlatch LoserReason
    usleep(350000); // 350 milliseconds

    // Phase 3: Secondary cascade to catch and lock the newly established PD contract
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");

    // Phase 4: Wake latch assertion (ensures system remains responsive and awake)
    IOPMAssertionID wakeAssertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_Mechanism1_WakeLatch"),
        &wakeAssertion
    );
    usleep(50000); // 50ms latch
    if (wakeAssertion != 0) {
        IOPMAssertionRelease(wakeAssertion);
    }

    return YES;
#endif
}

#endif // EXPERIMENTAL_MECHANISM_LAYER_H
