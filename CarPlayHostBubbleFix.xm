#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

// CarPlayHostBubbleFix.xm
// TA Context Test 16.42
// Uses the constructor proven by 16.40: +[CAContext localContextWithOptions:].
// Creates ONE independent CAContext-backed TA test surface. Original V15.9 bubble untouched.

static NSString * const HBLogPath = @"/var/mobile/VMLHostSniffer.txt";
static id gCtx = nil;
static CALayer *gRoot = nil;
static CALayer *gHost = nil;
static __weak UIWindow *gWindow = nil;
static BOOL gDisabled = NO;

static BOOL HBIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}
static void HBLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[TA-CONTEXT-16.42] %@\n", msg ?: @""];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:HBLogPath];
    if (!fh) [line writeToFile:HBLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; } @catch (__unused NSException *e) {}
}
static BOOL HBSceneLooksCarPlay(UIWindowScene *s) {
    if (!s) return NO;
    NSString *role = s.session.role ?: @"";
    if ([role localizedCaseInsensitiveContainsString:@"CarPlay"]) return YES;
    CGSize z=s.screen.bounds.size; return z.width>z.height && z.width>=300 && z.height<=500;
}
static UIWindow *HBWindow(void) {
    UIWindow *best=nil;
    CGFloat bestScore=-CGFLOAT_MAX;
    for (UIScene *raw in UIApplication.sharedApplication.connectedScenes) {
        if (![raw isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *s=(UIWindowScene *)raw; if (!HBSceneLooksCarPlay(s)) continue;
        CGSize screen=s.screen.bounds.size;
        for (UIWindow *w in s.windows) {
            if (w.hidden || w.alpha<=0.01) continue;
            NSString *n=NSStringFromClass(w.class) ?: @"";
            if ([n isEqualToString:@"VMLPassthroughWindow"]) continue;
            if ([n containsString:@"StatusBar"] || [n containsString:@"Notification"] ||
                [n containsString:@"Alert"] || [n containsString:@"Keyboard"]) continue;

            CGSize z=w.bounds.size;
            CGFloat area=z.width*z.height;
            CGFloat screenArea=screen.width*screen.height;
            BOOL full=(fabs(z.width-screen.width)<2.0 && fabs(z.height-screen.height)<2.0);
            CGFloat score=(full?1000000.0:0.0)+area-fabs(w.windowLevel)*1000.0;
            HBLog(@"WINDOW CANDIDATE %@ level=%.1f bounds=%@ full=%d score=%.1f",
                  n,w.windowLevel,NSStringFromCGRect(w.bounds),full,score);
            if (score>bestScore) { bestScore=score; best=w; }
        }
    }
    if (best) HBLog(@"WINDOW SELECTED %@ level=%.1f bounds=%@",
                    NSStringFromClass(best.class),best.windowLevel,NSStringFromCGRect(best.bounds));
    return best;
}
static void HBCleanup(void) {
    @try { [gHost removeFromSuperlayer]; } @catch (__unused NSException *e) {}
    if (gCtx) @try {
        SEL inv=NSSelectorFromString(@"invalidate");
        if ([gCtx respondsToSelector:inv]) ((void(*)(id,SEL))objc_msgSend)(gCtx,inv);
    } @catch (__unused NSException *e) {}
    gHost=nil; gRoot=nil; gCtx=nil; gWindow=nil;
}
static BOOL HBCreate(UIWindow *w) {
    if (!w || gDisabled) return NO;
    Class C=NSClassFromString(@"CAContext"), H=NSClassFromString(@"CALayerHost");
    SEL make=NSSelectorFromString(@"localContextWithOptions:");
    if (!C || !H || ![C respondsToSelector:make]) {
        HBLog(@"UNAVAILABLE C=%@ H=%@ localContextWithOptions=%d",C,H,[C respondsToSelector:make]);
        gDisabled=YES; return NO;
    }
    @try {
        id ctx=((id(*)(id,SEL,id))objc_msgSend)(C,make,@{});
        if (!ctx) { HBLog(@"FAILED localContextWithOptions returned nil"); gDisabled=YES; return NO; }

        CALayer *root=[CALayer layer]; root.frame=CGRectMake(0,0,82,82);
        CAShapeLayer *circle=[CAShapeLayer layer]; circle.frame=root.bounds;
        circle.path=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(root.bounds,5,5)].CGPath;
        circle.fillColor=UIColor.whiteColor.CGColor; circle.strokeColor=UIColor.systemRedColor.CGColor; circle.lineWidth=6;
        [root addSublayer:circle];
        CATextLayer *txt=[CATextLayer layer]; txt.frame=CGRectMake(0,23,82,36); txt.string=@"TA";
        txt.alignmentMode=kCAAlignmentCenter; txt.fontSize=24; txt.foregroundColor=UIColor.blackColor.CGColor;
        txt.contentsScale=UIScreen.mainScreen.scale; [root addSublayer:txt];

        ((void(*)(id,SEL,id))objc_msgSend)(ctx,NSSelectorFromString(@"setLayer:"),root);
        unsigned int cid=((unsigned int(*)(id,SEL))objc_msgSend)(ctx,NSSelectorFromString(@"contextId"));
        if (!cid) { HBLog(@"FAILED contextId=0"); gDisabled=YES; return NO; }

        CALayer *host=[H layer];
        ((void(*)(id,SEL,unsigned int))objc_msgSend)(host,NSSelectorFromString(@"setContextId:"),cid);
        if ([host respondsToSelector:NSSelectorFromString(@"setResizesHostedContext:")])
            ((void(*)(id,SEL,BOOL))objc_msgSend)(host,NSSelectorFromString(@"setResizesHostedContext:"),NO);
        host.frame=CGRectMake(MAX(8.0,CGRectGetWidth(w.bounds)-92.0),18,82,82);
        host.zPosition=1000000.0;
        [w.layer addSublayer:host];

        gCtx=ctx; gRoot=root; gHost=host; gWindow=w;
        HBLog(@"CREATED local CAContext id=%u valid=%@ host=%@ window=%@ level=%.1f frame=%@",
              cid, [ctx valueForKey:@"valid"], NSStringFromClass(host.class), NSStringFromClass(w.class),
              w.windowLevel, NSStringFromCGRect(host.frame));
        return YES;
    } @catch (NSException *e) {
        HBLog(@"EXCEPTION %@ reason=%@",e.name,e.reason); HBCleanup(); gDisabled=YES; return NO;
    }
}
static void HBTick(void) {
    UIWindow *w=HBWindow();
    if (!w) { if(gHost){HBLog(@"DETACH no CarPlay window");HBCleanup();} }
    else if (!gHost || gWindow!=w || !gHost.superlayer) { HBCleanup(); HBCreate(w); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{HBTick();});
}
%ctor {
    @autoreleasepool {
        if (!HBIsCarPlayApp()) return;
        HBLog(@"TA CONTEXT TEST 16.42 ACTIVE — localContextWithOptions");
        dispatch_async(dispatch_get_main_queue(),^{HBTick();});
    }
}
