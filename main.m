#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface NSTouchBarItem (Private)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (Private)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier identifier, BOOL present);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL shows);

@interface UniversalTouchBarController : NSObject <NSApplicationDelegate, NSTouchBarDelegate>
// --- Спільні елементи ---
@property (strong) NSStatusItem *statusItem;

// --- Meet UI & стан ---
@property (strong) NSCustomTouchBarItem *meetTrayItem;
@property (copy) NSString *currentMeetTrayId;
@property (assign) NSInteger meetTrayCounter;

@property (strong) NSTouchBar *meetTouchBar;
@property (strong) NSArray<NSTouchBarItemIdentifier> *meetMainIdentifiers;
@property (strong) NSArray<NSTouchBarItemIdentifier> *meetMainIdentifiersWithFocus;
@property (strong) NSArray<NSTouchBarItemIdentifier> *meetReactionIdentifiers;
@property (strong) NSTimer *meetWatchdogTimer;

@property (strong) NSButton *micButton;
@property (strong) NSButton *camButton;
@property (strong) NSButton *handButton;

@property (strong) NSMutableArray<NSString *> *commandQueue;
@property (strong) dispatch_semaphore_t cmdSemaphore;
@property (strong) NSDate *lastMeetPing;
@property (assign) BOOL isMeetBarVisible;
@property (assign) BOOL isShowingReactions;
@property (assign) BOOL isOnMeetTab;
@property (assign) BOOL isMeetTrayVisible;
@property (assign) BOOL userDismissedMeetManually;

// --- Arduino UI & стан ---
@property (strong) NSCustomTouchBarItem *arduinoTrayItem;
@property (copy) NSString *currentArduinoTrayId;
@property (assign) NSInteger arduinoTrayCounter;

@property (strong) NSTouchBar *arduinoTouchBar;
@property (strong) NSArray<NSTouchBarItemIdentifier> *arduinoMainIdentifiers;
@property (strong) NSArray<NSTouchBarItemIdentifier> *arduinoMainIdentifiersWithWindows;

@property (strong) NSArray<NSDictionary *> *openArduinoWindows;
@property (assign) BOOL isArduinoBarVisible;
@property (assign) BOOL isArduinoTrayVisible;
@property (assign) BOOL isShowingArduinoWindows;
@property (assign) BOOL userDismissedArduinoManually;

@end

@implementation UniversalTouchBarController

- (NSImage *)sfSymbol:(NSString *)name {
    if (@available(macOS 11.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        if (img) {
            [img setTemplate:YES];
            return img;
        }
    }
    return nil;
}

#pragma mark - Meet Tray Item

- (void)createMeetTrayItem {
    self.meetTrayCounter += 1;
    self.currentMeetTrayId = [NSString stringWithFormat:@"com.local.meetbar.tray.%ld", (long)self.meetTrayCounter];
    self.meetTrayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:self.currentMeetTrayId];

    NSImage *trayImg = [self sfSymbol:@"video.fill"];
    if (@available(macOS 11.0, *)) {
        if (trayImg) {
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:15.5 weight:NSFontWeightRegular];
            trayImg = [trayImg imageWithSymbolConfiguration:cfg];
            NSImage *whiteImg = [NSImage imageWithSize:trayImg.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
                [trayImg drawInRect:dstRect];
                [[NSColor whiteColor] set];
                NSRectFillUsingOperation(dstRect, NSCompositingOperationSourceAtop);
                return YES;
            }];
            [whiteImg setTemplate:NO];
            trayImg = whiteImg;
        }
    }

    NSButton *trayBtn = nil;
    if (trayImg) {
        trayBtn = [NSButton buttonWithImage:trayImg target:self action:@selector(toggleMeetBar:)];
        trayBtn.imageScaling = NSImageScaleNone;
    } else {
        trayBtn = [NSButton buttonWithTitle:@"Meet" target:self action:@selector(toggleMeetBar:)];
    }
    [trayBtn setButtonType:NSButtonTypeMomentaryChange];
    trayBtn.bordered = NO;
    trayBtn.wantsLayer = YES;
    trayBtn.layer.backgroundColor = [NSColor colorWithDisplayP3Red:54.5/255.0 green:54.5/255.0 blue:55.0/255.0 alpha:1.0].CGColor;
    trayBtn.layer.cornerRadius = 0.0;
    [trayBtn.widthAnchor constraintEqualToConstant:38].active = YES;

    self.meetTrayItem.view = trayBtn;
    [NSTouchBarItem addSystemTrayItem:self.meetTrayItem];
    DFRElementSetControlStripPresenceForIdentifier(self.currentMeetTrayId, YES);
    self.isMeetTrayVisible = YES;
}

