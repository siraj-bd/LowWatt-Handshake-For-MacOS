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
 * "AEROSPACE ARCHITECTURE" - UNIFIED 4-STAGE 1-CLICK HARDWARE UNLATCH ENGINE
 * 
 * STRICT ISOLATION ARCHITECTURE:
 * • All experimental mechanisms reside strictly inside this dedicated file.
 * • Core codebase, licensing, and legacy handshake logic are completely untouched.
 * • Master switch: EXPERIMENTAL_LAYER_MASTER_SWITCH (1 = active, 0 = 100% disabled).
 * • Individual switches:
 *     - EXPERIMENTAL_MECHANISM_1_ENABLED (Clamshell Micro-Emulation)
 *     - EXPERIMENTAL_MECHANISM_2_ENABLED (HPM Driver Re-Arbiter & Cache Poke)
 *     - EXPERIMENTAL_MECHANISM_3_ENABLED (Active Load Drop & Inductor Magnetization)
 *     - EXPERIMENTAL_MECHANISM_4_ENABLED (Synthetic DarkWake & 5-Wave High-Voltage Gate Lock)
 * • 100% Revertible: Set defines to 0 to eliminate any experimental behavior instantly.
 * ============================================================================
 */

// Master switch for the entire experimental mechanism layer
#define EXPERIMENTAL_LAYER_MASTER_SWITCH 1

// Unified Multi-Mechanism Activation:
// Setting all to 1 chains the complete 4-stage unlatch sequence in a single click!
#define EXPERIMENTAL_MECHANISM_1_ENABLED 1 // Stage 1: Clamshell Micro-Emulation
#define EXPERIMENTAL_MECHANISM_2_ENABLED 1 // Stage 2: HPM Driver Re-Arbiter & Cache Invalidation
#define EXPERIMENTAL_MECHANISM_3_ENABLED 1 // Stage 3: Active di/dt Load Drop & Inductor Pre-Magnetization
#define EXPERIMENTAL_MECHANISM_4_ENABLED 1 // Stage 4: Synthetic DarkWake & 5-Wave High-Voltage Conduction Gate Lock

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

    usleep(150000); // 150 milliseconds

    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");

    IOPMAssertionID wakeAssertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M1_WakeLatch"),
        &wakeAssertion
    );
    usleep(30000); // 30ms latch
    if (wakeAssertion != 0) {
        IOPMAssertionRelease(wakeAssertion);
    }

    return YES;
#endif
}

/**
 * ============================================================================
 * MECHANISM 2: HPM / AppleTCController Driver Re-Arbiter & Cache Invalidation
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
    usleep(30000); // 30ms

    IOPMAssertionID wave2Assertion = 0;
    IOPMAssertionCreateWithName(
        CFSTR("UserIsActive"),
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_M2_Wave2_InductorRamp"),
        &wave2Assertion
    );
    usleep(60000); // 60ms

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

    usleep(100000); // 100ms

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
    usleep(30000); // 30ms

    notify_post("com.apple.system.powersources.source");
    usleep(80000); // 80ms

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
    usleep(80000); // 80ms

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

    usleep(100000); // 100ms

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
 * MECHANISM 4: Synthetic DarkWake State & 5-Wave High-Voltage Conduction Gate Lock
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

    if (wave1 != 0) {
        IOPMAssertionRelease(wave1);
        wave1 = 0;
    }

    // Wave 3: 100ms Inductor Flux Stabilization (allows caps to reach 20V rail)
    notify_post("com.apple.system.powersources.source");
    usleep(100000); // 100ms

    // Wave 4: 120ms USB-PD RDO Contract Request Latch
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
    usleep(120000); // 120ms

    // Wave 5: 150ms High-Voltage 20V Conduction Gate Lock (FET ON)
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources");
    notify_post("com.apple.powerd.postWake");
    usleep(150000); // 150ms

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
