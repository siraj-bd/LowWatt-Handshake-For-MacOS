#include <stdio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <notify.h>
#include <unistd.h>

int main() {
    printf("[Kickstart] Sending deep power cycle notifications...\n");
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");
    notify_post("com.apple.system.powersources");
    notify_post("com.apple.PowerManagement.control");
    
    IOPMAssertionID assertionID;
    IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionLevelOn, CFSTR("HardHandshakeKick"), &assertionID);
    usleep(200000);
    IOPMAssertionRelease(assertionID);

    system("/usr/bin/killall -HUP powerd 2>/dev/null");
    printf("[Kickstart] Executed.\n");
    return 0;
}
