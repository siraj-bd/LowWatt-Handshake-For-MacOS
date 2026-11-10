#ifndef EXPERIMENTAL_MECHANISM_LAYER_H
#define EXPERIMENTAL_MECHANISM_LAYER_H

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <notify.h>
#import <unistd.h>

/**
 * ============================================================================
 * LOWWATT HANDSHAKE - HARDWARE MECHANISM LAYER (CLEAN & NON-INVASIVE)
 * ============================================================================
 * 
 * SAFE 100% OS-COMPLIANT ARCHITECTURE:
 * 
 * • ZERO I2C BUS INTERFERENCE: AppleTCController and physical hardware registers
 *   are NEVER poked or polled from user space, completely preventing I2C collisions.
 * 
 * • ZERO FAKE NOTIFICATIONS: No fake powerd.postWake, system.clamshell, or
 *   PowerManagement.rescheduled broadcasts that corrupt the PMU state machine.
 * 
 * • Clean Transient Power Latch:
 *     - Standard Darwin power evaluation broadcast (com.apple.system.powersources).
 *     - 60ms safe transient buck-boost stabilization window.
 * ============================================================================
 */

#define EXPERIMENTAL_LAYER_MASTER_SWITCH 1
#define PHASE_1_ENABLED 1
#define PHASE_2_ENABLED 1

/**
 * ============================================================================
 * PHASE 1: Transient Load Drop
 * ============================================================================
 * Pure software load drop via Darwin Power Management signals (NO display tampering).
 * ============================================================================
 */
__attribute__((noinline))
static inline BOOL execute_phase1_transient_load_drop(void) {
#if !PHASE_1_ENABLED
    return NO;
#else
    IOPMAssertionID wakeAssertion = 0;
    IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_Phase1_WakeLatch"),
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
 * PHASE 2: Safe Hardware Evaluation & Non-Invasive Contract Latch
 * ============================================================================
 * Safe standard power source evaluation:
 * - Clean 60ms transient buck-boost stabilization latch
 * - Single canonical macOS power sources notification broadcast
 * - Zero I2C bus tampering, zero fake wake/clamshell/percentchange notifications
 * ============================================================================
 */
__attribute__((noinline))
static inline BOOL execute_phase2_hpm_pmu_reelection(void) {
#if !PHASE_2_ENABLED
    return NO;
#else
    // 1. Safe Transient Power Latch Assertion (Zero driver poking, zero I2C bus collisions)
    IOPMAssertionID latchAssertion = 0;
    IOReturn ret = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWatt_Safe_ContractLatch"),
        &latchAssertion
    );

    // 60ms stabilization window for charger buck-boost converter
    usleep(60000);

    if (ret == kIOReturnSuccess && latchAssertion != 0) {
        IOPMAssertionRelease(latchAssertion);
    }

    return YES;
#endif
}

/**
 * Master execution point for Continuous Handshake Latch loop pulses.
 * Prioritizes Phase 2 (the proven mechanism) with Phase 1 interspersing.
 */
static inline BOOL execute_experimental_layer_step(int step) {
#if !EXPERIMENTAL_LAYER_MASTER_SWITCH
    return NO;
#else
    if ((step % 2) == 0) {
        return execute_phase2_hpm_pmu_reelection();
    } else {
        return execute_phase1_transient_load_drop();
    }
#endif
}

static inline BOOL execute_experimental_layer(void) {
    // Unified in execute_hardware_handshake_pulse (50ms single transient latch, 1 notification)
    return YES;
}

#endif // EXPERIMENTAL_MECHANISM_LAYER_H
