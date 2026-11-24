#import <Cocoa/Cocoa.h>
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

@interface MeetBarController : NSObject <NSApplicationDelegate, NSTouchBarDelegate>
@property (strong) NSCustomTouchBarItem *trayItem;
@property (copy) NSString *currentTrayId;
@property (assign) NSInteger trayCounter;

@property (strong) NSTouchBar *meetTouchBar;
@property (strong) NSArray<NSTouchBarItemIdentifier> *mainIdentifiers;
@property (strong) NSArray<NSTouchBarItemIdentifier> *mainIdentifiersWithFocus;
@property (strong) NSArray<NSTouchBarItemIdentifier> *reactionIdentifiers;
@property (strong) NSStatusItem *statusItem;
@property (strong) NSTimer *watchdogTimer;

@property (strong) NSButton *micButton;
@property (strong) NSButton *camButton;
@property (strong) NSButton *handButton;

@property (strong) NSMutableArray<NSString *> *commandQueue;
@property (strong) dispatch_semaphore_t cmdSemaphore;
@property (strong) NSDate *lastMeetPing;
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
    // Точний темніший тон Control Strip (#3B3B3D -> 59/255) та ширина 38pt як у сусідніх кнопок
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
                        if (!self.isTrayVisible) {
                            [self createTrayItem];
                        }
                        if (self.isOnMeetTab != onMeet) {
                            self.isOnMeetTab = onMeet;
                            if (!self.isShowingReactions && self.isBarVisible) {
                                self.meetTouchBar.defaultItemIdentifiers = onMeet ? self.mainIdentifiers : self.mainIdentifiersWithFocus;
                            }
                        }
                        if (!self.isBarVisible && !self.userDismissedManually) {
                            [self showMeetBar];
                        }
                        [self updateButtonsWithMic:micOn cam:camOn hand:handUp];
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
    if (self.isBarVisible) {
        [NSTouchBar dismissSystemModalTouchBar:self.meetTouchBar];
        self.isBarVisible = NO;
        self.isShowingReactions = NO;
        self.meetTouchBar.defaultItemIdentifiers = self.mainIdentifiers;
    }
    if (self.isTrayVisible && self.currentTrayId) {
        DFRElementSetControlStripPresenceForIdentifier(self.currentTrayId, NO);
        self.isTrayVisible = NO;
    }
    self.userDismissedManually = NO;
}

- (void)checkWatchdog {
    if (self.lastMeetPing == nil || [[NSDate date] timeIntervalSinceDate:self.lastMeetPing] > 2.5) {
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
    [menu addItemWithTitle:@"Показати / Сховати панель Meet" action:@selector(toggleMeetBar:) keyEquivalent:@"m"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Вийти з MeetBar" action:@selector(terminate:) keyEquivalent:@"q"];
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
        @"emoji.laugh",
        @"emoji.wow",
        @"emoji.sad",
        @"emoji.think",
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

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    NSButton *btn = nil;

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
        MeetBarController *controller = [[MeetBarController alloc] init];
        app.delegate = controller;
        [app run];
    }
    return 0;
}
