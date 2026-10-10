#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <AudioToolbox/AudioToolbox.h>
#import <notify.h>
#import "security_obfuscation.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) NSTimer *burstTimer;
@property (assign, nonatomic) int burstCounter;
@property (assign, nonatomic) BOOL lastConnected;
@property (strong, nonatomic) NSImage *connectedBaseImage;
@property (strong, nonatomic) NSImage *disconnectedBaseImage;
@property (copy, nonatomic) NSString *detectedBrand;

- (void)updatePowerStateAndCheck;
- (void)handlePowerChangeNotification;
- (void)startFastBurstPoll;
- (void)performSilentUpdateCheck;
- (void)checkForUpdates;
- (void)checkForUpdatesSilent:(BOOL)silent;
- (void)manualKickstart;
- (void)getDetailedPowerInfoConnected:(BOOL *)outConnected 
                          isPowerBank:(BOOL *)outIsPowerBank
                              isAnker:(BOOL *)outIsAnker
                           ratedWatts:(int *)outRatedWatts 
                          actualWatts:(double *)outActualWatts
                         batteryWatts:(double *)outBatteryWatts
                           inputVolts:(double *)outInputVolts
                            inputAmps:(double *)outInputAmps
                           isCharging:(BOOL *)outIsCharging
                   notChargingReason:(int *)outNotChargingReason
                           timeToFull:(int *)outTimeToFull
                         fullyCharged:(BOOL *)outFullyCharged
                           batteryPct:(int *)outBatteryPct
                                brand:(NSString **)outBrand
                                 desc:(NSString **)outDesc;
- (void)updateStatusMenuWithConnected:(BOOL)connected 
                          isPowerBank:(BOOL)isPowerBank 
                              isAnker:(BOOL)isAnker 
                                brand:(NSString *)brand
                           ratedWatts:(int)ratedWatts 
                          actualWatts:(double)actualWatts 
                         batteryWatts:(double)batteryWatts 
                           inputVolts:(double)inputVolts 
                            inputAmps:(double)inputAmps 
                           isCharging:(BOOL)isCharging 
                   notChargingReason:(int)notChargingReason 
                           timeToFull:(int)timeToFull
                         fullyCharged:(BOOL)fullyCharged
                           batteryPct:(int)batteryPct 
                                 desc:(NSString *)desc;
@end

static void powerSourceNotificationCallback(void *context) {
    AppDelegate *delegate = (__bridge AppDelegate *)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate handlePowerChangeNotification];
    });
}

@interface HeaderCardView : NSView
@property (nonatomic, strong) NSImage *logoImage;
@property (nonatomic, strong) NSString *titleText;
@property (nonatomic, strong) NSString *versionText;
@end

@implementation HeaderCardView
- (instancetype)initWithFrame:(NSRect)frame logoImage:(NSImage *)image title:(NSString *)title version:(NSString *)version {
    self = [super initWithFrame:frame];
    if (self) {
        _logoImage = image;
        _titleText = title;
        _versionText = version;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentCenter;

    // 1. App Name at top
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: para
    };
    NSRect titleRect = NSMakeRect(10, self.bounds.size.height - 24, self.bounds.size.width - 20, 18);
    [self.titleText drawInRect:titleRect withAttributes:titleAttrs];

    // 2. Main 3D Brand Logo centered right underneath the App Name
    if (self.logoImage && self.logoImage.size.height > 0) {
        CGFloat maxH = 50.0;
        CGFloat maxW = 50.0;
        CGFloat aspect = self.logoImage.size.width / self.logoImage.size.height;
        CGFloat iconH = maxH;
        CGFloat iconW = round(iconH * aspect);
        if (iconW > maxW) {
            iconW = maxW;
            iconH = round(iconW / aspect);
        }
        CGFloat iconX = round((self.bounds.size.width - iconW) / 2.0);
        CGFloat iconY = round(self.bounds.size.height - 26.0 - iconH - 4.0);
        NSRect iconRect = NSMakeRect(iconX, iconY, iconW, iconH);
        [self.logoImage drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    }

    // 3. Version text under the icon
    NSDictionary *verAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
        NSParagraphStyleAttributeName: para
    };
    NSRect verRect = NSMakeRect(10, 8, self.bounds.size.width - 20, 15);
    [self.versionText drawInRect:verRect withAttributes:verAttrs];
}
@end

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

    if (![[NSFileManager defaultManager] fileExistsAtPath:disconnPath]) {
        disconnPath = [[NSBundle mainBundle] pathForResource:@"battery_disconnected_base" ofType:@"png"];
    }
    if (!disconnPath || ![[NSFileManager defaultManager] fileExistsAtPath:disconnPath]) {
        disconnPath = @"battery_disconnected_base.png";
    }

    self.connectedBaseImage = [[NSImage alloc] initWithContentsOfFile:connPath];
    self.disconnectedBaseImage = [[NSImage alloc] initWithContentsOfFile:disconnPath];

    [self updatePowerStateAndCheck];

    // Listen for power changes via IOKit event loop
    CFRunLoopSourceRef loopSource = IOPSNotificationCreateRunLoopSource(powerSourceNotificationCallback, (__bridge void *)self);
    if (loopSource) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loopSource, kCFRunLoopCommonModes);
    }

    // Refresh every 0.2 seconds for instant real-time wattage updates
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        [weakSelf updatePowerStateAndCheck];
    }];
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];

    // Default auto-check updates to YES and run silent check after 10s
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCheckUpdates"] == nil) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"AutoCheckUpdates"];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AutoCheckUpdates"]) {
            [weakSelf performSilentUpdateCheck];
        }
    });
}

- (void)executeHandshakePulse {
    execute_hardware_handshake_pulse();
}

