#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// CarPlayHostBubbleFix.xm — TA UIKit Context Trace 16.54
// New branch: stop creating experimental contexts. Observe contexts UIKit/CarPlay already
// created with displayId=2 and map them back to UIWindow/UIWindowLayer ownership.
// Read-only, one-shot + delayed snapshots; original V15.9 bubble untouched.

static NSString *const P=@"/var/mobile/VMLHostSniffer.txt";
static BOOL IsCP(){return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];}
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);
 NSString*s=[NSString stringWithFormat:@"[TA-UICTX-16.54] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];
 if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static id V(id o,NSString*k){@try{return[o valueForKey:k];}@catch(__unused NSException*e){return nil;}}
static void Dump(NSString *why){
 Class C=NSClassFromString(@"CAContext"); NSArray *all=nil;
 @try{all=((id(*)(id,SEL))objc_msgSend)(C,NSSelectorFromString(@"allContexts"));}@catch(__unused NSException*e){}
 L(@"===== SNAPSHOT %@ allContexts=%lu =====",why,(unsigned long)all.count);
 for(id ctx in all){
  NSNumber*did=V(ctx,@"displayId"); if(did.intValue!=2)continue;
  NSNumber*cid=V(ctx,@"contextId"); id layer=V(ctx,@"layer");
  L(@"CTX id=%@ displayId=%@ valid=%@ level=%@ options=%@ layer=%@ layerClass=%@ delegate=%@",
    cid,did,V(ctx,@"valid"),V(ctx,@"level"),V(ctx,@"options"),layer,layer?NSStringFromClass([layer class]):@"nil",V(layer,@"delegate"));
  for(UIScene *raw in UIApplication.sharedApplication.connectedScenes){
   if(![raw isKindOfClass:UIWindowScene.class])continue; UIWindowScene*s=(UIWindowScene*)raw;
   for(UIWindow*w in s.windows){
    if(w.layer==layer || V(w.layer,@"context")==ctx)
      L(@" OWNER window=%@ level=%.1f frame=%@ rootVC=%@ sceneRole=%@",
        NSStringFromClass(w.class),w.windowLevel,NSStringFromCGRect(w.frame),
        w.rootViewController?NSStringFromClass(w.rootViewController.class):@"nil",s.session.role);
   }
  }
 }
 L(@"===== END SNAPSHOT %@ =====",why);
}
%ctor{@autoreleasepool{if(!IsCP())return;L(@"TA UIKIT CONTEXT TRACE 16.54 ACTIVE — READ ONLY");
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{Dump(@"T+1");});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{Dump(@"T+4");});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{Dump(@"T+8");});
}}
