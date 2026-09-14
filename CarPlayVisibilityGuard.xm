#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kCPVietMapNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
static NSString * const kCPVLogPath = @"/var/mobile/VMLVisibility.txt";
static int gCPVietMapToken = 0;
static BOOL gCPVietMapActive = NO;
static __weak id gCPForegroundAppController = nil;
static BOOL gCPUserAppActive = NO;

static BOOL CPVIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static void CPVLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ | %@\n", [NSDate date], body ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kCPVLogPath];
    if (!fh) { [data writeToFile:kCPVLogPath atomically:YES]; return; }
    @try { [fh seekToEndOfFile]; [fh writeData:data]; [fh closeFile]; }
    @catch (__unused NSException *e) {}
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

static BOOL CPVIsPrimaryBubbleWindow(UIWindow *window) {
    if (!window) return NO;
    NSString *cls = NSStringFromClass(window.class) ?: @"";
    return [cls isEqualToString:@"VMLPassthroughWindow"];
}

static BOOL CPVShouldHide(void) {
    // Home/App Grid and Dashboard are system surfaces: no real user app is foreground.
    // VietMap Live is a special hard-hide case even when it is foreground.
    return !gCPUserAppActive || gCPVietMapActive;
}

static void CPVApplyBubbleViewState(UIView *view, BOOL hide) {
    if (!view) return;
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
    }
}

static void CPVApplyVisibility(void) {
    BOOL hide = CPVShouldHide();
    NSUInteger overlayWindows = 0, bubbleViews = 0;

    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;

        for (UIWindow *window in scene.windows) {
            if (!window) continue;

            // Critical fix: the primary bubble lives in its own VMLPassthroughWindow.
            // Earlier builds only hid the tagged bubble UIView. If that window was
            // created AFTER the one-shot visibility pass, it became visible again.
            // Hide/show the whole bubble window as well, then keep enforcing it.
            if (CPVIsPrimaryBubbleWindow(window)) {
                overlayWindows++;
                window.userInteractionEnabled = !hide;
                if (hide) {
                    window.hidden = YES;
                    window.alpha = 0.0;
                    window.layer.hidden = YES;
                } else {
                    window.layer.hidden = NO;
                    window.alpha = 1.0;
                    window.hidden = NO;
                }
            }

            UIView *root = window.rootViewController.view;
            if (!root) continue;
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
            while (stack.count) {
                UIView *view = stack.lastObject;
                [stack removeLastObject];
                if (CPVIsBubbleView(view)) {
                    bubbleViews++;
                    CPVApplyBubbleViewState(view, hide);
                }
                for (UIView *sub in view.subviews) [stack addObject:sub];
            }
        }
    }

    static BOOL lastHide = NO;
    static BOOL initialized = NO;
    if (!initialized || lastHide != hide) {
        initialized = YES; lastHide = hide;
        CPVLog(@"APPLY hide=%d userApp=%d vietmap=%d overlayWindows=%lu bubbleViews=%lu",
               hide, gCPUserAppActive, gCPVietMapActive,
               (unsigned long)overlayWindows, (unsigned long)bubbleViews);
    }
}

static void CPVSetUserAppActive(id controller, BOOL active, NSString *reason) {
    if (active) {
        gCPForegroundAppController = controller;
        gCPUserAppActive = YES;
    } else {
        if (gCPForegroundAppController && controller && controller != gCPForegroundAppController) return;
        gCPForegroundAppController = nil;
        gCPUserAppActive = NO;
    }
    CPVLog(@"STATE userApp=%d vietmap=%d reason=%@ controller=%@",
           gCPUserAppActive, gCPVietMapActive, reason ?: @"?", controller);
    CPVApplyVisibility();
}

static void CPVReadVietMapState(void) {
    if (!gCPVietMapToken) return;
    uint64_t state = 0;
    if (notify_get_state(gCPVietMapToken, &state) == NOTIFY_STATUS_OK) {
        gCPVietMapActive = state != 0;
    }
}

%hook DBApplicationSceneViewController

- (void)foregroundSceneWithSettings:(id)settings completion:(id)completion {
    CPVSetUserAppActive(self, YES, @"foregroundScene");
    %orig;
}

- (id)presentationViewWithIdentifier:(id)identifier {
    if ([identifier isKindOfClass:NSString.class] &&
        [identifier isEqualToString:@"kCARAppToHomeAnimationIdentifier"]) {
        CPVSetUserAppActive(self, NO, @"appToHome");
    }
    return %orig;
}

- (void)backgroundSceneWithCompletion:(id)completion {
    CPVSetUserAppActive(self, NO, @"backgroundScene");
    %orig;
}

%end

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

%hook UIWindow
- (void)setHidden:(BOOL)hidden {
    if (CPVIsCarPlayApp() && CPVShouldHide() && CPVIsPrimaryBubbleWindow(self) && !hidden) {
        %orig(YES);
        return;
    }
    %orig(hidden);
}
- (void)setAlpha:(CGFloat)alpha {
    if (CPVIsCarPlayApp() && CPVShouldHide() && CPVIsPrimaryBubbleWindow(self) && alpha > 0.01) {
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
        if ([delegate isKindOfClass:UIWindow.class] && CPVIsPrimaryBubbleWindow((UIWindow *)delegate)) {
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
        CPVLog(@"16.27 visibility guard loaded");

        gCPForegroundAppController = nil;
        gCPUserAppActive = NO;

        int token = 0;
        uint32_t s = notify_register_dispatch(kCPVietMapNotify, &token, dispatch_get_main_queue(), ^(int incoming) {
            gCPVietMapToken = incoming;
            CPVReadVietMapState();
            CPVApplyVisibility();
        });
        if (s == NOTIFY_STATUS_OK) {
            gCPVietMapToken = token;
            CPVReadVietMapState();
        }

        // Lightweight enforcement only: no hierarchy/class probe. This catches the
        // bubble overlay when it is created after the guard's ctor and prevents the
        // V15.9 promoter from making it visible again on Home/Dashboard.
        [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer *timer) {
            CPVApplyVisibility();
        }];
        dispatch_async(dispatch_get_main_queue(), ^{ CPVApplyVisibility(); });
    }
}
