#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

// CarPlayHostBubbleFix.xm — TA Context Pair Probe 16.43
// Tests local/remote CAContext relationship without touching the V15.9 bubble.
// No window scanning spam and no repeating hierarchy scan.

static NSString * const P=@"/var/mobile/VMLHostSniffer.txt";
static id gLocal=nil, gRemote=nil;
static CALayer *gSource=nil, *gHost=nil;
static __weak UIWindow *gWindow=nil;

static BOOL IsCP(void){ return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"]; }
static void L(NSString *fmt,...){
 va_list a;va_start(a,fmt);NSString *m=[[NSString alloc]initWithFormat:fmt arguments:a];va_end(a);
 NSString *s=[NSString stringWithFormat:@"[TA-PAIR-16.43] %@\n",m?:@""];
 NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:P];
 if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];
 else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}
}
static BOOL CPScene(UIWindowScene*s){
 if(!s)return NO; NSString*r=s.session.role?:@""; if([r localizedCaseInsensitiveContainsString:@"CarPlay"])return YES;
 CGSize z=s.screen.bounds.size;return z.width>z.height&&z.width>=300&&z.height<=500;
}
static UIWindow *MainWindow(void){
 UIWindow *best=nil; CGFloat score=-CGFLOAT_MAX;
 for(UIScene *raw in UIApplication.sharedApplication.connectedScenes){
  if(![raw isKindOfClass:UIWindowScene.class])continue; UIWindowScene*s=(UIWindowScene*)raw;if(!CPScene(s))continue;
  CGSize ss=s.screen.bounds.size;
  for(UIWindow*w in s.windows){
   if(w.hidden||w.alpha<=.01)continue;NSString*n=NSStringFromClass(w.class)?:@"";
   if([n isEqualToString:@"VMLPassthroughWindow"]||[n containsString:@"StatusBar"]||[n containsString:@"Notification"]||
      [n containsString:@"Alert"]||[n containsString:@"Keyboard"]||[n containsString:@"TextEffects"])continue;
   CGSize z=w.bounds.size;BOOL full=fabs(z.width-ss.width)<2&&fabs(z.height-ss.height)<2;
   CGFloat q=(full?1000000:0)+z.width*z.height-fabs(w.windowLevel)*1000;
   if(q>score){score=q;best=w;}
  }
 }
 return best;
}
static unsigned CID(id c){return c&&[c respondsToSelector:NSSelectorFromString(@"contextId")]?
 ((unsigned(*)(id,SEL))objc_msgSend)(c,NSSelectorFromString(@"contextId")):0;}
static void Build(void){
 UIWindow*w=MainWindow();if(!w){L(@"NO MAIN WINDOW");return;}
 Class C=NSClassFromString(@"CAContext"),H=NSClassFromString(@"CALayerHost");
 @try{
  gLocal=((id(*)(id,SEL,id))objc_msgSend)(C,NSSelectorFromString(@"localContextWithOptions:"),@{});
  gRemote=((id(*)(id,SEL,id))objc_msgSend)(C,NSSelectorFromString(@"remoteContextWithOptions:"),@{});
  L(@"CONTEXTS local=%@ id=%u valid=%@ remote=%@ id=%u valid=%@",
    gLocal,CID(gLocal),[gLocal valueForKey:@"valid"],gRemote,CID(gRemote),[gRemote valueForKey:@"valid"]);
  gSource=[CALayer layer];gSource.frame=CGRectMake(0,0,84,84);
  CAShapeLayer*c=[CAShapeLayer layer];c.frame=gSource.bounds;c.path=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(gSource.bounds,5,5)].CGPath;
  c.fillColor=UIColor.whiteColor.CGColor;c.strokeColor=UIColor.systemRedColor.CGColor;c.lineWidth=6;[gSource addSublayer:c];
  CATextLayer*t=[CATextLayer layer];t.frame=CGRectMake(0,24,84,36);t.string=@"TA";t.alignmentMode=kCAAlignmentCenter;t.fontSize=24;
  t.foregroundColor=UIColor.blackColor.CGColor;t.contentsScale=UIScreen.mainScreen.scale;[gSource addSublayer:t];

  // Source belongs to the local context. Probe whether a separately-created remote context
  // exposes/aliases that source; log both IDs rather than assuming they are paired.
  ((void(*)(id,SEL,id))objc_msgSend)(gLocal,NSSelectorFromString(@"setLayer:"),gSource);
  unsigned lid=CID(gLocal),rid=CID(gRemote);
  id remoteLayer=nil;@try{remoteLayer=[gRemote valueForKey:@"layer"];}@catch(__unused NSException*e){}
  L(@"AFTER SET localId=%u remoteId=%u remoteLayer=%@",lid,rid,remoteLayer);

  // First host the local context ID; this repeats the known 16.42 path but in a clean,
  // non-polling probe. If remote exposes a distinct layer/context, log gives next step.
  gHost=[H layer];((void(*)(id,SEL,unsigned))objc_msgSend)(gHost,NSSelectorFromString(@"setContextId:"),lid);
  gHost.frame=CGRectMake(MAX(8.0,CGRectGetWidth(w.bounds)-94),18,84,84);gHost.zPosition=1000000;
  [w.layer addSublayer:gHost];gWindow=w;
  L(@"HOST localId=%u remoteId=%u window=%@ level=%.1f frame=%@",lid,rid,NSStringFromClass(w.class),w.windowLevel,NSStringFromCGRect(gHost.frame));

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
   @try{
    L(@"CHECK local valid=%@ commit=%@ remote valid=%@ commit=%@ hostContextId=%@",
      [gLocal valueForKey:@"valid"],[gLocal valueForKey:@"commitId"],
      [gRemote valueForKey:@"valid"],[gRemote valueForKey:@"commitId"],
      [gHost valueForKey:@"contextId"]);
   }@catch(NSException*e){L(@"CHECK EXCEPTION %@ %@",e.name,e.reason);}
  });
 }@catch(NSException*e){L(@"EXCEPTION %@ %@",e.name,e.reason);}
}
%ctor{@autoreleasepool{if(!IsCP())return;L(@"TA CONTEXT PAIR PROBE 16.43 ACTIVE");dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{Build();});}}
