#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// CarPlayHostBubbleFix.xm — CNABBubble Lifecycle Trace 16.61
// READ ONLY. Runtime proves CNABBubbleView is loaded, but it was absent from UIKit window walk.
// Hook its lifecycle to capture where/when DuoDash creates it.

static NSString *const P=@"/var/mobile/VMLHostSniffer.txt";
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);NSString*s=[NSString stringWithFormat:@"[TA-CNAB-16.61] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static void Dump(UIView*v,NSString*why){if(!v)return;L(@"%@ self=%p class=%@ frame=%@ hidden=%d alpha=%.2f window=%@",why,v,NSStringFromClass(v.class),NSStringFromCGRect(v.frame),v.hidden,v.alpha,NSStringFromClass(v.window.class));UIView*x=v;for(int i=0;x&&i<14;i++,x=x.superview)L(@" V%d %@ %p frame=%@",i,NSStringFromClass(x.class),x,NSStringFromCGRect(x.frame));if(v.window)@try{id c=[v.window.layer valueForKey:@"context"];L(@" WINDOW %@ level=%.1f ctxId=%@ displayId=%@",NSStringFromClass(v.window.class),v.window.windowLevel,[c valueForKey:@"contextId"],[c valueForKey:@"displayId"]);}@catch(__unused NSException*e){}}
%hook CNABBubbleView
-(id)initWithFrame:(CGRect)f{ id r=%orig; L(@"initWithFrame self=%p frame=%@",r,NSStringFromCGRect(f)); return r; }
-(void)didMoveToWindow{ %orig; Dump((UIView*)self,@"didMoveToWindow"); }
-(void)didMoveToSuperview{ %orig; Dump((UIView*)self,@"didMoveToSuperview"); }
-(void)setHidden:(BOOL)h{ L(@"setHidden self=%p value=%d",self,h); %orig; }
-(void)setFrame:(CGRect)f{ L(@"setFrame self=%p frame=%@",self,NSStringFromCGRect(f)); %orig; }
%end
%ctor{@autoreleasepool{if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"])return;L(@"CNABBUBBLE LIFECYCLE TRACE 16.61 ACTIVE");}}
