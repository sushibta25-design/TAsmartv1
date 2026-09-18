#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

// TA HostBridge 16.35: keep the primary V15.9 bubble untouched.
// This file creates only a satellite inside the CarPlay-owned notification/content
// host that survives DuoDash/AppBridge presentation changes.  Never reparents the
// primary bubble and never tears down the primary overlay.
static const char *kVietMapNotify = "com.sushibta.vmlspeedbubble.vmlcarplaysceneactive";
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

static BOOL HBIsCarPlayApp(void) { return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"]; }
static void HBLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt); NSString *msg=[[NSString alloc] initWithFormat:fmt arguments:args]; va_end(args);
    NSString *line=[NSString stringWithFormat:@"[TA-HOST-16.35] %@\n", msg ?: @""];
    NSString *path=@"/var/mobile/VMLHostSniffer.txt"; NSFileHandle *fh=[NSFileHandle fileHandleForWritingAtPath:path];
    if(!fh){[line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];}
    else {@try{[fh seekToEndOfFile];[fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];[fh closeFile];}@catch(__unused NSException *e){}}
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
    if ([name containsString:@"_UISceneLayerHostContainerView"] || [name containsString:@"UISceneLayerHostContainerView"]) return root;
    for (UIView *sub in [root.subviews reverseObjectEnumerator]) {
        UIView *found = HBFindHostContainer(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}
static UIView *HBDeepestLargeContentView(UIView *root, CGSize target, NSUInteger depth) {
    if(!root || depth>12 || root.hidden || root.alpha<=0.01) return nil;
    UIView *best=nil; CGFloat bestScore=0;
    for(UIView *v in root.subviews){
        CGRect b=v.bounds; CGFloat area=b.size.width*b.size.height;
        BOOL large=b.size.width>=target.width*0.75 && b.size.height>=target.height*0.75;
        NSString *n=NSStringFromClass(v.class)?:@"";
        if(large && ![n containsString:@"UISceneLayerHostContainerView"]){
            CGFloat score=area + depth*1000000.0; if(score>bestScore){best=v;bestScore=score;}
        }
        UIView *d=HBDeepestLargeContentView(v,target,depth+1);
        if(d){CGFloat a=d.bounds.size.width*d.bounds.size.height + (depth+1)*1000000.0;if(a>bestScore){best=d;bestScore=a;}}
    }
    return best;
}
static UIWindow *HBFindActiveHostedWindow(UIView **canvasOut) {
    UIWindow *fallback=nil; UIView *fallbackCanvas=nil;
    for(UIScene *raw in UIApplication.sharedApplication.connectedScenes){
        if(![raw isKindOfClass:UIWindowScene.class])continue; UIWindowScene *scene=(UIWindowScene*)raw; if(!HBSceneLooksCarPlay(scene))continue;
        for(UIWindow *w in scene.windows){
            if(!w||w.hidden||w.alpha<=0.01||!w.rootViewController.view)continue;
            NSString *wc=NSStringFromClass(w.class)?:@"";
            if([wc isEqualToString:@"VMLPassthroughWindow"])continue;
            // Strongest known DuoDash-compatible surface from runtime logs: DBNotificationWindow, 595x240 on 640x240 CarPlay.
            if([wc containsString:@"DBNotificationWindow"]){
                UIView *root=w.rootViewController.view; UIView *canvas=HBDeepestLargeContentView(root,w.bounds.size,0);
                if(!canvas)canvas=root; if(canvasOut)*canvasOut=canvas;
                HBLog(@"DBNotificationWindow FOUND window=%@ level=%.1f root=%@ canvas=%@ frame=%@",w,w.windowLevel,NSStringFromClass(root.class),NSStringFromClass(canvas.class),NSStringFromCGRect(canvas.frame));
                return w;
            }
            UIView *hc=HBFindHostContainer(w.rootViewController.view,0);
            if(hc&&hc.superview&&w.windowLevel>=UIWindowLevelAlert){fallback=w;fallbackCanvas=hc.superview;}
        }
    }
    if(canvasOut)*canvasOut=fallbackCanvas; return fallback;
}
static NSString *HBSpeedText(void) { return (gCurrentSpeed > 0 && gCurrentSpeed <= 200) ? [NSString stringWithFormat:@"%ld", (long)gCurrentSpeed] : @"--"; }
static CGPoint HBLoadCenterRatio(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    CGFloat x = [d doubleForKey:@"VMLSpeedBubble.CarPlayPosX"], y = [d doubleForKey:@"VMLSpeedBubble.CarPlayPosY"];
    if (x <= 0 || x >= 1 || y <= 0 || y >= 1) return CGPointMake(0.12, 0.60);
    return CGPointMake(x, y);
}
static void HBSaveCenterRatio(CGPoint p) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setDouble:p.x forKey:@"VMLSpeedBubble.CarPlayPosX"]; [d setDouble:p.y forKey:@"VMLSpeedBubble.CarPlayPosY"]; [d synchronize];
}
static CGRect HBFrameForCanvas(UIView *canvas, CGFloat size) {
    CGPoint r = HBLoadCenterRatio(); CGFloat W = MAX(CGRectGetWidth(canvas.bounds),1), H = MAX(CGRectGetHeight(canvas.bounds),1), half=size/2;
    CGFloat x=MAX(half+4,MIN(W-half-4,r.x*W)), y=MAX(half+4,MIN(H-half-4,r.y*H));
    return CGRectMake(x-half,y-half,size,size);
}
@interface VMLHostBubbleDragTarget : NSObject
- (void)pan:(UIPanGestureRecognizer *)pan;
@end
static VMLHostBubbleDragTarget *gDragTarget=nil;
@implementation VMLHostBubbleDragTarget
- (void)pan:(UIPanGestureRecognizer *)pan {
    UIView *bubble=pan.view,*canvas=bubble.superview; if(!bubble||!canvas)return;
    UIGestureRecognizerState s=pan.state; if(s==UIGestureRecognizerStateBegan)gHostDragging=YES;
    if(s==UIGestureRecognizerStateBegan||s==UIGestureRecognizerStateChanged){
        CGPoint p=[pan locationInView:canvas]; CGFloat half=CGRectGetWidth(bubble.bounds)/2,W=MAX(CGRectGetWidth(canvas.bounds),1),H=MAX(CGRectGetHeight(canvas.bounds),1);
        p.x=MAX(half+4,MIN(W-half-4,p.x)); p.y=MAX(half+4,MIN(H-half-4,p.y)); [UIView performWithoutAnimation:^{bubble.center=p;}]; HBSaveCenterRatio(CGPointMake(p.x/W,p.y/H));
    }
    if(s==UIGestureRecognizerStateEnded||s==UIGestureRecognizerStateCancelled||s==UIGestureRecognizerStateFailed)gHostDragging=NO;
}
@end
static UIView *HBMakeBubble(CGFloat size) {
    UIView *b=[[UIView alloc]initWithFrame:CGRectMake(0,0,size,size)]; b.tag=kHostBubbleTag; b.backgroundColor=UIColor.whiteColor; b.layer.cornerRadius=size/2; b.layer.borderWidth=5; b.layer.borderColor=UIColor.systemRedColor.CGColor; b.clipsToBounds=YES; b.userInteractionEnabled=YES;
    UILabel *l=[[UILabel alloc]initWithFrame:b.bounds]; l.tag=kHostLabelTag; l.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; l.text=HBSpeedText(); l.textColor=UIColor.blackColor; l.textAlignment=NSTextAlignmentCenter; l.font=[UIFont systemFontOfSize:size*.40 weight:UIFontWeightBold]; l.adjustsFontSizeToFitWidth=YES; l.minimumScaleFactor=.5; l.userInteractionEnabled=NO; [b addSubview:l];
    if(!gDragTarget)gDragTarget=[VMLHostBubbleDragTarget new]; UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:gDragTarget action:@selector(pan:)]; pan.cancelsTouchesInView=YES; pan.minimumNumberOfTouches=1; pan.maximumNumberOfTouches=1; [b addGestureRecognizer:pan]; return b;
}
static void HBRemoveBubble(void){if(gHostBubble)HBLog(@"SATELLITE REMOVE super=%@",NSStringFromClass(gHostBubble.superview.class));[gHostBubble removeFromSuperview];gHostBubble=nil;gHostCanvas=nil;gHostWindow=nil;}
static void HBReadVietMapState(void){if(!gVietMapToken)return;uint64_t state=0;if(notify_get_state(gVietMapToken,&state)==NOTIFY_STATUS_OK)gVietMapActive=state!=0;}
static void HBStartSpeedReceiver(void){
    if(gSpeedTokens)return; gSpeedTokens=[NSMutableArray arrayWithCapacity:200];
    for(NSInteger speed=1;speed<=200;speed++){NSString *name=[NSString stringWithFormat:@"com.sushibta.vmlspeedbubble.speed.%ld",(long)speed];int token=0;NSInteger captured=speed;uint32_t status=notify_register_dispatch(name.UTF8String,&token,dispatch_get_main_queue(),^(__unused int incoming){gCurrentSpeed=captured;UILabel*l=(UILabel*)[gHostBubble viewWithTag:kHostLabelTag];if(l)l.text=HBSpeedText();});if(status==NOTIFY_STATUS_OK)[gSpeedTokens addObject:@(token)];}
    notify_post("com.sushibta.vmlspeedbubble.speed.request");
}
static void HBTick(void){
    if(!HBIsCarPlayApp())return; HBReadVietMapState();
    if(gVietMapActive){ if(gHostBubble) gHostBubble.hidden=YES; }
    else {UIView *canvas=nil;UIWindow *host=HBFindActiveHostedWindow(&canvas);if(!host||!canvas){ if(gHostBubble){gHostBubble.hidden=NO;gHostBubble.alpha=1;[gHostBubble.superview bringSubviewToFront:gHostBubble];} }else{CGFloat size=MAX(84,MIN(112,MAX(CGRectGetHeight(canvas.bounds),1)*.40));if(host!=gHostWindow||canvas!=gHostCanvas||!gHostBubble||gHostBubble.superview!=canvas){HBRemoveBubble();gHostWindow=host;gHostCanvas=canvas;gHostBubble=HBMakeBubble(size);[canvas addSubview:gHostBubble];HBLog(@"SATELLITE ATTACHED window=%@ level=%.1f canvas=%@ frame=%@",NSStringFromClass(host.class),host.windowLevel,NSStringFromClass(canvas.class),NSStringFromCGRect(canvas.frame));}if(!gHostDragging)gHostBubble.frame=HBFrameForCanvas(canvas,size);UILabel*l=(UILabel*)[gHostBubble viewWithTag:kHostLabelTag];if(l)l.text=HBSpeedText();gHostBubble.hidden=NO;gHostBubble.alpha=1;gHostBubble.layer.hidden=NO;gHostBubble.layer.zPosition=CGFLOAT_MAX;gHostBubble.userInteractionEnabled=YES;[canvas bringSubviewToFront:gHostBubble];}}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{HBTick();});
}
%ctor { @autoreleasepool { if(!HBIsCarPlayApp())return; HBLog(@"TA HOSTBRIDGE 16.35 ACTIVE bundle=%@ process=%@",NSBundle.mainBundle.bundleIdentifier,NSProcessInfo.processInfo.processName); HBStartSpeedReceiver(); int token=0; uint32_t s=notify_register_dispatch(kVietMapNotify,&token,dispatch_get_main_queue(),^(int incoming){gVietMapToken=incoming;HBReadVietMapState();}); if(s==NOTIFY_STATUS_OK){gVietMapToken=token;HBReadVietMapState();} dispatch_async(dispatch_get_main_queue(),^{HBTick();}); } }
