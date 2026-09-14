#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kCPVietMapNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
static int gCPVietMapToken = 0;
static BOOL gCPVietMapActive = NO;
static BOOL gCPHomeActive = NO;

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
    NSInteger tag = view.tag;
    return tag >= 990199 && tag <= 991500;
}

static BOOL CPVStrongHomeClassName(NSString *name) {
    NSString *n = name.lowercaseString;
    if (!n.length) return NO;
    return [n containsString:@"appgrid"] ||
           [n containsString:@"applicationgrid"] ||
           [n containsString:@"icongrid"] ||
           [n containsString:@"iconlist"] ||
           [n containsString:@"homescreen"] ||
           [n containsString:@"carhome"];
}

static void CPVScanView(UIView *view, NSUInteger depth, BOOL *strongMarker, NSUInteger *iconLikeCount) {
    if (!view || depth > 18 || view.hidden || view.alpha <= 0.01) return;
    NSString *cls = NSStringFromClass(view.class) ?: @"";
    if (CPVStrongHomeClassName(cls)) *strongMarker = YES;
    NSString *lower = cls.lowercaseString;
    if ([lower containsString:@"appicon"] || [lower containsString:@"applicationicon"]) {
        (*iconLikeCount)++;
    }
    for (UIView *sub in view.subviews) CPVScanView(sub, depth + 1, strongMarker, iconLikeCount);
}

static void CPVScanController(UIViewController *vc, NSUInteger depth, BOOL *strongMarker) {
    if (!vc || depth > 12) return;
    NSString *cls = NSStringFromClass(vc.class) ?: @"";
    if (CPVStrongHomeClassName(cls)) *strongMarker = YES;
    for (UIViewController *child in vc.childViewControllers) CPVScanController(child, depth + 1, strongMarker);
    if (vc.presentedViewController) CPVScanController(vc.presentedViewController, depth + 1, strongMarker);
}

static BOOL CPVDetectHome(void) {
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;

        BOOL strong = NO;
        NSUInteger iconCount = 0;
        for (UIWindow *window in scene.windows) {
            if (!window || window.hidden || window.alpha <= 0.01) continue;
            if (window.rootViewController) {
                CPVScanController(window.rootViewController, 0, &strong);
                if (window.rootViewController.view) {
                    CPVScanView(window.rootViewController.view, 0, &strong, &iconCount);
                }
            }
        }
        if (strong || iconCount >= 5) return YES;
    }
    return NO;
}

static BOOL CPVShouldHide(void) {
    return gCPHomeActive || gCPVietMapActive;
}

static void CPVApplyVisibility(void) {
    BOOL hide = CPVShouldHide();
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;
        for (UIWindow *window in scene.windows) {
            NSMutableArray<UIView *> *stack = [NSMutableArray array];
            if (window.rootViewController.view) [stack addObject:window.rootViewController.view];
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
                        if (view.tag != 990200) view.userInteractionEnabled = YES;
                    }
                }
                for (UIView *sub in view.subviews) [stack addObject:sub];
            }
        }
    }
}

static void CPVReadVietMapState(void) {
    if (!gCPVietMapToken) return;
    uint64_t state = 0;
    if (notify_get_state(gCPVietMapToken, &state) == NOTIFY_STATUS_OK) {
        gCPVietMapActive = state != 0;
    }
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

        [NSTimer scheduledTimerWithTimeInterval:0.20 repeats:YES block:^(__unused NSTimer *timer) {
            BOOL home = CPVDetectHome();
            if (home != gCPHomeActive) {
                gCPHomeActive = home;
                NSLog(@"[CPVIS] Home CarPlay=%d VietMap=%d", home, gCPVietMapActive);
            }
            CPVApplyVisibility();
        }];
    }
}
