#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

static UIView *gHostBubble = nil;
static __weak UIWindow *gHostWindow = nil;
static UIPanGestureRecognizer *gHostPan = nil;
static BOOL gHostDragging = NO;
static const NSInteger kHostBubbleTag = 991498;
static const NSInteger kHostLabelTag = 991497;

static BOOL HBIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static BOOL HBSceneLooksCarPlay(UIWindowScene *scene) {
    if (!scene) return NO;
    NSString *role = scene.session.role ?: @"";
    if ([role localizedCaseInsensitiveContainsString:@"CarPlay"]) return YES;
    CGSize s = scene.screen.bounds.size;
    return s.width > s.height && s.width >= 300 && s.height <= 500;
}

static NSUInteger HBHostedSceneCount(UIView *view, NSUInteger depth) {
    if (!view || depth > 18 || view.hidden || view.alpha <= 0.01) return 0;
    NSString *name = NSStringFromClass(view.class) ?: @"";
    NSUInteger count = ([name containsString:@"_UISceneLayerHostContainerView"] ||
                        [name containsString:@"UISceneLayerHostContainerView"]) ? 1 : 0;
    for (UIView *sub in view.subviews) count += HBHostedSceneCount(sub, depth + 1);
    return count;
}

static UIWindow *HBFindElevatedHostedWindow(void) {
    UIWindow *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!HBSceneLooksCarPlay(scene)) continue;
        CGRect sceneBounds = scene.coordinateSpace.bounds;
        for (UIWindow *w in scene.windows) {
            if (!w || w.hidden || w.alpha <= 0.01 || !w.rootViewController.view) continue;
            if ([NSStringFromClass(w.class) isEqualToString:@"VMLPassthroughWindow"]) continue;
            NSUInteger hosted = HBHostedSceneCount(w.rootViewController.view, 0);
            if (hosted < 2) continue;
            // Ignore the stock Dashboard host at level -1. DuoPhone/Main CarPlay
            // lives in an elevated hosted window (~2070-2300 on this setup).
            if (w.windowLevel < UIWindowLevelAlert) continue;
            CGRect f = w.frame;
            BOOL usableGeometry = CGRectGetWidth(f) > CGRectGetWidth(sceneBounds) * 0.55 &&
                                  CGRectGetHeight(f) > CGRectGetHeight(sceneBounds) * 0.55;
            CGFloat score = w.windowLevel * 1000.0 + hosted * 100.0 + (usableGeometry ? 50.0 : 0.0);
            if (!best || score > bestScore) { best = w; bestScore = score; }
        }
    }
    return best;
}

static NSString *HBCurrentSpeedText(void) {
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!HBSceneLooksCarPlay(scene)) continue;
        for (UIWindow *w in scene.windows) {
            UIView *root = w.rootViewController.view;
            if (!root) continue;
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
            while (stack.count) {
                UIView *v = stack.lastObject; [stack removeLastObject];
                if (v == gHostBubble) continue;
                if (v.tag >= 990199 && v.tag <= 991500 && v.tag != kHostBubbleTag) {
                    for (UIView *sub in v.subviews) {
                        if ([sub isKindOfClass:UILabel.class]) {
                            NSString *t = ((UILabel *)sub).text ?: @"";
                            if (t.length && ([t isEqualToString:@"--"] || t.integerValue > 0)) return t;
                        }
                    }
                }
                for (UIView *sub in v.subviews) [stack addObject:sub];
            }
        }
    }
    return @"--";
}

static CGPoint HBLoadCenterRatio(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    CGFloat x = [d doubleForKey:@"VMLSpeedBubble.CarPlayPosX"];
    CGFloat y = [d doubleForKey:@"VMLSpeedBubble.CarPlayPosY"];
    if (x <= 0 || x >= 1 || y <= 0 || y >= 1) return CGPointMake(0.08, 0.60);
    return CGPointMake(x, y);
}

static void HBSaveCenterRatio(CGPoint p) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setDouble:p.x forKey:@"VMLSpeedBubble.CarPlayPosX"];
    [d setDouble:p.y forKey:@"VMLSpeedBubble.CarPlayPosY"];
    [d synchronize];
}

static CGRect HBFrameForCanvas(UIView *canvas, CGFloat size) {
    CGPoint r = HBLoadCenterRatio();
    CGFloat W = MAX(CGRectGetWidth(canvas.bounds), 1), H = MAX(CGRectGetHeight(canvas.bounds), 1), half = size/2.0;
    CGFloat x = MAX(half+4, MIN(W-half-4, r.x*W));
    CGFloat y = MAX(half+4, MIN(H-half-4, r.y*H));
    return CGRectMake(x-half, y-half, size, size);
}

