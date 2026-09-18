#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

// CarPlayHostBubbleFix.xm — TA System Window Child Test 16.58
// Put one test view inside persistent CarPlay system windows instead of a new overlay window.
// Primary target: DBNotificationWindow; fallback: _DBCornerRadiusWindow. Original bubble untouched.

static NSString *const P=@"/var/mobile/VMLHostSniffer.txt";
static UIView *gV=nil; static __weak UIWindow *gW=nil;
static BOOL IsCP(){return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];}
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);NSString*s=[NSString stringWithFormat:@"[TA-SYSWIN-16.58] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static UIWindow *Target(){
 UIWindow *corner=nil;
 for(UIScene*raw in UIApplication.sharedApplication.connectedScenes){if(![raw isKindOfClass:UIWindowScene.class])continue;UIWindowScene*s=(UIWindowScene*)raw;NSString*r=s.session.role?:@"";if(![r localizedCaseInsensitiveContainsString:@"CarPlay"])continue;
  for(UIWindow*w in s.windows){NSString*n=NSStringFromClass(w.class);
   if([n isEqualToString:@"DBNotificationWindow"]&&!w.hidden)return w;
   if([n isEqualToString:@"_DBCornerRadiusWindow"]&&!w.hidden)corner=w;
  }
 } return corner;
}
static void Attach(){
 UIWindow*w=Target(); if(!w){L(@"NO TARGET");return;}
 UIView *host=w.rootViewController.view ?: w;
 CGFloat sz=86; gV=[[UIView alloc]initWithFrame:CGRectMake(MAX(2,CGRectGetWidth(host.bounds)-sz-6),8,sz,sz)];
 gV.backgroundColor=UIColor.systemYellowColor;gV.layer.cornerRadius=sz/2;gV.layer.borderWidth=7;gV.layer.borderColor=UIColor.systemGreenColor.CGColor;gV.userInteractionEnabled=NO;
 UILabel*l=[[UILabel alloc]initWithFrame:gV.bounds];l.text=@"58";l.textAlignment=NSTextAlignmentCenter;l.font=[UIFont boldSystemFontOfSize:28];l.textColor=UIColor.blackColor;[gV addSubview:l];
 [host addSubview:gV];[host bringSubviewToFront:gV];gV.layer.zPosition=1000000;gW=w;
 id ctx=nil;@try{ctx=[w.layer valueForKey:@"context"];}@catch(__unused NSException*e){}
 L(@"ATTACHED window=%@ level=%.1f frame=%@ root=%@ contextId=%@ displayId=%@",NSStringFromClass(w.class),w.windowLevel,NSStringFromCGRect(w.frame),w.rootViewController?NSStringFromClass(w.rootViewController.class):@"nil",ctx?[ctx valueForKey:@"contextId"]:nil,ctx?[ctx valueForKey:@"displayId"]:nil);
}
%ctor{@autoreleasepool{if(!IsCP())return;L(@"TA SYSTEM WINDOW CHILD TEST 16.58 ACTIVE");dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{Attach();});}}
