#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

// CarPlayHostBubbleFix.xm — TA Persistent Window Survey 16.57
// READ ONLY. Compare CarPlay windows/contexts before and after hosted apps cover Dashboard.
// Goal: find a native system window/context that remains visible/present across fullscreen hosting.

static NSString *const P=@"/var/mobile/VMLHostSniffer.txt";
static BOOL IsCP(){return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];}
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);
 NSString*s=[NSString stringWithFormat:@"[TA-SURVEY-16.57] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];
 if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static id V(id o,NSString*k){@try{return[o valueForKey:k];}@catch(__unused NSException*e){return nil;}}
static BOOL CP(UIWindowScene*s){NSString*r=s.session.role?:@"";CGSize z=s.screen.bounds.size;return [r localizedCaseInsensitiveContainsString:@"CarPlay"]||(z.width>z.height&&z.width>=300&&z.height<=500);}
static void Snap(NSString*why){
 L(@"===== %@ =====",why);
 for(UIScene*raw in UIApplication.sharedApplication.connectedScenes){if(![raw isKindOfClass:UIWindowScene.class])continue;UIWindowScene*s=(UIWindowScene*)raw;if(!CP(s))continue;
  for(UIWindow*w in s.windows){
   id ctx=V(w.layer,@"context");
   L(@"WIN class=%@ level=%.1f hidden=%d alpha=%.2f key=%d frame=%@ root=%@ ctxId=%@ displayId=%@ ctxLevel=%@ options=%@",
    NSStringFromClass(w.class),w.windowLevel,w.hidden,w.alpha,w.keyWindow,NSStringFromCGRect(w.frame),
    w.rootViewController?NSStringFromClass(w.rootViewController.class):@"nil",
    V(ctx,@"contextId"),V(ctx,@"displayId"),V(ctx,@"level"),V(ctx,@"options"));
  }
 }
 L(@"===== END %@ =====",why);
}
%ctor{@autoreleasepool{if(!IsCP())return;L(@"TA PERSISTENT WINDOW SURVEY 16.57 ACTIVE — READ ONLY");
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{Snap(@"T+1");});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{Snap(@"T+4");});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{Snap(@"T+8");});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,14*NSEC_PER_SEC),dispatch_get_main_queue(),^{Snap(@"T+14");});
}}
