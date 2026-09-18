#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// CarPlayHostBubbleFix.xm
// TA Layer Probe 16.38
// READ-ONLY probe. No bubble, no mirror, no addSubview, no layer mutation.
// Captures the layer/superlayer chain around _UIContextLayerHostView and
// its _UISceneLayerHostContainerView / _UIScenePresentationView ancestors.

static NSString * const HBLogPath = @"/var/mobile/VMLHostSniffer.txt";
static NSString *gLastSignature = nil;

static BOOL HBIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static void HBLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[TA-LAYER-16.38] %@\n", msg ?: @""];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:HBLogPath];
    if (!fh) {
        [line writeToFile:HBLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    @try {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (__unused NSException *e) {}
}

static BOOL HBSceneLooksCarPlay(UIWindowScene *scene) {
    if (!scene) return NO;
    NSString *role = scene.session.role ?: @"";
    if ([role localizedCaseInsensitiveContainsString:@"CarPlay"]) return YES;
    CGSize s = scene.screen.bounds.size;
    return s.width > s.height && s.width >= 300 && s.height <= 500;
}

static NSString *HBSafeValue(id obj, NSString *key) {
    if (!obj || !key.length) return @"nil";
    @try {
        id value = [obj valueForKey:key];
        if (!value) return @"nil";
        NSString *s = [value description];
        if (s.length > 180) s = [s substringToIndex:180];
        return s ?: @"?";
    } @catch (__unused NSException *e) {
        return @"<unavailable>";
    }
}

static NSString *HBInterestingRuntimeValues(id obj) {
    if (!obj) return @"";
    NSArray<NSString *> *keys = @[
        @"contextId", @"contextID", @"context",
        @"hostContextIdentifier", @"layerContext",
        @"windowServerHitTestContextID",
        @"presentationContext", @"sceneIdentifier"
    ];
    NSMutableString *s = [NSMutableString string];
    for (NSString *key in keys) {
        NSString *v = HBSafeValue(obj, key);
        if (![v isEqualToString:@"<unavailable>"]) {
            [s appendFormat:@" %@=%@", key, v];
        }
    }
    return s;
}

static NSString *HBLayerLine(CALayer *layer, NSUInteger depth) {
    if (!layer) return @"";
    NSString *indent = [@"" stringByPaddingToLength:MIN(depth * 2, 24)
                                         withString:@" "
                                    startingAtIndex:0];
    return [NSString stringWithFormat:
            @"%@L%lu %@ frame=%@ bounds=%@ z=%.1f hidden=%d opacity=%.2f sublayers=%lu%@\n",
            indent,
            (unsigned long)depth,
            NSStringFromClass(layer.class),
            NSStringFromCGRect(layer.frame),
            NSStringFromCGRect(layer.bounds),
            layer.zPosition,
            layer.hidden,
            layer.opacity,
            (unsigned long)layer.sublayers.count,
            HBInterestingRuntimeValues(layer)];
}

static void HBAppendLayerChain(CALayer *layer, NSMutableString *dump) {
    [dump appendString:@"  LAYER CHAIN (host -> superlayers)\n"];
    CALayer *cur = layer;
    for (NSUInteger i = 0; cur && i < 14; i++, cur = cur.superlayer) {
        [dump appendString:HBLayerLine(cur, i)];
    }
}

static void HBAppendSiblingLayers(CALayer *layer, NSMutableString *dump) {
    CALayer *parent = layer.superlayer;
    if (!parent) return;
    [dump appendFormat:@"  SIBLING LAYERS parent=%@ count=%lu\n",
     NSStringFromClass(parent.class), (unsigned long)parent.sublayers.count];

    NSUInteger idx = [parent.sublayers indexOfObject:layer];
    NSInteger start = MAX(0, (NSInteger)idx - 4);
    NSInteger end = MIN((NSInteger)parent.sublayers.count - 1, (NSInteger)idx + 4);
    for (NSInteger i = start; i <= end; i++) {
        CALayer *sib = parent.sublayers[(NSUInteger)i];
        [dump appendFormat:@"   [%ld]%@ %@ frame=%@ z=%.1f hidden=%d opacity=%.2f%@\n",
         (long)i,
         sib == layer ? @" *HOST*" : @"",
         NSStringFromClass(sib.class),
         NSStringFromCGRect(sib.frame),
         sib.zPosition,
         sib.hidden,
         sib.opacity,
         HBInterestingRuntimeValues(sib)];
    }
}

static void HBAppendViewAncestors(UIView *view, NSMutableString *dump) {
    [dump appendString:@"  VIEW CHAIN (context host -> ancestors)\n"];
    UIView *cur = view;
    for (NSUInteger i = 0; cur && i < 14; i++, cur = cur.superview) {
        [dump appendFormat:@"   V%lu %@ frame=%@ bounds=%@ hidden=%d alpha=%.2f layer=%@%@\n",
         (unsigned long)i,
         NSStringFromClass(cur.class),
         NSStringFromCGRect(cur.frame),
         NSStringFromCGRect(cur.bounds),
         cur.hidden,
         cur.alpha,
         NSStringFromClass(cur.layer.class),
         HBInterestingRuntimeValues(cur)];
    }
}

static void HBCollectContextHosts(UIView *root, NSMutableArray<UIView *> *out, NSUInteger depth) {
    if (!root || depth > 22) return;
    NSString *name = NSStringFromClass(root.class) ?: @"";
    if ([name containsString:@"_UIContextLayerHostView"]) {
        [out addObject:root];
    }
    for (UIView *sub in root.subviews) {
        HBCollectContextHosts(sub, out, depth + 1);
    }
}

static void HBSnapshot(void) {
    if (!HBIsCarPlayApp()) return;

    NSMutableArray<UIView *> *hosts = [NSMutableArray array];

    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!HBSceneLooksCarPlay(scene)) continue;

        for (UIWindow *w in scene.windows) {
            if (w.hidden || w.alpha <= 0.01) continue;
            NSString *wc = NSStringFromClass(w.class) ?: @"";
            if ([wc isEqualToString:@"VMLPassthroughWindow"]) continue;
            UIView *root = w.rootViewController.view;
            if (root) HBCollectContextHosts(root, hosts, 0);
        }
    }

    NSMutableString *signature = [NSMutableString string];
    NSMutableString *dump = [NSMutableString string];

    [signature appendFormat:@"count=%lu;", (unsigned long)hosts.count];
    [dump appendFormat:@"===== CONTEXT SNAPSHOT hosts=%lu =====\n", (unsigned long)hosts.count];

    NSUInteger n = 0;
    for (UIView *host in hosts) {
        n++;
        CGRect screenRect = CGRectZero;
        @try { screenRect = [host convertRect:host.bounds toView:nil]; } @catch (__unused NSException *e) {}

        [signature appendFormat:@"%@:%@:%@:%d:%.2f;",
         NSStringFromClass(host.class),
         NSStringFromCGRect(host.frame),
         NSStringFromCGRect(screenRect),
         host.hidden,
         host.alpha];

        [dump appendFormat:@"HOST #%lu %@ frame=%@ screen=%@ hidden=%d alpha=%.2f%@\n",
         (unsigned long)n,
         NSStringFromClass(host.class),
         NSStringFromCGRect(host.frame),
         NSStringFromCGRect(screenRect),
         host.hidden,
         host.alpha,
         HBInterestingRuntimeValues(host)];

        HBAppendViewAncestors(host, dump);
        HBAppendLayerChain(host.layer, dump);
        HBAppendSiblingLayers(host.layer, dump);
    }

    [dump appendString:@"===== END CONTEXT SNAPSHOT ====="];

    if (gLastSignature && [gLastSignature isEqualToString:signature]) return;
    gLastSignature = [signature copy];
    HBLog(@"%@", dump);
}

static void HBTick(void) {
    HBSnapshot();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 700 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        HBTick();
    });
}

%ctor {
    @autoreleasepool {
        if (!HBIsCarPlayApp()) return;
        HBLog(@"TA LAYER PROBE 16.38 ACTIVE — READ ONLY / NO UI OR LAYER MUTATION");
        dispatch_async(dispatch_get_main_queue(), ^{
            HBTick();
        });
    }
}