#pragma mark - Arduino Tray Item

- (void)createArduinoTrayItem {
    self.arduinoTrayCounter += 1;
    self.currentArduinoTrayId = [NSString stringWithFormat:@"com.local.arduinobar.tray.%ld", (long)self.arduinoTrayCounter];
    self.arduinoTrayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:self.currentArduinoTrayId];

    NSImage *trayImg = [self sfSymbol:@"cpu"];
    if (@available(macOS 11.0, *)) {
        if (trayImg) {
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:15.5 weight:NSFontWeightRegular];
            trayImg = [trayImg imageWithSymbolConfiguration:cfg];
            NSImage *whiteImg = [NSImage imageWithSize:trayImg.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
                [trayImg drawInRect:dstRect];
                [[NSColor whiteColor] set];
                NSRectFillUsingOperation(dstRect, NSCompositingOperationSourceAtop);
                return YES;
            }];
            [whiteImg setTemplate:NO];
            trayImg = whiteImg;
        }
    }

    NSButton *trayBtn = nil;
    if (trayImg) {
        trayBtn = [NSButton buttonWithImage:trayImg target:self action:@selector(toggleArduinoBar:)];
        trayBtn.imageScaling = NSImageScaleNone;
    } else {
        trayBtn = [NSButton buttonWithTitle:@"INO" target:self action:@selector(toggleArduinoBar:)];
    }
    [trayBtn setButtonType:NSButtonTypeMomentaryChange];
    trayBtn.bordered = NO;
    trayBtn.wantsLayer = YES;
    trayBtn.layer.backgroundColor = [NSColor colorWithDisplayP3Red:54.5/255.0 green:54.5/255.0 blue:55.0/255.0 alpha:1.0].CGColor;
    trayBtn.layer.cornerRadius = 0.0;
    [trayBtn.widthAnchor constraintEqualToConstant:38].active = YES;

    self.arduinoTrayItem.view = trayBtn;
    [NSTouchBarItem addSystemTrayItem:self.arduinoTrayItem];
    DFRElementSetControlStripPresenceForIdentifier(self.currentArduinoTrayId, YES);
    self.isArduinoTrayVisible = YES;
}

