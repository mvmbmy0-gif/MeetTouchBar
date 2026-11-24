#import <Cocoa/Cocoa.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

// ==============================================================================
//  LANGUAGE / LOCALIZATION CONFIGURATION
//  ------------------------------------------------------------------------------
//  - Set FORCE_LANGUAGE to nil for automatic system language detection (en/uk),
//    or explicitly set to @"en", @"uk", @"es", @"de", etc.
//  - To add a new language, simply add a new key dictionary to kI18n below!
// ==============================================================================

#define FORCE_LANGUAGE nil

static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *kI18n = @{
    @"en": @{
        @"mic":         @"Mic",
        @"cam":         @"Camera",
        @"hand":        @"Hand",
        @"reactions":   @"Reactions",
        @"focus":       @"To Meeting",
        @"menu_toggle": @"Show / Hide Meet Bar",
        @"menu_quit":   @"Quit MeetBar"
    },
    @"uk": @{
        @"mic":         @"Мікрофон",
        @"cam":         @"Камера",
        @"hand":        @"Рука",
        @"reactions":   @"Реакції",
        @"focus":       @"До уроку",
        @"menu_toggle": @"Показати / Сховати панель Meet",
        @"menu_quit":   @"Вийти з MeetBar"
    }
};

static NSString *Localized(NSString *key) {
    NSString *lang = FORCE_LANGUAGE;
    if (!lang) {
        NSString *preferred = [NSLocale preferredLanguages].firstObject ?: @"en";
        if ([preferred hasPrefix:@"uk"]) {
            lang = @"uk";
        } else {
            lang = @"en";
        }
    }
    NSDictionary *dict = kI18n[lang] ?: kI18n[@"en"];
    return dict[key] ?: kI18n[@"en"][key] ?: key;
}

// --- Private Touch Bar and DFR APIs ---
@interface NSTouchBarItem (Private)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (Private)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier identifier, BOOL present);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL shows);

@interface MeetBarController : NSObject <NSApplicationDelegate, NSTouchBarDelegate>
@property (strong) NSCustomTouchBarItem *trayItem;
@property (copy) NSString *currentTrayId;
@property (assign) NSInteger trayCounter;

@property (strong) NSTouchBar *meetTouchBar;
@property (strong) NSArray<NSTouchBarItemIdentifier> *mainIdentifiers;
@property (strong) NSArray<NSTouchBarItemIdentifier> *mainIdentifiersWithFocus;
@property (strong) NSArray<NSTouchBarItemIdentifier> *reactionIdentifiers;
@property (strong) NSStatusItem *statusItem;

@property (strong) NSButton *micButton;
@property (strong) NSButton *camButton;
@property (strong) NSButton *handButton;

@property (strong) NSMutableArray<NSString *> *commandQueue;
@property (strong) dispatch_semaphore_t cmdSemaphore;

@property (assign) NSTimeInterval lastHeartbeat;
@property (strong) NSTimer *watchdogTimer;
@property (assign) BOOL isBarVisible;
@property (assign) BOOL isShowingReactions;
@property (assign) BOOL isOnMeetTab;
@property (assign) BOOL isTrayVisible;
@property (assign) BOOL userDismissedManually;
@end

@implementation MeetBarController

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

