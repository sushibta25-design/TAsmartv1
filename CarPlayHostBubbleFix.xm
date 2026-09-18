#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

// CarPlayHostBubbleFix.xm — TA Native Window Test 16.56
// Uses UIKit's own UIWindowScene pipeline (proven in 16.54 to create displayId=2 contexts).
// Creates one tiny native CarPlay UIWindow test. No manual CAContext/CALayerHost.

static NSString *const P=@"/var/mobile/VMLHostSniffer.txt";
static UIWindow *gTest=nil;
static BOOL IsCP(){return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];}
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);
 NSString*s=[NSString stringWithFormat:@"[TA-NATIVEOVER-16.56] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];
 if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static UIWindowScene *Scene(){
 for(UIScene *raw in UIApplication.sharedApplication.connectedScenes){
  if(![raw isKindOfClass:UIWindowScene.class])continue; UIWindowScene*s=(UIWindowScene*)raw;
  NSString*r=s.session.role?:@"";CGSize z=s.screen.bounds.size;
  if([r localizedCaseInsensitiveContainsString:@"CarPlay"]||(z.width>z.height&&z.width>=300&&z.height<=500))return s;
 } return nil;
}
static void Build(){
 UIWindowScene*s=Scene();if(!s){L(@"NO CARPLAY SCENE");return;}
 CGRect b=s.screen.bounds;
 gTest=[[UIWindow alloc]initWithWindowScene:s];
 gTest.frame=CGRectMake(MAX(4.0,CGRectGetWidth(b)-100.0),8,92,92);
 gTest.windowLevel=3000.0;
 UIViewController*vc=[UIViewController new];vc.view.backgroundColor=UIColor.clearColor;gTest.rootViewController=vc;
 UIView*v=[[UIView alloc]initWithFrame:CGRectMake(4,4,84,84)];v.backgroundColor=UIColor.systemYellowColor;v.layer.cornerRadius=42;
 v.layer.borderWidth=7;v.layer.borderColor=UIColor.systemGreenColor.CGColor;[vc.view addSubview:v];
 UILabel*l=[[UILabel alloc]initWithFrame:v.bounds];l.text=@"56";l.textAlignment=NSTextAlignmentCenter;l.font=[UIFont boldSystemFontOfSize:28];l.textColor=UIColor.blackColor;[v addSubview:l];
 gTest.hidden=NO;
 // Order the UIKit-created native context above every currently known displayId=2 context,
 // and repeat briefly because AppBridge contexts appear after app launch.
 void (^orderNow)(void)=^{
   @try{
    id mine=[gTest.layer valueForKey:@"context"]; unsigned mid=[[mine valueForKey:@"contextId"] unsignedIntValue];
    NSArray *all=[NSClassFromString(@"CAContext") performSelector:NSSelectorFromString(@"allContexts")];
    NSMutableArray *ids=[NSMutableArray array];
    for(id x in all){NSNumber*d=[x valueForKey:@"displayId"];NSNumber*i=[x valueForKey:@"contextId"];
      if(d.intValue==2 && i.unsignedIntValue && i.unsignedIntValue!=mid){[ids addObject:i];
        if([mine respondsToSelector:NSSelectorFromString(@"orderAbove:")])
          ((void(*)(id,SEL,unsigned))objc_msgSend)(mine,NSSelectorFromString(@"orderAbove:"),i.unsignedIntValue);
      }}
    L(@"ORDER nativeId=%u above=%@ level=%@",mid,ids,[mine valueForKey:@"level"]);
   }@catch(NSException*e){L(@"ORDER EXCEPTION %@ %@",e.name,e.reason);}
 };
 orderNow();
 for(int k=1;k<=12;k++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,k*500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{orderNow();});
 // Keep the UIKit-native CarPlay window alive and above ordinary local windows.
 // This test deliberately avoids manual CAContext/CALayerHost.
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{
   if(gTest){ gTest.windowLevel=3000.0; gTest.hidden=NO; L(@"ALIVE level=%.1f scene=%@",gTest.windowLevel,gTest.windowScene.session.persistentIdentifier); }
 });
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  @try{ id ctx=[gTest.layer valueForKey:@"context"];
   L(@"CREATED window=%@ level=%.1f frame=%@ layer=%@ context=%@ contextId=%@ displayId=%@ options=%@",
     NSStringFromClass(gTest.class),gTest.windowLevel,NSStringFromCGRect(gTest.frame),NSStringFromClass(gTest.layer.class),
     ctx,[ctx valueForKey:@"contextId"],[ctx valueForKey:@"displayId"],[ctx valueForKey:@"options"]);
  }@catch(NSException*e){L(@"INSPECT EXCEPTION %@ %@",e.name,e.reason);}
 });
}
%ctor{@autoreleasepool{if(!IsCP())return;L(@"TA NATIVE OVERLAY TEST 16.56 ACTIVE");dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{Build();});}}