#pragma mark - Application Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Перевірка дозволу Accessibility (без спаму діалогів, якщо вже надано)
    NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @NO};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);

    // Meet стан
    self.commandQueue = [NSMutableArray array];
    self.cmdSemaphore = dispatch_semaphore_create(0);
    self.meetTrayCounter = 0;
    self.isMeetBarVisible = NO;
    self.isShowingReactions = NO;
    self.isOnMeetTab = YES;
    self.isMeetTrayVisible = NO;
    self.userDismissedMeetManually = NO;

    // Arduino стан
    self.arduinoTrayCounter = 0;
    self.isShowingArduinoWindows = NO;
    self.isArduinoBarVisible = NO;
    self.isArduinoTrayVisible = NO;
    self.userDismissedArduinoManually = NO;
    self.openArduinoWindows = @[];

    // Єдине меню у рядку стану (Menu Bar)
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage *menuImg = [self sfSymbol:@"slider.horizontal.below.rectangle"];
    if (menuImg) {
        self.statusItem.button.image = menuImg;
    } else {
        self.statusItem.button.title = @"TouchBar";
    }
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Панель Meet" action:@selector(toggleMeetBar:) keyEquivalent:@"m"];
    [menu addItemWithTitle:@"Панель Arduino" action:@selector(toggleArduinoBar:) keyEquivalent:@"a"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Вийти" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;

    DFRSystemModalShowsCloseBoxWhenFrontMost(YES);

    // Ідентифікатори Meet
    self.meetMainIdentifiers = @[
        @"com.local.meet.mic",
        @"com.local.meet.cam",
        @"com.local.meet.hand",
        @"com.local.meet.reactions"
    ];

    self.meetMainIdentifiersWithFocus = @[
        @"com.local.meet.mic",
        @"com.local.meet.cam",
        @"com.local.meet.hand",
        @"com.local.meet.reactions",
        @"com.local.meet.focus"
    ];

    self.meetReactionIdentifiers = @[
        @"emoji.back",
        @"emoji.heart",
        @"emoji.like",
        @"emoji.party",
        @"emoji.clap",
        @"emoji.laugh",
        @"emoji.wow",
        @"emoji.sad",
        @"emoji.think",
        @"emoji.dislike"
    ];

    self.meetTouchBar = [[NSTouchBar alloc] init];
    self.meetTouchBar.delegate = self;
    self.meetTouchBar.defaultItemIdentifiers = self.meetMainIdentifiers;

    // Ідентифікатори Arduino
    self.arduinoMainIdentifiers = @[
        @"com.local.ino.verify",
        @"com.local.ino.upload",
        @"com.local.ino.serial",
        @"com.local.ino.sketchbook",
        @"com.local.ino.libs"
    ];

    self.arduinoMainIdentifiersWithWindows = @[
        @"com.local.ino.verify",
        @"com.local.ino.upload",
        @"com.local.ino.serial",
        @"com.local.ino.sketchbook",
        @"com.local.ino.libs",
        @"com.local.ino.windows"
    ];

    self.arduinoTouchBar = [[NSTouchBar alloc] init];
    self.arduinoTouchBar.delegate = self;
    self.arduinoTouchBar.defaultItemIdentifiers = self.arduinoMainIdentifiers;

    // Реактивне відстеження активного вікна (БЕЗ фонових таймерів, 0% CPU!)
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(activeAppChanged:)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];

    [self checkFrontApp];

    // Запуск HTTP-сервера для зв'язку з Meet розширенням
    [self startHTTPServer];
}

#pragma mark - Arduino Logic (Працює ТІЛЬКИ коли Arduino відкритий)

