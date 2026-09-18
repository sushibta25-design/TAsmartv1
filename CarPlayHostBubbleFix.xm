#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

// CarPlayHostBubbleFix.xm — TA Context Lookup Test 16.50
// Create local producer context, then resolve it with +contextWithId: and host that exact ID.
// Original V15.9 bubble remains untouched.

static NSString *const P=@"/var/mobile/VMLHostSniffer.txt";
static id gLocal=nil,gLookup=nil; static CALayer *gRoot=nil,*gHost=nil; static NSString *gLastIds=@""; static __weak CALayer *gRemoteParent=nil;
static BOOL IsCP(){return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];}
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);
 NSString*s=[NSString stringWithFormat:@"[TA-REMOTEOPT-16.50] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];
 if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static BOOL CPS(UIWindowScene*s){if(!s)return NO;NSString*r=s.session.role?:@"";if([r localizedCaseInsensitiveContainsString:@"CarPlay"])return YES;CGSize z=s.screen.bounds.size;return z.width>z.height&&z.width>=300&&z.height<=500;}
static UIWindow* W(){UIWindow*b=nil;CGFloat q0=-CGFLOAT_MAX;for(UIScene*raw in UIApplication.sharedApplication.connectedScenes){if(![raw isKindOfClass:UIWindowScene.class])continue;UIWindowScene*s=(UIWindowScene*)raw;if(!CPS(s))continue;CGSize ss=s.screen.bounds.size;for(UIWindow*w in s.windows){if(w.hidden||w.alpha<=.01)continue;NSString*n=NSStringFromClass(w.class)?:@"";if([n isEqualToString:@"VMLPassthroughWindow"]||[n containsString:@"StatusBar"]||[n containsString:@"Notification"]||[n containsString:@"Alert"]||[n containsString:@"Keyboard"]||[n containsString:@"TextEffects"])continue;CGSize z=w.bounds.size;BOOL full=fabs(z.width-ss.width)<2&&fabs(z.height-ss.height)<2;CGFloat q=(full?1e6:0)+z.width*z.height-fabs(w.windowLevel)*1e3;if(q>q0){q0=q;b=w;}}}return b;}
static unsigned CID(id c){return c?((unsigned(*)(id,SEL))objc_msgSend)(c,NSSelectorFromString(@"contextId")):0;}

// Re-scan only after the host has been created. Remote AppBridge CALayerHosts often appear later.
static void LateOrder(void){
 if(!gLocal||!gHost)return;
 NSMutableSet *set=[NSMutableSet set];
 for(UIScene *raw in UIApplication.sharedApplication.connectedScenes){
  if(![raw isKindOfClass:UIWindowScene.class])continue; UIWindowScene*s=(UIWindowScene*)raw;if(!CPS(s))continue;
  for(UIWindow*w in s.windows){
   NSMutableArray *stack=[NSMutableArray arrayWithObject:w.layer];
   while(stack.count){CALayer*x=stack.lastObject;[stack removeLastObject];
    if([NSStringFromClass(x.class) isEqualToString:@"CALayerHost"])@try{
      NSNumber*n=[x valueForKey:@"contextId"];if(n&&n.unsignedIntValue&&n.unsignedIntValue!=CID(gLocal))[set addObject:n];
    }@catch(__unused NSException*e){}
    for(CALayer*sl in x.sublayers?:@[])[stack addObject:sl];
   }
  }
 }
 NSArray *ids=[[set allObjects] sortedArrayUsingSelector:@selector(compare:)];
 NSString *sig=[ids description];
 // If remote hosted surfaces exist, move our CALayerHost beside the highest visible
 // CALayerHost instead of leaving it under the base UIWindow layer.
 CALayer *bestRemote=nil;
 for(UIScene *raw in UIApplication.sharedApplication.connectedScenes){
  if(![raw isKindOfClass:UIWindowScene.class])continue; UIWindowScene*s=(UIWindowScene*)raw;if(!CPS(s))continue;
  for(UIWindow*w in s.windows){NSMutableArray*stack=[NSMutableArray arrayWithObject:w.layer];
   while(stack.count){CALayer*x=stack.lastObject;[stack removeLastObject];
    if([NSStringFromClass(x.class) isEqualToString:@"CALayerHost"])@try{
      NSNumber*n=[x valueForKey:@"contextId"];if(n.unsignedIntValue&&n.unsignedIntValue!=CID(gLocal)&&x.superlayer)bestRemote=x;
    }@catch(__unused NSException*e){}
    for(CALayer*sl in x.sublayers?:@[])[stack addObject:sl];
   }
  }
 }
 if(bestRemote){
   @try{
    NSNumber *rid=[bestRemote valueForKey:@"contextId"];
    Class CC=NSClassFromString(@"CAContext");
    id rc=((id(*)(id,SEL,unsigned))objc_msgSend)(CC,NSSelectorFromString(@"contextWithId:"),rid.unsignedIntValue);
    if(rc) L(@"REMOTE id=%@ ctx=%@ options=%@ displayId=%@ level=%@ format=%@ secure=%@ annotation=%@ layer=%@",
      rid,rc,[rc valueForKey:@"options"],[rc valueForKey:@"displayId"],[rc valueForKey:@"level"],
      [rc valueForKey:@"contentsFormat"],[rc valueForKey:@"secure"],[rc valueForKey:@"annotation"],[rc valueForKey:@"layer"]);
    else L(@"REMOTE id=%@ contextWithId returned nil",rid);
   }@catch(NSException*e){L(@"REMOTE INSPECT EXCEPTION %@ %@",e.name,e.reason);}
  }
 if(bestRemote && gHost.superlayer!=bestRemote.superlayer){
   [gHost removeFromSuperlayer]; [bestRemote.superlayer addSublayer:gHost]; gRemoteParent=bestRemote.superlayer;
   CGRect r=bestRemote.frame; gHost.frame=CGRectMake(MAX(4.0,CGRectGetMaxX(r)-92.0),CGRectGetMinY(r)+8.0,88,88);
   gHost.zPosition=1000000.0; L(@"REPARENT beside remoteId=%@ parent=%@ remoteFrame=%@ hostFrame=%@",
      [bestRemote valueForKey:@"contextId"],NSStringFromClass(bestRemote.superlayer.class),NSStringFromCGRect(r),NSStringFromCGRect(gHost.frame));
 }
 if(![sig isEqualToString:gLastIds]){
  gLastIds=sig;
  @try{for(NSNumber*n in ids)((void(*)(id,SEL,unsigned))objc_msgSend)(gLocal,NSSelectorFromString(@"orderAbove:"),n.unsignedIntValue);
   L(@"LATE ORDER localId=%u aboveIds=%@ level=%.1f",CID(gLocal),ids,((float(*)(id,SEL))objc_msgSend)(gLocal,NSSelectorFromString(@"level")));
  }@catch(NSException*e){L(@"LATE ORDER EXCEPTION %@ %@",e.name,e.reason);}
 }
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{LateOrder();});
}