@interface VMLHostBubbleDragTarget : NSObject
- (void)pan:(UIPanGestureRecognizer *)pan;
@end
static VMLHostBubbleDragTarget *gHostDragTarget = nil;

@implementation VMLHostBubbleDragTarget
- (void)pan:(UIPanGestureRecognizer *)pan {
    UIView *bubble = pan.view;
    UIView *canvas = bubble.superview;
    if (!bubble || !canvas) return;
    UIGestureRecognizerState s = pan.state;
    if (s == UIGestureRecognizerStateBegan) gHostDragging = YES;
    if (s == UIGestureRecognizerStateBegan || s == UIGestureRecognizerStateChanged) {
        CGPoint p = [pan locationInView:canvas];
        CGFloat half = CGRectGetWidth(bubble.bounds)/2.0;
        CGFloat W = MAX(CGRectGetWidth(canvas.bounds),1), H = MAX(CGRectGetHeight(canvas.bounds),1);
        p.x = MAX(half+4, MIN(W-half-4, p.x));
        p.y = MAX(half+4, MIN(H-half-4, p.y));
        [UIView performWithoutAnimation:^{ bubble.center = p; }];
        HBSaveCenterRatio(CGPointMake(p.x/W, p.y/H));
    }
    if (s == UIGestureRecognizerStateEnded || s == UIGestureRecognizerStateCancelled || s == UIGestureRecognizerStateFailed)
        gHostDragging = NO;
}
@end

static UIView *HBMakeBubble(CGFloat size) {
    UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0,0,size,size)];
    b.tag = kHostBubbleTag;
    b.backgroundColor = UIColor.whiteColor;
    b.layer.cornerRadius = size/2.0;
    b.layer.borderWidth = 5.0;
    b.layer.borderColor = UIColor.systemRedColor.CGColor;
    b.clipsToBounds = YES;
    b.userInteractionEnabled = YES;
    UILabel *label = [[UILabel alloc] initWithFrame:b.bounds];
    label.tag = kHostLabelTag;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.text = HBCurrentSpeedText();
    label.textColor = UIColor.blackColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:size*0.40 weight:UIFontWeightBold];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.5;
    [b addSubview:label];
    if (!gHostDragTarget) gHostDragTarget = [VMLHostBubbleDragTarget new];
    gHostPan = [[UIPanGestureRecognizer alloc] initWithTarget:gHostDragTarget action:@selector(pan:)];
    gHostPan.cancelsTouchesInView = YES;
    gHostPan.minimumNumberOfTouches = 1;
    gHostPan.maximumNumberOfTouches = 1;
    [b addGestureRecognizer:gHostPan];
    return b;
}

static void HBRemove(void) {
    [gHostBubble removeFromSuperview];
    gHostBubble = nil;
    gHostWindow = nil;
    gHostPan = nil;
}

static void HBTick(void) {
    if (!HBIsCarPlayApp()) return;
    UIWindow *host = HBFindElevatedHostedWindow();
    UIView *canvas = host.rootViewController.view;
    if (!host || !canvas) {
        HBRemove();
    } else {
        CGFloat size = MAX(84, MIN(112, MAX(CGRectGetHeight(canvas.bounds),1)*0.40));
        if (host != gHostWindow || !gHostBubble || gHostBubble.superview != canvas) {
            HBRemove();
            gHostBubble = HBMakeBubble(size);
            gHostWindow = host;
            [canvas addSubview:gHostBubble];
            NSLog(@"[VMLHOSTFIX] attached host=%@ level=%.1f scene=%@", NSStringFromClass(host.class), host.windowLevel, host.windowScene.session.persistentIdentifier ?: @"");
        }
        if (!gHostDragging) gHostBubble.frame = HBFrameForCanvas(canvas, size);
        UILabel *label = (UILabel *)[gHostBubble viewWithTag:kHostLabelTag];
        label.text = HBCurrentSpeedText();
        gHostBubble.hidden = NO;
        gHostBubble.alpha = 1.0;
        gHostBubble.layer.hidden = NO;
        gHostBubble.layer.zPosition = CGFLOAT_MAX;
        gHostBubble.userInteractionEnabled = YES;
        [canvas bringSubviewToFront:gHostBubble];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ HBTick(); });
}

%ctor {
    @autoreleasepool {
        if (!HBIsCarPlayApp()) return;
        dispatch_async(dispatch_get_main_queue(), ^{ HBTick(); });
    }
}
