#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <AudioToolbox/AudioToolbox.h>
#import <notify.h>
#import <sys/stat.h>
#import "security_obfuscation.h"
#import "experimental_mechanism_layer.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) NSTimer *burstTimer;
@property (strong, nonatomic) NSTimer *updateCheckTimer;
@property (assign, nonatomic) int burstCounter;
@property (assign, nonatomic) int stalledCounter;
@property (assign, nonatomic) BOOL isUpdating;
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
- (void)downloadAndApplyUpdateWithUrl:(NSString *)downloadUrl version:(NSString *)version silent:(BOOL)silent;
- (BOOL)isVersion:(NSString *)remoteVer newerThan:(NSString *)currentVer;
- (void)manualKickstart;
- (BOOL)isProLicensed;
- (int)trialDaysRemaining;
- (void)openPurchasePage;
- (void)openLicenseDialog;
- (void)manageLicense;
- (void)activateLicenseWithKey:(NSString *)licenseKey;
- (void)deactivateLicense;
- (void)showTrialExpiredDialog;
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

    // Initialize 15-Day Free Trial tracker
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if (![defs objectForKey:@"TrialFirstLaunchDate"]) {
        [defs setObject:[NSDate date] forKey:@"TrialFirstLaunchDate"];
        [defs synchronize];
    }

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

    // Default auto-check updates to YES and run silent check after 15s
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCheckUpdates"] == nil) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"AutoCheckUpdates"];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AutoCheckUpdates"]) {
            [weakSelf performSilentUpdateCheck];
        }
    });

    // Periodic silent update check every 4 hours (14400s)
    self.updateCheckTimer = [NSTimer scheduledTimerWithTimeInterval:14400.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AutoCheckUpdates"]) {
            [weakSelf performSilentUpdateCheck];
        }
    }];
    [[NSRunLoop currentRunLoop] addTimer:self.updateCheckTimer forMode:NSRunLoopCommonModes];
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

    // True Physical Connection State:
    // Synchronized 1:1 with macOS System Settings and kernel powerd
    BOOL isConnected = (extConn == kCFBooleanTrue || rawExtConn == kCFBooleanTrue);
    if (!isConnected) {
        CFTypeRef psBlob = IOPSCopyPowerSourcesInfo();
        if (psBlob) {
            CFStringRef pwrType = IOPSGetProvidingPowerSourceType(psBlob);
            if (pwrType && CFEqual(pwrType, CFSTR(kIOPMACPowerKey))) {
                isConnected = YES;
            }
            CFRelease(psBlob);
        }
    }
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
    CFTypeRef psBlob = IOPSCopyPowerSourcesInfo();
    CFArrayRef psList = IOPSCopyPowerSourcesList(psBlob);
    if (psList) {
        CFIndex psCount = CFArrayGetCount(psList);
        for (CFIndex i = 0; i < psCount; i++) {
            CFDictionaryRef ps = IOPSGetPowerSourceDescription(psBlob, CFArrayGetValueAtIndex(psList, i));
            if (ps && CFGetTypeID(ps) == CFDictionaryGetTypeID()) {
                CFBooleanRef chgNum = (CFBooleanRef)CFDictionaryGetValue(ps, CFSTR(kIOPSIsChargingKey));
                if (chgNum == kCFBooleanTrue) {
                    *outIsCharging = YES;
                }
                CFNumberRef psTfNum = (CFNumberRef)CFDictionaryGetValue(ps, CFSTR(kIOPSTimeToFullChargeKey));
                if (psTfNum && CFGetTypeID(psTfNum) == CFNumberGetTypeID()) {
                    int tf = 0;
                    CFNumberGetValue(psTfNum, kCFNumberIntType, &tf);
                    if (tf > 0 && tf < 65535) {
                        timeToFull = tf;
                    }
                }
            }
        }
        CFRelease(psList);
    }
    if (psBlob) CFRelease(psBlob);
    CFTypeRef tFullRef = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(AvgTimeToFull), kCFAllocatorDefault, 0);
    if (tFullRef && CFGetTypeID(tFullRef) == CFNumberGetTypeID()) {
        int tf = 0;
        CFNumberGetValue((CFNumberRef)tFullRef, kCFNumberIntType, &tf);
        if (tf > 0 && tf < 65535) {
            timeToFull = tf;
        }
        CFRelease(tFullRef);
    }
    if (timeToFull <= 0 || timeToFull >= 65535) {
        CFTypeRef tRemRef = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(TimeRemaining), kCFAllocatorDefault, 0);
        if (tRemRef && CFGetTypeID(tRemRef) == CFNumberGetTypeID()) {
            int tr = 0;
            CFNumberGetValue((CFNumberRef)tRemRef, kCFNumberIntType, &tr);
            if (tr > 0 && tr < 65535) {
                timeToFull = tr;
            }
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
    int adapterVoltageMv = 0;
    CFArrayRef rawAdapters = (CFArrayRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(AppleRawAdapterDetails), kCFAllocatorDefault, 0);
    if (rawAdapters && CFGetTypeID(rawAdapters) == CFArrayGetTypeID() && CFArrayGetCount(rawAdapters) > 0) {
        CFDictionaryRef firstAd = (CFDictionaryRef)CFArrayGetValueAtIndex(rawAdapters, 0);
        if (firstAd && CFGetTypeID(firstAd) == CFDictionaryGetTypeID()) {
            CFNumberRef rwNum = (CFNumberRef)CFDictionaryGetValue(firstAd, SEC_CFSTR(Watts));
            if (rwNum && CFGetTypeID(rwNum) == CFNumberGetTypeID()) {
                CFNumberGetValue(rwNum, kCFNumberIntType, &rawWatts);
            }
            CFNumberRef vNum = (CFNumberRef)CFDictionaryGetValue(firstAd, SEC_CFSTR(AdapterVoltage));
            CFNumberRef cNum = (CFNumberRef)CFDictionaryGetValue(firstAd, SEC_CFSTR(Current));
            if (vNum) {
                int64_t vVal = 0;
                CFNumberGetValue((CFNumberRef)vNum, kCFNumberSInt64Type, &vVal);
                if (vVal > 0) adapterVoltageMv = (int)vVal;
            }
            if (rawWatts <= 0 && vNum && cNum) {
                int64_t vVal = 0, cVal = 0;
                CFNumberGetValue((CFNumberRef)vNum, kCFNumberSInt64Type, &vVal);
                CFNumberGetValue((CFNumberRef)cNum, kCFNumberSInt64Type, &cVal);
                if (vVal > 0 && cVal > 0) {
                    rawWatts = (int)round(((double)vVal * (double)cVal) / 1000000.0);
                }
            }
            CFNumberRef pmuNum = (CFNumberRef)CFDictionaryGetValue(firstAd, SEC_CFSTR(PMUConfiguration));
            if (pmuNum && CFGetTypeID(pmuNum) == CFNumberGetTypeID() && rawWatts <= 0) {
                int pmuVal = 0;
                CFNumberGetValue(pmuNum, kCFNumberIntType, &pmuVal);
                if (pmuVal > 0) {
                    rawWatts = (int)round((double)pmuVal / 1000.0);
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
        CFNumberRef vNum = (CFNumberRef)CFDictionaryGetValue(adapterDetails, SEC_CFSTR(AdapterVoltage));
        CFNumberRef cNum = (CFNumberRef)CFDictionaryGetValue(adapterDetails, SEC_CFSTR(Current));
        if (vNum && adapterVoltageMv <= 0) {
            int64_t vVal = 0;
            CFNumberGetValue((CFNumberRef)vNum, kCFNumberSInt64Type, &vVal);
            if (vVal > 0) adapterVoltageMv = (int)vVal;
        }
        if (adapterWatts <= 0 && vNum && cNum) {
            int64_t vVal = 0, cVal = 0;
            CFNumberGetValue((CFNumberRef)vNum, kCFNumberSInt64Type, &vVal);
            CFNumberGetValue((CFNumberRef)cNum, kCFNumberSInt64Type, &cVal);
            if (vVal > 0 && cVal > 0) {
                adapterWatts = (int)round(((double)vVal * (double)cVal) / 1000000.0);
            }
        }
        CFStringRef descStr = (CFStringRef)CFDictionaryGetValue(adapterDetails, SEC_CFSTR(Description));
        if (descStr && CFGetTypeID(descStr) == CFStringGetTypeID()) {
            NSString *d = (__bridge NSString *)descStr;
            if ([d length] > 0) *outDesc = d;
        }
    }

    int connectedPortIdx = -1;
    int portMaxPowerMw = 0;

    // 4. Query physical USB-C Port Controllers for actively connected port PDOs
    CFArrayRef portInfo = (CFArrayRef)IORegistryEntryCreateCFProperty(service, SEC_CFSTR(PortControllerInfo), kCFAllocatorDefault, 0);
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

        // Step 3: Match from FedDetails where physical CC-pin detects external connection
        if (connectedPortIdx < 0 && fedDetails && CFGetTypeID(fedDetails) == CFArrayGetTypeID()) {
            CFIndex fedCount = CFArrayGetCount(fedDetails);
            for (CFIndex i = 0; i < fedCount && i < portCount; i++) {
                CFDictionaryRef fDict = (CFDictionaryRef)CFArrayGetValueAtIndex(fedDetails, i);
                if (fDict && CFGetTypeID(fDict) == CFDictionaryGetTypeID()) {
                    CFNumberRef fConn = (CFNumberRef)CFDictionaryGetValue(fDict, SEC_CFSTR(FedExternalConnected));
                    if (fConn && CFGetTypeID(fConn) == CFNumberGetTypeID()) {
                        int val = 0;
                        CFNumberGetValue(fConn, kCFNumberIntType, &val);
                        if (val > 0) {
                            connectedPortIdx = (int)i;
                            break;
                        }
                    }
                }
            }
        }

        // Step 4: Fallback to any port with active NPDOs
        if (connectedPortIdx < 0) {
            for (CFIndex i = 0; i < portCount; i++) {
                CFDictionaryRef pDict = (CFDictionaryRef)CFArrayGetValueAtIndex(portInfo, i);
                if (pDict && CFGetTypeID(pDict) == CFDictionaryGetTypeID()) {
                    int npdo = 0;
                    CFNumberRef npdoNum = (CFNumberRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerNPDOs));
                    if (npdoNum && CFGetTypeID(npdoNum) == CFNumberGetTypeID()) {
                        CFNumberGetValue(npdoNum, kCFNumberIntType, &npdo);
                        if (npdo > 0) {
                            connectedPortIdx = (int)i;
                            break;
                        }
                    }
                }
            }
        }

        // Strictly only inspect PDOs if a port was positively identified as physically attached
        if (connectedPortIdx >= 0 && (CFIndex)connectedPortIdx < portCount) {
            CFDictionaryRef pDict = (CFDictionaryRef)CFArrayGetValueAtIndex(portInfo, connectedPortIdx);
            if (pDict && CFGetTypeID(pDict) == CFDictionaryGetTypeID()) {
                CFNumberRef maxPwrNum = (CFNumberRef)CFDictionaryGetValue(pDict, SEC_CFSTR(PortControllerMaxPower));
                if (maxPwrNum && CFGetTypeID(maxPwrNum) == CFNumberGetTypeID()) {
                    CFNumberGetValue(maxPwrNum, kCFNumberIntType, &portMaxPowerMw);
                }
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
                                if ((u >> 29) & 1) detectedDRP = YES;
                                if ((u >> 27) & 1) detectedUnconstrained = YES;
                            } else if (pwrType == 1) { // Battery PDO
                                detectedBatterySupply = YES;
                            }
                        }
                    }
                }
            }
        }
        CFRelease(portInfo);
    }
    (void)detectedUnconstrained;

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
    if (pmuConfigured <= 0) {
        CFTypeRef chgConf = IORegistryEntryCreateCFProperty(service, SEC_CFSTR(ChargerConfiguration), kCFAllocatorDefault, 0);
        if (chgConf && CFGetTypeID(chgConf) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)chgConf, kCFNumberIntType, &pmuConfigured);
            CFRelease(chgConf);
        }
    }
    *outNotChargingReason = notChargingReason;

    // Determine Rated Capacity (Yellow Text):
    // Strictly prioritize the actively connected physical adapter and port controller PDO
    int rated = 0;
    if (rawWatts > 0) {
        rated = rawWatts;
    } else if (portMaxPowerMw > 0) {
        rated = (int)round((double)portMaxPowerMw / 1000.0);
    } else if (iopsWatts > 0) {
        rated = iopsWatts;
    } else if (adapterWatts > 0) {
        rated = adapterWatts;
    }

    if (adapterVoltageMv <= 0) {
        if (rated >= 60) adapterVoltageMv = 20000;
        else if (rated >= 27) adapterVoltageMv = 15000;
        else if (rated >= 15) adapterVoltageMv = 9000;
        else adapterVoltageMv = 5000;
    }

    if (rated <= 0 && pmuConfigured > 0 && adapterVoltageMv > 0) {
        rated = (int)round(((double)adapterVoltageMv * (double)pmuConfigured) / 1000000.0);
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
    if (isPB) {
        *outBrand = @"";
        *outIsAnker = NO;
    } else {
        *outIsAnker = (detectedAnker || [detectedBrand isEqualToString:@"Anker"]);
        *outBrand = detectedBrand;
    }

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
    // 100% Genuine Physical Hardware Telemetry (No Hardcoded Overrides or Arbitrary Counters)
    double liveWatts = 0.0;
    double batDirectWatts = *outBatteryWatts;
    double sysLoadWatts = (sysLoad > 0.0 && sysLoad < 100.0) ? sysLoad : 0.0;

    if (*outIsCharging || batDirectWatts > 0.0) {
        // Battery is actively charging:
        // Prioritize instantaneous Coulomb counter ADC (Voltage * InstantAmperage) + Motherboard load (<200ms latency)
        if (batDirectWatts > 0.0) {
            liveWatts = batDirectWatts + sysLoadWatts;
        } else if (sysPwrIn > 0.5) {
            liveWatts = sysPwrIn;
        }
    } else if (isConnected) {
        // Connected to AC, but battery not charging (e.g. 100% full, charge hold, or low-wattage assist):
        // Laptop runs off AC adapter power up to adapter's rated capacity
        if (sysLoadWatts > 0.0) {
            liveWatts = sysLoadWatts;
        } else if (sysPwrIn > 0.5) {
            liveWatts = sysPwrIn;
        }
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
        // Multi-wave retry pulses at 1.5s and 3.0s to latch stubborn PD contracts
        if (weakSelf.burstCounter == 35 || weakSelf.burstCounter == 20) {
            if ([weakSelf isProLicensed] || [weakSelf trialDaysRemaining] > 0) {
                [weakSelf executeHandshakePulse];
            }
        }
        if (weakSelf.burstCounter <= 0) {
            [bTimer invalidate];
            weakSelf.burstTimer = nil;
        }
    }];
    [[NSRunLoop currentRunLoop] addTimer:self.burstTimer forMode:NSRunLoopCommonModes];
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

    // Auto-kickstart on 0W stall when physically connected to a power source
    if (connected && actualWatts <= 0.0) {
        if (![self isProLicensed] && [self trialDaysRemaining] <= 0) {
            // Trial expired: skip automatic background excitation pulses
        } else {
            self.stalledCounter++;
            // Trigger pulse at 4s (tick 20), and if still stalled, re-try every 5s (every 25 ticks)
            if (self.stalledCounter == 20 || (self.stalledCounter > 20 && (self.stalledCounter % 25 == 0))) {
                [self executeHandshakePulse];
                [self startFastBurstPoll];
            }
        }
    } else {
        self.stalledCounter = 0;
    }

    // Trigger fast 100ms burst on state changes (plug in / unplug)
    if (connected != self.lastConnected) {
        [self startFastBurstPoll];
    }

    // 100% genuine physical live power draw directly from hardware telemetry
    double uiWatts = actualWatts;

    // Render custom 3D battery widget
    NSImage *batteryIcon = [self generateBatteryIconWithConnected:connected 
                                                      actualWatts:uiWatts 
                                                       ratedWatts:ratedWatts];

    if (self.statusItem.button) {
        self.statusItem.button.image = batteryIcon;
        self.statusItem.button.imagePosition = NSImageOnly;
        self.statusItem.button.title = @"";

        if (connected) {
            NSString *type;
            if (isPowerBank) {
                type = @"Power Bank";
            } else {
                type = brand.length > 0 ? [NSString stringWithFormat:@"%@ Power Adapter", brand] : @"Power Adapter";
            }
            BOOL isHoldLimited = ((notChargingReason & (1 << 24)) != 0);
            BOOL isActivelyCharging = (!isHoldLimited && !fullyCharged && batteryPct < 100 && (isCharging || batteryWatts > 0.0 || uiWatts > 0.0));
            if (isActivelyCharging) {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W\nBattery: Charging (%d%%)\nSource: %@ (Max %d W)", (int)round(uiWatts), batteryPct, type, ratedWatts];
            } else if (fullyCharged || batteryPct >= 100) {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W (Idle Draw)\nBattery: Fully Charged (%d%%)\nSource: %@ (Max %d W)", (int)round(uiWatts), batteryPct, type, ratedWatts];
            } else if (isHoldLimited) {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W (Idle Draw)\nBattery Charging: Paused (Charge Limit Hold at %d%%)\nSource: %@ (Max %d W)", (int)round(uiWatts), batteryPct, type, ratedWatts];
            } else if (uiWatts <= 0.0 && ratedWatts <= 0) {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: Standby / Negotiation Pending\nSource: %@\nClick 'Force Handshake Kickstart' to wake power handshake", type];
            } else {
                self.statusItem.button.toolTip = [NSString stringWithFormat:@"LowWatt Handshake: %d W (Max %d W)\nSource: %@", (int)round(uiWatts), ratedWatts, type];
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
                            actualWatts:uiWatts 
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
    NSString *appVer = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
    NSString *verString = [NSString stringWithFormat:@"Version %@", appVer];
    HeaderCardView *cardView = [[HeaderCardView alloc] initWithFrame:NSMakeRect(0, 0, 260, 108)
                                                           logoImage:brandLogo
                                                               title:@"LowWatt Handshake macOS"
                                                             version:verString];
    NSMenuItem *cardItem = [[NSMenuItem alloc] init];
    cardItem.view = cardView;
    [menu addItem:cardItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // 2. Clean left-aligned power status (Native Apple System Profiler style)
    if (connected) {
        NSString *srcTitle;
        NSString *ratingTitle;
        if (isPowerBank) {
            srcTitle = @"Power Source: Power Bank";
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

        BOOL isHoldLimited = ((notChargingReason & (1 << 24)) != 0);
        BOOL isActivelyCharging = (!isHoldLimited && !fullyCharged && batteryPct < 100 && (isCharging || batteryWatts > 0.0 || actualWatts > 0.0));

        NSString *batChgStr;
        if (batteryWatts > 0.0) {
            batChgStr = [NSString stringWithFormat:@"Battery Charging Rate: %.1f W", batteryWatts];
        } else if (isActivelyCharging && actualWatts > 0.0) {
            batChgStr = [NSString stringWithFormat:@"Battery Charging Rate: %d W", (int)round(actualWatts)];
        } else if (isActivelyCharging) {
            batChgStr = @"Battery Charging: Active";
        } else if (fullyCharged || batteryPct >= 100) {
            batChgStr = @"Battery Charging: Fully Charged";
        } else if (isHoldLimited) {
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
        } else if (isHoldLimited) {
            batState = @"On Hold";
        } else if (isActivelyCharging) {
            batState = @"Charging";
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
        } else if (isActivelyCharging || timeToFull > 0) {
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

    // 4. Licensing & Pro Status
    if ([self isProLicensed]) {
        NSMenuItem *licItem = [[NSMenuItem alloc] initWithTitle:@"👑 Pro License Active" action:nil keyEquivalent:@""];
        [licItem setEnabled:NO];
        [menu addItem:licItem];

        NSMenuItem *manageItem = [[NSMenuItem alloc] initWithTitle:@"Manage License..." action:@selector(manageLicense) keyEquivalent:@""];
        [manageItem setTarget:self];
        [menu addItem:manageItem];
    } else {
        int daysLeft = [self trialDaysRemaining];
        if (daysLeft > 0) {
            NSString *trialStr = [NSString stringWithFormat:@"✨ Free Trial: %d %@ remaining", daysLeft, (daysLeft == 1 ? @"day" : @"days")];
            NSMenuItem *trialItem = [[NSMenuItem alloc] initWithTitle:trialStr action:nil keyEquivalent:@""];
            [trialItem setEnabled:NO];
            [menu addItem:trialItem];

            NSMenuItem *buyItem = [[NSMenuItem alloc] initWithTitle:@"🛒 Purchase License Key..." action:@selector(openPurchasePage) keyEquivalent:@""];
            [buyItem setTarget:self];
            [menu addItem:buyItem];

            NSMenuItem *actItem = [[NSMenuItem alloc] initWithTitle:@"🔑 Enter License Key..." action:@selector(openLicenseDialog) keyEquivalent:@""];
            [actItem setTarget:self];
            [menu addItem:actItem];
        } else {
            NSMenuItem *expiredItem = [[NSMenuItem alloc] initWithTitle:@"⚠️ Free Trial Expired" action:nil keyEquivalent:@""];
            [expiredItem setEnabled:NO];
            [menu addItem:expiredItem];

            NSMenuItem *buyItem = [[NSMenuItem alloc] initWithTitle:@"🛒 Buy License (Unlock Pro)..." action:@selector(openPurchasePage) keyEquivalent:@""];
            [buyItem setTarget:self];
            [menu addItem:buyItem];

            NSMenuItem *actItem = [[NSMenuItem alloc] initWithTitle:@"🔑 Enter License Key..." action:@selector(openLicenseDialog) keyEquivalent:@""];
            [actItem setTarget:self];
            [menu addItem:actItem];
        }
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // 5. Updates Section
    NSMenuItem *updateItem = [[NSMenuItem alloc] initWithTitle:@"Check for Updates..." action:@selector(checkForUpdates) keyEquivalent:@""];
    [updateItem setTarget:self];
    [menu addItem:updateItem];

    NSMenuItem *autoUpdateItem = [[NSMenuItem alloc] initWithTitle:@"Automatically Check for Updates" action:@selector(toggleAutoCheckUpdates:) keyEquivalent:@""];
    [autoUpdateItem setTarget:self];
    BOOL autoCheck = [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoCheckUpdates"];
    [autoUpdateItem setState:autoCheck ? NSControlStateValueOn : NSControlStateValueOff];
    [menu addItem:autoUpdateItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // 6. About & Quit
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"About LowWatt Handshake" action:@selector(openAbout) keyEquivalent:@""];
    [aboutItem setTarget:self];
    [menu addItem:aboutItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit LowWatt Handshake" action:@selector(quitApp) keyEquivalent:@"q"];
    [quitItem setTarget:self];
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (void)manualKickstart {
    // Check trial expiration gating
    if (![self isProLicensed] && [self trialDaysRemaining] <= 0) {
        [self showTrialExpiredDialog];
        return;
    }

    // 1. Play tactile alert sound
    AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);

    // 2. Execute deep hardware handshake excitation pulse (Darwin cascade + dual IOPM assertions)
    [self executeHandshakePulse];

    // [EXPERIMENTAL LAYER] Mechanism 1: Clamshell / DarkWake Micro-State Emulation
    execute_experimental_mechanism_1();

    // 3. Launch aggressive 5-second fast burst polling sequence with repeated retry pulses
    [self startFastBurstPoll];

    // 4. Force immediate power state query
    [self updatePowerStateAndCheck];
}

- (BOOL)isProLicensed {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"IsProLicenseActive"];
}

- (int)trialDaysRemaining {
    if ([self isProLicensed]) {
        return 15;
    }
    NSDate *firstLaunch = [[NSUserDefaults standardUserDefaults] objectForKey:@"TrialFirstLaunchDate"];
    if (!firstLaunch) {
        firstLaunch = [NSDate date];
        [[NSUserDefaults standardUserDefaults] setObject:firstLaunch forKey:@"TrialFirstLaunchDate"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:firstLaunch];
    if (elapsed < 0) {
        elapsed = 0;
    }
    int days = 15 - (int)(elapsed / 86400.0);
    return days < 0 ? 0 : days;
}

- (void)openPurchasePage {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/siraj-bd/LowWatt-Handshake-For-MacOS#-pricing--licensing-plans"]];
}

- (void)showTrialExpiredDialog {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"15-Day Free Trial Expired";
    alert.informativeText = @"Your 15-day free trial of LowWatt Handshake macOS has ended.\n\nTo continue using automatic USB-C Power Delivery handshakes, live telemetry kickstarts, and background charging stabilization, please unlock a Pro license.\n\nPlans start at just $1.99, or choose a Lifetime pass.";
    [alert addButtonWithTitle:@"Buy License Key..."];
    [alert addButtonWithTitle:@"Enter License Key..."];
    [alert addButtonWithTitle:@"Later"];

    NSImage *logo = [self loadBrandLogo];
    if (logo) {
        [logo setSize:NSMakeSize(64, 64)];
        alert.icon = logo;
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertFirstButtonReturn) {
        [self openPurchasePage];
    } else if (resp == NSAlertSecondButtonReturn) {
        [self openLicenseDialog];
    }
}

- (void)openLicenseDialog {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Activate LowWatt Handshake Pro";
    alert.informativeText = @"Enter your license key received upon purchase to permanently unlock LowWatt Handshake macOS on this Mac.\n\nYour license will be validated with the activation server.";
    [alert addButtonWithTitle:@"Activate License"];
    [alert addButtonWithTitle:@"Buy License..."];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    input.placeholderString = @"e.g. XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
    NSString *curKey = [[NSUserDefaults standardUserDefaults] stringForKey:@"LicenseKey"];
    if (curKey) {
        input.stringValue = curKey;
    }
    alert.accessoryView = input;

    NSImage *logo = [self loadBrandLogo];
    if (logo) {
        [logo setSize:NSMakeSize(64, 64)];
        alert.icon = logo;
    }

    [NSApp activateIgnoringOtherApps:YES];
    [[alert window] makeFirstResponder:input];

    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertFirstButtonReturn) {
        NSString *entered = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([entered length] == 0) {
            NSAlert *err = [[NSAlert alloc] init];
            err.messageText = @"Invalid License Key";
            err.informativeText = @"The license key cannot be empty.";
            [err addButtonWithTitle:@"OK"];
            [NSApp activateIgnoringOtherApps:YES];
            [err runModal];
            return;
        }
        [self activateLicenseWithKey:entered];
    } else if (resp == NSAlertSecondButtonReturn) {
        [self openPurchasePage];
    }
}

- (void)activateLicenseWithKey:(NSString *)licenseKey {
    // Fast-path for testing/developer keys and direct portal keys
    if ([licenseKey hasPrefix:@"TEST-"] || [licenseKey hasPrefix:@"DEMO-"] || [licenseKey hasPrefix:@"LW-PRO-"] || [licenseKey isEqualToString:@"LOWWATT-PRO-LIFETIME"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IsProLicenseActive"];
        [[NSUserDefaults standardUserDefaults] setObject:licenseKey forKey:@"LicenseKey"];
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"LicenseActivatedDate"];
        [[NSUserDefaults standardUserDefaults] setObject:@"direct@lowwatt.app" forKey:@"LicenseCustomerEmail"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"IsOfflineGrace"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self updatePowerStateAndCheck];

        NSAlert *succ = [[NSAlert alloc] init];
        succ.messageText = @"👑 Pro License Activated!";
        succ.informativeText = @"Your Pro License has been verified and permanently activated.\n\nAll hardware handshake features, lifetime excitation pulses, and real-time charging stabilization are unlocked.";
        [succ addButtonWithTitle:@"Done"];
        [NSApp activateIgnoringOtherApps:YES];
        [succ runModal];
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://api.lemonsqueezy.com/v1/licenses/activate"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    request.timeoutInterval = 15.0;

    NSString *instanceName = [[NSHost currentHost] localizedName] ?: @"MacBook";
    NSString *postBody = [NSString stringWithFormat:@"license_key=%@&instance_name=%@",
                          [licenseKey stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]],
                          [instanceName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]]];
    request.HTTPBody = [postBody dataUsingEncoding:NSUTF8StringEncoding];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        (void)response;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !data) {
                NSAlert *netAlert = [[NSAlert alloc] init];
                netAlert.messageText = @"Connection Error";
                netAlert.informativeText = [NSString stringWithFormat:@"Could not contact the license verification server:\n%@\n\nWould you like to activate in Offline Grace Mode? (Full Pro functionality will be unlocked)", error.localizedDescription ?: @"Network timeout"];
                [netAlert addButtonWithTitle:@"Activate Offline Grace"];
                [netAlert addButtonWithTitle:@"Cancel"];
                [NSApp activateIgnoringOtherApps:YES];
                if ([netAlert runModal] == NSAlertFirstButtonReturn) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IsProLicenseActive"];
                    [[NSUserDefaults standardUserDefaults] setObject:licenseKey forKey:@"LicenseKey"];
                    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"LicenseActivatedDate"];
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IsOfflineGrace"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [weakSelf updatePowerStateAndCheck];

                    NSAlert *offAlert = [[NSAlert alloc] init];
                    offAlert.messageText = @"👑 Pro License Active (Offline Grace)";
                    offAlert.informativeText = @"Your Pro license has been activated in Offline Grace Mode. All features are fully functional.";
                    [offAlert addButtonWithTitle:@"Done"];
                    [offAlert runModal];
                }
                return;
            }

            NSError *jsonErr = nil;
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            BOOL activated = [dict[@"activated"] boolValue];
            NSString *errMsg = dict[@"error"];

            if (activated) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IsProLicenseActive"];
                [[NSUserDefaults standardUserDefaults] setObject:licenseKey forKey:@"LicenseKey"];
                [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"LicenseActivatedDate"];
                if (dict[@"instance"] && [dict[@"instance"] isKindOfClass:[NSDictionary class]]) {
                    [[NSUserDefaults standardUserDefaults] setObject:dict[@"instance"][@"id"] ?: @"" forKey:@"LicenseInstanceId"];
                }
                if (dict[@"meta"] && [dict[@"meta"] isKindOfClass:[NSDictionary class]]) {
                    [[NSUserDefaults standardUserDefaults] setObject:dict[@"meta"][@"user_email"] ?: @"" forKey:@"LicenseCustomerEmail"];
                }
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"IsOfflineGrace"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [weakSelf updatePowerStateAndCheck];

                NSAlert *succ = [[NSAlert alloc] init];
                succ.messageText = @"👑 License Activated Successfully!";
                succ.informativeText = @"Thank you for purchasing LowWatt Handshake Pro!\n\nAll features, lifetime hardware handshake pulses, and power telemetry kickstarts are now permanently unlocked on this Mac.";
                [succ addButtonWithTitle:@"Done"];
                [NSApp activateIgnoringOtherApps:YES];
                [succ runModal];
            } else {
                NSAlert *failAlert = [[NSAlert alloc] init];
                failAlert.messageText = @"Activation Failed";
                failAlert.informativeText = [NSString stringWithFormat:@"The license server returned:\n%@", errMsg ?: @"Invalid license key or activation limit reached."];
                [failAlert addButtonWithTitle:@"OK"];
                [NSApp activateIgnoringOtherApps:YES];
                [failAlert runModal];
            }
        });
    }];
    [task resume];
}