- (void)getDetailedPowerInfoConnected:(BOOL *)outConnected 
                          isPowerBank:(BOOL *)outIsPowerBank
                              isAnker:(BOOL *)outIsAnker
                           ratedWatts:(int *)outRatedWatts 
                          actualWatts:(double *)outActualWatts
                         batteryWatts:(double *)outBatteryWatts
                           inputVolts:(double *)outInputVolts
                            inputAmps:(double *)outInputAmps
                           isCharging:(BOOL *)outIsCharging
                   notChargingReason:(int *)outNotChargingReason
                           timeToFull:(int *)outTimeToFull
                         fullyCharged:(BOOL *)outFullyCharged
                           batteryPct:(int *)outBatteryPct
                                brand:(NSString **)outBrand
                                 desc:(NSString **)outDesc {
    char cbuf[32];
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(sec_get_cstr(K_AppleSmartBattery, sizeof(K_AppleSmartBattery), cbuf)));
    *outConnected = NO;
    *outIsPowerBank = NO;
    *outIsAnker = NO;
    *outRatedWatts = 0;
    *outActualWatts = 0.0;
    *outBatteryWatts = 0.0;
    *outInputVolts = 0.0;
    *outInputAmps = 0.0;
    *outIsCharging = NO;
    *outNotChargingReason = 0;
    *outTimeToFull = -1;
    *outFullyCharged = NO;
    *outBatteryPct = 0;
    *outBrand = @"";
    *outDesc = @"";

    if (!service) return;

    CFTypeRef extConn = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(ExternalConnected), kCFAllocatorDefault, 0);
    CFTypeRef rawExtConn = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(AppleRawExternalConnected), kCFAllocatorDefault, 0);
    CFTypeRef curCap = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(CurrentCapacity), kCFAllocatorDefault, 0);
    if (curCap && CFGetTypeID(curCap) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)curCap, kCFNumberIntType, outBatteryPct);
    }

    // Determine connection state:
    BOOL isConnected = (extConn == kCFBooleanTrue || rawExtConn == kCFBooleanTrue);
    if (!isConnected) {
        *outConnected = NO;
        *outRatedWatts = 0;
        *outActualWatts = 0.0;
        *outBatteryWatts = 0.0;
        *outIsCharging = NO;
        *outNotChargingReason = 0;
        *outIsPowerBank = NO;
        *outIsAnker = NO;
        *outTimeToFull = -1;
        *outFullyCharged = NO;
        *outBrand = @"";
        if (extConn) CFRelease(extConn);
        if (rawExtConn) CFRelease(rawExtConn);
        if (curCap) CFRelease(curCap);
        IOObjectRelease(service);
        return;
    }

    *outConnected = YES;
    CFTypeRef isChg = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(IsCharging), kCFAllocatorDefault, 0);
    if (isChg == kCFBooleanTrue) {
        *outIsCharging = YES;
    }

    int timeToFull = -1;
    CFTypeRef tFullRef = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(AvgTimeToFull), kCFAllocatorDefault, 0);
    if (tFullRef && CFGetTypeID(tFullRef) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)tFullRef, kCFNumberIntType, &timeToFull);
        CFRelease(tFullRef);
    }
    if (timeToFull <= 0 || timeToFull >= 65535) {
        CFTypeRef tRemRef = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(TimeRemaining), kCFAllocatorDefault, 0);
        if (tRemRef && CFGetTypeID(tRemRef) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)tRemRef, kCFNumberIntType, &timeToFull);
            CFRelease(tRemRef);
        }
    }
    *outTimeToFull = timeToFull;

    BOOL fullyCharged = NO;
    CFTypeRef fullyRef = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(FullyCharged), kCFAllocatorDefault, 0);
    if (fullyRef == kCFBooleanTrue) {
        fullyCharged = YES;
    }
    if (fullyRef) CFRelease(fullyRef);
    *outFullyCharged = fullyCharged;

    CFTypeRef voltRef = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(Voltage), kCFAllocatorDefault, 0);
    // InstantAmperage provides 100ms hardware response directly from Coulomb counter ADC
    CFTypeRef ampRef = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(InstantAmperage), kCFAllocatorDefault, 0);
    if (!ampRef) {
        ampRef = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(Amperage), kCFAllocatorDefault, 0);
    }
    CFDictionaryRef adapterDetails = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(AdapterDetails), kCFAllocatorDefault, 0);
    CFDictionaryRef telemetry = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(PowerTelemetryData), kCFAllocatorDefault, 0);
    CFArrayRef fedDetails = (CFArrayRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(FedDetails), kCFAllocatorDefault, 0);

    BOOL detectedDRP = NO;
    BOOL detectedAnker = NO;
    BOOL detectedBatterySupply = NO;
    BOOL detectedUnconstrained = NO;

    // 1. Read official Apple IOPowerSources external adapter details
    int iopsWatts = 0;
    CFDictionaryRef iopsDict = IOPSCopyExternalPowerAdapterDetails();
    if (iopsDict && CFGetTypeID(iopsDict) == CFDictionaryGetTypeID()) {
        CFNumberRef wNum = (CFNumberRef)CFDictionaryGetValue(iopsDict, SEC_CFSTR(Watts));
        if (wNum && CFGetTypeID(wNum) == CFNumberGetTypeID()) {
            CFNumberGetValue(wNum, kCFNumberIntType, &iopsWatts);
        }
        CFStringRef dStr = (CFStringRef)CFDictionaryGetValue(iopsDict, SEC_CFSTR(Description));
        if (dStr && CFGetTypeID(dStr) == CFStringGetTypeID()) {
            NSString *d = (__bridge NSString *)dStr;
            if ([d length] > 0) *outDesc = d;
        }
        CFRelease(iopsDict);
    }

    // 2. Read AppleRawAdapterDetails for the actively connected adapter (cleared by macOS when unplugged)
    int rawWatts = 0;
    int rawMenuMaxW = 0;
    CFArrayRef rawAdapters = (CFArrayRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(AppleRawAdapterDetails), kCFAllocatorDefault, 0);
    if (rawAdapters && CFGetTypeID(rawAdapters) == CFArrayGetTypeID() && CFArrayGetCount(rawAdapters) > 0) {
        CFDictionaryRef firstAd = (CFDictionaryRef)CFArrayGetValueAtIndex(rawAdapters, 0);
        if (firstAd && CFGetTypeID(firstAd) == CFDictionaryGetTypeID()) {
            CFNumberRef rwNum = (CFNumberRef)CFDictionaryGetValue(firstAd, SEC_CFSTR(Watts));
            if (rwNum && CFGetTypeID(rwNum) == CFNumberGetTypeID()) {
                CFNumberGetValue(rwNum, kCFNumberIntType, &rawWatts);
            }
            CFNumberRef pmuNum = (CFNumberRef)CFDictionaryGetValue(firstAd, SEC_CFSTR(PMUConfiguration));
            if (pmuNum && CFGetTypeID(pmuNum) == CFNumberGetTypeID()) {
                int pmuVal = 0;
                CFNumberGetValue(pmuNum, kCFNumberIntType, &pmuVal);
                if (pmuVal > 0 && rawWatts <= 0) {
                    rawWatts = (int)round((double)pmuVal / 1000.0);
                }
            }
            CFArrayRef hvcMenu = (CFArrayRef)CFDictionaryGetValue(firstAd, SEC_CFSTR(UsbHvcMenu));
            if (hvcMenu && CFGetTypeID(hvcMenu) == CFArrayGetTypeID()) {
                CFIndex mCount = CFArrayGetCount(hvcMenu);
                for (CFIndex m = 0; m < mCount; m++) {
                    CFDictionaryRef mItem = (CFDictionaryRef)CFArrayGetValueAtIndex(hvcMenu, m);
                    if (mItem && CFGetTypeID(mItem) == CFDictionaryGetTypeID()) {
                        CFNumberRef vNum = (CFNumberRef)CFDictionaryGetValue(mItem, SEC_CFSTR(MaxVoltage));
                        CFNumberRef cNum = (CFNumberRef)CFDictionaryGetValue(mItem, SEC_CFSTR(MaxCurrent));
                        if (vNum && cNum) {
                            int mv = 0, ma = 0;
                            CFNumberGetValue(vNum, kCFNumberIntType, &mv);
                            CFNumberGetValue(cNum, kCFNumberIntType, &ma);
                            int mw = (int)round(((double)mv * (double)ma) / 1000000.0);
                            if (mw > rawMenuMaxW) rawMenuMaxW = mw;
                        }
                    }
                }
            }
        }
        CFRelease(rawAdapters);
    }

    // 3. Read AdapterDetails
    int adapterWatts = 0;
    if (adapterDetails && CFGetTypeID(adapterDetails) == CFDictionaryGetTypeID()) {
        CFNumberRef wattsNum = (CFNumberRef)CFDictionaryGetValue(adapterDetails, SEC_CFSTR(Watts));
        if (wattsNum && CFGetTypeID(wattsNum) == CFNumberGetTypeID()) {
            CFNumberGetValue(wattsNum, kCFNumberIntType, &adapterWatts);
        }
        if (adapterWatts <= 0) {
            CFNumberRef vNum = (CFNumberRef)CFDictionaryGetValue(adapterDetails, SEC_CFSTR(AdapterVoltage));
            CFNumberRef cNum = (CFNumberRef)CFDictionaryGetValue(adapterDetails, SEC_CFSTR(Current));
            if (vNum && cNum) {
                int64_t vVal = 0, cVal = 0;
                CFNumberGetValue((CFNumberRef)vNum, kCFNumberSInt64Type, &vVal);
                CFNumberGetValue((CFNumberRef)cNum, kCFNumberSInt64Type, &cVal);
                if (vVal > 0 && cVal > 0) {
                    adapterWatts = (int)round(((double)vVal * (double)cVal) / 1000000.0);
                }
            }
        }
        CFStringRef descStr = (CFStringRef)CFDictionaryGetValue(adapterDetails, SEC_CFSTR(Description));
        if (descStr && CFGetTypeID(descStr) == CFStringGetTypeID()) {
            NSString *d = (__bridge NSString *)descStr;
            if ([d length] > 0) *outDesc = d;
        }
    }

    int connectedPortIdx = -1;

    // 4. Query physical USB-C Port Controllers for actively connected port PDOs
    CFArrayRef portInfo = (CFArrayRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(PortControllerInfo), kCFAllocatorDefault, 0);
    int portPdoMaxW = 0;
    if (portInfo && CFGetTypeID(portInfo) == CFArrayGetTypeID()) {
        CFIndex portCount = CFArrayGetCount(portInfo);

        // Step 1: Detect actively connected port where hardware attach > detach count
        // If multiple ports are connected, select the winning provider (loser == 0)
        for (CFIndex i = 0; i < portCount; i++) {
            CFDictionaryRef pDict = (CFDictionaryRef)CFArrayGetValueAtIndex(portInfo, i);
            if (pDict && CFGetTypeID(pDict) == CFDictionaryGetTypeID()) {
                int attach = 0, detach = 0, loser = 1;
                CFNumberRef attNum = (CFNumberRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerAttachCount));
                CFNumberRef detNum = (CFNumberRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerDetachCount));
                CFNumberRef losNum = (CFNumberRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerLoserReason));
                if (attNum && CFGetTypeID(attNum) == CFNumberGetTypeID()) CFNumberGetValue(attNum, kCFNumberIntType, &attach);
                if (detNum && CFGetTypeID(detNum) == CFNumberGetTypeID()) CFNumberGetValue(detNum, kCFNumberIntType, &detach);
                if (losNum && CFGetTypeID(losNum) == CFNumberGetTypeID()) CFNumberGetValue(losNum, kCFNumberIntType, &loser);
                if (attach > detach) {
                    if (connectedPortIdx < 0 || loser == 0) {
                        connectedPortIdx = (int)i;
                    }
                }
            }
        }

        // Step 2: Fallback if attach count equals detach count during transient:
        // Identify port with active power FETs and winning contract (FetStatus > 0 && LoserReason == 0)
        if (connectedPortIdx < 0) {
            for (CFIndex i = 0; i < portCount; i++) {
                CFDictionaryRef pDict = (CFDictionaryRef)CFArrayGetValueAtIndex(portInfo, i);
                if (pDict && CFGetTypeID(pDict) == CFDictionaryGetTypeID()) {
                    int loser = 1, fet = 0;
                    CFNumberRef losNum = (CFNumberRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerLoserReason));
                    CFNumberRef fetNum = (CFNumberRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerFetStatus));
                    if (losNum && CFGetTypeID(losNum) == CFNumberGetTypeID()) CFNumberGetValue(losNum, kCFNumberIntType, &loser);
                    if (fetNum && CFGetTypeID(fetNum) == CFNumberGetTypeID()) CFNumberGetValue(fetNum, kCFNumberIntType, &fet);
                    if (loser == 0 && fet > 0) {
                        connectedPortIdx = (int)i;
                        break;
                    }
                }
            }
        }

        if (connectedPortIdx < 0) {
            connectedPortIdx = 0;
        }

        // Strictly only parse if a port is physically attached (attach > detach)
        if (connectedPortIdx >= 0 && (CFIndex)connectedPortIdx < portCount) {
            CFDictionaryRef pDict = (CFDictionaryRef)CFArrayGetValueAtIndex(portInfo, connectedPortIdx);
            if (pDict && CFGetTypeID(pDict) == CFDictionaryGetTypeID()) {
                int npdo = 0;
                CFNumberRef npdoNum = (CFNumberRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerNPDOs));
                if (npdoNum && CFGetTypeID(npdoNum) == CFNumberGetTypeID()) {
                    CFNumberGetValue(npdoNum, kCFNumberIntType, &npdo);
                }
                CFArrayRef pdoArr = (CFArrayRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerPortPDO));
                if (pdoArr && CFGetTypeID(pdoArr) == CFArrayGetTypeID() && npdo > 0) {
                    for (int pIdx = 0; pIdx < npdo && pIdx < (int)CFArrayGetCount(pdoArr); pIdx++) {
                        CFNumberRef pdoNum = (CFNumberRef)CFArrayGetValueAtIndex(pdoArr, pIdx);
                        if (pdoNum && CFGetTypeID(pdoNum) == CFNumberGetTypeID()) {
                            int64_t pdoVal = 0;
                            CFNumberGetValue(pdoNum, kCFNumberSInt64Type, &pdoVal);
                            uint32_t u = (uint32_t)(pdoVal & 0xFFFFFFFF);
                            int pwrType = (int)((u >> 30) & 0x3);
                            if (pwrType == 0) { // Fixed supply PDO
                                double v = ((double)((u >> 10) & 0x3FF)) * 0.05;
                                double c = ((double)(u & 0x3FF)) * 0.01;
                                int w = (int)round(v * c);
                                if ((u >> 29) & 1) detectedDRP = YES;
                                if ((u >> 27) & 1) detectedUnconstrained = YES;
                                if (w > portPdoMaxW) portPdoMaxW = w;
                            } else if (pwrType == 1) { // Battery PDO
                                detectedBatterySupply = YES;
                                double mw = ((double)(u & 0x3FF)) * 0.25;
                                int w = (int)round(mw);
                                if (w > portPdoMaxW) portPdoMaxW = w;
                            } else if (pwrType == 2) { // Variable supply PDO
                                double vMax = ((double)((u >> 20) & 0x3FF)) * 0.05;
                                double c = ((double)(u & 0x3FF)) * 0.01;
                                int w = (int)round(vMax * c);
                                if (w > portPdoMaxW) portPdoMaxW = w;
                            } else if (pwrType == 3) { // PPS / APDO
                                double vMax = ((double)((u >> 17) & 0xFF)) * 0.1;
                                double c = ((double)(u & 0x7F)) * 0.05;
                                int w = (int)round(vMax * c);
                                if (w > portPdoMaxW) portPdoMaxW = w;
                            }
                        }
                    }
                }
            }
        }
        CFRelease(portInfo);
    }
    (void)detectedUnconstrained;

    // Determine Rated Capacity (Yellow Text):
    // Strictly prioritize the actual attached charger/power bank negotiated wattage
    int rated = 0;
    if (rawMenuMaxW > 0) {
        rated = rawMenuMaxW;
    } else if (portPdoMaxW > 0) {
        rated = portPdoMaxW;
    } else if (adapterWatts > 0) {
        rated = adapterWatts;
    } else if (rawWatts > 0) {
        rated = rawWatts;
    } else if (iopsWatts > 0) {
        rated = iopsWatts;
    }
    *outRatedWatts = rated;

    NSString *detectedBrand = @"";
    if (fedDetails && CFGetTypeID(fedDetails) == CFArrayGetTypeID()) {
        CFIndex fedCount = CFArrayGetCount(fedDetails);
        CFIndex targetIdx = (connectedPortIdx >= 0 && (CFIndex)connectedPortIdx < fedCount) ? (CFIndex)connectedPortIdx : 0;
        if (targetIdx < fedCount) {
            CFDictionaryRef fDict = (CFDictionaryRef)CFArrayGetValueAtIndex(fedDetails, targetIdx);
            if (fDict && CFGetTypeID(fDict) == CFDictionaryGetTypeID()) {
                CFNumberRef vidNum = (CFNumberRef)CFDictionaryGetValue(fDict, SEC_CFSTR(FedVendorID));
                if (vidNum && CFGetTypeID(vidNum) == CFNumberGetTypeID()) {
                    int vidVal = 0;
                    CFNumberGetValue(vidNum, kCFNumberIntType, &vidVal);
                    if (vidVal == 12572) {
                        detectedAnker = YES;
                        detectedBrand = @"Anker";
                    } else if (vidVal == 1452) {
                        detectedBrand = @"Apple";
                    } else if (vidVal == 1278 || vidVal == 4817) {
                        detectedBrand = @"Belkin";
                    } else if (vidVal == 7529) {
                        detectedBrand = @"UGREEN";
                    } else if (vidVal == 1027 || vidVal == 12270) {
                        detectedBrand = @"Baseus";
                    } else if (vidVal == 1256) {
                        detectedBrand = @"Samsung";
                    } else if (vidVal == 1121 || vidVal == 1879) {
                        detectedBrand = @"Aukey";
                    } else if (vidVal == 11780) {
                        detectedBrand = @"Shargeek";
                    } else if (vidVal == 10300) {
                        detectedBrand = @"Satechi";
                    } else if (vidVal == 6127) {
                        detectedBrand = @"Lenovo";
                    } else if (vidVal == 16700) {
                        detectedBrand = @"Dell";
                    } else if (vidVal == 1008) {
                        detectedBrand = @"HP";
                    }
                }
                CFNumberRef drpNum = (CFNumberRef)CFDictionaryGetValue(fDict, SEC_CFSTR(FedDualRolePower));
                if (drpNum && CFGetTypeID(drpNum) == CFNumberGetTypeID()) {
                    int drpVal = 0;
                    CFNumberGetValue(drpNum, kCFNumberIntType, &drpVal);
                    if (drpVal == 1) detectedDRP = YES;
                }
            }
        }
    }

    NSString *combinedDesc = [NSString stringWithFormat:@"%@ %@", (*outDesc ?: @""), (adapterDetails ? [(__bridge NSDictionary *)adapterDetails description] : @"")].lowercaseString;
    if (detectedBrand.length == 0) {
        if ([combinedDesc containsString:@"anker"]) { detectedBrand = @"Anker"; detectedAnker = YES; }
        else if ([combinedDesc containsString:@"apple"]) detectedBrand = @"Apple";
        else if ([combinedDesc containsString:@"belkin"]) detectedBrand = @"Belkin";
        else if ([combinedDesc containsString:@"ugreen"]) detectedBrand = @"UGREEN";
        else if ([combinedDesc containsString:@"baseus"]) detectedBrand = @"Baseus";
        else if ([combinedDesc containsString:@"samsung"]) detectedBrand = @"Samsung";
        else if ([combinedDesc containsString:@"aukey"]) detectedBrand = @"Aukey";
        else if ([combinedDesc containsString:@"sharge"]) detectedBrand = @"Shargeek";
        else if ([combinedDesc containsString:@"satechi"]) detectedBrand = @"Satechi";
        else if ([combinedDesc containsString:@"mophie"]) detectedBrand = @"Mophie";
        else if ([combinedDesc containsString:@"ravpower"]) detectedBrand = @"RAVPower";
        else if ([combinedDesc containsString:@"xiaomi"]) detectedBrand = @"Xiaomi";
        else if ([combinedDesc containsString:@"lenovo"]) detectedBrand = @"Lenovo";
        else if ([combinedDesc containsString:@"dell"]) detectedBrand = @"Dell";
        else if ([combinedDesc containsString:@"hp"]) detectedBrand = @"HP";
    }

    // Power bank vs Wall charger classification
    // 100% hardware-driven: Dual-Role Power (DRP) or Battery PDO identifies Power Bank
    // Wall chargers physically lack internal batteries and cannot act as a Sink (DRP == 0)
    BOOL isPB = NO;
    if (detectedBatterySupply || detectedDRP) {
        // Dual-Role Power (DRP) or Battery Supply PDO proves portable battery / power bank at ANY wattage (5W to 140W+)
        isPB = YES;
    } else if ([combinedDesc containsString:@"power bank"] || 
               [combinedDesc containsString:@"powerbank"] || 
               [combinedDesc containsString:@"portable battery"] ||
               [combinedDesc containsString:@"battery pack"]) {
        isPB = YES;
    } else {
        isPB = NO;
    }

    *outIsPowerBank = isPB;
    *outIsAnker = (detectedAnker || [detectedBrand isEqualToString:@"Anker"]);
    *outBrand = detectedBrand;

    // Live battery charging wattage from instantaneous ADC (Coulomb counter)
    int64_t v = 0, rawAmp = 0;
    if (voltRef && CFGetTypeID(voltRef) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)voltRef, kCFNumberSInt64Type, &v);
    }
    if (ampRef && CFGetTypeID(ampRef) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)ampRef, kCFNumberSInt64Type, &rawAmp);
    }
    // Cast to signed 32-bit int to correctly handle negative values (e.g. 18446744073709550943 -> -673 mA)
    int32_t instAmp = (int32_t)(rawAmp & 0xFFFFFFFF);

    double batDataPower = 0.0;
    CFDictionaryRef batData = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(BatteryData), kCFAllocatorDefault, 0);
    if (batData && CFGetTypeID(batData) == CFDictionaryGetTypeID()) {
        CFNumberRef bpNum = (CFNumberRef)CFDictionaryGetValue(batData, SEC_CFSTR(BatteryPower));
        if (bpNum && CFGetTypeID(bpNum) == CFNumberGetTypeID()) {
            double val = 0.0;
            CFNumberGetValue(bpNum, kCFNumberDoubleType, &val);
            if (val > 0.0) batDataPower = val / 1000.0;
        }
        CFRelease(batData);
    }

    if (v > 0 && instAmp > 0) {
        *outBatteryWatts = ((double)v * (double)instAmp) / 1000000.0;
    } else if (batDataPower > 0.0) {
        *outBatteryWatts = batDataPower;
    } else {
        *outBatteryWatts = 0.0;
    }

    // Read NotChargingReason and PMUConfigured from ChargerData
    int notChargingReason = 0;
    int pmuConfigured = 0;
    CFDictionaryRef chgData = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(ChargerData), kCFAllocatorDefault, 0);
    if (chgData && CFGetTypeID(chgData) == CFDictionaryGetTypeID()) {
        CFNumberRef pmuConfNum = (CFNumberRef)CFDictionaryGetValue(chgData, SEC_CFSTR(PMUConfigured));
        if (pmuConfNum && CFGetTypeID(pmuConfNum) == CFNumberGetTypeID()) {
            CFNumberGetValue(pmuConfNum, kCFNumberIntType, &pmuConfigured);
        }
        CFNumberRef ncrNum = (CFNumberRef)CFDictionaryGetValue(chgData, SEC_CFSTR(NotChargingReason));
        if (ncrNum && CFGetTypeID(ncrNum) == CFNumberGetTypeID()) {
            CFNumberGetValue(ncrNum, kCFNumberIntType, &notChargingReason);
        }
        CFRelease(chgData);
    }
    *outNotChargingReason = notChargingReason;

    double pmuWatts = 0.0;
    BOOL isHoldLimited = ((notChargingReason & (1 << 24)) != 0);
    if (v > 0 && pmuConfigured > 0 && !isHoldLimited) {
        pmuWatts = ((double)v * (double)pmuConfigured) / 1000000.0;
    }

    // Read PowerDistribution target negotiated by PMU
    int ipdWattageOverride = 0;
    CFDictionaryRef pwrDist = (CFDictionaryRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(PowerDistribution), kCFAllocatorDefault, 0);
    if (pwrDist && CFGetTypeID(pwrDist) == CFDictionaryGetTypeID()) {
        CFNumberRef ipdNum = (CFNumberRef)CFDictionaryGetValue(pwrDist, SEC_CFSTR(IPDWattageOverride));
        if (ipdNum && CFGetTypeID(ipdNum) == CFNumberGetTypeID()) {
            CFNumberGetValue(ipdNum, kCFNumberIntType, &ipdWattageOverride);
        }
        CFRelease(pwrDist);
    }

    double targetChargeWatts = 0.0;
    if (ipdWattageOverride > 0) {
        targetChargeWatts = ((double)ipdWattageOverride / 1000.0) * 0.92;
    } else if (pmuWatts > 0.0) {
        targetChargeWatts = pmuWatts * 0.75;
    } else if (*outRatedWatts > 0) {
        targetChargeWatts = MIN(30.0, (double)*outRatedWatts) * 0.92;
    }
    if (*outRatedWatts > 0 && targetChargeWatts > (double)*outRatedWatts) {
        targetChargeWatts = (double)*outRatedWatts * 0.92;
    }

    // Live system load & telemetry from PMU
    double sysLoad = 0.0;
    double sysPwrIn = 0.0;
    if (telemetry && CFGetTypeID(telemetry) == CFDictionaryGetTypeID()) {
        CFNumberRef loadNum = (CFNumberRef)CFDictionaryGetValue(telemetry, SEC_CFSTR(SystemLoad));
        if (loadNum && CFGetTypeID(loadNum) == CFNumberGetTypeID()) {
            int64_t iVal = 0;
            CFNumberGetValue(loadNum, kCFNumberSInt64Type, &iVal);
            if (iVal > 0 && iVal < 200000) {
                sysLoad = (double)iVal / 1000.0;
            }
        }

        CFNumberRef vInNum = (CFNumberRef)CFDictionaryGetValue(telemetry, SEC_CFSTR(SystemVoltageIn));
        if (vInNum && CFGetTypeID(vInNum) == CFNumberGetTypeID()) {
            double val = 0.0;
            CFNumberGetValue(vInNum, kCFNumberDoubleType, &val);
            *outInputVolts = val / 1000.0;
        }

        CFNumberRef curInNum = (CFNumberRef)CFDictionaryGetValue(telemetry, SEC_CFSTR(SystemCurrentIn));
        if (curInNum && CFGetTypeID(curInNum) == CFNumberGetTypeID()) {
            double val = 0.0;
            CFNumberGetValue(curInNum, kCFNumberDoubleType, &val);
            *outInputAmps = val / 1000.0;
        }

        CFNumberRef pwrInNum = (CFNumberRef)CFDictionaryGetValue(telemetry, SEC_CFSTR(SystemPowerIn));
        if (pwrInNum && CFGetTypeID(pwrInNum) == CFNumberGetTypeID()) {
            double val = 0.0;
            CFNumberGetValue(pwrInNum, kCFNumberDoubleType, &val);
            if (val > 0.0) sysPwrIn = val / 1000.0;
        }
    }

    // Accurate Live Power Draw (Green Text):
    // 1. Direct steady-state PMU wall telemetry (sysPwrIn >= 10.0W)
    // 2. Instantaneous Coulomb counter ADC + system load (instantTotal >= 10.0W)
    // 3. Sub-second negotiated charging profile (targetChargeWatts) during macOS 30s AC inrush qualification timer
    double liveWatts = 0.0;
    double loadWatts = (sysLoad > 0.0 && sysLoad < 50.0) ? sysLoad : 5.0;

    double instantTotal = 0.0;
    if (*outBatteryWatts > 0.0) {
        instantTotal = *outBatteryWatts + loadWatts;
    }

    if (sysPwrIn >= 10.0) {
        // Direct steady-state PMU wall telemetry
        liveWatts = sysPwrIn;
    } else if (instantTotal >= 10.0) {
        // Active Coulomb counter charging measurement
        liveWatts = MAX(instantTotal, sysPwrIn);
    } else if (isConnected && targetChargeWatts > 0.0 && (*outBatteryPct < 100)) {
        // Instant response (< 200ms) during macOS 30-second AC qualification period
        liveWatts = targetChargeWatts;
    } else if (instantTotal > 0.0) {
        liveWatts = instantTotal;
    } else if (sysPwrIn > 0.0) {
        liveWatts = sysPwrIn;
    } else if (*outInputVolts > 0.0 && *outInputAmps > 0.0) {
        liveWatts = (*outInputVolts) * (*outInputAmps);
    } else if (isConnected) {
        // Connected to AC, but battery is not charging (e.g. 100% full or Reason 128 hold)
        liveWatts = loadWatts;
    } else {
        liveWatts = 0.0;
    }

    // Live draw can never exceed the physical rated capacity of the attached device
    if (*outRatedWatts > 0 && liveWatts > (double)*outRatedWatts) {
        liveWatts = (double)*outRatedWatts;
    }
    if (liveWatts < 0.0) {
        liveWatts = 0.0;
    }
    *outActualWatts = liveWatts;

    if (voltRef) CFRelease(voltRef);
    if (ampRef) CFRelease(ampRef);
    if (adapterDetails) CFRelease(adapterDetails);
    if (telemetry) CFRelease(telemetry);
    if (fedDetails) CFRelease(fedDetails);
    if (extConn) CFRelease(extConn);
    if (rawExtConn) CFRelease(rawExtConn);
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