- (void)createTrayItem {
    self.trayCounter += 1;
    self.currentTrayId = [NSString stringWithFormat:@"com.local.meetbar.tray.%ld", (long)self.trayCounter];
    self.trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:self.currentTrayId];

    NSImage *trayImg = [self sfSymbol:@"video.bubble.left.fill"];
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
    // Native Control Strip dark tint (#3B3B3D) and standard 38pt width
    trayBtn.layer.backgroundColor = [NSColor colorWithDisplayP3Red:54.5/255.0 green:54.5/255.0 blue:55.0/255.0 alpha:1.0].CGColor;
    trayBtn.layer.cornerRadius = 0.0;
    [trayBtn.widthAnchor constraintEqualToConstant:38].active = YES;

    self.trayItem.view = trayBtn;

    [NSTouchBarItem addSystemTrayItem:self.trayItem];
    DFRElementSetControlStripPresenceForIdentifier(self.currentTrayId, YES);
    self.isTrayVisible = YES;
}

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
            if (n <= 0) {
                close(client_fd);
                continue;
            }
            buf[n] = '\0';
            NSString *req = [NSString stringWithUTF8String:buf];

            if ([req containsString:@"OPTIONS /"]) {
                const char *resp = "HTTP/1.1 204 No Content\r\n"
                                   "Access-Control-Allow-Origin: *\r\n"
                                   "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
                                   "Access-Control-Allow-Headers: Content-Type\r\n"
                                   "Connection: close\r\n\r\n";
                send(client_fd, resp, strlen(resp), 0);
                close(client_fd);
                continue;
            }

            if ([req containsString:@"POST /state"]) {
                NSRange bodyRange = [req rangeOfString:@"\r\n\r\n"];
                if (bodyRange.location != NSNotFound) {
                    NSString *body = [req substringFromIndex:bodyRange.location + 4];
                    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (json) {
                        BOOL mic = [json[@"mic"] boolValue];
                        BOOL cam = [json[@"cam"] boolValue];
                        BOOL hand = [json[@"hand"] boolValue];
                        BOOL onTab = json[@"onTab"] ? [json[@"onTab"] boolValue] : YES;

                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.lastHeartbeat = [NSDate timeIntervalSinceReferenceDate];
                            self.isOnMeetTab = onTab;

                            if (!self.isShowingReactions) {
                                NSArray *desired = onTab ? self.mainIdentifiers : self.mainIdentifiersWithFocus;
                                if (![self.meetTouchBar.defaultItemIdentifiers isEqualToArray:desired]) {
                                    self.meetTouchBar.defaultItemIdentifiers = desired;
                                }
                            }
                            [self updateButtonsWithMic:mic cam:cam hand:hand];

                            if (!self.isTrayVisible) {
                                [self createTrayItem];
                            }
                            if (!self.isBarVisible && !self.userDismissedManually) {
                                [self showMeetBar];
                            }
                        });
                    }
                }
                const char *resp = "HTTP/1.1 200 OK\r\n"
                                   "Access-Control-Allow-Origin: *\r\n"
                                   "Content-Type: application/json\r\n"
                                   "Connection: close\r\n\r\n{\"ok\":true}";
                send(client_fd, resp, strlen(resp), 0);
                close(client_fd);
                continue;
            }

            if ([req containsString:@"GET /poll"]) {
                dispatch_semaphore_wait(self.cmdSemaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

                NSString *cmd = @"";
                @synchronized (self.commandQueue) {
                    if (self.commandQueue.count > 0) {
                        cmd = self.commandQueue.firstObject;
                        [self.commandQueue removeObjectAtIndex:0];
                    }
                }

                NSString *body = [NSString stringWithFormat:@"{\"command\":\"%@\"}", cmd];
                NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
                NSString *resp = [NSString stringWithFormat:
                                  @"HTTP/1.1 200 OK\r\n"
                                  "Access-Control-Allow-Origin: *\r\n"
                                  "Content-Type: application/json\r\n"
                                  "Content-Length: %lu\r\n"
                                  "Connection: close\r\n\r\n%@",
                                  (unsigned long)bodyData.length, body];
                const char *cresp = [resp UTF8String];
                send(client_fd, cresp, strlen(cresp), 0);
                close(client_fd);
                continue;
            }

            const char *resp = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n";
            send(client_fd, resp, strlen(resp), 0);
            close(client_fd);
        }
    });
}

- (void)hideMeetUI {
    if (self.isTrayVisible && self.currentTrayId) {
        DFRElementSetControlStripPresenceForIdentifier(self.currentTrayId, NO);
        self.isTrayVisible = NO;
    }
    if (self.isBarVisible) {
        [NSTouchBar dismissSystemModalTouchBar:self.meetTouchBar];
        self.isBarVisible = NO;
        self.isShowingReactions = NO;
        self.meetTouchBar.defaultItemIdentifiers = self.isOnMeetTab ? self.mainIdentifiers : self.mainIdentifiersWithFocus;
    }
    self.userDismissedManually = NO;
}