- (NSRunningApplication *)findArduinoApp {
    NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *name = front.localizedName ?: @"";
    NSString *bid = front.bundleIdentifier ?: @"";
    if ([name rangeOfString:@"Arduino" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [bid rangeOfString:@"arduino" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return front;
    }
    return nil;
}

- (NSString *)formatWindowTitle:(NSString *)rawTitle {
    NSString *clean = rawTitle ?: @"Скетч";
    NSArray *seps = @[@" — Arduino IDE", @" - Arduino IDE", @" | Arduino IDE"];
    for (NSString *sep in seps) {
        NSRange r = [clean rangeOfString:sep];
        if (r.location != NSNotFound) {
            clean = [clean substringToIndex:r.location];
            break;
        }
    }
    if (clean.length > 24) {
        clean = [[clean substringToIndex:23] stringByAppendingString:@"…"];
    }
    return clean;
}

- (void)refreshArduinoWindowsForApp:(NSRunningApplication *)app {
    if (!app || !AXIsProcessTrusted()) return;

    NSMutableArray *found = [NSMutableArray array];
    AXUIElementRef appRef = AXUIElementCreateApplication(app.processIdentifier);
    CFArrayRef winList = NULL;
    if (AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, (CFTypeRef *)&winList) == kAXErrorSuccess && winList != NULL) {
        CFIndex count = CFArrayGetCount(winList);
        for (CFIndex i = 0; i < count; i++) {
            AXUIElementRef winRef = (AXUIElementRef)CFArrayGetValueAtIndex(winList, i);
            CFTypeRef titleRef = NULL;
            AXUIElementCopyAttributeValue(winRef, kAXTitleAttribute, &titleRef);
            NSString *rawTitle = titleRef ? (__bridge_transfer NSString *)titleRef : @"";
            if (rawTitle.length == 0) continue;

            [found addObject:@{
                @"title": [self formatWindowTitle:rawTitle],
                @"rawTitle": rawTitle,
                @"pid": @(app.processIdentifier)
            }];
        }
        CFRelease(winList);
    }
    CFRelease(appRef);

    BOOL countChanged = ((self.openArduinoWindows.count > 1) != (found.count > 1));
    self.openArduinoWindows = found;

    if (self.isArduinoBarVisible && !self.isShowingArduinoWindows && countChanged) {
        self.arduinoTouchBar.defaultItemIdentifiers = (self.openArduinoWindows.count > 1) ? self.arduinoMainIdentifiersWithWindows : self.arduinoMainIdentifiers;
    }
}

- (void)activeAppChanged:(NSNotification *)note {
    [self checkFrontApp];
}

- (void)checkFrontApp {
    NSRunningApplication *arduino = [self findArduinoApp];
    if (arduino) {
        [self refreshArduinoWindowsForApp:arduino];
        if (!self.isArduinoTrayVisible) {
            [self createArduinoTrayItem];
        }
        if (!self.isArduinoBarVisible && !self.userDismissedArduinoManually) {
            [self showArduinoBar];
        }
    } else {
        [self hideArduinoBar];
    }
}

- (void)showArduinoBar {
    if (!self.isArduinoTrayVisible) {
        [self createArduinoTrayItem];
    }
    self.isShowingArduinoWindows = NO;
    self.arduinoTouchBar.defaultItemIdentifiers = (self.openArduinoWindows.count > 1) ? self.arduinoMainIdentifiersWithWindows : self.arduinoMainIdentifiers;
    [NSTouchBar presentSystemModalTouchBar:self.arduinoTouchBar systemTrayItemIdentifier:self.currentArduinoTrayId];
    self.isArduinoBarVisible = YES;
    self.userDismissedArduinoManually = NO;
}

- (void)hideArduinoBar {
    if (self.isArduinoBarVisible) {
        [NSTouchBar dismissSystemModalTouchBar:self.arduinoTouchBar];
        self.isArduinoBarVisible = NO;
        self.isShowingArduinoWindows = NO;
        self.arduinoTouchBar.defaultItemIdentifiers = self.arduinoMainIdentifiers;
    }
    if (self.isArduinoTrayVisible && self.currentArduinoTrayId) {
        DFRElementSetControlStripPresenceForIdentifier(self.currentArduinoTrayId, NO);
        self.isArduinoTrayVisible = NO;
    }
    self.userDismissedArduinoManually = NO;
}

- (void)toggleArduinoBar:(id)sender {
    if (self.isArduinoBarVisible) {
        [NSTouchBar dismissSystemModalTouchBar:self.arduinoTouchBar];
        self.isArduinoBarVisible = NO;
        self.isShowingArduinoWindows = NO;
        self.userDismissedArduinoManually = YES;
    } else {
        [self showArduinoBar];
    }
}

- (void)openArduinoWindowsMenu:(id)sender {
    NSRunningApplication *arduino = [self findArduinoApp];
    if (arduino) [self refreshArduinoWindowsForApp:arduino];
    if (self.openArduinoWindows.count <= 1) return;
    self.isShowingArduinoWindows = YES;
    NSMutableArray *ids = [NSMutableArray arrayWithObject:@"com.local.ino.back"];
    for (NSUInteger i = 0; i < MIN(self.openArduinoWindows.count, 5); i++) {
        [ids addObject:[NSString stringWithFormat:@"com.local.ino.win.%lu", (unsigned long)i]];
    }
    self.arduinoTouchBar.defaultItemIdentifiers = ids;
}

- (void)closeArduinoWindowsMenu:(id)sender {
    self.isShowingArduinoWindows = NO;
    self.arduinoTouchBar.defaultItemIdentifiers = (self.openArduinoWindows.count > 1) ? self.arduinoMainIdentifiersWithWindows : self.arduinoMainIdentifiers;
}

- (void)raiseArduinoWindow:(NSButton *)sender {
    NSInteger pos = sender.tag;
    if (pos < 0 || pos >= (NSInteger)self.openArduinoWindows.count) return;

    NSDictionary *info = self.openArduinoWindows[pos];
    pid_t pid = [info[@"pid"] intValue];
    NSString *targetRaw = info[@"rawTitle"] ?: @"";

    if (pid > 0 && AXIsProcessTrusted()) {
        AXUIElementRef appRef = AXUIElementCreateApplication(pid);
        CFArrayRef winList = NULL;
        if (AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, (CFTypeRef *)&winList) == kAXErrorSuccess && winList != NULL) {
            CFIndex count = CFArrayGetCount(winList);
            for (CFIndex i = 0; i < count; i++) {
                AXUIElementRef winRef = (AXUIElementRef)CFArrayGetValueAtIndex(winList, i);
                CFTypeRef titleRef = NULL;
                AXUIElementCopyAttributeValue(winRef, kAXTitleAttribute, &titleRef);
                NSString *t = titleRef ? (__bridge_transfer NSString *)titleRef : @"";
                if ([t isEqualToString:targetRaw] || (count == 1)) {
                    AXUIElementPerformAction(winRef, kAXRaiseAction);
                    AXUIElementSetAttributeValue(winRef, kAXMainAttribute, kCFBooleanTrue);
                    break;
                }
            }
            CFRelease(winList);
        }
        CFRelease(appRef);

        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        [app activateWithOptions:0];
    }
    [self closeArduinoWindowsMenu:nil];
}

