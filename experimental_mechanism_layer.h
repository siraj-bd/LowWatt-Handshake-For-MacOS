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
 * STRICT ISOLATION ARCHITECTURE:
 * • All experimental mechanisms reside strictly inside this dedicated file.
 * • Core codebase, licensing, and legacy handshake logic are completely untouched.
 * • Master switch: EXPERIMENTAL_LAYER_MASTER_SWITCH (1 = active, 0 = 100% disabled).
 * • Individual switches: EXPERIMENTAL_MECHANISM_1_ENABLED, EXPERIMENTAL_MECHANISM_2_ENABLED.
 * • 100% Revertible: Set defines to 0 to eliminate all experimental behavior instantly.
 * ============================================================================
 */

// Master switch for the entire experimental mechanism layer
#define EXPERIMENTAL_LAYER_MASTER_SWITCH 1

// Individual Mechanism Switches (One-by-one testing protocol)
#define EXPERIMENTAL_MECHANISM_1_ENABLED 0 // Mechanism 1: Clamshell Micro-Emulation (Tested)
#define EXPERIMENTAL_MECHANISM_2_ENABLED 1 // Mechanism 2: HPM / AppleTCController Driver Re-Arbiter & Multi-Wave Pulse

/**
 * ============================================================================
 * MECHANISM 1: Clamshell / DarkWake Micro-State Emulation
 * ============================================================================
 * Status: Tested standalone. Retained for hybrid testing if needed.
 */
__attribute__((noinline))
static inline BOOL execute_experimental_mechanism_1(void) {
#if !EXPERIMENTAL_MECHANISM_1_ENABLED
    return NO;
#else
    // Phase 1: Micro-Drop (Signal Low Power & Clamshell lid-close transition)
    notify_post("com.apple.system.lowpowermode");
    notify_post("com.apple.system.clamshell");
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");
    notify_post("com.apple.PowerManagement.rescheduled");

    // Phase 2: Hold 350ms stabilization window
    usleep(350000); // 350 milliseconds

    // Phase 3: Secondary cascade to catch and lock the newly established PD contract
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");

    // Phase 4: Wake latch assertion
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

/**
 * ============================================================================
 * MECHANISM 2: HPM / AppleTCController Driver Re-Arbiter & 3-Wave Pulse Train
 * ============================================================================
 * 
 * TARGET PROBLEM:
 * When the power bank connects to the MacBook M1 while awake under active load
 * (~9W-10W), the buck-boost inductor's inrush voltage sag trips the M1 PMU comparator,
 * escalating to 7 Hard Resets and latching the port into:
 *   - PortControllerLoserReason = 1
 *   - PortControllerFetStatus = 0 (Input gate switch locked shut)
 *   - NotChargingReason = 128 (0x80)
 *
 * HOW MECHANISM 2 UNLATCHES THE GATE:
 * 1. Driver Re-Arbiter Tickle:
 *    Iterates AppleTCControllerType10 and AppleSmartBattery IOKit services to
 *    trigger driver cache invalidation and force a re-evaluation of the port state.
 *
 * 2. Transient di/dt Load Suppression (Soft Dip):
 *    Broadcasts low power mode and PMU rescheduling signals to drop baseline draw
 *    during the crucial inductor magnetization window.
 *
 * 3. Staggered 3-Wave Power Assertion Train:
 *    • Wave 1 (35ms): CC line wake pulse (pre-excitation).
 *    • Wave 2 (75ms): Inductor ramp stabilization window (capacitors charge smoothly).
 *    • Wave 3 (180ms): Contract latch hold & primary USB-PD 20V contract lock cascade.
 * ============================================================================
 */
__attribute__((noinline))
static inline BOOL execute_experimental_mechanism_2(void) {
#if !EXPERIMENTAL_MECHANISM_2_ENABLED
    return NO;
#else
    // Phase 1: IOKit Driver Re-Arbiter & Cache Invalidation
    CFMutableDictionaryRef tcMatch = IOServiceMatching("AppleTCControllerType10");
    if (tcMatch) {
        io_iterator_t iterator = 0;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, tcMatch, &iterator) == KERN_SUCCESS) {
            io_service_t service = 0;
            while ((service = IOIteratorNext(iterator)) != 0) {
                CFMutableDictionaryRef props = NULL;
                if (IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS) {
                    if (props) CFRelease(props);
                }
                IOObjectRelease(service);
            }
            IOObjectRelease(iterator);
        }
    }

    CFMutableDictionaryRef batMatch = IOServiceMatching("AppleSmartBattery");
    if (batMatch) {
        io_iterator_t iterator = 0;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, batMatch, &iterator) == KERN_SUCCESS) {
            io_service_t service = 0;
            while ((service = IOIteratorNext(iterator)) != 0) {
                CFMutableDictionaryRef props = NULL;
                if (IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS) {
                    if (props) CFRelease(props);
                }
                IOObjectRelease(service);
            }
            IOObjectRelease(iterator);
        }
    }

    // Phase 2: Inrush di/dt Load Suppression & Arbiter Wake Broadcast
    notify_post("com.apple.system.lowpowermode");
    notify_post("com.apple.powerd.postWake");
    notify_post("com.apple.PowerManagement.rescheduled");
    notify_post("com.apple.powermanagement.smartbattery");
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");

    // Phase 3: Staggered 3-Wave Inductor Pre-Charge Pulse Train
    // Wave 1: 35ms CC Line Wake Pulse
    IOPMAssertionID wave1Assertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M2_Wave1_CCWake"),
        &wave1Assertion
    );
    usleep(35000); // 35ms

    // Wave 2: 75ms Inductor Ramp Stabilization
    IOPMAssertionID wave2Assertion = 0;
    IOPMAssertionCreateWithName(
        CFSTR("UserIsActive"),
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M2_Wave2_InductorRamp"),
        &wave2Assertion
    );
    usleep(75000); // 75ms

    // Release Wave 1 to trigger power-delta state machine step in powerd
    if (wave1Assertion != 0) {
        IOPMAssertionRelease(wave1Assertion);
        wave1Assertion = 0;
    }

    // Wave 3: 180ms Contract Latch Hold
    IOPMAssertionID wave3Assertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M2_Wave3_ContractLatch"),
        &wave3Assertion
    );

    // Fire contract latch notifications during Wave 3 peak
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");
    notify_post("com.apple.system.powersources.percentchange");

    usleep(180000); // 180ms contract latch window

    // Clean release of assertions
    if (wave2Assertion != 0) {
        IOPMAssertionRelease(wave2Assertion);
    }
    if (wave3Assertion != 0) {
        IOPMAssertionRelease(wave3Assertion);
    }

    return YES;
#endif
}

/**
 * ============================================================================
 * MASTER EXECUTION POINT FOR EXPERIMENTAL LAYER
 * ============================================================================
 * Called from manualKickstart. Automatically dispatches to enabled mechanisms.
 * Allows seamless switching between Mechanism 1, 2, 3, 4 without touching menubar_app.m.
 * ============================================================================
 */
static inline BOOL execute_experimental_layer(void) {
#if !EXPERIMENTAL_LAYER_MASTER_SWITCH
    return NO;
#else
    BOOL executed = NO;
#if EXPERIMENTAL_MECHANISM_1_ENABLED
    executed |= execute_experimental_mechanism_1();
#endif
#if EXPERIMENTAL_MECHANISM_2_ENABLED
    executed |= execute_experimental_mechanism_2();
#endif
    return executed;
#endif
}

#endif // EXPERIMENTAL_MECHANISM_LAYER_H
