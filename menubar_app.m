#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <AudioToolbox/AudioToolbox.h>
#import <notify.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTimer *timer;
@property (assign, nonatomic) BOOL lastConnected;
@property (assign, nonatomic) int consecutiveMisses;
@property (strong, nonatomic) NSImage *connectedBaseImage;
@property (strong, nonatomic) NSImage *disconnectedBaseImage;

- (void)updatePowerStateAndCheck;
@end

static void powerSourceNotificationCallback(void *context) {
    AppDelegate *delegate = (__bridge AppDelegate *)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate updatePowerStateAndCheck];
    });
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    (void)aNotification;
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    // Load high-resolution 3D battery base templates
    NSString *resPath = [[NSBundle mainBundle] resourcePath];
    NSString *connPath = [resPath stringByAppendingPathComponent:@"battery_connected_base.png"];
    NSString *disconnPath = [resPath stringByAppendingPathComponent:@"battery_disconnected_base.png"];

    // Fallbacks if running standalone binary outside app bundle
    if (![[NSFileManager defaultManager] fileExistsAtPath:connPath]) {
        connPath = [[NSBundle mainBundle] pathForResource:@"battery_connected_base" ofType:@"png"];
    }
    if (!connPath || ![[NSFileManager defaultManager] fileExistsAtPath:connPath]) {
        connPath = @"battery_connected_base.png";
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:connPath]) {
        connPath = @"/Volumes/backup-software/software/Macbook-Anker-Handshake/battery_connected_base.png";
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:disconnPath]) {
        disconnPath = [[NSBundle mainBundle] pathForResource:@"battery_disconnected_base" ofType:@"png"];
    }
    if (!disconnPath || ![[NSFileManager defaultManager] fileExistsAtPath:disconnPath]) {
        disconnPath = @"battery_disconnected_base.png";
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:disconnPath]) {
        disconnPath = @"/Volumes/backup-software/software/Macbook-Anker-Handshake/battery_disconnected_base.png";
    }

    self.connectedBaseImage = [[NSImage alloc] initWithContentsOfFile:connPath];
    self.disconnectedBaseImage = [[NSImage alloc] initWithContentsOfFile:disconnPath];

    [self updatePowerStateAndCheck];

    // Listen for power changes via IOKit event loop
    CFRunLoopSourceRef loopSource = IOPSNotificationCreateRunLoopSource(powerSourceNotificationCallback, (__bridge void *)self);
    if (loopSource) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loopSource, kCFRunLoopDefaultMode);
    }

    // Refresh every 1.5 seconds for instant real-time wattage updates
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        [weakSelf updatePowerStateAndCheck];
    }];
}

- (void)triggerKickstart {
    notify_post("com.apple.system.powersources.source");
    notify_post("com.apple.system.powersources.timer");

    IOPMAssertionID assertionID;
    IOReturn res = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("LowWattHandshakeKickstart"),
        &assertionID
    );
    if (res == kIOReturnSuccess) {
        usleep(150000);
        IOPMAssertionRelease(assertionID);
    }
    system("/usr/bin/killall -HUP powerd 2>/dev/null");
}

