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

            // Exact state observed on this CarPlay setup:
            // Home/App Grid exposes DBIconScrollView + DBIconListView with no hosted app scene.
            return iconScroll && iconList && hosted == 0;
        }
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

        // Lightweight check only. No full-tree logging/probe on the main thread.
        [NSTimer scheduledTimerWithTimeInterval:0.40 repeats:YES block:^(__unused NSTimer *timer) {
            BOOL home = CPVDetectHome();
            if (home != gCPHomeActive) gCPHomeActive = home;
            CPVApplyVisibility();
        }];
    }
}
