#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kCPVietMapNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
static NSString * const kCPVProbePath = @"/var/mobile/VMLCarPlayHomeState.txt";
static int gCPVietMapToken = 0;
static BOOL gCPVietMapActive = NO;
static NSString *gCPVLastSignature = nil;

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

static void CPVWrite(NSString *line) {
    if (!line.length) return;
    NSString *text = [NSString stringWithFormat:@"%@ | %@\n", [NSDate date], line];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:kCPVProbePath]) { [data writeToFile:kCPVProbePath atomically:YES]; return; }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kCPVProbePath];
    if (!fh) return;
    @try { [fh seekToEndOfFile]; [fh writeData:data]; [fh closeFile]; } @catch (__unused NSException *e) {}
}

static void CPVCollectClasses(UIView *view, NSUInteger depth, NSMutableArray<NSString *> *out) {
    if (!view || depth > 8 || view.hidden || view.alpha <= 0.01) return;
    NSString *cls = NSStringFromClass(view.class) ?: @"";
    CGRect r = [view convertRect:view.bounds toView:nil];
    if ([cls localizedCaseInsensitiveContainsString:@"Scene"] ||
        [cls localizedCaseInsensitiveContainsString:@"Host"] ||
        [cls localizedCaseInsensitiveContainsString:@"Grid"] ||
        [cls localizedCaseInsensitiveContainsString:@"Icon"] ||
        [cls localizedCaseInsensitiveContainsString:@"Dashboard"] ||
        [cls localizedCaseInsensitiveContainsString:@"Dock"] ||
        [cls localizedCaseInsensitiveContainsString:@"Application"] ||
        [cls localizedCaseInsensitiveContainsString:@"Launcher"]) {
        NSString *indent = [@"" stringByPaddingToLength:depth withString:@" " startingAtIndex:0];
        [out addObject:[NSString stringWithFormat:@"%@%@ frame=%@", indent, cls, NSStringFromCGRect(r)]];
    }
    for (UIView *sub in view.subviews) CPVCollectClasses(sub, depth + 1, out);
}

static NSString *CPVBuildSignatureAndDump(BOOL writeFull) {
    NSMutableArray<NSString *> *sig = [NSMutableArray array];
    NSMutableArray<NSString *> *detail = [NSMutableArray array];
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;
        NSString *pid = scene.session.persistentIdentifier ?: @"";
        [sig addObject:[NSString stringWithFormat:@"SCENE:%@:%ld:%lu", pid, (long)scene.activationState, (unsigned long)scene.windows.count]];
        [detail addObject:[NSString stringWithFormat:@"SCENE pid=%@ role=%@ state=%ld bounds=%@ windows=%lu", pid, scene.session.role ?: @"", (long)scene.activationState, NSStringFromCGRect(scene.coordinateSpace.bounds), (unsigned long)scene.windows.count]];
        NSInteger wi = 0;
        for (UIWindow *w in scene.windows) {
            if (!w || w.hidden || w.alpha <= 0.01) { wi++; continue; }
            NSString *root = w.rootViewController ? NSStringFromClass(w.rootViewController.class) : @"nil";
            [sig addObject:[NSString stringWithFormat:@"W:%ld:%@:%0.1f:%@", (long)wi, NSStringFromClass(w.class), w.windowLevel, root]];
            [detail addObject:[NSString stringWithFormat:@" WINDOW[%ld] class=%@ level=%.1f key=%d frame=%@ root=%@", (long)wi, NSStringFromClass(w.class), w.windowLevel, w.isKeyWindow, NSStringFromCGRect(w.frame), root]];
            NSMutableArray<NSString *> *classes = [NSMutableArray array];
            if (w.rootViewController.view) CPVCollectClasses(w.rootViewController.view, 0, classes);
            for (NSString *s in classes) [detail addObject:[@"  " stringByAppendingString:s]];
            wi++;
        }
    }
    NSString *signature = [sig componentsJoinedByString:@"|"];
    if (writeFull) {
        CPVWrite(@"========== STATE CHANGE ==========");
        for (NSString *line in detail) CPVWrite(line);
        CPVWrite(@"==================================");
    }
    return signature;
}

static void CPVApplyVietMapVisibility(void) {
    if (!gCPVietMapActive) return;
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        if (!CPVSceneLooksCarPlay(scene)) continue;
        for (UIWindow *window in scene.windows) {
            NSMutableArray<UIView *> *stack = [NSMutableArray array];
            if (window.rootViewController.view) [stack addObject:window.rootViewController.view];
            while (stack.count) {
                UIView *view = stack.lastObject; [stack removeLastObject];
                if (CPVIsBubbleView(view)) {
                    view.hidden = YES; view.layer.hidden = YES; view.alpha = 0.0; view.userInteractionEnabled = NO;
                }
                for (UIView *sub in view.subviews) [stack addObject:sub];
            }
        }
    }
}

static void CPVReadVietMapState(void) {
    if (!gCPVietMapToken) return;
    uint64_t state = 0;
    if (notify_get_state(gCPVietMapToken, &state) == NOTIFY_STATUS_OK) gCPVietMapActive = state != 0;
}

%hook UIView
- (void)setHidden:(BOOL)hidden {
    if (CPVIsCarPlayApp() && gCPVietMapActive && CPVIsBubbleView(self) && !hidden) { %orig(YES); return; }
    %orig(hidden);
}
- (void)setAlpha:(CGFloat)alpha {
    if (CPVIsCarPlayApp() && gCPVietMapActive && CPVIsBubbleView(self) && alpha > 0.01) { %orig(0.0); return; }
    %orig(alpha);
}
%end

%ctor {
    @autoreleasepool {
        if (!CPVIsCarPlayApp()) return;
        [[NSFileManager defaultManager] removeItemAtPath:kCPVProbePath error:nil];
        CPVWrite(@"16.24 CarPlay Home state probe loaded; Home hiding temporarily disabled");
        int token = 0;
        uint32_t s = notify_register_dispatch(kCPVietMapNotify, &token, dispatch_get_main_queue(), ^(int incoming) {
            gCPVietMapToken = incoming; CPVReadVietMapState(); CPVApplyVietMapVisibility();
        });
        if (s == NOTIFY_STATUS_OK) { gCPVietMapToken = token; CPVReadVietMapState(); }
        [NSTimer scheduledTimerWithTimeInterval:0.50 repeats:YES block:^(__unused NSTimer *timer) {
            NSString *signature = CPVBuildSignatureAndDump(NO);
            if (!gCPVLastSignature || ![signature isEqualToString:gCPVLastSignature]) {
                gCPVLastSignature = [signature copy];
                CPVBuildSignatureAndDump(YES);
            }
            if (gCPVietMapActive) CPVApplyVietMapVisibility();
        }];
    }
}