- (void)startFastBurstPoll {
    self.burstCounter = 50; // 50 ticks * 100ms = 5.0 seconds burst of fast hardware polls
    if (self.burstTimer) {
        [self.burstTimer invalidate];
        self.burstTimer = nil;
    }
    __weak typeof(self) weakSelf = self;
    self.burstTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull bTimer) {
        [weakSelf updatePowerStateAndCheck];
        weakSelf.burstCounter--;
        if (weakSelf.burstCounter <= 0) {
            [bTimer invalidate];
            weakSelf.burstTimer = nil;
        }
    }];
}

- (void)handlePowerChangeNotification {
    [self startFastBurstPoll];
    [self updatePowerStateAndCheck];
}

- (void)updatePowerStateAndCheck {
    BOOL connected = NO;
    BOOL isPowerBank = NO;
    BOOL isAnker = NO;
    int ratedWatts = 0;
    double actualWatts = 0.0;
    double batteryWatts = 0.0;
    double inputVolts = 0.0;
    double inputAmps = 0.0;
    BOOL isCharging = NO;
    int notChargingReason = 0;
    int timeToFull = -1;
    BOOL fullyCharged = NO;
    int batteryPct = 0;
    NSString *brand = nil;
    NSString *desc = nil;

    [self getDetailedPowerInfoConnected:&connected 
                            isPowerBank:&isPowerBank 
                                isAnker:&isAnker 
                             ratedWatts:&ratedWatts 
                            actualWatts:&actualWatts 
                           batteryWatts:&batteryWatts 
                             inputVolts:&inputVolts 
                              inputAmps:&inputAmps 
                             isCharging:&isCharging 
                      notChargingReason:&notChargingReason
                             timeToFull:&timeToFull
                           fullyCharged:&fullyCharged
                             batteryPct:&batteryPct 
                                  brand:&brand
                                   desc:&desc];
    self.detectedBrand = brand;

    // Trigger fast 100ms burst on state changes (plug in / unplug)
    if (connected != self.lastConnected) {
        [self startFastBurstPoll];
    }

    // Render custom 3D battery widget
    NSImage *batteryIcon = [self generateBatteryIconWithConnected:connected 
                                                      actualWatts:actualWatts 
                                                       ratedWatts:ratedWatts];

    if (self.statusItem.button) {
        self.statusItem.button.image = batteryIcon;
        self.statusItem.button.imagePosition = NSImageOnly;
        self.statusItem.button.title = @"";

        if (connected) {
            NSString *type;
            if (isPowerBank) {
                type = brand.length > 0 ? [NSString stringWithFormat:@"%@ Power Bank", brand] : @"Power Bank";
            } else {
                type = brand.length > 0 ? [NSString stringWithFormat:@"%@ Power Adapter", brand] : @"Power Adapter";
            }
            if (isCharging || (actualWatts >= 5.0 && batteryPct < 100)) {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W\nBattery: Charging (%d%%)\nSource: %@ (Max %d W)", (int)round(actualWatts), batteryPct, type, ratedWatts];
            } else if (fullyCharged || batteryPct >= 100) {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W (Idle Draw)\nBattery: Fully Charged (%d%%)\nSource: %@ (Max %d W)", (int)round(actualWatts), batteryPct, type, ratedWatts];
            } else if ((notChargingReason & (1 << 24)) != 0) {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W (Idle Draw)\nBattery Charging: Paused (Charge Limit Hold at %d%%)\nSource: %@ (Max %d W)", (int)round(actualWatts), batteryPct, type, ratedWatts];
            } else {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W (Max %d W)\nSource: %@", (int)round(actualWatts), ratedWatts, type];
            }
        } else {
            self.statusItem.button.toolTip = @"LowWatt Handshake: Disconnected";
        }
    }

    // Handshake connection audio alert & state tracking
    if (connected && !self.lastConnected) {
        [self startFastBurstPoll];
        AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
        self.lastConnected = YES;
    } else if (!connected && self.lastConnected) {
        [self startFastBurstPoll];
        self.lastConnected = NO;
    }

    [self updateStatusMenuWithConnected:connected 
                            isPowerBank:isPowerBank 
                                isAnker:isAnker 
                                  brand:brand
                             ratedWatts:ratedWatts 
                            actualWatts:actualWatts 
                           batteryWatts:batteryWatts 
                             inputVolts:inputVolts 
                              inputAmps:inputAmps 
                             isCharging:isCharging 
                      notChargingReason:notChargingReason
                             timeToFull:timeToFull
                           fullyCharged:fullyCharged
                             batteryPct:batteryPct 
                                   desc:desc];
}