- (void)getDetailedPowerInfoConnected:(BOOL *)outConnected 
                         ratedWatts:(int *)outRatedWatts 
                        actualWatts:(double *)outActualWatts
                       batteryWatts:(double *)outBatteryWatts
                         inputVolts:(double *)outInputVolts
                          inputAmps:(double *)outInputAmps
                         isCharging:(BOOL *)outIsCharging
                        batteryPct:(int *)outBatteryPct
                               desc:(NSString **)outDesc {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    *outConnected = NO;
    *outRatedWatts = 0;
    *outActualWatts = 0.0;
    *outBatteryWatts = 0.0;
    *outInputVolts = 0.0;
    *outInputAmps = 0.0;
    *outIsCharging = NO;
    *outBatteryPct = 0;
    *outDesc = @"No Charger";

    if (!service) return;

    CFTypeRef extConn = IORegistryEntryCreateCFProperty(service, CFSTR("ExternalConnected"), kCFAllocatorDefault, 0);
    CFTypeRef isChg = IORegistryEntryCreateCFProperty(service, CFSTR("IsCharging"), kCFAllocatorDefault, 0);
    CFTypeRef curCap = IORegistryEntryCreateCFProperty(service, CFSTR("CurrentCapacity"), kCFAllocatorDefault, 0);
    CFTypeRef voltRef = IORegistryEntryCreateCFProperty(service, CFSTR("Voltage"), kCFAllocatorDefault, 0);
    CFTypeRef ampRef = IORegistryEntryCreateCFProperty(service, CFSTR("Amperage"), kCFAllocatorDefault, 0);
    CFDictionaryRef adapterDetails = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, CFSTR("AdapterDetails"), kCFAllocatorDefault, 0);
    CFDictionaryRef telemetry = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, CFSTR("PowerTelemetryData"), kCFAllocatorDefault, 0);

    if (extConn == kCFBooleanTrue) {
        *outConnected = YES;
    }
    if (isChg == kCFBooleanTrue) {
        *outIsCharging = YES;
    }
    if (curCap && CFGetTypeID(curCap) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)curCap, kCFNumberIntType, outBatteryPct);
    }

    if (adapterDetails && CFGetTypeID(adapterDetails) == CFDictionaryGetTypeID()) {
        CFNumberRef wattsNum = (CFNumberRef)CFDictionaryGetValue(adapterDetails, CFSTR("Watts"));
        if (wattsNum && CFGetTypeID(wattsNum) == CFNumberGetTypeID()) {
            CFNumberGetValue(wattsNum, kCFNumberIntType, outRatedWatts);
        }
        CFStringRef descStr = (CFStringRef)CFDictionaryGetValue(adapterDetails, CFSTR("Description"));
        if (descStr && CFGetTypeID(descStr) == CFStringGetTypeID()) {
            *outDesc = (__bridge NSString *)descStr;
        }
    }

    // 1. Primary: Hardware SystemPowerIn telemetry
    double sysLoad = 0.0;
    if (telemetry && CFGetTypeID(telemetry) == CFDictionaryGetTypeID()) {
        CFNumberRef pwrInNum = (CFNumberRef)CFDictionaryGetValue(telemetry, CFSTR("SystemPowerIn"));
        if (pwrInNum && CFGetTypeID(pwrInNum) == CFNumberGetTypeID()) {
            double val = 0.0;
            CFNumberGetValue(pwrInNum, kCFNumberDoubleType, &val);
            if (val > 0.0) {
                *outActualWatts = val / 1000.0;
            }
        }

        CFNumberRef batPwrNum = (CFNumberRef)CFDictionaryGetValue(telemetry, CFSTR("BatteryPower"));
        if (batPwrNum && CFGetTypeID(batPwrNum) == CFNumberGetTypeID()) {
            int64_t bp = 0;
            CFNumberGetValue(batPwrNum, kCFNumberSInt64Type, &bp);
            if (bp > 0) {
                *outBatteryWatts = ((double)bp) / 1000.0;
            }
        }

        CFNumberRef loadNum = (CFNumberRef)CFDictionaryGetValue(telemetry, CFSTR("SystemLoad"));
        if (loadNum && CFGetTypeID(loadNum) == CFNumberGetTypeID()) {
            double val = 0.0;
            CFNumberGetValue(loadNum, kCFNumberDoubleType, &val);
            sysLoad = val / 1000.0;
        }

        CFNumberRef vInNum = (CFNumberRef)CFDictionaryGetValue(telemetry, CFSTR("SystemVoltageIn"));
        if (vInNum && CFGetTypeID(vInNum) == CFNumberGetTypeID()) {
            double val = 0.0;
            CFNumberGetValue(vInNum, kCFNumberDoubleType, &val);
            *outInputVolts = val / 1000.0;
        }

        CFNumberRef curInNum = (CFNumberRef)CFDictionaryGetValue(telemetry, CFSTR("SystemCurrentIn"));
        if (curInNum && CFGetTypeID(curInNum) == CFNumberGetTypeID()) {
            double val = 0.0;
            CFNumberGetValue(curInNum, kCFNumberDoubleType, &val);
            *outInputAmps = val / 1000.0;
        }
    }

    // 2. Real-time Hardware Calculation: Voltage * Amperage
    double battPwrCalc = 0.0;
    if (voltRef && ampRef && CFGetTypeID(voltRef) == CFNumberGetTypeID() && CFGetTypeID(ampRef) == CFNumberGetTypeID()) {
        int64_t v = 0, a = 0;
        CFNumberGetValue((CFNumberRef)voltRef, kCFNumberSInt64Type, &v);
        CFNumberGetValue((CFNumberRef)ampRef, kCFNumberSInt64Type, &a);
        if (a > 0) {
            battPwrCalc = ((double)v * (double)a) / 1000000.0;
        }
    }

    if (*outBatteryWatts <= 0.0 && battPwrCalc > 0.0) {
        *outBatteryWatts = battPwrCalc;
    }

    // If actively charging battery, actual wattage includes battery charge flow + system load
    if (*outBatteryWatts > 0.0) {
        double totalDraw = *outBatteryWatts + (sysLoad > 0.0 ? sysLoad : 3.5);
        if (totalDraw > *outActualWatts) {
            *outActualWatts = totalDraw;
        }
    }

    // 3. Fallback: PowerDistribution IPDInputPower
    CFDictionaryRef pDist = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, CFSTR("PowerDistribution"), kCFAllocatorDefault, 0);
    if (pDist && CFGetTypeID(pDist) == CFDictionaryGetTypeID()) {
        CFNumberRef ipdNum = (CFNumberRef)CFDictionaryGetValue(pDist, CFSTR("IPDInputPower"));
        if (ipdNum && CFGetTypeID(ipdNum) == CFNumberGetTypeID()) {
            double ipdVal = 0.0;
            CFNumberGetValue(ipdNum, kCFNumberDoubleType, &ipdVal);
            if (ipdVal > 0.0 && *outActualWatts <= 0.0) {
                *outActualWatts = ipdVal / 1000.0;
            }
        }
        CFRelease(pDist);
    }

    // 4. Fallback if connected and drawing AC power
    if (*outConnected) {
        if (*outActualWatts <= 0.0) {
            if (sysLoad > 0.0) {
                *outActualWatts = sysLoad;
            } else if (*outRatedWatts > 0) {
                *outActualWatts = (double)(*outRatedWatts) * 0.85;
            }
        }
        // Allow actual wattage up to USB-PD maximum (240W) so 100+ W values show true actual power
        if (*outActualWatts > 240.0) {
            *outActualWatts = (*outRatedWatts > 0) ? (double)(*outRatedWatts) : 240.0;
        }
    } else {
        *outActualWatts = 0.0;
        *outBatteryWatts = 0.0;
    }

    if (voltRef) CFRelease(voltRef);
    if (ampRef) CFRelease(ampRef);
    if (adapterDetails) CFRelease(adapterDetails);
    if (telemetry) CFRelease(telemetry);
    if (extConn) CFRelease(extConn);
    if (isChg) CFRelease(isChg);
    if (curCap) CFRelease(curCap);
    IOObjectRelease(service);
}