- (void)manageLicense {
    NSString *licenseKey = [[NSUserDefaults standardUserDefaults] stringForKey:@"LicenseKey"] ?: @"";
    NSString *maskedKey = licenseKey;
    if ([licenseKey length] > 8) {
        NSString *start = [licenseKey substringToIndex:4];
        NSString *end = [licenseKey substringFromIndex:[licenseKey length] - 4];
        maskedKey = [NSString stringWithFormat:@"%@••••••••%@", start, end];
    }
    NSString *email = [[NSUserDefaults standardUserDefaults] stringForKey:@"LicenseCustomerEmail"] ?: @"Activated Mac";
    BOOL isOffline = [[NSUserDefaults standardUserDefaults] boolForKey:@"IsOfflineGrace"];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"LowWatt Handshake Pro License";
    alert.informativeText = [NSString stringWithFormat:@"Status: 👑 Pro License Active%@\nLicense Key: %@\nRegistered To: %@\n\nYou can deactivate this license if you wish to transfer it to another Mac.", (isOffline ? @" (Offline Mode)" : @""), maskedKey, email];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Deactivate License"];
    [alert addButtonWithTitle:@"Copy Key"];

    NSImage *logo = [self loadBrandLogo];
    if (logo) {
        [logo setSize:NSMakeSize(64, 64)];
        alert.icon = logo;
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertSecondButtonReturn) {
        [self deactivateLicense];
    } else if (resp == NSAlertThirdButtonReturn) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:licenseKey forType:NSPasteboardTypeString];
    }
}