- (void)checkWatchdog {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (self.lastHeartbeat > 0 && (now - self.lastHeartbeat > 3.0)) {
        self.lastHeartbeat = 0;
        [self hideMeetUI];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.commandQueue = [NSMutableArray array];
    self.cmdSemaphore = dispatch_semaphore_create(0);
    self.trayCounter = 0;
    self.isBarVisible = NO;
    self.isShowingReactions = NO;
    self.isOnMeetTab = YES;
    self.isTrayVisible = NO;
    self.userDismissedManually = NO;

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage *menuImg = [self sfSymbol:@"video.bubble.left.fill"];
    if (menuImg) {
        self.statusItem.button.image = menuImg;
    } else {
        self.statusItem.button.title = @"MeetBar";
    }
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:Localized(@"menu_toggle") action:@selector(toggleMeetBar:) keyEquivalent:@"m"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:Localized(@"menu_quit") action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;

    DFRSystemModalShowsCloseBoxWhenFrontMost(YES);

    self.mainIdentifiers = @[
        @"com.local.meet.mic",
        @"com.local.meet.cam",
        @"com.local.meet.hand",
        @"com.local.meet.reactions"
    ];

    self.mainIdentifiersWithFocus = @[
        @"com.local.meet.mic",
        @"com.local.meet.cam",
        @"com.local.meet.hand",
        @"com.local.meet.reactions",
        @"com.local.meet.focus"
    ];

    self.reactionIdentifiers = @[
        @"emoji.back",
        @"emoji.heart",
        @"emoji.like",
        @"emoji.party",
        @"emoji.clap",
        @"emoji.joy",
        @"emoji.surprised",
        @"emoji.sad",
        @"emoji.thinking",
        @"emoji.dislike"
    ];

    self.meetTouchBar = [[NSTouchBar alloc] init];
    self.meetTouchBar.delegate = self;
    self.meetTouchBar.defaultItemIdentifiers = self.mainIdentifiers;

    [self startHTTPServer];

    self.watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(checkWatchdog)
                                                        userInfo:nil
                                                         repeats:YES];
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
    if (!self.isTrayVisible) {
        [self createTrayItem];
    }
    self.isShowingReactions = NO;
    self.meetTouchBar.defaultItemIdentifiers = self.isOnMeetTab ? self.mainIdentifiers : self.mainIdentifiersWithFocus;
    [NSTouchBar presentSystemModalTouchBar:self.meetTouchBar systemTrayItemIdentifier:self.currentTrayId];
    self.isBarVisible = YES;
    self.userDismissedManually = NO;
}

- (void)openReactionsBar:(id)sender {
    self.isShowingReactions = YES;
    self.meetTouchBar.defaultItemIdentifiers = self.reactionIdentifiers;
}

- (void)closeReactionsBar:(id)sender {
    self.isShowingReactions = NO;
    self.meetTouchBar.defaultItemIdentifiers = self.isOnMeetTab ? self.mainIdentifiers : self.mainIdentifiersWithFocus;
    [self enqueueCommand:@"closeReactions"];
}

