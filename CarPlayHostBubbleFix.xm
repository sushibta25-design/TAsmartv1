#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

// CarPlayHostBubbleFix.xm — DuoDash Bubble Trace 16.59
// READ ONLY. Finds CNABBubbleView / bubble-like DuoDash views while DuoDash is ON,
// then dumps view ancestors, owning window and CA context.

static NSString *const P=@"/var/mobile/VMLHostSniffer.txt";
static BOOL IsCP(){return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];}
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);NSString*s=[NSString stringWithFormat:@"[TA-DUOBUBBLE-16.59] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static id V(id o,NSString*k){@try{return[o valueForKey:k];}@catch(__unused NSException*e){return nil;}}
static BOOL Candidate(UIView*v){
 NSString*n=NSStringFromClass(v.class)?:@"";
 return [n localizedCaseInsensitiveContainsString:@"CNAB"]||[n localizedCaseInsensitiveContainsString:@"Bubble"]||[n localizedCaseInsensitiveContainsString:@"DuoDash"];
}
static void DumpView(UIView*v){
 L(@"FOUND view=%@ ptr=%p frame=%@ bounds=%@ hidden=%d alpha=%.2f window=%@",NSStringFromClass(v.class),v,NSStringFromCGRect(v.frame),NSStringFromCGRect(v.bounds),v.hidden,v.alpha,NSStringFromClass(v.window.class));
 UIView*x=v;for(int i=0;x&&i<16;i++,x=x.superview)L(@" V%d %@ ptr=%p frame=%@ layer=%@ z=%.1f",i,NSStringFromClass(x.class),x,NSStringFromCGRect(x.frame),NSStringFromClass(x.layer.class),x.layer.zPosition);
 UIWindow*w=v.window;if(w){id ctx=V(w.layer,@"context");L(@" WINDOW %@ level=%.1f frame=%@ root=%@ layer=%@ ctx=%@ ctxId=%@ displayId=%@ ctxLevel=%@ options=%@",NSStringFromClass(w.class),w.windowLevel,NSStringFromCGRect(w.frame),w.rootViewController?NSStringFromClass(w.rootViewController.class):@"nil",NSStringFromClass(w.layer.class),ctx,V(ctx,@"contextId"),V(ctx,@"displayId"),V(ctx,@"level"),V(ctx,@"options"));}
 CALayer*l=v.layer;for(int i=0;l&&i<16;i++,l=l.superlayer)L(@" L%d %@ ptr=%p frame=%@ z=%.1f super=%@",i,NSStringFromClass(l.class),l,NSStringFromCGRect(l.frame),l.zPosition,NSStringFromClass(l.superlayer.class));
}
static void Walk(UIView*r,NSMutableSet*seen){if(!r)return;if(Candidate(r)){NSString*k=[NSString stringWithFormat:@"%p",r];if(![seen containsObject:k]){[seen addObject:k];DumpView(r);}}for(UIView*s in r.subviews)Walk(s,seen);}
static void Snap(NSString*why){
 NSMutableSet*seen=[NSMutableSet set];L(@"===== SNAP %@ =====",why);
 for(UIScene*raw in UIApplication.sharedApplication.connectedScenes){if(![raw isKindOfClass:UIWindowScene.class])continue;UIWindowScene*s=(UIWindowScene*)raw;NSString*role=s.session.role?:@"";if(![role localizedCaseInsensitiveContainsString:@"CarPlay"])continue;for(UIWindow*w in s.windows){Walk(w,seen);}}
 L(@"FOUND COUNT=%lu",(unsigned long)seen.count);L(@"===== END %@ =====",why);
}
%ctor{@autoreleasepool{if(!IsCP())return;L(@"DUODASH BUBBLE TRACE 16.59 ACTIVE — READ ONLY");
 for(int i=1;i<=6;i++)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,i*2*NSEC_PER_SEC),dispatch_get_main_queue(),^{Snap([NSString stringWithFormat:@"T+%d",i*2]);});
}}
