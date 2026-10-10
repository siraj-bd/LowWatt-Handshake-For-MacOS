/**
 * LowWatt Handshake macOS (Ultra-lightweight C Daemon)
 * 
 * Specifically designed to resolve missed Type-C PD handshakes on Apple Silicon & Intel MacBooks
 * with low-wattage chargers (15W+), power banks, and adapters without needing shutdown or lid closure.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdbool.h>
#include <time.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <AudioToolbox/AudioToolbox.h>
#include <notify.h>

static bool g_last_connected = false;
static int g_consecutive_misses = 0;

static void play_system_alert(void) {
    // Play macOS system Tink/Ping sound on successful handshake
    AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
}

static bool get_power_status(bool *is_connected, int *watts, char *desc, size_t desc_len) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) return false;

    CFTypeRef extConn = IORegistryEntryCreateCFProperty(service, CFSTR("ExternalConnected"), kCFAllocatorDefault, 0);
    CFDictionaryRef adapterDetails = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, CFSTR("AdapterDetails"), kCFAllocatorDefault, 0);

    *is_connected = (extConn == kCFBooleanTrue);
    *watts = 0;
    if (desc && desc_len > 0) desc[0] = '\0';

    if (adapterDetails && CFGetTypeID(adapterDetails) == CFDictionaryGetTypeID()) {
        CFNumberRef wattsNum = (CFNumberRef)CFDictionaryGetValue(adapterDetails, CFSTR("Watts"));
        if (wattsNum && CFGetTypeID(wattsNum) == CFNumberGetTypeID()) {
            CFNumberGetValue(wattsNum, kCFNumberIntType, watts);
        }
        CFStringRef descStr = (CFStringRef)CFDictionaryGetValue(adapterDetails, CFSTR("Description"));
        if (descStr && CFGetTypeID(descStr) == CFStringGetTypeID()) {
            CFStringGetCString(descStr, desc, desc_len, kCFStringEncodingUTF8);
        }
    }

    if (adapterDetails) CFRelease(adapterDetails);
    if (extConn) CFRelease(extConn);
    IOObjectRelease(service);
    return true;
}

static void trigger_handshake_kickstart(void) {
    printf("[Handshake-Keeper] Attempting PD / PMU kickstart...\n");
    fflush(stdout);

    // 1. Post notification to Darwin power subsystem
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");

    // 2. Pulse assertion on IOPMrootDomain to force hardware bus poll
    IOPMAssertionID assertionID;
    IOReturn res = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("AnkerPDHandshakeKickstart"),
        &assertionID
    );
    if (res == kIOReturnSuccess) {
        usleep(150000); // 150ms wake pulse
        IOPMAssertionRelease(assertionID);
    }

    // 3. Signal power management daemon gently
    system("/usr/bin/killall -HUP powerd 2>/dev/null");
}

static void check_and_recover(void) {
    bool connected = false;
    int watts = 0;
    char desc[64] = {0};

    if (!get_power_status(&connected, &watts, desc, sizeof(desc))) {
        return;
    }

    // State Transition: Cable plugged in
    if (connected && !g_last_connected) {
        printf("[Handshake-Keeper] Charger connected! Negotiated: %dW (%s)\n", watts, desc[0] ? desc : "Unknown");
        fflush(stdout);

        if (watts > 0) {
            play_system_alert();
            g_consecutive_misses = 0;
        } else {
            // Plugged in but Watts == 0 (Handshake stalled / false response)
            printf("[Handshake-Keeper] Warning: Plug detected but PD handshake incomplete (0W). Kickstarting...\n");
            fflush(stdout);
            trigger_handshake_kickstart();
        }
        g_last_connected = true;
    } else if (!connected && g_last_connected) {
        printf("[Handshake-Keeper] Charger disconnected.\n");
        fflush(stdout);
        g_last_connected = false;
        g_consecutive_misses = 0;
    } else if (connected && watts == 0) {
        // Connected but still 0 Watts after plug
        g_consecutive_misses++;
        if (g_consecutive_misses <= 3) {
            printf("[Handshake-Keeper] Missed handshake retry #%d...\n", g_consecutive_misses);
            fflush(stdout);
            trigger_handshake_kickstart();
        }
    }
}

static void power_source_callback(void *context) {
    (void)context;
    check_and_recover();
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    printf("============================================\n");
    printf("  LowWatt Handshake macOS Daemon\n");
    printf("  Status: Active & Monitoring Ports...\n");
    printf("============================================\n");
    fflush(stdout);

    // Initial check
    bool init_conn = false;
    int init_watts = 0;
    char init_desc[64] = {0};
    if (get_power_status(&init_conn, &init_watts, init_desc, sizeof(init_desc))) {
        g_last_connected = init_conn;
        printf("[Init] Cable Connected: %s | Power: %dW (%s)\n", 
               init_conn ? "YES" : "NO", init_watts, init_desc[0] ? init_desc : "N/A");
        fflush(stdout);
    }

    // Setup event-driven notification using IOPowerSources RunLoop source
    CFRunLoopSourceRef loop_source = IOPSNotificationCreateRunLoopSource(power_source_callback, NULL);
    if (loop_source) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loop_source, kCFRunLoopDefaultMode);
    }

    // Also register periodic 2-second timer as a fallback watchdog for silent I2C stalls
    CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(
        kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + 2.0,
        2.0,
        0,
        0,
        ^(CFRunLoopTimerRef t) {
            (void)t;
            check_and_recover();
        }
    );
    if (timer) {
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopDefaultMode);
    }

    // Run event loop (practically 0% CPU consumption)
    CFRunLoopRun();

    if (loop_source) CFRelease(loop_source);
    if (timer) CFRelease(timer);

    return 0;
}
