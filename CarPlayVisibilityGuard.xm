#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kCPVietMapNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
static const char *kCPYouTubeNotify = "com.sushibta.vmlspeedbubble.youtubeactive";
static NSString * const kCPVLogPath = @"/var/mobile/VMLVisibilityGuard.txt";

static int gCPVietMapToken = 0;
static int gCPYouTubeToken = 0;
static BOOL gCPVietMapActive = NO;
static BOOL gCPYouTubeActive = NO;
static BOOL gCPHomeActive = NO;
static BOOL gLastLoggedHome = NO;
static BOOL gLastLoggedVML = NO;
static BOOL gLastLoggedYT = NO;
static BOOL gHaveLoggedState = NO;

static BOOL CPVIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static void CPVLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ | %@\n", [NSDate date], msg ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:kCPVLogPath]) { [data writeToFile:kCPVLogPath atomically:YES]; return; }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kCPVLogPath];
    if (!fh) return;
    @try { [fh seekToEndOfFile]; [fh writeData:data]; [fh closeFile]; } @catch (__unused NSException *e) {}
}

static BOOL CPVSceneLooksCarPlay(UIWindowScene *scene) {
    if (!scene) return NO;
    NSString *role = scene.session.role ?: @"";
    if ([role localizedCaseInsensitiveContainsString:@"CarPlay"]) return YES;
    CGSize s = scene.screen.bounds.size;
    return s.width > s.height && s.width >= 300 && s.height <= 500;
}

static BOOL CPVIsBubbleView(UIView *view) {
    if (!view) return NO;
    return view.tag >= 990199 && view.tag <= 991500;
}

static BOOL CPVViewTreeHasClass(UIView *root, NSString *wanted, NSUInteger depth) {
    if (!root || depth > 12 || root.hidden || root.alpha <= 0.01) return NO;
    if ([NSStringFromClass(root.class) isEqualToString:wanted]) {
        CGRect r = [root convertRect:root.bounds toView:nil];
        if (CGRectGetWidth(r) > 20.0 && CGRectGetHeight(r) > 20.0) return YES;
    }
    for (UIView *sub in root.subviews) {
        if (CPVViewTreeHasClass(sub, wanted, depth + 1)) return YES;
    }
    return NO;
}

static NSUInteger CPVHostedSceneCount(UIView *root, NSUInteger depth) {
    if (!root || depth > 12 || root.hidden || root.alpha <= 0.01) return 0;
    NSString *name = NSStringFromClass(root.class) ?: @"";
    NSUInteger count = ([name containsString:@"_UISceneLayerHostContainerView"] ||
                        [name containsString:@"UISceneLayerHostContainerView"] ||
                        [name localizedCaseInsensitiveContainsString:@"HostedScene"]) ? 1 : 0;
    for (UIView *sub in root.subviews) count += CPVHostedSceneCount(sub, depth + 1);
    return count;
}

static BOOL CPVDetectHome(void) {
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;
        NSString *pid = scene.session.persistentIdentifier ?: @"";
        if (![pid containsString:@"DBDashboard-Car"] && ![pid containsString:@"DBDashboard"]) continue;

        for (UIWindow *window in scene.windows) {
            if (!window || window.hidden || window.alpha <= 0.01 || !window.rootViewController.view) continue;
            NSString *rootClass = NSStringFromClass(window.rootViewController.class) ?: @"";
            if (![rootClass isEqualToString:@"DBDashboardRootViewController"]) continue;

            UIView *root = window.rootViewController.view;
            BOOL iconScroll = CPVViewTreeHasClass(root, @"DBIconScrollView", 0);
            BOOL iconList = CPVViewTreeHasClass(root, @"DBIconListView", 0);
            NSUInteger hosted = CPVHostedSceneCount(root, 0);

            // Exact Home/App Grid state from the previously successful build.
            // Dashboard still has hosted scene surfaces, so it remains visible there.
            return iconScroll && iconList && hosted == 0;
        }
    }
    return NO;
}

static BOOL CPVShouldHide(void) {
    // Home always hides. VietMap keeps the previously proven hide behavior.
    // YouTube intentionally does NOT hide; it forces the opposite path below.
    return gCPHomeActive || gCPVietMapActive;
}