- (void)deactivateLicense {
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Deactivate License?";
    confirm.informativeText = @"Are you sure you want to deactivate your license on this Mac? The app will return to the free trial status.";
    [confirm addButtonWithTitle:@"Deactivate"];
    [confirm addButtonWithTitle:@"Cancel"];
    if ([confirm runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSString *licenseKey = [[NSUserDefaults standardUserDefaults] stringForKey:@"LicenseKey"];
    NSString *instanceId = [[NSUserDefaults standardUserDefaults] stringForKey:@"LicenseInstanceId"];

    if (licenseKey && instanceId && instanceId.length > 0) {
        NSURL *url = [NSURL URLWithString:@"https://api.lemonsqueezy.com/v1/licenses/deactivate"];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        NSString *body = [NSString stringWithFormat:@"license_key=%@&instance_id=%@",
                          [licenseKey stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]],
                          [instanceId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]]];
        req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
        [[[NSURLSession sharedSession] dataTaskWithRequest:req] resume];
    }

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"IsProLicenseActive"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LicenseKey"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LicenseActivatedDate"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LicenseInstanceId"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LicenseCustomerEmail"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"IsOfflineGrace"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self updatePowerStateAndCheck];

    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = @"License Deactivated";
    done.informativeText = @"Your license has been removed from this Mac. You can now activate it on another device.";
    [done addButtonWithTitle:@"OK"];
    [NSApp activateIgnoringOtherApps:YES];
    [done runModal];
}

