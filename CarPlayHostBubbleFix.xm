#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kVietMapNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
static NSString * const kHBLogPath = @"/var/mobile/VMLHostBubbleFix.txt";
static UIView *gHostBubble = nil;
static __weak UIView *gHostCanvas = nil;
static __weak UIWindow *gHostWindow = nil;
static BOOL gHostDragging = NO;
static NSInteger gCurrentSpeed = 0;
static int gVietMapToken = 0;
static BOOL gVietMapActive = NO;
static NSMutableArray<NSNumber *> *gSpeedTokens = nil;
static const NSInteger kHostBubbleTag = 992500;
static const NSInteger kHostLabelTag = 992501;

static BOOL HBIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static void HBLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ | %@\n", [NSDate date], body ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kHBLogPath];
    if (!fh) { [data writeToFile:kHBLogPath atomically:YES]; return; }
    @try { [fh seekToEndOfFile]; [fh writeData:data]; [fh closeFile]; } @catch (__unused NSException *e) {}
}

static BOOL HBSceneLooksCarPlay(UIWindowScene *scene) {
    if (!scene) return NO;
    NSString *role = scene.session.role ?: @"";
    if ([role localizedCaseInsensitiveContainsString:@"CarPlay"]) return YES;
    CGSize s = scene.screen.bounds.size;
    return s.width > s.height && s.width >= 300 && s.height <= 500;
}

static UIView *HBFindHostContainer(UIView *root, NSUInteger depth) {
    if (!root || depth > 18 || root.hidden || root.alpha <= 0.01) return nil;
    NSString *name = NSStringFromClass(root.class) ?: @"";
    if ([name containsString:@"_UISceneLayerHostContainerView"] ||
        [name containsString:@"UISceneLayerHostContainerView"]) return root;
    for (UIView *sub in [root.subviews reverseObjectEnumerator]) {
        UIView *found = HBFindHostContainer(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

static UIWindow *HBFindActiveHostedWindow(UIView **canvasOut) {
    UIWindow *best = nil;
    UIView *bestCanvas = nil;
    CGFloat bestScore = -CGFLOAT_MAX;

    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!HBSceneLooksCarPlay(scene)) continue;

        for (UIWindow *w in scene.windows) {
            if (!w || w.hidden || w.alpha <= 0.01 || !w.rootViewController.view) continue;
            if ([NSStringFromClass(w.class) isEqualToString:@"VMLPassthroughWindow"]) continue;
            if (w.windowLevel < UIWindowLevelAlert) continue;

            UIView *hostContainer = HBFindHostContainer(w.rootViewController.view, 0);
            if (!hostContainer || !hostContainer.superview) continue;

            UIView *canvas = hostContainer.superview;
            CGRect frame = [canvas convertRect:canvas.bounds toView:w];
            CGFloat area = CGRectGetWidth(frame) * CGRectGetHeight(frame);
            CGFloat score = w.windowLevel * 1000000.0 + area;
            if (!best || score > bestScore) {
                best = w;
                bestCanvas = canvas;
                bestScore = score;
            }
        }
    }

    if (canvasOut) *canvasOut = bestCanvas;
    return best;
}

static NSString *HBSpeedText(void) {
    return (gCurrentSpeed > 0 && gCurrentSpeed <= 200) ? [NSString stringWithFormat:@"%ld", (long)gCurrentSpeed] : @"--";
}

static CGPoint HBLoadCenterRatio(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    CGFloat x = [d doubleForKey:@"VMLSpeedBubble.CarPlayPosX"];
    CGFloat y = [d doubleForKey:@"VMLSpeedBubble.CarPlayPosY"];
    if (x <= 0 || x >= 1 || y <= 0 || y >= 1) return CGPointMake(0.12, 0.60);
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
    CGFloat W = MAX(CGRectGetWidth(canvas.bounds), 1.0);
    CGFloat H = MAX(CGRectGetHeight(canvas.bounds), 1.0);
    CGFloat half = size / 2.0;
    CGFloat x = MAX(half + 4, MIN(W - half - 4, r.x * W));
    CGFloat y = MAX(half + 4, MIN(H - half - 4, r.y * H));
    return CGRectMake(x - half, y - half, size, size);
}

@interface VMLHostBubbleDragTarget : NSObject
- (void)pan:(UIPanGestureRecognizer *)pan;
@end
static VMLHostBubbleDragTarget *gDragTarget = nil;

@implementation VMLHostBubbleDragTarget
- (void)pan:(UIPanGestureRecognizer *)pan {
    UIView *bubble = pan.view;
    UIView *canvas = bubble.superview;
    if (!bubble || !canvas) return;

    UIGestureRecognizerState state = pan.state;
    if (state == UIGestureRecognizerStateBegan) {
        gHostDragging = YES;
        HBLog(@"PAN began window=%@ level=%.1f", NSStringFromClass(gHostWindow.class), gHostWindow.windowLevel);
    }
    if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged) {
        CGPoint p = [pan locationInView:canvas];
        CGFloat half = CGRectGetWidth(bubble.bounds) / 2.0;
        CGFloat W = MAX(CGRectGetWidth(canvas.bounds), 1.0);
        CGFloat H = MAX(CGRectGetHeight(canvas.bounds), 1.0);
        p.x = MAX(half + 4, MIN(W - half - 4, p.x));
        p.y = MAX(half + 4, MIN(H - half - 4, p.y));
        [UIView performWithoutAnimation:^{ bubble.center = p; }];
        HBSaveCenterRatio(CGPointMake(p.x / W, p.y / H));
    }
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed) {
        gHostDragging = NO;
        HBLog(@"PAN ended center=%@", NSStringFromCGPoint(bubble.center));
    }
}
@end