- (void)sendKeyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags {
    if (!AXIsProcessTrusted()) {
        NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
        return;
    }
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef down = CGEventCreateKeyboardEvent(src, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(src, keyCode, false);
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    CFRelease(src);
}

- (void)doVerify:(id)sender     { [self sendKeyCode:kVK_ANSI_R flags:kCGEventFlagMaskCommand]; }
- (void)doUpload:(id)sender     { [self sendKeyCode:kVK_ANSI_U flags:kCGEventFlagMaskCommand]; }
- (void)doSerial:(id)sender     { [self sendKeyCode:kVK_ANSI_M flags:(kCGEventFlagMaskCommand | kCGEventFlagMaskShift)]; }
- (void)doSketchbook:(id)sender { [self sendKeyCode:kVK_ANSI_B flags:(kCGEventFlagMaskCommand | kCGEventFlagMaskShift)]; }
- (void)doLibs:(id)sender       { [self sendKeyCode:kVK_ANSI_I flags:(kCGEventFlagMaskCommand | kCGEventFlagMaskShift)]; }

#pragma mark - HTTP Server & Meet Logic

- (void)startHTTPServer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd < 0) return;

        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = inet_addr("127.0.0.1");
        addr.sin_port = htons(48123);

        if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(server_fd);
            return;
        }
        listen(server_fd, 16);

        while (1) {
            int client_fd = accept(server_fd, NULL, NULL);
            if (client_fd < 0) continue;

            char buf[2048];
            ssize_t n = recv(client_fd, buf, sizeof(buf) - 1, 0);
            if (n > 0) {
                buf[n] = '\0';
                NSString *req = [NSString stringWithUTF8String:buf];
                NSString *firstLine = [[req componentsSeparatedByString:@"\r\n"] firstObject];

                BOOL hasMeet = [firstLine containsString:@"hasMeet=1"];
                BOOL micOn = [firstLine containsString:@"mic=1"];
                BOOL camOn = [firstLine containsString:@"cam=1"];
                BOOL handUp = [firstLine containsString:@"hand=1"];
                BOOL onMeet = [firstLine containsString:@"onMeet=1"];

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (hasMeet) {
                        self.lastMeetPing = [NSDate date];
                        if (!self.isMeetTrayVisible) {
                            [self createMeetTrayItem];
                        }
                        if (self.isOnMeetTab != onMeet) {
                            self.isOnMeetTab = onMeet;
                            if (!self.isShowingReactions && self.isMeetBarVisible) {
                                self.meetTouchBar.defaultItemIdentifiers = onMeet ? self.meetMainIdentifiers : self.meetMainIdentifiersWithFocus;
                            }
                        }
                        if (!self.isMeetBarVisible && !self.userDismissedMeetManually) {
                            [self showMeetBar];
                        }
                        [self updateButtonsWithMic:micOn cam:camOn hand:handUp];

                        // Запускаємо сторожовий таймер тільки при активному дзвінку
                        if (!self.meetWatchdogTimer) {
                            self.meetWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                                                      target:self
                                                                                    selector:@selector(checkWatchdog)
                                                                                    userInfo:nil
                                                                                     repeats:YES];
                        }
                    } else {
                        [self hideMeetUI];
                    }
                });

                BOOL queueEmpty = NO;
                @synchronized (self.commandQueue) {
                    queueEmpty = (self.commandQueue.count == 0);
                }
                if (hasMeet && queueEmpty) {
                    dispatch_semaphore_wait(self.cmdSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)));
                }

                NSString *cmdToSend = @"";
                @synchronized (self.commandQueue) {
                    if (self.commandQueue.count > 0) {
                        cmdToSend = self.commandQueue.firstObject;
                        [self.commandQueue removeObjectAtIndex:0];
                    }
                }

                NSString *json = [NSString stringWithFormat:@"{\"cmd\":\"%@\"}", cmdToSend];
                NSString *httpResp = [NSString stringWithFormat:
                    @"HTTP/1.1 200 OK\r\n"
                    @"Access-Control-Allow-Origin: *\r\n"
                    @"Content-Type: application/json; charset=utf-8\r\n"
                    @"Content-Length: %lu\r\n"
                    @"Connection: close\r\n\r\n%@",
                    (unsigned long)[json lengthOfBytesUsingEncoding:NSUTF8StringEncoding], json];

                const char *respBytes = [httpResp UTF8String];
                send(client_fd, respBytes, strlen(respBytes), 0);
            }
            close(client_fd);
        }
    });
}