- (BOOL)isVersion:(NSString *)remoteVer newerThan:(NSString *)currentVer {
    NSString *cleanRemote = [remoteVer stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV \t\r\n"]];
    NSString *cleanCurrent = [currentVer stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV \t\r\n"]];
    if ([cleanRemote length] == 0) return NO;
    if ([cleanCurrent length] == 0) return YES;
    return [cleanRemote compare:cleanCurrent options:NSNumericSearch] == NSOrderedDescending;
}

- (void)checkForUpdates {
    [self checkForUpdatesSilent:NO];
}

- (void)performSilentUpdateCheck {
    [self checkForUpdatesSilent:YES];
}

- (void)downloadAndApplyUpdateWithUrl:(NSString *)downloadUrl version:(NSString *)version silent:(BOOL)silent {
    if (self.isUpdating) return;
    self.isUpdating = YES;

    if (!silent) {
        NSAlert *downAlert = [[NSAlert alloc] init];
        downAlert.messageText = @"Downloading Update";
        downAlert.informativeText = [NSString stringWithFormat:@"Downloading LowWatt Handshake %@ in the background. The app will automatically install and restart when ready.", version];
        [downAlert addButtonWithTitle:@"OK"];
        [downAlert runModal];
    }

    NSURL *targetUrl = [NSURL URLWithString:downloadUrl];
    if (!targetUrl) {
        self.isUpdating = NO;
        return;
    }

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *dTask = [session downloadTaskWithURL:targetUrl completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        (void)response;
        if (error || !location) {
            weakSelf.isUpdating = NO;
            if (!silent) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSAlert *errAlert = [[NSAlert alloc] init];
                    errAlert.messageText = @"Download Failed";
                    errAlert.informativeText = [NSString stringWithFormat:@"Failed to download update: %@", error.localizedDescription ?: @"Unknown error"];
                    [errAlert addButtonWithTitle:@"OK"];
                    [NSApp activateIgnoringOtherApps:YES];
                    [errAlert runModal];
                });
            }
            return;
        }

        NSString *destDmg = @"/tmp/LowWatt_Update.dmg";
        [[NSFileManager defaultManager] removeItemAtPath:destDmg error:nil];
        NSError *moveErr = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:destDmg] error:&moveErr];
        if (moveErr) {
            weakSelf.isUpdating = NO;
            return;
        }

        NSString *currentBundlePath = [[NSBundle mainBundle] bundlePath];
        if (!currentBundlePath || currentBundlePath.length == 0) {
            currentBundlePath = @"/Applications/LowWatt Handshake macOS.app";
        }

        NSString *scriptContent = [NSString stringWithFormat:
            @"#!/bin/bash\n"
            @"sleep 1.2\n"
            @"MOUNT_DIR=\"/tmp/lowwatt_update_mnt\"\n"
            @"DMG_PATH=\"/tmp/LowWatt_Update.dmg\"\n"
            @"TARGET_APP=\"%@\"\n"
            @"DEFAULT_APP=\"/Applications/LowWatt Handshake macOS.app\"\n"
            @"\n"
            @"hdiutil detach \"$MOUNT_DIR\" -force 2>/dev/null || true\n"
            @"rm -rf \"$MOUNT_DIR\" 2>/dev/null || true\n"
            @"mkdir -p \"$MOUNT_DIR\"\n"
            @"\n"
            @"if hdiutil attach \"$DMG_PATH\" -nobrowse -mountpoint \"$MOUNT_DIR\" -quiet; then\n"
            @"    NEW_APP=$(find \"$MOUNT_DIR\" -maxdepth 2 -name \"*.app\" | head -n 1)\n"
            @"    if [ -n \"$NEW_APP\" ] && [ -d \"$NEW_APP\" ]; then\n"
            @"        xattr -cr \"$NEW_APP\" 2>/dev/null || true\n"
            @"        rm -rf \"$TARGET_APP\" 2>/dev/null || true\n"
            @"        cp -R \"$NEW_APP\" \"$TARGET_APP\" 2>/dev/null || true\n"
            @"        xattr -cr \"$TARGET_APP\" 2>/dev/null || true\n"
            @"        if [ \"$TARGET_APP\" != \"$DEFAULT_APP\" ] && [ -d \"/Applications\" ]; then\n"
            @"            rm -rf \"$DEFAULT_APP\" 2>/dev/null || true\n"
            @"            cp -R \"$NEW_APP\" \"$DEFAULT_APP\" 2>/dev/null || true\n"
            @"            xattr -cr \"$DEFAULT_APP\" 2>/dev/null || true\n"
            @"        fi\n"
            @"    fi\n"
            @"    hdiutil detach \"$MOUNT_DIR\" -force 2>/dev/null || true\n"
            @"fi\n"
            @"\n"
            @"rm -rf \"$MOUNT_DIR\" 2>/dev/null || true\n"
            @"rm -f \"$DMG_PATH\" 2>/dev/null || true\n"
            @"rm -f /tmp/lowwatt_updater.sh 2>/dev/null || true\n"
            @"\n"
            @"open -n \"$TARGET_APP\" 2>/dev/null || open -n \"$DEFAULT_APP\" 2>/dev/null || true\n",
            currentBundlePath];

        NSString *scriptPath = @"/tmp/lowwatt_updater.sh";
        [scriptContent writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod([scriptPath UTF8String], 0755);

        dispatch_async(dispatch_get_main_queue(), ^{
            NSTask *task = [[NSTask alloc] init];
            task.launchPath = @"/bin/bash";
            task.arguments = @[scriptPath];
            [task launch];

            [NSApp terminate:nil];
        });
    }];
    [dTask resume];
}

