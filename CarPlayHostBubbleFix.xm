#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// CarPlayHostBubbleFix.xm — DuoDash Runtime Class Trace 16.60
// READ ONLY. 16.59 found no matching live UIView, so inspect loaded runtime classes
// and summarize unusual visible view classes while DuoDash bubble is ON.

static NSString *const P=@"/var/mobile/VMLHostSniffer.txt";
static BOOL IsCP(){return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];}
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);NSString*s=[NSString stringWithFormat:@"[TA-DUOCLASS-16.60] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static BOOL Hit(NSString*n){return [n localizedCaseInsensitiveContainsString:@"duo"]||[n localizedCaseInsensitiveContainsString:@"cnab"]||[n localizedCaseInsensitiveContainsString:@"bubble"]||[n localizedCaseInsensitiveContainsString:@"dash"];}
static void ScanClasses(){
 int n=objc_getClassList(NULL,0);Class *cs=(Class*)malloc(sizeof(Class)*n);n=objc_getClassList(cs,n);NSMutableArray*a=[NSMutableArray array];
 for(int i=0;i<n;i++){NSString*s=NSStringFromClass(cs[i]);if(Hit(s))[a addObject:s];}free(cs);[a sortUsingSelector:@selector(compare:)];L(@"RUNTIME MATCHES count=%lu %@",(unsigned long)a.count,a);
}
static void Walk(UIView*v,NSMutableDictionary*d){if(!v||v.hidden||v.alpha<=.01)return;NSString*n=NSStringFromClass(v.class);d[n]=@([d[n] integerValue]+1);for(UIView*s in v.subviews)Walk(s,d);}
static void Snap(){
 ScanClasses();NSMutableDictionary*d=[NSMutableDictionary dictionary];
 for(UIScene*raw in UIApplication.sharedApplication.connectedScenes)if([raw isKindOfClass:UIWindowScene.class]){UIWindowScene*s=(UIWindowScene*)raw;if(![s.session.role localizedCaseInsensitiveContainsString:@"CarPlay"])continue;for(UIWindow*w in s.windows)Walk(w,d);}
 NSArray*keys=[[d allKeys] sortedArrayUsingSelector:@selector(compare:)];NSMutableArray*out=[NSMutableArray array];for(NSString*k in keys)if(Hit(k)||![k hasPrefix:@"UI"])[out addObject:[NSString stringWithFormat:@"%@=%@",k,d[k]]];L(@"VISIBLE CLASS SUMMARY %@",out);
}
%ctor{@autoreleasepool{if(!IsCP())return;L(@"DUODASH RUNTIME CLASS TRACE 16.60 ACTIVE — READ ONLY");dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{Snap();});dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{Snap();});}}
