#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

// CarPlayHostBubbleFix.xm
// TA Context Test 16.39
// Experimental CAContext-backed test surface. Does NOT touch/reparent V15.9 bubble.
// Dynamically uses private CAContext/CALayerHost APIs so unsupported selectors fail closed.

static NSString * const HBLogPath = @"/var/mobile/VMLHostSniffer.txt";
static id gTAContext = nil;
static CALayer *gTARootLayer = nil;
static CALayer *gTAHostLayer = nil;
static __weak UIWindow *gTAWindow = nil;
static BOOL gTADisabled = NO;

static BOOL HBIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}
static void HBLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[TA-CONTEXT-16.39] %@\n", msg ?: @""];
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
static UIWindow *HBFindBaseCarPlayWindow(void) {
    UIWindow *best = nil;
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!HBSceneLooksCarPlay(scene)) continue;
        for (UIWindow *w in scene.windows) {
            if (w.hidden || w.alpha <= 0.01) continue;
            NSString *cn = NSStringFromClass(w.class) ?: @"";
            if ([cn isEqualToString:@"VMLPassthroughWindow"]) continue;
            if (!best || w.windowLevel > best.windowLevel) best = w;
        }
    }
    return best;
}
static NSNumber *HBSafeNumber(id obj, NSString *key) {
    @try {
        id v = [obj valueForKey:key];
        return [v isKindOfClass:NSNumber.class] ? v : nil;
    } @catch (__unused NSException *e) { return nil; }
}
static void HBCleanup(void) {
    @try { [gTAHostLayer removeFromSuperlayer]; } @catch (__unused NSException *e) {}
    gTAHostLayer = nil;
    gTARootLayer = nil;
    gTAContext = nil;
    gTAWindow = nil;
}
static BOOL HBCreateContextTest(UIWindow *window) {
    if (!window || gTADisabled) return NO;
    Class CAContextClass = NSClassFromString(@"CAContext");
    Class CALayerHostClass = NSClassFromString(@"CALayerHost");
    if (!CAContextClass || !CALayerHostClass) {
        HBLog(@"UNAVAILABLE CAContext=%@ CALayerHost=%@", CAContextClass, CALayerHostClass);
        gTADisabled = YES;
        return NO;
    }

    @try {
        id ctx = nil;
        SEL contextWithOptions = NSSelectorFromString(@"contextWithOptions:");
        SEL contextWithId = NSSelectorFromString(@"contextWithId:");
        if ([CAContextClass respondsToSelector:contextWithOptions]) {
            ctx = ((id(*)(id,SEL,id))objc_msgSend)(CAContextClass, contextWithOptions, @{});
        } else if ([CAContextClass respondsToSelector:contextWithId]) {
            ctx = ((id(*)(id,SEL,unsigned int))objc_msgSend)(CAContextClass, contextWithId, 0);
        }
        if (!ctx) {
            HBLog(@"FAILED create CAContext (no supported constructor)");
            gTADisabled = YES;
            return NO;
        }

        CALayer *root = [CALayer layer];
        root.frame = CGRectMake(0, 0, 80, 80);
        root.backgroundColor = UIColor.clearColor.CGColor;

        CAShapeLayer *circle = [CAShapeLayer layer];
        circle.frame = root.bounds;
        circle.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(root.bounds, 5, 5)].CGPath;
        circle.fillColor = UIColor.whiteColor.CGColor;
        circle.strokeColor = UIColor.systemRedColor.CGColor;
        circle.lineWidth = 6.0;
        [root addSublayer:circle];

        CATextLayer *text = [CATextLayer layer];
        text.frame = CGRectMake(0, 22, 80, 36);
        text.string = @"TA";
        text.alignmentMode = kCAAlignmentCenter;
        text.fontSize = 24;
        text.foregroundColor = UIColor.blackColor.CGColor;
        text.contentsScale = UIScreen.mainScreen.scale;
        [root addSublayer:text];

        BOOL setLayer = NO;
        SEL setLayerSel = NSSelectorFromString(@"setLayer:");
        if ([ctx respondsToSelector:setLayerSel]) {
            ((void(*)(id,SEL,id))objc_msgSend)(ctx, setLayerSel, root);
            setLayer = YES;
        } else {
            @try { [ctx setValue:root forKey:@"layer"]; setLayer = YES; }
            @catch (__unused NSException *e) {}
        }
        if (!setLayer) {
            HBLog(@"FAILED CAContext setLayer");
            gTADisabled = YES;
            return NO;
        }

        NSNumber *cid = HBSafeNumber(ctx, @"contextId");
        if (!cid) cid = HBSafeNumber(ctx, @"contextID");
        if (!cid) {
            HBLog(@"FAILED read created contextId");
            gTADisabled = YES;
            return NO;
        }

        CALayer *host = [CALayerHostClass layer];
        SEL setContextId = NSSelectorFromString(@"setContextId:");
        SEL setContextID = NSSelectorFromString(@"setContextID:");
        if ([host respondsToSelector:setContextId]) {
            ((void(*)(id,SEL,unsigned int))objc_msgSend)(host, setContextId, cid.unsignedIntValue);
        } else if ([host respondsToSelector:setContextID]) {
            ((void(*)(id,SEL,unsigned int))objc_msgSend)(host, setContextID, cid.unsignedIntValue);
        } else {
            @try { [host setValue:cid forKey:@"contextId"]; }
            @catch (__unused NSException *e) {
                HBLog(@"FAILED CALayerHost setContextId=%@", cid);
                gTADisabled = YES;
                return NO;
            }
        }

        host.frame = CGRectMake(330, 18, 80, 80);
        host.zPosition = 1000000.0;

        // Put our CALayerHost at the CarPlay window layer level, not inside a remote host.
        [window.layer addSublayer:host];

        gTAContext = ctx;
        gTARootLayer = root;
        gTAHostLayer = host;
        gTAWindow = window;
        HBLog(@"CREATED own CAContext id=%@ host=%@ window=%@ level=%.1f frame=%@",
              cid, NSStringFromClass(host.class), NSStringFromClass(window.class),
              window.windowLevel, NSStringFromCGRect(host.frame));
        return YES;
    } @catch (NSException *e) {
        HBLog(@"EXCEPTION %@ reason=%@ — disabling test", e.name, e.reason);
        HBCleanup();
        gTADisabled = YES;
        return NO;
    }
}
static void HBTick(void) {
    if (!HBIsCarPlayApp()) return;
    UIWindow *w = HBFindBaseCarPlayWindow();

    if (!w) {
        if (gTAHostLayer) { HBLog(@"DETACH no CarPlay window"); HBCleanup(); }
    } else if (!gTAHostLayer || gTAWindow != w || gTAHostLayer.superlayer != w.layer) {
        HBCleanup();
        HBCreateContextTest(w);
    } else {
        // Keep only our host layer ordered last inside the chosen local window.
        @try {
            [gTAHostLayer removeFromSuperlayer];
            [w.layer addSublayer:gTAHostLayer];
        } @catch (__unused NSException *e) {}
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ HBTick(); });
}
%ctor {
    @autoreleasepool {
        if (!HBIsCarPlayApp()) return;
        HBLog(@"TA CONTEXT TEST 16.39 ACTIVE — experimental own CAContext / original bubble untouched");
        dispatch_async(dispatch_get_main_queue(), ^{ HBTick(); });
    }
}