- (NSImage *)generateBatteryIconWithConnected:(BOOL)connected 
                                  actualWatts:(double)actualWatts 
                                   ratedWatts:(int)ratedWatts {
    NSImage *baseImage = connected ? self.connectedBaseImage : self.disconnectedBaseImage;
    if (!baseImage) return nil;

    NSString *topText = @"";
    NSString *bottomText = @"";

    if (connected) {
        if (actualWatts > 0.0) {
            topText = [NSString stringWithFormat:@"%d W", (int)round(actualWatts)];
        } else {
            topText = @"0 W";
        }
        if (ratedWatts > 0) {
            bottomText = [NSString stringWithFormat:@"%d W", ratedWatts];
        } else {
            bottomText = @"0 W";
        }
    } else {
        topText = @"0 W";
        bottomText = @"0 W";
    }

    // High-visibility Tahoma-Bold font (both top & bottom same size: 10.0pt, -1px reduced)
    CGFloat fontSize = 10.0;
    NSFont *tahomaFont = [NSFont fontWithName:@"Tahoma-Bold" size:fontSize];
    if (!tahomaFont) tahomaFont = [NSFont fontWithName:@"Tahoma Bold" size:fontSize];
    if (!tahomaFont) tahomaFont = [NSFont boldSystemFontOfSize:fontSize];

    // Colors: Vibrant neon green for top text, Radiant bright yellow for bottom text
    NSColor *greenColor = [NSColor colorWithSRGBRed:0.20 green:1.0 blue:0.25 alpha:1.0];
    NSColor *yellowColor = [NSColor colorWithSRGBRed:1.0 green:0.86 blue:0.10 alpha:1.0];

    // Contrast shadow so it pops clearly against any background
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithSRGBRed:0.0 green:0.0 blue:0.0 alpha:0.9];
    shadow.shadowOffset = NSMakeSize(0, -1);
    shadow.shadowBlurRadius = 2.0;

    NSDictionary *topAttrs = @{
        NSFontAttributeName: tahomaFont,
        NSForegroundColorAttributeName: greenColor,
        NSShadowAttributeName: shadow
    };

    NSDictionary *bottomAttrs = @{
        NSFontAttributeName: tahomaFont,
        NSForegroundColorAttributeName: yellowColor,
        NSShadowAttributeName: shadow
    };

    NSSize topSize = [topText sizeWithAttributes:topAttrs];
    NSSize bottomSize = [bottomText sizeWithAttributes:bottomAttrs];
    CGFloat maxTextWidth = MAX(topSize.width, bottomSize.width);

    // Battery geometry (native Retina points: +2px size boost)
    CGFloat batteryHeight = 24.0;
    CGFloat batteryWidth = round(batteryHeight * (baseImage.size.width / baseImage.size.height)); // 16.0pt
    CGFloat spacing = 4.5;
    CGFloat totalWidth = batteryWidth + spacing + maxTextWidth + 2.0;
    CGFloat totalHeight = 24.0;

    // Vector drawing handler: renders at exact native screen pixel density with subpixel anti-aliasing
    NSImage *compositeImage = [NSImage imageWithSize:NSMakeSize(totalWidth, totalHeight) 
                                             flipped:NO 
                                      drawingHandler:^BOOL(NSRect dstRect) {
        (void)dstRect;
        // 1. Draw 3D battery on the left (with bolt when connected)
        NSRect battRect = NSMakeRect(0, 0, batteryWidth, batteryHeight);
        [baseImage drawInRect:battRect
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0];

        // 2. Draw Top Text (running capacity, e.g. 20.5 W)
        CGFloat textX = batteryWidth + spacing;
        NSRect topRect = NSMakeRect(textX, 12.0, maxTextWidth, topSize.height);
        [topText drawInRect:topRect withAttributes:topAttrs];

        // 3. Draw Bottom Text (charger max capacity, e.g. 20 W)
        NSRect bottomRect = NSMakeRect(textX, 1.5, maxTextWidth, bottomSize.height);
        [bottomText drawInRect:bottomRect withAttributes:bottomAttrs];

        return YES;
    }];

    return compositeImage;
}

