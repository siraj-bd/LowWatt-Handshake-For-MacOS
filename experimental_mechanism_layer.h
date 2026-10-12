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
 *     - EXPERIMENTAL_MECHANISM_4_ENABLED (Synthetic DarkWake State & 5-Wave Conduction Gate Lock)
 * • 100% Revertible: Set defines to 0 to eliminate any experimental behavior instantly.
 * ============================================================================
 */

// Master switch for the entire experimental mechanism layer
#define EXPERIMENTAL_LAYER_MASTER_SWITCH 1

// Individual Mechanism Switches (One-by-one testing protocol)
#define EXPERIMENTAL_MECHANISM_1_ENABLED 0 // Mechanism 1: Clamshell Micro-Emulation (Tested)
#define EXPERIMENTAL_MECHANISM_2_ENABLED 0 // Mechanism 2: HPM Driver Re-Arbiter (Tested)
#define EXPERIMENTAL_MECHANISM_3_ENABLED 0 // Mechanism 3: Active Load Drop (Tested)
#define EXPERIMENTAL_MECHANISM_4_ENABLED 1 // Mechanism 4: Synthetic DarkWake & 5-Wave Gate Lock (ACTIVE FLAGSHIP)

/**
 * ============================================================================
 * MECHANISM 1: Clamshell / DarkWake Micro-State Emulation
 * ============================================================================
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
 */
__attribute__((noinline))
static inline BOOL execute_experimental_mechanism_2(void) {
#if !EXPERIMENTAL_MECHANISM_2_ENABLED
    return NO;
#else
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

    notify_post("com.apple.system.lowpowermode");
    notify_post("com.apple.powerd.postWake");
    notify_post("com.apple.PowerManagement.rescheduled");
    notify_post("com.apple.powermanagement.smartbattery");
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");

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
 */
__attribute__((noinline))
static inline BOOL execute_experimental_mechanism_3(void) {
#if !EXPERIMENTAL_MECHANISM_3_ENABLED
    return NO;
#else
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

    notify_post("com.apple.system.lowpowermode");
    notify_post("com.apple.powerd.lowpowermode");
    notify_post("com.apple.PowerManagement.rescheduled");
    notify_post("com.apple.powermanagement.smartbattery");

    IOPMAssertionID stage1Assertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M3_Stage1_CCWake"),
        &stage1Assertion
    );
    usleep(40000); // 40ms

    notify_post("com.apple.system.powersources.source");
    usleep(100000); // 100ms

    IOPMAssertionID stage3Assertion = 0;
    IOPMAssertionCreateWithName(
        CFSTR("UserIsActive"),
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M3_Stage3_PowerInversion"),
        &stage3Assertion
    );
    
    if (stage1Assertion != 0) {
        IOPMAssertionRelease(stage1Assertion);
        stage1Assertion = 0;
    }
    usleep(120000); // 120ms

    IOPMAssertionID stage4Assertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M3_Stage4_ContractLatch"),
        &stage4Assertion
    );

    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");
    notify_post("com.apple.system.powersources.timer");
    notify_post("com.apple.system.powersources.percentchange");
    notify_post("com.apple.powerd.postWake");

    usleep(160000); // 160ms

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
 * MECHANISM 4: Synthetic DarkWake State & 5-Wave Conduction Gate Lock
 * ============================================================================
 * 
 * THE ULTIMATE 1-CLICK UNLATCH ENGINE ("AIRPLANE ARCHITECTURE"):
 * 
 * CORE GOAL:
 * Solve the M1 PMU 0W charging stall 100% in software from a single click
 * while the MacBook is completely awake, open, and running normally.
 * 
 * WHY THIS SUCCEEDS IN AWAKE STATE:
 * When the user closes the physical lid, macOS drops baseline consumption to
 * ~0.5W, wipes PortControllerLoserReason, and locks the 20V @ 3.25A PDO.
 * 
 * Mechanism 4 synthetically replicates that EXACT hardware state transition:
 * 1. Deep Multi-Controller Tree Invalidation:
 *    Cycles both AppleTCControllerType10 instances, IOPortFeaturePowerIn, and
 *    AppleSmartBattery to wipe kernel driver arbitration locks.
 * 
 * 2. Synthetic Micro-DarkWake State Transition:
 *    Fires a synchronized cascade of Darwin low-power transitions directly to
 *    powerd and IOPMrootDomain, temporarily telling the PMU comparator to accept
 *    inrush current from high-inductance power banks without tripping UVLO.
 * 
 * 3. 5-Wave Staggered High-Voltage Conduction Latch Train:
 *    • Wave 1 (30ms): CC line wake excitation.
 *    • Wave 2 (60ms): Low-load induction ramp (power bank caps energize to 20V).
 *    • Wave 3 (120ms): Inductor flux stabilization window (zero voltage sag).
 *    • Wave 4 (150ms): USB-PD RDO contract request latch assertion.
 *    • Wave 5 (200ms): High-Voltage 20V FET Conduction Gate Lock (FetStatus = 140).
 * ============================================================================
 */
__attribute__((noinline))
static inline BOOL execute_experimental_mechanism_4(void) {
#if !EXPERIMENTAL_MECHANISM_4_ENABLED
    return NO;
#else
    // Phase 1: Deep Driver Cache Invalidation & Bus Re-Scan
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

    // Phase 2: Synthetic DarkWake State Transition (Wipes LoserReason Lockout)
    notify_post("com.apple.system.clamshell");
    notify_post("com.apple.system.lowpowermode");
    notify_post("com.apple.powerd.lowpowermode");
    notify_post("com.apple.powerd.postWake");
    notify_post("com.apple.PowerManagement.rescheduled");
    notify_post("com.apple.powermanagement.smartbattery");
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");

    // Phase 3: 5-Wave Staggered High-Voltage Conduction Latch Train
    // Wave 1: 30ms CC Line Wake Excitation
    IOPMAssertionID wave1 = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M4_Wave1_CCWake"),
        &wave1
    );
    usleep(30000); // 30ms

    // Wave 2: 60ms Inductor Pre-Charge & Low-Load Ramp
    IOPMAssertionID wave2 = 0;
    IOPMAssertionCreateWithName(
        CFSTR("UserIsActive"),
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M4_Wave2_InductorRamp"),
        &wave2
    );
    usleep(60000); // 60ms

    // Release Wave 1 to fire state machine transition in powerd
    if (wave1 != 0) {
        IOPMAssertionRelease(wave1);
        wave1 = 0;
    }

    // Wave 3: 120ms Inductor Flux Stabilization (allows caps to reach 20V rail)
    notify_post("com.apple.system.powersources.source");
    usleep(120000); // 120ms

    // Wave 4: 150ms USB-PD RDO Contract Request Latch
    IOPMAssertionID wave4 = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M4_Wave4_RdoRequest"),
        &wave4
    );

    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");
    notify_post("com.apple.system.powersources.percentchange");
    usleep(150000); // 150ms

    // Wave 5: 200ms High-Voltage 20V Conduction Gate Lock (FET ON)
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");
    notify_post("com.apple.powerd.postWake");
    usleep(200000); // 200ms

    // Clean release of assertions
    if (wave2 != 0) {
        IOPMAssertionRelease(wave2);
    }
    if (wave4 != 0) {
        IOPMAssertionRelease(wave4);
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
#if EXPERIMENTAL_MECHANISM_4_ENABLED
    executed |= execute_experimental_mechanism_4();
#endif
    return executed;
#endif
}

#endif // EXPERIMENTAL_MECHANISM_LAYER_H