- (void)toggleMeetBar:(id)sender {
    if (self.isBarVisible) {
        [NSTouchBar dismissSystemModalTouchBar:self.meetTouchBar];
        self.isBarVisible = NO;
        self.isShowingReactions = NO;
        self.meetTouchBar.defaultItemIdentifiers = self.isOnMeetTab ? self.mainIdentifiers : self.mainIdentifiersWithFocus;
        self.userDismissedManually = YES;
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

- (NSButton *)makeNotoEmojiButton:(NSString *)filename tag:(NSString *)tag {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:filename ofType:@"png" inDirectory:@"emojis"];
    if (!bundlePath) {
        bundlePath = [NSString stringWithFormat:@"/Users/matvii/MeetTouchBar/emojis/%@.png", filename];
    }
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:bundlePath];
    NSButton *btn = [NSButton buttonWithTitle:@"" target:self action:@selector(sendEmoji:)];
    if (img) {
        [img setSize:NSMakeSize(22, 22)];
        btn.image = img;
        btn.imagePosition = NSImageOnly;
    } else {
        btn.title = tag;
    }
    btn.bezelStyle = NSBezelStyleRounded;
    btn.identifier = tag;
    [btn.widthAnchor constraintEqualToConstant:46].active = YES;
    return btn;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    NSButton *btn = nil;

    if ([identifier isEqualToString:@"com.local.meet.mic"]) {
        btn = [self makeSymbolButton:@"mic.slash.fill" title:Localized(@"mic") action:@selector(toggleMic:)];
        self.micButton = btn;
    } else if ([identifier isEqualToString:@"com.local.meet.cam"]) {
        btn = [self makeSymbolButton:@"video.slash.fill" title:Localized(@"cam") action:@selector(toggleCam:)];
        self.camButton = btn;
    } else if ([identifier isEqualToString:@"com.local.meet.hand"]) {
        btn = [self makeSymbolButton:@"hand.raised.fill" title:Localized(@"hand") action:@selector(toggleHand:)];
        self.handButton = btn;
    } else if ([identifier isEqualToString:@"com.local.meet.reactions"]) {
        btn = [self makeSymbolButton:@"face.smiling" title:Localized(@"reactions") action:@selector(openReactionsBar:)];
    } else if ([identifier isEqualToString:@"com.local.meet.focus"]) {
        btn = [self makeSymbolButton:@"arrow.up.forward.app.fill" title:Localized(@"focus") action:@selector(focusMeetTab:)];
    } else if ([identifier isEqualToString:@"emoji.back"]) {
        btn = [self makeSymbolButton:@"chevron.left" title:@"" action:@selector(closeReactionsBar:)];
        [btn.widthAnchor constraintEqualToConstant:48].active = YES;
    } else if ([identifier isEqualToString:@"emoji.heart"]) {
        btn = [self makeNotoEmojiButton:@"sparkling_heart" tag:@"💖"];
    } else if ([identifier isEqualToString:@"emoji.like"]) {
        btn = [self makeNotoEmojiButton:@"thumbs_up" tag:@"👍"];
    } else if ([identifier isEqualToString:@"emoji.party"]) {
        btn = [self makeNotoEmojiButton:@"party_popper" tag:@"🎉"];
    } else if ([identifier isEqualToString:@"emoji.clap"]) {
        btn = [self makeNotoEmojiButton:@"clapping_hands" tag:@"👏"];
    } else if ([identifier isEqualToString:@"emoji.joy"]) {
        btn = [self makeNotoEmojiButton:@"joy" tag:@"😂"];
    } else if ([identifier isEqualToString:@"emoji.surprised"]) {
        btn = [self makeNotoEmojiButton:@"open_mouth" tag:@"😮"];
    } else if ([identifier isEqualToString:@"emoji.sad"]) {
        btn = [self makeNotoEmojiButton:@"crying_face" tag:@"😢"];
    } else if ([identifier isEqualToString:@"emoji.thinking"]) {
        btn = [self makeNotoEmojiButton:@"thinking_face" tag:@"🤔"];
    } else if ([identifier isEqualToString:@"emoji.dislike"]) {
        btn = [self makeNotoEmojiButton:@"thumbs_down" tag:@"👎"];
    }

    if (btn) {
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

- (void)toggleMic:(id)sender {
    [self enqueueCommand:@"toggleMic"];
}

- (void)toggleCam:(id)sender {
    [self enqueueCommand:@"toggleCam"];
}

- (void)toggleHand:(id)sender {
    [self enqueueCommand:@"toggleHand"];
}

- (void)focusMeetTab:(id)sender {
    [self enqueueCommand:@"focusMeetTab"];
}

- (void)sendEmoji:(NSButton *)sender {
    NSString *tag = sender.identifier;
    if (tag) {
        [self enqueueCommand:[NSString stringWithFormat:@"emoji:%@", tag]];
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        MeetBarController *controller = [[MeetBarController alloc] init];
        app.delegate = controller;
        [app run];
    }
    return 0;
}
