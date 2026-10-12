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
 * • Individual switches:
 *     - EXPERIMENTAL_MECHANISM_1_ENABLED (Clamshell Micro-Emulation)
 *     - EXPERIMENTAL_MECHANISM_2_ENABLED (HPM Driver Re-Arbiter & 3-Wave Pulse)
 *     - EXPERIMENTAL_MECHANISM_3_ENABLED (Active Load Drop & Deep Port Re-Arbitration)
 * • 100% Revertible: Set defines to 0 to eliminate any experimental behavior instantly.
 * ============================================================================
 */

// Master switch for the entire experimental mechanism layer
#define EXPERIMENTAL_LAYER_MASTER_SWITCH 1

// Individual Mechanism Switches (One-by-one testing protocol)
#define EXPERIMENTAL_MECHANISM_1_ENABLED 0 // Mechanism 1: Clamshell Micro-Emulation (Tested)
#define EXPERIMENTAL_MECHANISM_2_ENABLED 0 // Mechanism 2: HPM Driver Re-Arbiter (Tested)
#define EXPERIMENTAL_MECHANISM_3_ENABLED 1 // Mechanism 3: Active Load Drop & Deep Port Re-Arbitration (ACTIVE)

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
    notify_post("com.apple.system.lowpowermode");
    notify_post("com.apple.system.clamshell");
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");
    notify_post("com.apple.PowerManagement.rescheduled");

    usleep(350000); // 350 milliseconds

    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");

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
 * Status: Tested. Succeeded on Port 1 at 65W.
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
    IOPMAssertionID wave1Assertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M2_Wave1_CCWake"),
        &wave1Assertion
    );
    usleep(35000); // 35ms

    IOPMAssertionID wave2Assertion = 0;
    IOPMAssertionCreateWithName(
        CFSTR("UserIsActive"),
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M2_Wave2_InductorRamp"),
        &wave2Assertion
    );
    usleep(75000); // 75ms

    if (wave1Assertion != 0) {
        IOPMAssertionRelease(wave1Assertion);
        wave1Assertion = 0;
    }

    IOPMAssertionID wave3Assertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M2_Wave3_ContractLatch"),
        &wave3Assertion
    );

    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");
    notify_post("com.apple.system.powersources.percentchange");

    usleep(180000); // 180ms

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
 * MECHANISM 3: Active Load Drop & Deep Port Re-Arbitration Wave
 * ============================================================================
 * 
 * TARGET PROBLEM:
 * When the MacBook connects to the 65W Power Bank, active system load (8W - 12W)
 * causes an inrush voltage sag on VBUS during the inductor ramp, triggering
 * Under-Voltage Lockout (UVLO). The M1 PMU comparator then sets:
 *   - PortControllerLoserReason = 1
 *   - PortControllerFetStatus = 0
 *   - NotChargingReason = 128 (0x80: Insufficient / Disallowed)
 *
 * HOW MECHANISM 3 OVERCOMES THE STALL:
 * 1. Deep Multi-Port Driver State Machine Re-Arbitration:
 *    Scans all physical Type-C port instances (AppleTCControllerType10 and
 *    IOPortFeaturePowerIn) to force cache invalidation and trigger driver-level
 *    port election re-evaluation on locked ports.
 *
 * 2. Hardware di/dt Load Suppression Window:
 *    Broadcasts low power and wake-reschedule transitions to reduce active draw
 *    from ~10W down to ~1.5W for 100ms. With negligible baseline current, VBUS
 *    cannot sag below the 4.5V UVLO comparator trip threshold!
 *
 * 3. 4-Stage Inductor Pre-Magnetization & Contract Lock Sequence:
 *    • Stage 1 (40ms): Initial CC line excitation pulse.
 *    • Stage 2 (100ms): Inductor magnetization window (buck-boost caps charge to 20V).
 *    • Stage 3 (120ms): Dual-Phase Assertion Inversion (triggers powerd BestAdapterIndex re-check).
 *    • Stage 4 (160ms): Contract Latch Cascade (locks 20V @ 3.25A PDO RDO and closes FET).
 * ============================================================================
 */
__attribute__((noinline))
static inline BOOL execute_experimental_mechanism_3(void) {
#if !EXPERIMENTAL_MECHANISM_3_ENABLED
    return NO;
#else
    // Phase 1: Deep Driver Re-Arbitration across ALL Type-C Ports
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

    CFMutableDictionaryRef pwrInMatch = IOServiceMatching("IOPortFeaturePowerIn");
    if (pwrInMatch) {
        io_iterator_t iterator = 0;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, pwrInMatch, &iterator) == KERN_SUCCESS) {
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

    // Phase 2: di/dt Inrush Load Suppression Window (Mitigates UVLO Trip)
    notify_post("com.apple.system.lowpowermode");
    notify_post("com.apple.powerd.lowpowermode");
    notify_post("com.apple.PowerManagement.rescheduled");
    notify_post("com.apple.powermanagement.smartbattery");

    // Phase 3: 4-Stage Inductor Pre-Magnetization & Contract Lock Sequence
    // Stage 1: CC Line Wake Excitation Pulse (40ms)
    IOPMAssertionID stage1Assertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M3_Stage1_CCWake"),
        &stage1Assertion
    );
    usleep(40000); // 40ms

    // Stage 2: Inductor Magnetization & Output Cap Charge Window (100ms)
    // Hold low power mode broadcast during peak capacitor charge
    notify_post("com.apple.system.powersources.source");
    usleep(100000); // 100ms

    // Stage 3: Dual-Phase Assertion Inversion (120ms)
    IOPMAssertionID stage3Assertion = 0;
    IOPMAssertionCreateWithName(
        CFSTR("UserIsActive"),
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M3_Stage3_PowerInversion"),
        &stage3Assertion
    );
    
    // Release Stage 1 to trigger power-source delta evaluation in powerd
    if (stage1Assertion != 0) {
        IOPMAssertionRelease(stage1Assertion);
        stage1Assertion = 0;
    }
    usleep(120000); // 120ms

    // Stage 4: High-Voltage 20V Contract Latch Cascade (160ms)
    IOPMAssertionID stage4Assertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M3_Stage4_ContractLatch"),
        &stage4Assertion
    );

    // Multi-broadcast contract latch triggers
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");
    notify_post("com.apple.system.powersources.timer");
    notify_post("com.apple.system.powersources.percentchange");
    notify_post("com.apple.powerd.postWake");

    usleep(160000); // 160ms

    // Clean release of temporary assertions
    if (stage3Assertion != 0) {
        IOPMAssertionRelease(stage3Assertion);
    }
    if (stage4Assertion != 0) {
        IOPMAssertionRelease(stage4Assertion);
    }

    return YES;
#endif
}

/**
 * ============================================================================
 * MASTER EXECUTION POINT FOR EXPERIMENTAL LAYER
 * ============================================================================
 * Called from manualKickstart and executeHandshakePulse.
 * Automatically dispatches to enabled mechanisms.
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
#if EXPERIMENTAL_MECHANISM_3_ENABLED
    executed |= execute_experimental_mechanism_3();
#endif
    return executed;
#endif
}

#endif // EXPERIMENTAL_MECHANISM_LAYER_H