static NSUInteger CPVApplyVisibility(void) {
    BOOL hide = CPVShouldHide();
    NSUInteger bubbleCount = 0;

    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;

        CGFloat highestOther = UIWindowLevelNormal;
        for (UIWindow *w in scene.windows) {
            if (!w || w.hidden || w.alpha <= 0.01) continue;
            if (![NSStringFromClass(w.class) isEqualToString:@"VMLPassthroughWindow"]) highestOther = MAX(highestOther, w.windowLevel);
        }

        for (UIWindow *window in scene.windows) {
            if (!window.rootViewController.view) continue;
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window.rootViewController.view];
            while (stack.count) {
                UIView *view = stack.lastObject;
                [stack removeLastObject];
                if (CPVIsBubbleView(view)) {
                    bubbleCount++;
                    if (hide) {
                        view.hidden = YES;
                        view.layer.hidden = YES;
                        view.alpha = 0.0;
                        view.userInteractionEnabled = NO;
                    } else {
                        view.layer.hidden = NO;
                        view.hidden = NO;
                        view.alpha = 1.0;
                        view.userInteractionEnabled = (view.tag != 990200);
                        [view.superview bringSubviewToFront:view];

                        // Reverse of VietMap hide: while YouTube is active, keep the
                        // existing VML overlay window alive and promoted. No new bubble
                        // or hosted-surface mirror is created here.
                        if (gCPYouTubeActive && [NSStringFromClass(window.class) isEqualToString:@"VMLPassthroughWindow"]) {
                            window.hidden = NO;
                            window.alpha = 1.0;
                            if (window.windowLevel <= highestOther) window.windowLevel = highestOther + 100.0;
                        }
                    }
                }
                for (UIView *sub in view.subviews) [stack addObject:sub];
            }
        }
    }
    return bubbleCount;
}

static void CPVReadVietMapState(void) {
    if (!gCPVietMapToken) return;
    uint64_t state = 0;
    if (notify_get_state(gCPVietMapToken, &state) == NOTIFY_STATUS_OK) gCPVietMapActive = state != 0;
}

static void CPVReadYouTubeState(void) {
    if (!gCPYouTubeToken) return;
    uint64_t state = 0;
    if (notify_get_state(gCPYouTubeToken, &state) == NOTIFY_STATUS_OK) gCPYouTubeActive = state != 0;
}

%hook UIView
- (void)setHidden:(BOOL)hidden {
    if (CPVIsCarPlayApp() && CPVShouldHide() && CPVIsBubbleView(self) && !hidden) {
        %orig(YES);
        return;
    }
    %orig(hidden);
}
- (void)setAlpha:(CGFloat)alpha {
    if (CPVIsCarPlayApp() && CPVShouldHide() && CPVIsBubbleView(self) && alpha > 0.01) {
        %orig(0.0);
        return;
    }
    %orig(alpha);
}
%end

%hook CALayer
- (void)setHidden:(BOOL)hidden {
    if (CPVIsCarPlayApp() && CPVShouldHide() && !hidden) {
        id delegate = self.delegate;
        if ([delegate isKindOfClass:UIView.class] && CPVIsBubbleView((UIView *)delegate)) {
            %orig(YES);
            return;
        }
    }
    %orig(hidden);
}
%end

%ctor {
    @autoreleasepool {
        if (!CPVIsCarPlayApp()) return;
        [[NSFileManager defaultManager] removeItemAtPath:kCPVLogPath error:nil];
        CPVLog(@"16.31 guard loaded: Home hide + Dashboard show + YouTube force-show");

        int vmlToken = 0;
        uint32_t vmlStatus = notify_register_dispatch(kCPVietMapNotify, &vmlToken, dispatch_get_main_queue(), ^(int incoming) {
            gCPVietMapToken = incoming;
            CPVReadVietMapState();
            CPVApplyVisibility();
        });
        if (vmlStatus == NOTIFY_STATUS_OK) { gCPVietMapToken = vmlToken; CPVReadVietMapState(); }

        int ytToken = 0;
        uint32_t ytStatus = notify_register_dispatch(kCPYouTubeNotify, &ytToken, dispatch_get_main_queue(), ^(int incoming) {
            gCPYouTubeToken = incoming;
            CPVReadYouTubeState();
            CPVApplyVisibility();
        });
        if (ytStatus == NOTIFY_STATUS_OK) { gCPYouTubeToken = ytToken; CPVReadYouTubeState(); }

        [NSTimer scheduledTimerWithTimeInterval:0.40 repeats:YES block:^(__unused NSTimer *timer) {
            gCPHomeActive = CPVDetectHome();
            CPVReadVietMapState();
            CPVReadYouTubeState();
            NSUInteger count = CPVApplyVisibility();
            if (!gHaveLoggedState || gLastLoggedHome != gCPHomeActive || gLastLoggedVML != gCPVietMapActive || gLastLoggedYT != gCPYouTubeActive) {
                gHaveLoggedState = YES;
                gLastLoggedHome = gCPHomeActive;
                gLastLoggedVML = gCPVietMapActive;
                gLastLoggedYT = gCPYouTubeActive;
                CPVLog(@"STATE home=%d vml=%d youtube=%d bubbles=%lu hide=%d", gCPHomeActive, gCPVietMapActive, gCPYouTubeActive, (unsigned long)count, CPVShouldHide());
            }
        }];
    }
}