static void Build(){
 UIWindow*w=W();if(!w){L(@"NO WINDOW");return;}Class C=NSClassFromString(@"CAContext"),H=NSClassFromString(@"CALayerHost");
 @try{
  gLocal=((id(*)(id,SEL,id))objc_msgSend)(C,NSSelectorFromString(@"localContextWithOptions:"),@{});
  gRoot=[CALayer layer];gRoot.frame=CGRectMake(0,0,88,88);
  CAShapeLayer*c=[CAShapeLayer layer];c.frame=gRoot.bounds;c.path=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(gRoot.bounds,5,5)].CGPath;c.fillColor=UIColor.whiteColor.CGColor;c.strokeColor=UIColor.systemGreenColor.CGColor;c.lineWidth=7;[gRoot addSublayer:c];
  CATextLayer*t=[CATextLayer layer];t.frame=CGRectMake(0,25,88,38);t.string=@"44";t.alignmentMode=kCAAlignmentCenter;t.fontSize=25;t.foregroundColor=UIColor.blackColor.CGColor;t.contentsScale=UIScreen.mainScreen.scale;[gRoot addSublayer:t];
  // Make producer content deliberately unmistakable and force a CA transaction.
  gRoot.backgroundColor=UIColor.systemYellowColor.CGColor;
  gRoot.opaque=YES;
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  ((void(*)(id,SEL,id))objc_msgSend)(gLocal,NSSelectorFromString(@"setLayer:"),gRoot);
  [gRoot setNeedsDisplay]; [CATransaction commit]; [CATransaction flush];
  @try{
    ((void(*)(id,SEL,float))objc_msgSend)(gLocal,NSSelectorFromString(@"setLevel:"),1000000.0f);
    [gLocal setValue:@"TA16.50" forKey:@"annotation"];
    L(@"PRODUCER options=%@ layer=%@ contentsFormat=%@ displayId=%@ level=%@",
      [gLocal valueForKey:@"options"],[gLocal valueForKey:@"layer"],[gLocal valueForKey:@"contentsFormat"],
      [gLocal valueForKey:@"displayId"],[gLocal valueForKey:@"level"]);
  }@catch(NSException*e){L(@"PRODUCER META EXCEPTION %@ %@",e.name,e.reason);}

  unsigned id0=CID(gLocal);
  gLookup=((id(*)(id,SEL,unsigned))objc_msgSend)(C,NSSelectorFromString(@"contextWithId:"),id0);
  L(@"LOCAL=%@ id=%u valid=%@ LOOKUP=%@ id=%u valid=%@ sameObject=%d lookupLayer=%@",gLocal,id0,[gLocal valueForKey:@"valid"],gLookup,CID(gLookup),gLookup?[gLookup valueForKey:@"valid"]:@0,gLookup==gLocal,gLookup?[gLookup valueForKey:@"layer"]:nil);
  gHost=[H layer];((void(*)(id,SEL,unsigned))objc_msgSend)(gHost,NSSelectorFromString(@"setContextId:"),id0);
  gHost.frame=CGRectMake(MAX(8.0,CGRectGetWidth(w.bounds)-98),16,88,88);gHost.zPosition=1000000;
  // CAContext-level ordering test. Existing hosted AppBridge contexts are discovered
  // from CALayerHost layers in the selected CarPlay window tree.
  NSMutableArray *ids=[NSMutableArray array];
  void (^walk)(CALayer*)=^(CALayer *root){
    NSMutableArray *stack=[NSMutableArray arrayWithObject:root];
    while(stack.count){ CALayer *x=stack.lastObject; [stack removeLastObject];
      if([NSStringFromClass(x.class) isEqualToString:@"CALayerHost"]){
        @try{ NSNumber *n=[x valueForKey:@"contextId"]; if(n && n.unsignedIntValue && n.unsignedIntValue!=id0)[ids addObject:n]; }@catch(__unused NSException*e){}
      }
      for(CALayer *s in x.sublayers?:@[]) [stack addObject:s];
    }
  }; walk(w.layer);
  @try{
    float old=((float(*)(id,SEL))objc_msgSend)(gLocal,NSSelectorFromString(@"level"));
    ((void(*)(id,SEL,float))objc_msgSend)(gLocal,NSSelectorFromString(@"setLevel:"),1000000.0f);
    for(NSNumber *n in ids) ((void(*)(id,SEL,unsigned))objc_msgSend)(gLocal,NSSelectorFromString(@"orderAbove:"),n.unsignedIntValue);
    L(@"ORDER localId=%u oldLevel=%.1f newLevel=%.1f aboveIds=%@",id0,old,((float(*)(id,SEL))objc_msgSend)(gLocal,NSSelectorFromString(@"level")),ids);
  }@catch(NSException*e){L(@"ORDER EXCEPTION %@ %@",e.name,e.reason);}
  [w.layer addSublayer:gHost]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{LateOrder();});
  L(@"HOST id=%u window=%@ level=%.1f",id0,NSStringFromClass(w.class),w.windowLevel);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
   [CATransaction flush];

   @try{L(@"CHECK localCommit=%@ lookupCommit=%@ hostId=%@ localValid=%@ lookupValid=%@",[gLocal valueForKey:@"commitId"],[gLookup valueForKey:@"commitId"],[gHost valueForKey:@"contextId"],[gLocal valueForKey:@"valid"],[gLookup valueForKey:@"valid"]);}@catch(NSException*e){L(@"CHECK EXCEPTION %@ %@",e.name,e.reason);}
  });
 }@catch(NSException*e){L(@"EXCEPTION %@ %@",e.name,e.reason);}
}
%ctor{@autoreleasepool{if(!IsCP())return;L(@"TA REMOTE CONTEXT OPTIONS 16.50 ACTIVE");dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{Build();});}}
