#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

// TA HostProbe 16.36
// Probe-only: NEVER creates/reparents/removes/raises any bubble or view.
// It snapshots CarPlay window/view topology and logs only when the topology changes.

static NSString * const kHBLogPath = @"/var/mobile/VMLHostSniffer.txt";
static NSString *gLastSignature = nil;
static NSUInteger gGeneration = 0;

static BOOL HBIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static void HBLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[TA-PROBE-16.36] %@\n", msg ?: @""];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kHBLogPath];
    if (!fh) {
        [line writeToFile:kHBLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
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

static BOOL HBInterestingClass(NSString *name) {
    if (!name.length) return NO;
    NSArray<NSString *> *needles = @[
        @"Scene", @"Host", @"Presentation", @"LayerHost",
        @"Notification", @"Dashboard", @"Dock", @"Split",
        @"VisualEffect", @"Content", @"Window", @"Bubble"
    ];
    for (NSString *needle in needles) {
        if ([name localizedCaseInsensitiveContainsString:needle]) return YES;
    }
    return NO;
}

static void HBAppendView(UIView *view,
                         NSUInteger depth,
                         NSMutableString *signature,
                         NSMutableString *dump,
                         NSUInteger *count) {
    if (!view || depth > 18 || *count > 500) return;
    (*count)++;

    NSString *name = NSStringFromClass(view.class) ?: @"?";
    CGRect frame = view.frame;
    CGRect bounds = view.bounds;

    // Signature contains every view class + geometry so structural changes trigger a dump.
    [signature appendFormat:@"%@|%.1f,%.1f,%.1f,%.1f|h%d|a%.2f;",
     name, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
     view.hidden, view.alpha];

    BOOL interesting = HBInterestingClass(name) ||
                       frame.size.width >= 300 ||
                       bounds.size.width >= 300;

    if (interesting) {
        NSString *indent = [@"" stringByPaddingToLength:MIN(depth * 2, 36)
                                             withString:@" "
                                        startingAtIndex:0];
        [dump appendFormat:@"%@d%lu %@ frame=%@ bounds=%@ hidden=%d alpha=%.2f z=%.1f sub=%lu\n",
         indent,
         (unsigned long)depth,
         name,
         NSStringFromCGRect(frame),
         NSStringFromCGRect(bounds),
         view.hidden,
         view.alpha,
         view.layer.zPosition,
         (unsigned long)view.subviews.count];
    }

    for (UIView *sub in view.subviews) {
        HBAppendView(sub, depth + 1, signature, dump, count);
    }
}

static void HBSnapshotIfChanged(void) {
    if (!HBIsCarPlayApp()) return;

    NSMutableString *signature = [NSMutableString string];
    NSMutableString *dump = [NSMutableString string];
    NSUInteger sceneCount = 0;
    NSUInteger windowCount = 0;

    NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
    for (UIScene *raw in scenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!HBSceneLooksCarPlay(scene)) continue;

        sceneCount++;
        NSString *role = scene.session.role ?: @"";
        CGSize size = scene.screen.bounds.size;
        [signature appendFormat:@"SCENE:%@:%0.1fx%0.1f;", role, size.width, size.height];
        [dump appendFormat:@"SCENE role=%@ size=%@ activation=%ld windows=%lu\n",
         role,
         NSStringFromCGSize(size),
         (long)scene.activationState,
         (unsigned long)scene.windows.count];

        for (UIWindow *window in scene.windows) {
            windowCount++;
            NSString *wc = NSStringFromClass(window.class) ?: @"?";
            NSString *root = window.rootViewController ?
                (NSStringFromClass(window.rootViewController.class) ?: @"?") : @"nil";

            [signature appendFormat:@"WIN:%@:%0.1f:%d:%0.2f:%@;",
             wc, window.windowLevel, window.hidden, window.alpha,
             NSStringFromCGRect(window.frame)];

            [dump appendFormat:@" WINDOW %@ level=%.1f frame=%@ hidden=%d alpha=%.2f key=%d root=%@\n",
             wc,
             window.windowLevel,
             NSStringFromCGRect(window.frame),
             window.hidden,
             window.alpha,
             window.isKeyWindow,
             root];

            if (window.rootViewController.view) {
                NSUInteger count = 0;
                HBAppendView(window.rootViewController.view, 1, signature, dump, &count);
            }
        }
    }

    // Also record whether known DuoDash/AppBridge clues are present in this process.
    NSArray<NSString *> *classNames = @[
        @"CNABBubbleView",
        @"DBNotificationWindow",
        @"_UIScenePresentationView",
        @"_UISceneLayerHostContainerView"
    ];
    for (NSString *name in classNames) {
        Class c = NSClassFromString(name);
        [signature appendFormat:@"CLASS:%@:%d;", name, c != Nil];
        [dump appendFormat:@" CLASS %@ loaded=%d\n", name, c != Nil];
    }

    if (gLastSignature && [gLastSignature isEqualToString:signature]) return;

    gLastSignature = [signature copy];
    gGeneration++;
    HBLog(@"===== TOPOLOGY CHANGE #%lu scenes=%lu windows=%lu =====\n%@===== END #%lu =====",
          (unsigned long)gGeneration,
          (unsigned long)sceneCount,
          (unsigned long)windowCount,
          dump,
          (unsigned long)gGeneration);
}

static void HBTick(void) {
    HBSnapshotIfChanged();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        HBTick();
    });
}

%ctor {
    @autoreleasepool {
        if (!HBIsCarPlayApp()) return;
        HBLog(@"TA HOST PROBE 16.36 ACTIVE bundle=%@ process=%@ — PROBE ONLY / NO UI MUTATION",
              NSBundle.mainBundle.bundleIdentifier,
              NSProcessInfo.processInfo.processName);
        dispatch_async(dispatch_get_main_queue(), ^{
            HBTick();
        });
    }
}