- (void)updatePowerStateAndCheck {
    BOOL connected = NO;
    int ratedWatts = 0;
    double actualWatts = 0.0;
    double batteryWatts = 0.0;
    double inputVolts = 0.0;
    double inputAmps = 0.0;
    BOOL isCharging = NO;
    int batteryPct = 0;
    NSString *desc = nil;

    [self getDetailedPowerInfoConnected:&connected 
                             ratedWatts:&ratedWatts 
                            actualWatts:&actualWatts 
                           batteryWatts:&batteryWatts 
                             inputVolts:&inputVolts 
                              inputAmps:&inputAmps 
                             isCharging:&isCharging 
                            batteryPct:&batteryPct 
                                   desc:&desc];

    // Render custom 3D battery widget
    NSImage *batteryIcon = [self generateBatteryIconWithConnected:connected 
                                                      actualWatts:actualWatts 
                                                       ratedWatts:ratedWatts];

    if (self.statusItem.button) {
        self.statusItem.button.image = batteryIcon;
        self.statusItem.button.imagePosition = NSImageOnly;
        self.statusItem.button.title = @"";

        if (connected) {
            self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W (Max %d W)\nCharger: %@", (int)round(actualWatts), ratedWatts, desc];
        } else {
            self.statusItem.button.toolTip = @"LowWatt Handshake: Disconnected";
        }
    }

    // Automatic handshake stall detection & kickstart
    if (connected && !self.lastConnected) {
        if (ratedWatts > 0) {
            AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
            self.consecutiveMisses = 0;
        } else {
            [self triggerKickstart];
        }
        self.lastConnected = YES;
    } else if (!connected && self.lastConnected) {
        self.lastConnected = NO;
        self.consecutiveMisses = 0;
    } else if (connected && ratedWatts == 0) {
        self.consecutiveMisses++;
        if (self.consecutiveMisses <= 3) {
            [self triggerKickstart];
        }
    }

    [self updateStatusMenu];
}