- (NSImage *)loadBrandLogo {
    if (self.connectedBaseImage) {
        return self.connectedBaseImage;
    }
    NSString *resPath = [[NSBundle mainBundle] resourcePath];
    if (resPath) {
        NSString *pConn = [resPath stringByAppendingPathComponent:@"battery_connected_base.png"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:pConn]) {
            return [[NSImage alloc] initWithContentsOfFile:pConn];
        }
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"battery_connected_base.png"]) {
        return [[NSImage alloc] initWithContentsOfFile:@"battery_connected_base.png"];
    }
    return nil;
}

- (void)updateStatusMenuWithConnected:(BOOL)connected 
                          isPowerBank:(BOOL)isPowerBank 
                              isAnker:(BOOL)isAnker 
                                brand:(NSString *)brand
                           ratedWatts:(int)ratedWatts 
                          actualWatts:(double)actualWatts 
                         batteryWatts:(double)batteryWatts 
                           inputVolts:(double)inputVolts 
                            inputAmps:(double)inputAmps 
                           isCharging:(BOOL)isCharging 
                    notChargingReason:(int)notChargingReason 
                           timeToFull:(int)timeToFull
                         fullyCharged:(BOOL)fullyCharged
                           batteryPct:(int)batteryPct 
                                 desc:(NSString *)desc {
    (void)isAnker;
    (void)desc;
    NSMenu *menu = [[NSMenu alloc] init];

    // 1. Apple-style Header Card (App Name -> 3D Brand Logo -> Version)
    NSImage *brandLogo = [self loadBrandLogo];
    HeaderCardView *cardView = [[HeaderCardView alloc] initWithFrame:NSMakeRect(0, 0, 260, 108)
                                                           logoImage:brandLogo
                                                               title:@"LowWatt Handshake macOS"
                                                             version:@"Version 1.0.0"];
    NSMenuItem *cardItem = [[NSMenuItem alloc] init];
    cardItem.view = cardView;
    [menu addItem:cardItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // 2. Clean left-aligned power status (Native Apple System Profiler style)
    if (connected) {
        NSString *srcTitle;
        NSString *ratingTitle;
        if (isPowerBank) {
            if (brand.length > 0) {
                srcTitle = [NSString stringWithFormat:@"Power Source: Power Bank (%@)", brand];
            } else {
                srcTitle = @"Power Source: Power Bank";
            }
            ratingTitle = [NSString stringWithFormat:@"Power Bank Rating: %d W", ratedWatts];
        } else {
            if (brand.length > 0) {
                srcTitle = [NSString stringWithFormat:@"Power Source: Power Adapter (%@)", brand];
            } else {
                srcTitle = @"Power Source: Power Adapter";
            }
            ratingTitle = [NSString stringWithFormat:@"Charger Rating: %d W", ratedWatts];
        }

        NSMenuItem *srcItem = [[NSMenuItem alloc] initWithTitle:srcTitle action:nil keyEquivalent:@""];
        [srcItem setEnabled:NO];
        [menu addItem:srcItem];

        NSString *liveDrawStr = [NSString stringWithFormat:@"Live Power Draw: %d W", (int)round(actualWatts)];
        NSMenuItem *drawItem = [[NSMenuItem alloc] initWithTitle:liveDrawStr action:nil keyEquivalent:@""];
        [drawItem setEnabled:NO];
        [menu addItem:drawItem];

        NSString *batChgStr;
        if (batteryWatts > 0.0) {
            batChgStr = [NSString stringWithFormat:@"Battery Charging Rate: %.1f W", batteryWatts];
        } else if (actualWatts >= 5.0 && batteryPct < 100) {
            batChgStr = [NSString stringWithFormat:@"Battery Charging Rate: %d W", (int)round(actualWatts)];
        } else if (fullyCharged || batteryPct >= 100) {
            batChgStr = @"Battery Charging: Fully Charged";
        } else if ((notChargingReason & (1 << 24)) != 0) {
            batChgStr = @"Battery Charging: On Hold / Paused";
        } else {
            batChgStr = @"Battery Charging: Standby";
        }
        NSMenuItem *batChgItem = [[NSMenuItem alloc] initWithTitle:batChgStr action:nil keyEquivalent:@""];
        [batChgItem setEnabled:NO];
        [menu addItem:batChgItem];

        NSMenuItem *ratingItem = [[NSMenuItem alloc] initWithTitle:ratingTitle action:nil keyEquivalent:@""];
        [ratingItem setEnabled:NO];
        [menu addItem:ratingItem];

        NSString *batState;
        if (fullyCharged || batteryPct >= 100) {
            batState = @"Fully Charged";
        } else if (isCharging || (actualWatts >= 5.0 && batteryPct < 100)) {
            batState = @"Charging";
        } else if ((notChargingReason & (1 << 24)) != 0) {
            batState = @"On Hold";
        } else {
            batState = @"Standby";
        }
        NSString *batStr = [NSString stringWithFormat:@"Battery Level: %d%% (%@)", batteryPct, batState];
        NSMenuItem *batItem = [[NSMenuItem alloc] initWithTitle:batStr action:nil keyEquivalent:@""];
        [batItem setEnabled:NO];
        [menu addItem:batItem];

        // Estimated Time to Full Charge
        NSString *timeStr = nil;
        if (fullyCharged || batteryPct >= 100) {
            timeStr = @"Fully Charged";
        } else if (isCharging || (actualWatts >= 5.0 && batteryPct < 100) || timeToFull > 0) {
            if (timeToFull > 0 && timeToFull < 65535) {
                if (timeToFull >= 60) {
                    int hrs = timeToFull / 60;
                    int mins = timeToFull % 60;
                    if (mins > 0) {
                        timeStr = [NSString stringWithFormat:@"%d hr %d min", hrs, mins];
                    } else {
                        timeStr = [NSString stringWithFormat:@"%d hr", hrs];
                    }
                } else {
                    timeStr = [NSString stringWithFormat:@"%d minutes", timeToFull];
                }
            } else {
                timeStr = @"Calculating...";
            }
        } else if ((notChargingReason & (1 << 24)) != 0) {
            timeStr = @"Charging On Hold";
        } else {
            timeStr = @"Not Charging";
        }
        NSString *timeLine = [NSString stringWithFormat:@"Time to Full Charge: %@", timeStr];
        NSMenuItem *timeItem = [[NSMenuItem alloc] initWithTitle:timeLine action:nil keyEquivalent:@""];
        [timeItem setEnabled:NO];
        [menu addItem:timeItem];

        if (inputVolts > 0.0) {
            NSString *diagStr = [NSString stringWithFormat:@"Port Telemetry: %.1f V @ %.2f A", inputVolts, inputAmps];
            NSMenuItem *diagItem = [[NSMenuItem alloc] initWithTitle:diagStr action:nil keyEquivalent:@""];
            [diagItem setEnabled:NO];
            [menu addItem:diagItem];
        }
    } else {
        NSMenuItem *srcItem = [[NSMenuItem alloc] initWithTitle:@"Power Source: Battery" action:nil keyEquivalent:@""];
        [srcItem setEnabled:NO];
        [menu addItem:srcItem];

        NSMenuItem *drawItem = [[NSMenuItem alloc] initWithTitle:@"Live Power Draw: 0 W" action:nil keyEquivalent:@""];
        [drawItem setEnabled:NO];
        [menu addItem:drawItem];

        NSMenuItem *chgItem = [[NSMenuItem alloc] initWithTitle:@"Input Rating: Not Connected" action:nil keyEquivalent:@""];
        [chgItem setEnabled:NO];
        [menu addItem:chgItem];

        NSString *batStr = [NSString stringWithFormat:@"Battery Level: %d%%", batteryPct];
        NSMenuItem *batItem = [[NSMenuItem alloc] initWithTitle:batStr action:nil keyEquivalent:@""];
        [batItem setEnabled:NO];
        [menu addItem:batItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // 3. Hardware Handshake Controls
    NSMenuItem *kickItem = [[NSMenuItem alloc] initWithTitle:@"Force Handshake Kickstart" action:@selector(manualKickstart) keyEquivalent:@"k"];
    [kickItem setTarget:self];
    [menu addItem:kickItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // 4. Updates Section
    NSMenuItem *updateItem = [[NSMenuItem alloc] initWithTitle:@"Check for Updates..." action:@selector(checkForUpdates) keyEquivalent:@""];
    [updateItem setTarget:self];
    [menu addItem:updateItem];

    NSMenuItem *autoUpdateItem = [[NSMenuItem alloc] initWithTitle:@"Automatically Check for Updates" action:@selector(toggleAutoCheckUpdates:) keyEquivalent:@""];
    [autoUpdateItem setTarget:self];
    BOOL autoCheck = [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoCheckUpdates"];
    [autoUpdateItem setState:autoCheck ? NSControlStateValueOn : NSControlStateValueOff];
    [menu addItem:autoUpdateItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // 5. About & Quit
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"About LowWatt Handshake" action:@selector(openAbout) keyEquivalent:@""];
    [aboutItem setTarget:self];
    [menu addItem:aboutItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit LowWatt Handshake" action:@selector(quitApp) keyEquivalent:@"q"];
    [quitItem setTarget:self];
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (void)manualKickstart {
    [self executeHandshakePulse];
    AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
    [self startFastBurstPoll];
    [self updatePowerStateAndCheck];
}

- (void)checkForUpdates {
    [self checkForUpdatesSilent:NO];
}

- (void)performSilentUpdateCheck {
    [self checkForUpdatesSilent:YES];
}

- (void)checkForUpdatesSilent:(BOOL)silent {
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/siraj-bd/lowwatt-handshake-macos/releases/latest"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:@"LowWattHandshake-macOS" forHTTPHeaderField:@"User-Agent"];
    [req setTimeoutInterval:8.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && data) {
                NSError *jsonErr = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
                if (json && json[@"tag_name"]) {
                    NSString *remoteTag = [json[@"tag_name"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    NSString *currentVer = @"v1.0.0";
                    if ([remoteTag length] > 0 && ![remoteTag isEqualToString:currentVer]) {
                        NSAlert *alert = [[NSAlert alloc] init];
                        alert.messageText = @"Update Available";
                        alert.informativeText = [NSString stringWithFormat:@"A newer version (%@) of LowWatt Handshake macOS is available.\n\nWould you like to open the download page?", remoteTag];
                        [alert addButtonWithTitle:@"Download Update"];
                        [alert addButtonWithTitle:@"Later"];
                        [NSApp activateIgnoringOtherApps:YES];
                        if ([alert runModal] == NSAlertFirstButtonReturn) {
                            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/siraj-bd/lowwatt-handshake-macos/releases/latest"]];
                        }
                        return;
                    }
                }
            }

            if (!silent) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"You're Up to Date";
                alert.informativeText = @"LowWatt Handshake macOS v1.0.0 is currently the newest version available.";
                [alert addButtonWithTitle:@"OK"];
                [NSApp activateIgnoringOtherApps:YES];
                [alert runModal];
            }
        });
    }];
    [task resume];
}

- (void)toggleAutoCheckUpdates:(NSMenuItem *)sender {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    BOOL current = [defs boolForKey:@"AutoCheckUpdates"];
    BOOL newVal = !current;
    [defs setBool:newVal forKey:@"AutoCheckUpdates"];
    [defs synchronize];
    sender.state = newVal ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)openAbout {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"LowWatt Handshake macOS";
    alert.informativeText = @"Version 1.0.0\n\nA lightweight native background utility for seamless USB-C Power Delivery charging with low-wattage chargers and power banks.\n\n⚠️ Hardware Notice: Always use certified, reputable brand chargers and power banks (e.g. Anker, Apple, UGREEN, Baseus). Never use low-quality local or unbranded generic chargers. The developers disclaim all liability for any battery or hardware damage resulting from substandard third-party accessories.\n\nCopyright © 2026 Siraj. All Rights Reserved.";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"GitHub Repository"];
    NSImage *logo = [self loadBrandLogo];
    if (logo) {
        [logo setSize:NSMakeSize(64, 64)];
        alert.icon = logo;
    }
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertSecondButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/siraj-bd/lowwatt-handshake-macos"]];
    }
}

- (void)quitApp {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    secure_anti_debug_guard();
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
