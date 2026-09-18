#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

// CarPlayHostBubbleFix.xm
// TA Platter Bridge 16.37
// Experimental: create ONE small bubble sibling immediately above a remote
// _UIScenePresentationView inside the same Dashboard host hierarchy.
// Never touches DBNotificationWindow and never reparents/removes the V15.9 primary bubble.

static NSString * const HBLogPath = @"/var/mobile/VMLHostSniffer.txt";
static UIView *gPlatterBubble = nil;
static __weak UIView *gPlatterHost = nil;
static NSString *gLastHostDesc = nil;

static BOOL HBIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static void HBLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[TA-PLATTER-16.37] %@\n", msg ?: @""];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:HBLogPath];
    if (!fh) {
        [line writeToFile:HBLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        @try {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } @catch (__unused NSException *e) {}
    }
}

static BOOL HBSceneLooksCarPlay(UIWindowScene *scene) {
    if (!scene) return NO;
    NSString *role = scene.session.role ?: @"";
    if ([role localizedCaseInsensitiveContainsString:@"CarPlay"]) return YES;
    CGSize s = scene.screen.bounds.size;
    return s.width > s.height && s.width >= 300 && s.height <= 500;
}

static BOOL HBIsPresentation(UIView *v) {
    return [NSStringFromClass(v.class) containsString:@"_UIScenePresentationView"];
}

static UIView *HBFindBestPresentation(UIView *root, NSUInteger depth) {
    if (!root || depth > 20 || root.hidden) return nil;
    UIView *best = nil;
    CGFloat bestArea = 0;
    if (HBIsPresentation(root) && root.alpha > 0.01) {
        CGFloat a = CGRectGetWidth(root.bounds) * CGRectGetHeight(root.bounds);
        // Prefer substantial hosted app surfaces, not tiny icons/cards.
        if (a >= 20000) { best = root; bestArea = a; }
    }
    for (UIView *sub in root.subviews) {
        UIView *candidate = HBFindBestPresentation(sub, depth + 1);
        if (candidate) {
            CGFloat a = CGRectGetWidth(candidate.bounds) * CGRectGetHeight(candidate.bounds);
            if (a > bestArea) { best = candidate; bestArea = a; }
        }
    }
    return best;
}

static UIView *HBFindPresentationInCarPlay(void) {
    UIView *best = nil;
    CGFloat bestArea = 0;
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!HBSceneLooksCarPlay(scene)) continue;
        for (UIWindow *w in scene.windows) {
            NSString *wc = NSStringFromClass(w.class) ?: @"";
            if ([wc isEqualToString:@"VMLPassthroughWindow"] || w.hidden || w.alpha <= 0.01) continue;
            UIView *root = w.rootViewController.view;
            if (!root) continue;
            UIView *p = HBFindBestPresentation(root, 0);
            if (p) {
                CGFloat a = CGRectGetWidth(p.bounds) * CGRectGetHeight(p.bounds);
                if (a > bestArea) { best = p; bestArea = a; }
            }
        }
    }
    return best;
}

static UIView *HBMakeTestBubble(void) {
    CGFloat size = 72.0;
    UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    b.backgroundColor = UIColor.whiteColor;
    b.layer.cornerRadius = size / 2.0;
    b.layer.borderWidth = 5.0;
    b.layer.borderColor = UIColor.systemRedColor.CGColor;
    b.userInteractionEnabled = NO;
    b.accessibilityIdentifier = @"TAPlatterBubble16.37";

    UILabel *l = [[UILabel alloc] initWithFrame:b.bounds];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    l.text = @"TA";
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = UIColor.blackColor;
    l.font = [UIFont boldSystemFontOfSize:25];
    l.userInteractionEnabled = NO;
    [b addSubview:l];
    return b;
}

static void HBDetach(void) {
    if (gPlatterBubble) {
        HBLog(@"DETACH host=%@", NSStringFromClass(gPlatterBubble.superview.class));
        [gPlatterBubble removeFromSuperview];
    }
    gPlatterBubble = nil;
    gPlatterHost = nil;
    gLastHostDesc = nil;
}

static void HBTick(void) {
    if (!HBIsCarPlayApp()) return;

    UIView *presentation = HBFindPresentationInCarPlay();
    UIView *host = presentation.superview;

    // Key rule: sibling of _UIScenePresentationView, never child of the remote host container.
    if (!presentation || !host) {
        if (gPlatterBubble) HBDetach();
    } else {
        NSString *desc = [NSString stringWithFormat:@"%@ frame=%@ presentation=%@ pframe=%@",
                          NSStringFromClass(host.class), NSStringFromCGRect(host.bounds),
                          NSStringFromClass(presentation.class), NSStringFromCGRect(presentation.frame)];

        if (!gPlatterBubble || gPlatterHost != host || gPlatterBubble.superview != host) {
            HBDetach();
            gPlatterHost = host;
            gPlatterBubble = HBMakeTestBubble();

            NSUInteger idx = [host.subviews indexOfObject:presentation];
            if (idx != NSNotFound && idx + 1 <= host.subviews.count) {
                [host insertSubview:gPlatterBubble aboveSubview:presentation];
            } else {
                [host addSubview:gPlatterBubble];
            }

            CGFloat W = CGRectGetWidth(host.bounds), H = CGRectGetHeight(host.bounds);
            gPlatterBubble.center = CGPointMake(MAX(42.0, W * 0.18), MAX(42.0, H * 0.50));
            gPlatterBubble.layer.zPosition = 1000000.0;
            gLastHostDesc = desc;
            HBLog(@"ATTACHED SIBLING %@", desc);
        } else {
            if (![gLastHostDesc isEqualToString:desc]) {
                gLastHostDesc = desc;
                HBLog(@"HOST CHANGED %@", desc);
            }
            [host bringSubviewToFront:gPlatterBubble];
            gPlatterBubble.layer.zPosition = 1000000.0;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ HBTick(); });
}

%ctor {
    @autoreleasepool {
        if (!HBIsCarPlayApp()) return;
        HBLog(@"TA PLATTER BRIDGE 16.37 ACTIVE — one TA test bubble / presentation sibling");
        dispatch_async(dispatch_get_main_queue(), ^{ HBTick(); });
    }
}