- (void)hideMeetUI {
    if (self.isMeetBarVisible) {
        [NSTouchBar dismissSystemModalTouchBar:self.meetTouchBar];
        self.isMeetBarVisible = NO;
        self.isShowingReactions = NO;
        self.meetTouchBar.defaultItemIdentifiers = self.meetMainIdentifiers;
    }
    if (self.isMeetTrayVisible && self.currentMeetTrayId) {
        DFRElementSetControlStripPresenceForIdentifier(self.currentMeetTrayId, NO);
        self.isMeetTrayVisible = NO;
    }
    self.userDismissedMeetManually = NO;

    // Зупиняємо таймер Meet, коли дзвінок закритий — 0% CPU!
    if (self.meetWatchdogTimer) {
        [self.meetWatchdogTimer invalidate];
        self.meetWatchdogTimer = nil;
    }
}

- (void)checkWatchdog {
    if (self.lastMeetPing == nil || [[NSDate date] timeIntervalSinceDate:self.lastMeetPing] > 3.0) {
        [self hideMeetUI];
    }
}

- (void)updateButtonsWithMic:(BOOL)micOn cam:(BOOL)camOn hand:(BOOL)handUp {
    if (self.micButton) {
        self.micButton.bezelColor = micOn ? [NSColor systemRedColor] : nil;
        NSImage *img = [self sfSymbol:(micOn ? @"mic.fill" : @"mic.slash.fill")];
        if (img) self.micButton.image = img;
    }
    if (self.camButton) {
        self.camButton.bezelColor = camOn ? [NSColor systemBlueColor] : nil;
        NSImage *img = [self sfSymbol:(camOn ? @"video.fill" : @"video.slash.fill")];
        if (img) self.camButton.image = img;
    }
    if (self.handButton) {
        self.handButton.bezelColor = handUp ? [NSColor systemOrangeColor] : nil;
    }
}

- (void)showMeetBar {
    if (!self.isMeetTrayVisible) {
        [self createMeetTrayItem];
    }
    self.isShowingReactions = NO;
    self.meetTouchBar.defaultItemIdentifiers = self.isOnMeetTab ? self.meetMainIdentifiers : self.meetMainIdentifiersWithFocus;
    [NSTouchBar presentSystemModalTouchBar:self.meetTouchBar systemTrayItemIdentifier:self.currentMeetTrayId];
    self.isMeetBarVisible = YES;
    self.userDismissedMeetManually = NO;
}

- (void)openReactionsBar:(id)sender {
    self.isShowingReactions = YES;
    self.meetTouchBar.defaultItemIdentifiers = self.meetReactionIdentifiers;
}

- (void)closeReactionsBar:(id)sender {
    self.isShowingReactions = NO;
    self.meetTouchBar.defaultItemIdentifiers = self.isOnMeetTab ? self.meetMainIdentifiers : self.meetMainIdentifiersWithFocus;
    [self enqueueCommand:@"closeReactions"];
}

- (void)toggleMeetBar:(id)sender {
    if (self.isMeetBarVisible) {
        [NSTouchBar dismissSystemModalTouchBar:self.meetTouchBar];
        self.isMeetBarVisible = NO;
        self.isShowingReactions = NO;
        self.meetTouchBar.defaultItemIdentifiers = self.isOnMeetTab ? self.meetMainIdentifiers : self.meetMainIdentifiersWithFocus;
        self.userDismissedMeetManually = YES;
    } else {
        [self showMeetBar];
    }
}

