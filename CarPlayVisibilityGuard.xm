#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kCPVietMapNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
static int gCPVietMapToken = 0;
static BOOL gCPVietMapActive = NO;
static BOOL gCPHomeActive = NO;
static UIView *gCPPinnedMirror = nil;
static __weak UIWindow *gCPPinnedHostWindow = nil;

static const NSInteger kCPPrimaryBubbleTag = 990199;
static const NSInteger kCPLegacyMirrorTag = 990200;
static const NSInteger kCPPinnedMirrorTag = 991499;
static const NSInteger kCPLabelTag = 990100;

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
           [n containsString:@"carhome"] ||
           [n containsString:@"applicationlauncher"] ||
           [n containsString:@"applauncher"];
}

static BOOL CPVIsHostedSceneViewName(NSString *name) {
    NSString *n = name.lowercaseString;
    return [n containsString:@"scenelayerhostcontainerview"] ||
           [n containsString:@"scenehostcontainerview"] ||
           [n containsString:@"hostedscene"];
}

static NSUInteger CPVHostedSceneCount(UIView *view, NSUInteger depth) {
    if (!view || depth > 18 || view.hidden || view.alpha <= 0.01) return 0;
    NSUInteger count = CPVIsHostedSceneViewName(NSStringFromClass(view.class) ?: @"") ? 1 : 0;
    for (UIView *sub in view.subviews) count += CPVHostedSceneCount(sub, depth + 1);
    return count;
}

static void CPVScanHomeEvidence(UIView *view,
                                NSUInteger depth,
                                BOOL *strongMarker,
                                NSUInteger *cellCount,
                                NSUInteger *buttonCount) {
    if (!view || depth > 18 || view.hidden || view.alpha <= 0.01) return;
    NSString *cls = NSStringFromClass(view.class) ?: @"";
    if (CPVStrongHomeClassName(cls)) *strongMarker = YES;

    CGRect r = [view convertRect:view.bounds toView:nil];
    CGFloat area = CGRectGetWidth(r) * CGRectGetHeight(r);
    if ([view isKindOfClass:UICollectionViewCell.class] && area > 900.0) (*cellCount)++;
    if ([view isKindOfClass:UIButton.class] && view.userInteractionEnabled && area > 700.0) (*buttonCount)++;

    NSString *lower = cls.lowercaseString;
    if (([lower containsString:@"appicon"] || [lower containsString:@"applicationicon"]) && area > 500.0) {
        (*cellCount)++;
    }

    for (UIView *sub in view.subviews) {
        CPVScanHomeEvidence(sub, depth + 1, strongMarker, cellCount, buttonCount);
    }
}

static void CPVScanController(UIViewController *vc, NSUInteger depth, BOOL *strongMarker) {
    if (!vc || depth > 12) return;
    NSString *cls = NSStringFromClass(vc.class) ?: @"";
    if (CPVStrongHomeClassName(cls)) *strongMarker = YES;
    for (UIViewController *child in vc.childViewControllers) CPVScanController(child, depth + 1, strongMarker);
    if (vc.presentedViewController) CPVScanController(vc.presentedViewController, depth + 1, strongMarker);
}

static BOOL CPVWindowContainsBubble(UIWindow *window) {
    if (!window.rootViewController.view) return NO;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window.rootViewController.view];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (CPVIsBubbleView(v)) return YES;
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return NO;
}

static UIWindow *CPVBestElevatedHostedWindow(UIWindowScene *scene, NSUInteger *hostCountOut) {
    UIWindow *best = nil;
    NSUInteger bestCount = 0;
    CGFloat bestLevel = -CGFLOAT_MAX;
    for (UIWindow *window in scene.windows) {
        if (!window || window.hidden || window.alpha <= 0.01 || !window.rootViewController.view) continue;
        if (CPVWindowContainsBubble(window)) continue;
        NSUInteger count = CPVHostedSceneCount(window.rootViewController.view, 0);
        if (count < 2) continue;
        if (window.windowLevel < UIWindowLevelAlert) continue;
        if (!best || window.windowLevel > bestLevel ||
            (fabs(window.windowLevel - bestLevel) < 0.5 && count > bestCount)) {
            best = window;
            bestLevel = window.windowLevel;
            bestCount = count;
        }
    }
    if (hostCountOut) *hostCountOut = bestCount;
    return best;
}

