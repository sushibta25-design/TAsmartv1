#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *kVMLStableNotify = "com.sushibta.vmlspeedbubble.vmlcarplaystable";
static int gVMLStableToken = 0;
static BOOL gVMLStableVisible = NO;
static NSUInteger gVMLReleaseGeneration = 0;

static BOOL VMLFixIsVietMap(void){ return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"vn.vietmap.live"]; }
static BOOL VMLFixIsCarPlayApp(void){ return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"]; }

static BOOL VMLFixIsTemplateScene(UIScene *scene){
    if(!scene) return NO;
    NSString *cls=NSStringFromClass(scene.class)?:@"";
    NSString *role=scene.session.role?:@"";
    return [cls containsString:@"CPTemplateApplicationScene"] ||
           [role localizedCaseInsensitiveContainsString:@"CarTemplateApplication"] ||
           [role localizedCaseInsensitiveContainsString:@"CarPlay"];
}

static BOOL VMLFixVietMapVisibleOnCarPlay(void){
    if(!VMLFixIsVietMap()) return NO;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
        if(!VMLFixIsTemplateScene(scene)) continue;
        UISceneActivationState s=scene.activationState;
        if(s==UISceneActivationStateForegroundActive || s==UISceneActivationStateForegroundInactive) return YES;
    }
    return NO;
}

static void VMLFixPublishStableState(void){
    if(!VMLFixIsVietMap()) return;
    if(!gVMLStableToken){
        int token=0;
        if(notify_register_check(kVMLStableNotify,&token)!=NOTIFY_STATUS_OK) return;
        gVMLStableToken=token;
    }
    BOOL visible=VMLFixVietMapVisibleOnCarPlay();
    notify_set_state(gVMLStableToken,visible?1:0);
    notify_post(kVMLStableNotify);
}

static BOOL VMLFixIsBubbleView(UIView *view){
    if(!view) return NO;
    NSInteger tag=view.tag;
    return tag>=990199 && tag<=991000;
}

static void VMLFixHideBubbleTree(UIView *root){
    if(!root) return;
    if(VMLFixIsBubbleView(root)){
        root.hidden=YES;
        root.alpha=0.0;
        root.layer.hidden=YES;
        root.layer.opacity=0.0;
        return;
    }
    for(UIView *sub in root.subviews) VMLFixHideBubbleTree(sub);
}

static void VMLFixApplyHardHide(void){
    if(!VMLFixIsCarPlayApp() || !gVMLStableVisible) return;
    for(UIScene *raw in UIApplication.sharedApplication.connectedScenes){
        if(![raw isKindOfClass:UIWindowScene.class]) continue;
        for(UIWindow *w in ((UIWindowScene *)raw).windows){
            UIView *root=w.rootViewController.view;
            if(root) VMLFixHideBubbleTree(root);
        }
    }
}

static void VMLFixReadStableState(void){
    if(!gVMLStableToken) return;
    uint64_t state=0;
    if(notify_get_state(gVMLStableToken,&state)!=NOTIFY_STATUS_OK) return;
    NSUInteger generation=++gVMLReleaseGeneration;
    if(state!=0){
        gVMLStableVisible=YES;
        VMLFixApplyHardHide();
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.7*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(generation!=gVMLReleaseGeneration) return;
        uint64_t confirm=1;
        if(notify_get_state(gVMLStableToken,&confirm)!=NOTIFY_STATUS_OK) return;
        if(confirm==0) gVMLStableVisible=NO;
    });
}

%hook UIView
- (void)setHidden:(BOOL)hidden{
    if(VMLFixIsCarPlayApp() && gVMLStableVisible && VMLFixIsBubbleView(self) && !hidden){ %orig(YES); return; }
    %orig(hidden);
}
- (void)setAlpha:(CGFloat)alpha{
    if(VMLFixIsCarPlayApp() && gVMLStableVisible && VMLFixIsBubbleView(self) && alpha>0.01){ %orig(0.0); return; }
    %orig(alpha);
}
%end

%hook CALayer
- (void)setHidden:(BOOL)hidden{
    if(VMLFixIsCarPlayApp() && gVMLStableVisible && !hidden){
        id d=self.delegate;
        if([d isKindOfClass:UIView.class] && VMLFixIsBubbleView((UIView *)d)){ %orig(YES); return; }
    }
    %orig(hidden);
}
- (void)setOpacity:(float)opacity{
    if(VMLFixIsCarPlayApp() && gVMLStableVisible && opacity>0.01f){
        id d=self.delegate;
        if([d isKindOfClass:UIView.class] && VMLFixIsBubbleView((UIView *)d)){ %orig(0.0f); return; }
    }
    %orig(opacity);
}
%end

%ctor{
    @autoreleasepool{
        if(VMLFixIsVietMap()){
            VMLFixPublishStableState();
            NSArray *names=@[UISceneDidActivateNotification,UISceneWillDeactivateNotification,UISceneDidEnterBackgroundNotification,UISceneWillEnterForegroundNotification];
            for(NSString *name in names){
                [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),^{VMLFixPublishStableState();});
                }];
            }
            [NSTimer scheduledTimerWithTimeInterval:.20 repeats:YES block:^(__unused NSTimer *timer){VMLFixPublishStableState();}];
            return;
        }
        if(VMLFixIsCarPlayApp()){
            int token=0;
            uint32_t s=notify_register_dispatch(kVMLStableNotify,&token,dispatch_get_main_queue(),^(int incoming){
                gVMLStableToken=incoming; VMLFixReadStableState(); if(gVMLStableVisible) VMLFixApplyHardHide();
            });
            if(s==NOTIFY_STATUS_OK){ gVMLStableToken=token; VMLFixReadStableState(); }
            [NSTimer scheduledTimerWithTimeInterval:.12 repeats:YES block:^(__unused NSTimer *timer){ if(gVMLStableVisible) VMLFixApplyHardHide(); }];
        }
    }
}