- (NSButton *)makeSymbolButton:(NSString *)symbolName title:(NSString *)title action:(SEL)action {
    NSImage *img = [self sfSymbol:symbolName];
    NSButton *btn;
    if (img) {
        btn = [NSButton buttonWithTitle:title image:img target:self action:action];
        btn.imagePosition = title.length > 0 ? NSImageLeft : NSImageOnly;
    } else {
        btn = [NSButton buttonWithTitle:title target:self action:action];
    }
    btn.bezelStyle = NSBezelStyleRounded;
    return btn;
}

- (NSButton *)makeNotoEmojiButton:(NSString *)code fallback:(NSString *)fallback tag:(NSInteger)tag width:(CGFloat)width {
    NSString *path = [NSString stringWithFormat:@"%@/MeetTouchBar/emojis/%@.png", NSHomeDirectory(), code];
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
    NSButton *btn;
    if (img) {
        img.size = NSMakeSize(22, 22);
        btn = [NSButton buttonWithImage:img target:self action:@selector(sendEmoji:)];
        btn.imageScaling = NSImageScaleProportionallyDown;
    } else {
        btn = [NSButton buttonWithTitle:fallback target:self action:@selector(sendEmoji:)];
    }
    btn.tag = tag;
    btn.bezelStyle = NSBezelStyleRounded;
    [btn.widthAnchor constraintEqualToConstant:width].active = YES;
    return btn;
}

