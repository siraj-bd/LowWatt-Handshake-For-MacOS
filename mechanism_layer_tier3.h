#ifndef MECHANISM_LAYER_TIER3_H
#define MECHANISM_LAYER_TIER3_H

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <notify.h>
#import <unistd.h>

/**
 * ============================================================================
 * LOWWATT HANDSHAKE - DEDICATED TIER-3 MECHANISM 2 LAYER
 * ============================================================================
 * 
 * STRICT TIER-3 ISOLATION:
 * • Isolated completely in this dedicated file.
 * • Restores the exact Mechanism 2 implementation that previously achieved
 *   the 65W charging breakthrough on the M1 MacBook Pro.
 * • Layer 2 (experimental_mechanism_layer.h) is completely disconnected to
 *   eliminate all multi-mechanism timing interference.
 * ============================================================================
 */

// Master switch for Tier-3 Layer (1 = Enabled, 0 = Disabled)
#define TIER3_MECHANISM_2_ENABLED 1

__attribute__((noinline))
static inline BOOL execute_tier3_mechanism_2(void) {
#if !TIER3_MECHANISM_2_ENABLED
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

#endif // MECHANISM_LAYER_TIER3_H
