#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kYTNotify = "com.sushibta.vmlspeedbubble.youtubeactive";
static int gYTToken = 0;
static BOOL gYTLast = NO;

static BOOL YTIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static BOOL YTHasActiveScene(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) return YES;
    }
    return app.applicationState == UIApplicationStateActive;
}

static void YTSetState(BOOL active) {
    if (!YTIsYouTube()) return;
    if (!gYTToken) {
        int token = 0;
        if (notify_register_check(kYTNotify, &token) != NOTIFY_STATUS_OK) return;
        gYTToken = token;
    }
    if (gYTLast == active) return;
    gYTLast = active;
    notify_set_state(gYTToken, active ? 1 : 0);
    notify_post(kYTNotify);
}

static void YTRefresh(void) {
    YTSetState(YTHasActiveScene());
}

%ctor {
    @autoreleasepool {
        if (!YTIsYouTube()) return;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){ YTSetState(YES); }];
        [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ YTRefresh(); }); }];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ YTRefresh(); }); }];
        if (@available(iOS 13.0, *)) {
            [nc addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){ YTSetState(YES); }];
            [nc addObserverForName:UISceneWillDeactivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ YTRefresh(); }); }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            YTRefresh();
            [NSTimer scheduledTimerWithTimeInterval:0.75 repeats:YES block:^(__unused NSTimer *timer){ YTRefresh(); }];
        });
    }
}
