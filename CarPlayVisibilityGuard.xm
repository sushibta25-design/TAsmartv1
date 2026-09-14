#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kCPVietMapNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
static int gCPVietMapToken = 0;
static BOOL gCPVietMapActive = NO;

// System-surface policy:
// - Home/App Grid: hidden
// - CarPlay Dashboard (map + Now Playing cards): hidden
// - Any real CarPlay app: visible
// - VietMap Live: hidden regardless
// Track the actual foreground application controller instead of guessing from
// Dashboard view hierarchy. Home <-> Dashboard swipes never set this controller.
static __weak id gCPForegroundAppController = nil;
static BOOL gCPUserAppActive = NO;

static BOOL CPVIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
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

static BOOL CPVShouldHide(void) {
    // If no user app is foreground, CarPlay is on one of its own system surfaces
    // (App Grid/Home or Dashboard). Both must hide the bubble.
    return !gCPUserAppActive || gCPVietMapActive;
}

static void CPVApplyVisibility(void) {
    BOOL hide = CPVShouldHide();
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;
        for (UIWindow *window in scene.windows) {
            if (!window.rootViewController.view) continue;
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window.rootViewController.view];
            while (stack.count) {
                UIView *view = stack.lastObject;
                [stack removeLastObject];
                if (CPVIsBubbleView(view)) {
                    if (hide) {
                        view.hidden = YES;
                        view.layer.hidden = YES;
                        view.alpha = 0.0;
                        view.userInteractionEnabled = NO;
                    } else {
                        view.layer.hidden = NO;
                        view.hidden = NO;
                        view.alpha = 1.0;
                        // Legacy DuoDash mirror is display-only; primary/satellite bubbles remain draggable.
                        view.userInteractionEnabled = (view.tag != 990200);
                    }
                }
                for (UIView *sub in view.subviews) [stack addObject:sub];
            }
        }
    }
}

static void CPVSetUserAppActive(id controller, BOOL active, NSString *reason) {
    if (active) {
        gCPForegroundAppController = controller;
        gCPUserAppActive = YES;
    } else {
        // Ignore a delayed background callback from an older app after another app
        // has already become foreground.
        if (gCPForegroundAppController && controller && controller != gCPForegroundAppController) return;
        gCPForegroundAppController = nil;
        gCPUserAppActive = NO;
    }
    NSLog(@"[CPVIS] userApp=%d vietmap=%d reason=%@ controller=%@",
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

// These are the same Dashboard lifecycle callbacks used by CarPlay itself when
// switching between an application and the system Home/Dashboard surfaces.
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

        // Safe default at CarPlay process startup: system surface => bubble hidden.
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

        dispatch_async(dispatch_get_main_queue(), ^{
            CPVApplyVisibility();
        });
    }
}