static UIView *HBMakeBubble(CGFloat size) {
    UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    b.tag = kHostBubbleTag;
    b.backgroundColor = UIColor.whiteColor;
    b.layer.cornerRadius = size / 2.0;
    b.layer.borderWidth = 5.0;
    b.layer.borderColor = UIColor.systemRedColor.CGColor;
    b.clipsToBounds = YES;
    b.userInteractionEnabled = YES;
    b.multipleTouchEnabled = NO;

    UILabel *label = [[UILabel alloc] initWithFrame:b.bounds];
    label.tag = kHostLabelTag;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.text = HBSpeedText();
    label.textColor = UIColor.blackColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:size * 0.40 weight:UIFontWeightBold];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.5;
    label.userInteractionEnabled = NO;
    [b addSubview:label];

    if (!gDragTarget) gDragTarget = [VMLHostBubbleDragTarget new];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gDragTarget action:@selector(pan:)];
    pan.cancelsTouchesInView = YES;
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    [b addGestureRecognizer:pan];
    return b;
}

static void HBRemoveBubble(NSString *reason) {
    if (gHostBubble) HBLog(@"REMOVE reason=%@", reason ?: @"?");
    [gHostBubble removeFromSuperview];
    gHostBubble = nil;
    gHostCanvas = nil;
    gHostWindow = nil;
}

static void HBReadVietMapState(void) {
    if (!gVietMapToken) return;
    uint64_t state = 0;
    if (notify_get_state(gVietMapToken, &state) == NOTIFY_STATUS_OK) gVietMapActive = state != 0;
}

static void HBStartSpeedReceiver(void) {
    if (gSpeedTokens) return;
    gSpeedTokens = [NSMutableArray arrayWithCapacity:200];
    for (NSInteger speed = 1; speed <= 200; speed++) {
        NSString *name = [NSString stringWithFormat:@"com.sushibta.vmlspeedbubble.speed.%ld", (long)speed];
        int token = 0;
        NSInteger captured = speed;
        uint32_t status = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int incoming) {
            gCurrentSpeed = captured;
            UILabel *label = (UILabel *)[gHostBubble viewWithTag:kHostLabelTag];
            if (label) label.text = HBSpeedText();
        });
        if (status == NOTIFY_STATUS_OK) [gSpeedTokens addObject:@(token)];
    }
    notify_post("com.sushibta.vmlspeedbubble.speed.request");
}

static void HBTick(void) {
    if (!HBIsCarPlayApp()) return;
    HBReadVietMapState();
    if (gVietMapActive) {
        HBRemoveBubble(@"vietmap-active");
    } else {
        UIView *canvas = nil;
        UIWindow *host = HBFindActiveHostedWindow(&canvas);
        if (!host || !canvas) {
            HBRemoveBubble(@"no-elevated-host");
        } else {
            CGFloat size = MAX(84, MIN(112, MAX(CGRectGetHeight(canvas.bounds), 1.0) * 0.40));
            if (host != gHostWindow || canvas != gHostCanvas || !gHostBubble || gHostBubble.superview != canvas) {
                HBRemoveBubble(@"host-changed");
                gHostWindow = host;
                gHostCanvas = canvas;
                gHostBubble = HBMakeBubble(size);
                canvas.userInteractionEnabled = YES;
                [canvas addSubview:gHostBubble];
                HBLog(@"ATTACH window=%@ level=%.1f scene=%@ canvas=%@ frame=%@",
                      NSStringFromClass(host.class), host.windowLevel,
                      host.windowScene.session.persistentIdentifier ?: @"",
                      NSStringFromClass(canvas.class), NSStringFromCGRect(canvas.frame));
            }

            if (!gHostDragging) gHostBubble.frame = HBFrameForCanvas(canvas, size);
            UILabel *label = (UILabel *)[gHostBubble viewWithTag:kHostLabelTag];
            if (label) label.text = HBSpeedText();
            gHostBubble.hidden = NO;
            gHostBubble.alpha = 1.0;
            gHostBubble.layer.hidden = NO;
            gHostBubble.layer.zPosition = CGFLOAT_MAX;
            gHostBubble.userInteractionEnabled = YES;
            [canvas bringSubviewToFront:gHostBubble];
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ HBTick(); });
}

%ctor {
    @autoreleasepool {
        if (!HBIsCarPlayApp()) return;
        [[NSFileManager defaultManager] removeItemAtPath:kHBLogPath error:nil];
        HBLog(@"16.29 surface bubble loaded");
        HBStartSpeedReceiver();

        int token = 0;
        uint32_t s = notify_register_dispatch(kVietMapNotify, &token, dispatch_get_main_queue(), ^(int incoming) {
            gVietMapToken = incoming;
            HBReadVietMapState();
        });
        if (s == NOTIFY_STATUS_OK) {
            gVietMapToken = token;
            HBReadVietMapState();
        }

        dispatch_async(dispatch_get_main_queue(), ^{ HBTick(); });
    }
}