#pragma mark - Unified TouchBar Delegate

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    NSButton *btn = nil;

    // === Кнопки Meet ===
    if ([identifier isEqualToString:@"com.local.meet.mic"]) {
        btn = [self makeSymbolButton:@"mic.slash.fill" title:@"Мікрофон" action:@selector(toggleMic:)];
        self.micButton = btn;
    } else if ([identifier isEqualToString:@"com.local.meet.cam"]) {
        btn = [self makeSymbolButton:@"video.slash.fill" title:@"Камера" action:@selector(toggleCam:)];
        self.camButton = btn;
    } else if ([identifier isEqualToString:@"com.local.meet.hand"]) {
        btn = [self makeSymbolButton:@"hand.raised.fill" title:@"Рука" action:@selector(toggleHand:)];
        self.handButton = btn;
    } else if ([identifier isEqualToString:@"com.local.meet.reactions"]) {
        btn = [self makeSymbolButton:@"face.smiling" title:@"Реакції" action:@selector(openReactionsBar:)];
    } else if ([identifier isEqualToString:@"com.local.meet.focus"]) {
        btn = [self makeSymbolButton:@"arrow.up.forward.app.fill" title:@"До уроку" action:@selector(focusMeetTab:)];
        [btn.widthAnchor constraintGreaterThanOrEqualToConstant:115].active = YES;
    } else if ([identifier isEqualToString:@"emoji.back"]) {
        btn = [self makeSymbolButton:@"chevron.left" title:@"" action:@selector(closeReactionsBar:)];
        [btn.widthAnchor constraintEqualToConstant:64].active = YES;
    } else if ([identifier isEqualToString:@"emoji.heart"]) {
        btn = [self makeNotoEmojiButton:@"1f496" fallback:@"💖" tag:1 width:46];
    } else if ([identifier isEqualToString:@"emoji.like"]) {
        btn = [self makeNotoEmojiButton:@"1f44d" fallback:@"👍" tag:2 width:46];
    } else if ([identifier isEqualToString:@"emoji.party"]) {
        btn = [self makeNotoEmojiButton:@"1f389" fallback:@"🎉" tag:3 width:46];
    } else if ([identifier isEqualToString:@"emoji.clap"]) {
        btn = [self makeNotoEmojiButton:@"1f44f" fallback:@"👏" tag:4 width:46];
    } else if ([identifier isEqualToString:@"emoji.laugh"]) {
        btn = [self makeNotoEmojiButton:@"1f602" fallback:@"😂" tag:5 width:46];
    } else if ([identifier isEqualToString:@"emoji.wow"]) {
        btn = [self makeNotoEmojiButton:@"1f62e" fallback:@"😮" tag:6 width:46];
    } else if ([identifier isEqualToString:@"emoji.sad"]) {
        btn = [self makeNotoEmojiButton:@"1f622" fallback:@"😢" tag:7 width:46];
    } else if ([identifier isEqualToString:@"emoji.think"]) {
        btn = [self makeNotoEmojiButton:@"1f914" fallback:@"🤔" tag:8 width:46];
    } else if ([identifier isEqualToString:@"emoji.dislike"]) {
        btn = [self makeNotoEmojiButton:@"1f44e" fallback:@"👎" tag:9 width:46];
    }
    // === Кнопки Arduino ===
    else if ([identifier isEqualToString:@"com.local.ino.verify"]) {
        btn = [self makeSymbolButton:@"checkmark.circle" title:@"Перевірити" action:@selector(doVerify:)];
    } else if ([identifier isEqualToString:@"com.local.ino.upload"]) {
        btn = [self makeSymbolButton:@"arrow.right.circle" title:@"Зашити" action:@selector(doUpload:)];
    } else if ([identifier isEqualToString:@"com.local.ino.serial"]) {
        btn = [self makeSymbolButton:@"terminal" title:@"Монітор" action:@selector(doSerial:)];
    } else if ([identifier isEqualToString:@"com.local.ino.sketchbook"]) {
        btn = [self makeSymbolButton:@"folder" title:@"Скетчі" action:@selector(doSketchbook:)];
    } else if ([identifier isEqualToString:@"com.local.ino.libs"]) {
        btn = [self makeSymbolButton:@"books.vertical" title:@"Бібліотеки" action:@selector(doLibs:)];
    } else if ([identifier isEqualToString:@"com.local.ino.windows"]) {
        btn = [self makeSymbolButton:@"macwindow.on.rectangle" title:@"" action:@selector(openArduinoWindowsMenu:)];
        [btn.widthAnchor constraintEqualToConstant:48].active = YES;
    } else if ([identifier isEqualToString:@"com.local.ino.back"]) {
        btn = [self makeSymbolButton:@"chevron.left" title:@"" action:@selector(closeArduinoWindowsMenu:)];
        [btn.widthAnchor constraintEqualToConstant:64].active = YES;
    } else if ([identifier hasPrefix:@"com.local.ino.win."]) {
        NSInteger pos = [[identifier substringFromIndex:18] integerValue];
        if (pos >= 0 && pos < (NSInteger)self.openArduinoWindows.count) {
            NSDictionary *info = self.openArduinoWindows[pos];
            btn = [self makeSymbolButton:@"doc.text" title:info[@"title"] action:@selector(raiseArduinoWindow:)];
            btn.tag = pos;
        }
    }

    if (btn) {
        btn.bezelStyle = NSBezelStyleRounded;
        item.view = btn;
    }
    return item;
}

- (void)enqueueCommand:(NSString *)cmd {
    @synchronized (self.commandQueue) {
        [self.commandQueue addObject:cmd];
    }
    dispatch_semaphore_signal(self.cmdSemaphore);
}

- (void)toggleMic:(id)sender { [self enqueueCommand:@"mic"]; }
- (void)toggleCam:(id)sender { [self enqueueCommand:@"cam"]; }
- (void)toggleHand:(id)sender { [self enqueueCommand:@"hand"]; }
- (void)focusMeetTab:(id)sender { [self enqueueCommand:@"focusMeet"]; }

- (void)sendEmoji:(NSButton *)sender {
    NSString *emoji = @"💖";
    switch (sender.tag) {
        case 1: emoji = @"💖"; break;
        case 2: emoji = @"👍"; break;
        case 3: emoji = @"🎉"; break;
        case 4: emoji = @"👏"; break;
        case 5: emoji = @"😂"; break;
        case 6: emoji = @"😮"; break;
        case 7: emoji = @"😢"; break;
        case 8: emoji = @"🤔"; break;
        case 9: emoji = @"👎"; break;
    }
    [self enqueueCommand:[NSString stringWithFormat:@"emoji:%@", emoji]];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        UniversalTouchBarController *controller = [[UniversalTouchBarController alloc] init];
        app.delegate = controller;
        [app run];
    }
    return 0;
}