- (void)updateStatusMenu {
    BOOL connected = NO;
    int ratedWatts = 0;
    double actualWatts = 0.0;
    double batteryWatts = 0.0;
    double inputVolts = 0.0;
    double inputAmps = 0.0;
    BOOL isCharging = NO;
    int batteryPct = 0;
    NSString *desc = nil;

    [self getDetailedPowerInfoConnected:&connected 
                             ratedWatts:&ratedWatts 
                            actualWatts:&actualWatts 
                           batteryWatts:&batteryWatts 
                             inputVolts:&inputVolts 
                              inputAmps:&inputAmps 
                             isCharging:&isCharging 
                            batteryPct:&batteryPct 
                                   desc:&desc];

    NSMenu *menu = [[NSMenu alloc] init];

    // Header info
    NSMenuItem *headItem = [[NSMenuItem alloc] initWithTitle:@"⚡ LowWatt Handshake macOS" action:nil keyEquivalent:@""];
    [headItem setEnabled:NO];
    [menu addItem:headItem];
    [menu addItem:[NSMenuItem separatorItem]];

    if (connected) {
        NSString *actualStr = [NSString stringWithFormat:@"⚡ Live Running Draw: %.1f W", actualWatts];
        NSMenuItem *actualItem = [[NSMenuItem alloc] initWithTitle:actualStr action:nil keyEquivalent:@""];
        [actualItem setEnabled:NO];
        [menu addItem:actualItem];

        NSString *flowStr = [NSString stringWithFormat:@"🔋 Battery Inflow: %.1f W (%@)", batteryWatts, isCharging ? @"Charging" : @"Idle/Held"];
        NSMenuItem *flowItem = [[NSMenuItem alloc] initWithTitle:flowStr action:nil keyEquivalent:@""];
        [flowItem setEnabled:NO];
        [menu addItem:flowItem];

        if (inputVolts > 0.0) {
            NSString *elecStr = [NSString stringWithFormat:@"⚡ Port Voltage: %.1f V @ %.2f A", inputVolts, inputAmps];
            NSMenuItem *elecItem = [[NSMenuItem alloc] initWithTitle:elecStr action:nil keyEquivalent:@""];
            [elecItem setEnabled:NO];
            [menu addItem:elecItem];
        }

        NSString *maxStr = [NSString stringWithFormat:@"🔌 Charger Max Capacity: %d W (%@)", ratedWatts, desc];
        NSMenuItem *maxItem = [[NSMenuItem alloc] initWithTitle:maxStr action:nil keyEquivalent:@""];
        [maxItem setEnabled:NO];
        [menu addItem:maxItem];
    } else {
        NSMenuItem *disconnItem = [[NSMenuItem alloc] initWithTitle:@"No USB-C Charger Connected" action:nil keyEquivalent:@""];
        [disconnItem setEnabled:NO];
        [menu addItem:disconnItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *kickItem = [[NSMenuItem alloc] initWithTitle:@"⚡ Force Handshake Kickstart" action:@selector(manualKickstart) keyEquivalent:@"k"];
    [kickItem setTarget:self];
    [menu addItem:kickItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit LowWatt Handshake" action:@selector(quitApp) keyEquivalent:@"q"];
    [quitItem setTarget:self];
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (void)manualKickstart {
    [self triggerKickstart];
    AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
    [self updatePowerStateAndCheck];
}

- (void)quitApp {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