static UIView *CPVFindViewWithTag(NSInteger tag) {
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;
        for (UIWindow *window in scene.windows) {
            if (!window.rootViewController.view) continue;
            UIView *found = [window.rootViewController.view viewWithTag:tag];
            if (found) return found;
        }
    }
    return nil;
}

static BOOL CPVDetectHome(void) {
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;

        NSUInteger elevatedHosted = 0;
        UIWindow *elevatedHost = CPVBestElevatedHostedWindow(scene, &elevatedHosted);
        if (elevatedHost && elevatedHosted >= 2) {
            NSLog(@"[CPVIS] active hosted app level=%.1f surfaces=%lu => home=0",
                  elevatedHost.windowLevel, (unsigned long)elevatedHosted);
            return NO;
        }

        BOOL strong = NO;
        NSUInteger cells = 0;
        NSUInteger buttons = 0;
        for (UIWindow *window in scene.windows) {
            if (!window || window.hidden || window.alpha <= 0.01) continue;
            if (CPVWindowContainsBubble(window)) continue;
            if (!window.rootViewController) continue;
            CPVScanController(window.rootViewController, 0, &strong);
            if (window.rootViewController.view) {
                CPVScanHomeEvidence(window.rootViewController.view, 0, &strong, &cells, &buttons);
            }
        }

        // CarPlay Home is the only state in this setup with no elevated hosted-app
        // window and a launcher-like collection of app cells/buttons. A strong
        // class-name marker is enough only when the elevated app host is absent.
        BOOL launcherEvidence = strong || cells >= 4 || buttons >= 6;
        BOOL home = launcherEvidence;
        NSLog(@"[CPVIS] detect strong=%d cells=%lu buttons=%lu elevated=0 => home=%d",
              strong, (unsigned long)cells, (unsigned long)buttons, home);
        if (home) return YES;
    }
    return NO;
}

static BOOL CPVShouldHide(void) {
    return gCPHomeActive || gCPVietMapActive;
}

static void CPVRemovePinnedMirror(void) {
    if (gCPPinnedMirror) [gCPPinnedMirror removeFromSuperview];
    gCPPinnedMirror = nil;
    gCPPinnedHostWindow = nil;
}

