#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kVMLSceneNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
static int gVMLFixToken = 0;
static BOOL gVMLHardHide = NO;
static NSUInteger gVMLHideGeneration = 0;

static BOOL VMLFixIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static BOOL VMLFixIsBubbleView(UIView *view) {
    if (!view) return NO;
    NSInteger tag = view.tag;
    return (tag >= 990199 && tag <= 991000);
}

static void VMLFixApplyHardHide(void) {
    if (!gVMLHardHide) return;
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)raw;
        for (UIWindow *window in scene.windows) {
            NSMutableArray<UIView *> *stack = [NSMutableArray array];
            if (window.rootViewController.view) [stack addObject:window.rootViewController.view];
            while (stack.count) {
                UIView *view = stack.lastObject;
                [stack removeLastObject];
                if (VMLFixIsBubbleView(view)) {
                    view.hidden = YES;
                    view.layer.hidden = YES;
                    view.alpha = 0.0;
                }
                for (UIView *sub in view.subviews) [stack addObject:sub];
            }
        }
    }
}

static void VMLFixReadState(void) {
    if (!gVMLFixToken) return;
    uint64_t state = 0;
    if (notify_get_state(gVMLFixToken, &state) != NOTIFY_STATUS_OK) return;
    NSUInteger generation = ++gVMLHideGeneration;
    if (state != 0) {
        gVMLHardHide = YES;
        VMLFixApplyHardHide();
        return;
    }

    // Debounce OFF so transient CarPlay scene transitions inside VietMap Live
    // cannot briefly reveal the bubble. Only release after a stable false state.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != gVMLHideGeneration) return;
        uint64_t confirm = 1;
        if (notify_get_state(gVMLFixToken, &confirm) != NOTIFY_STATUS_OK) return;
        if (confirm == 0) gVMLHardHide = NO;
    });
}

%hook UIView
- (void)setHidden:(BOOL)hidden {
    if (VMLFixIsCarPlayApp() && gVMLHardHide && VMLFixIsBubbleView(self) && !hidden) {
        %orig(YES);
        return;
    }
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    if (VMLFixIsCarPlayApp() && gVMLHardHide && VMLFixIsBubbleView(self) && alpha > 0.01) {
        %orig(0.0);
        return;
    }
    %orig(alpha);
}
%end

%hook CALayer
- (void)setHidden:(BOOL)hidden {
    if (VMLFixIsCarPlayApp() && gVMLHardHide && !hidden) {
        id delegate = self.delegate;
        if ([delegate isKindOfClass:UIView.class] && VMLFixIsBubbleView((UIView *)delegate)) {
            %orig(YES);
            return;
        }
    }
    %orig(hidden);
}
%end

%ctor {
    @autoreleasepool {
        if (!VMLFixIsCarPlayApp()) return;
        int token = 0;
        uint32_t status = notify_register_dispatch(kVMLSceneNotify, &token,
            dispatch_get_main_queue(), ^(int incoming) {
                gVMLFixToken = incoming;
                VMLFixReadState();
                if (gVMLHardHide) VMLFixApplyHardHide();
            });
        if (status == NOTIFY_STATUS_OK) {
            gVMLFixToken = token;
            VMLFixReadState();
        }

        [NSTimer scheduledTimerWithTimeInterval:0.20 repeats:YES block:^(__unused NSTimer *timer) {
            if (gVMLHardHide) VMLFixApplyHardHide();
        }];
    }
}