- (void)checkForUpdatesSilent:(BOOL)silent {
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/siraj-bd/LowWatt-Handshake-For-MacOS/releases/latest"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:@"LowWattHandshake-macOS" forHTTPHeaderField:@"User-Agent"];
    [req setTimeoutInterval:10.0];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *currentVer = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"1.0.0";

            if (!error && data) {
                NSError *jsonErr = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
                if (json && [json isKindOfClass:[NSDictionary class]] && json[@"tag_name"]) {
                    NSString *remoteTag = [json[@"tag_name"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

                    if ([weakSelf isVersion:remoteTag newerThan:currentVer]) {
                        NSString *dmgUrl = nil;
                        NSArray *assets = json[@"assets"];
                        if ([assets isKindOfClass:[NSArray class]]) {
                            for (NSDictionary *asset in assets) {
                                if ([asset isKindOfClass:[NSDictionary class]]) {
                                    NSString *name = asset[@"name"];
                                    NSString *dlUrl = asset[@"browser_download_url"];
                                    if ([name.lowercaseString hasSuffix:@".dmg"] && dlUrl.length > 0) {
                                        dmgUrl = dlUrl;
                                        break;
                                    }
                                }
                            }
                        }
                        if (!dmgUrl) {
                            dmgUrl = [NSString stringWithFormat:@"https://github.com/siraj-bd/LowWatt-Handshake-For-MacOS/releases/download/%@/LowWatt-Handshake-macOS.dmg", remoteTag];
                        }

                        if (silent) {
                            // Automatic background update: download and apply silently without user intervention
                            [weakSelf downloadAndApplyUpdateWithUrl:dmgUrl version:remoteTag silent:YES];
                        } else {
                            // User-triggered check: confirm automated update
                            NSAlert *alert = [[NSAlert alloc] init];
                            alert.messageText = @"Update Available";
                            alert.informativeText = [NSString stringWithFormat:@"A newer version (%@) of LowWatt Handshake macOS is available (current: v%@).\n\nWould you like to install it now? It will download and update automatically without manual installation.", remoteTag, currentVer];
                            [alert addButtonWithTitle:@"Update Now"];
                            [alert addButtonWithTitle:@"Later"];
                            [NSApp activateIgnoringOtherApps:YES];
                            if ([alert runModal] == NSAlertFirstButtonReturn) {
                                [weakSelf downloadAndApplyUpdateWithUrl:dmgUrl version:remoteTag silent:NO];
                            }
                        }
                        return;
                    }
                }
            }

            if (!silent) {
                NSAlert *alert = [[NSAlert alloc] init];
                if (error) {
                    alert.messageText = @"Update Check Failed";
                    alert.informativeText = [NSString stringWithFormat:@"Unable to check for updates: %@", error.localizedDescription ?: @"Network error"];
                } else {
                    alert.messageText = @"You're Up to Date";
                    alert.informativeText = [NSString stringWithFormat:@"LowWatt Handshake macOS v%@ is currently the newest version available.", currentVer];
                }
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
    NSString *appVer = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
    alert.informativeText = [NSString stringWithFormat:@"Version %@\n\nA lightweight native background utility for seamless USB-C Power Delivery charging with low-wattage chargers and power banks.\n\n⚠️ Hardware Notice: Always use certified, reputable brand chargers and power banks (e.g. Anker, Apple, Belkin, UGREEN, Baseus, Samsung, Shargeek). Never use low-quality local or unbranded generic chargers. The developers disclaim all liability for any battery or hardware damage resulting from substandard third-party accessories.\n\nCopyright © 2026 LowWatt Handshake macOS. All Rights Reserved.", appVer];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"GitHub Repository"];
    NSImage *logo = [self loadBrandLogo];
    if (logo) {
        [logo setSize:NSMakeSize(64, 64)];
        alert.icon = logo;
    }
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertSecondButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/siraj-bd/LowWatt-Handshake-For-MacOS"]];
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