static void CPVSyncPinnedMirror(void) {
    if (CPVShouldHide()) {
        CPVRemovePinnedMirror();
        return;
    }

    UIView *primary = CPVFindViewWithTag(kCPPrimaryBubbleTag);
    if (!primary || !primary.window || primary.hidden || primary.alpha <= 0.01) {
        CPVRemovePinnedMirror();
        return;
    }

    UIWindowScene *scene = primary.window.windowScene;
    if (!scene || !CPVSceneLooksCarPlay(scene)) {
        CPVRemovePinnedMirror();
        return;
    }

    NSUInteger hostCount = 0;
    UIWindow *host = CPVBestElevatedHostedWindow(scene, &hostCount);
    UIView *canvas = host.rootViewController.view;
    if (!host || !canvas || hostCount < 2) {
        CPVRemovePinnedMirror();
        return;
    }

    if (!gCPPinnedMirror || gCPPinnedHostWindow != host || gCPPinnedMirror.superview != canvas) {
        CPVRemovePinnedMirror();
        UIView *mirror = [[UIView alloc] initWithFrame:primary.bounds];
        mirror.tag = kCPPinnedMirrorTag;
        mirror.userInteractionEnabled = NO;
        mirror.backgroundColor = primary.backgroundColor ?: UIColor.whiteColor;
        mirror.clipsToBounds = YES;
        mirror.layer.borderWidth = primary.layer.borderWidth;
        mirror.layer.borderColor = primary.layer.borderColor;
        mirror.layer.cornerRadius = CGRectGetWidth(primary.bounds) / 2.0;

        UILabel *label = [[UILabel alloc] initWithFrame:mirror.bounds];
        label.tag = kCPLabelTag;
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = UIColor.blackColor;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.5;
        label.font = [UIFont systemFontOfSize:MAX(12.0, CGRectGetWidth(mirror.bounds) * 0.40)
                                         weight:UIFontWeightBold];
        [mirror addSubview:label];
        [canvas addSubview:mirror];
        gCPPinnedMirror = mirror;
        gCPPinnedHostWindow = host;
        NSLog(@"[CPVIS] pinned mirror attached level=%.1f surfaces=%lu",
              host.windowLevel, (unsigned long)hostCount);
    }

    UILabel *sourceLabel = (UILabel *)[primary viewWithTag:kCPLabelTag];
    UILabel *mirrorLabel = (UILabel *)[gCPPinnedMirror viewWithTag:kCPLabelTag];
    if (mirrorLabel) mirrorLabel.text = sourceLabel.text ?: @"--";

    CGRect sceneFrame = [primary.superview convertRect:primary.frame toCoordinateSpace:scene.coordinateSpace];
    CGRect localFrame = [canvas convertRect:sceneFrame fromCoordinateSpace:scene.coordinateSpace];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gCPPinnedMirror.frame = localFrame;
    gCPPinnedMirror.layer.cornerRadius = CGRectGetWidth(localFrame) / 2.0;
    gCPPinnedMirror.hidden = NO;
    gCPPinnedMirror.alpha = 1.0;
    gCPPinnedMirror.layer.hidden = NO;
    gCPPinnedMirror.layer.opacity = 1.0;
    gCPPinnedMirror.layer.zPosition = CGFLOAT_MAX;
    [CATransaction commit];
    [canvas bringSubviewToFront:gCPPinnedMirror];
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
                    if (view.tag == kCPLegacyMirrorTag) {
                        // The old mirror jumps between the Dashboard level -1 host
                        // and DuoPhone's elevated host. Keep it disabled; the pinned
                        // mirror below is attached only to the elevated hosted-app window.
                        view.hidden = YES;
                        view.layer.hidden = YES;
                        view.alpha = 0.0;
                        view.userInteractionEnabled = NO;
                    } else if (hide) {
                        view.hidden = YES;
                        view.layer.hidden = YES;
                        view.alpha = 0.0;
                        view.userInteractionEnabled = NO;
                    } else {
                        view.layer.hidden = NO;
                        view.hidden = NO;
                        view.alpha = 1.0;
                        if (view.tag != kCPPinnedMirrorTag) view.userInteractionEnabled = YES;
                    }
                }
                for (UIView *sub in view.subviews) [stack addObject:sub];
            }
        }
    }
    CPVSyncPinnedMirror();
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
    if (CPVIsCarPlayApp() && self.tag == kCPLegacyMirrorTag && !hidden) {
        %orig(YES);
        return;
    }
    if (CPVIsCarPlayApp() && CPVShouldHide() && CPVIsBubbleView(self) && !hidden) {
        %orig(YES);
        return;
    }
    %orig(hidden);
}
- (void)setAlpha:(CGFloat)alpha {
    if (CPVIsCarPlayApp() && self.tag == kCPLegacyMirrorTag && alpha > 0.01) {
        %orig(0.0);
        return;
    }
    if (CPVIsCarPlayApp() && CPVShouldHide() && CPVIsBubbleView(self) && alpha > 0.01) {
        %orig(0.0);
        return;
    }
    %orig(alpha);
}
%end

%hook CALayer
- (void)setHidden:(BOOL)hidden {
    if (CPVIsCarPlayApp() && !hidden) {
        id delegate = self.delegate;
        if ([delegate isKindOfClass:UIView.class]) {
            UIView *view = (UIView *)delegate;
            if (view.tag == kCPLegacyMirrorTag || (CPVShouldHide() && CPVIsBubbleView(view))) {
                %orig(YES);
                return;
            }
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
