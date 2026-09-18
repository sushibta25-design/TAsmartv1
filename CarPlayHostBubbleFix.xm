#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
static NSString*const P=@"/var/mobile/VMLHostSniffer.txt";
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);NSString*s=[NSString stringWithFormat:@"[TA-APPBRIDGE-16.62] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static id V(id o,NSString*k){@try{return[o valueForKey:k];}@catch(__unused NSException*e){return nil;}}
static void D(UIView*v,NSString*why){if(!v)return;L(@"%@ self=%p %@ frame=%@ window=%@",why,v,NSStringFromClass(v.class),NSStringFromCGRect(v.frame),NSStringFromClass(v.window.class));UIView*x=v;for(int i=0;x&&i<14;i++,x=x.superview)L(@" V%d %@ %p frame=%@ subviews=%lu",i,NSStringFromClass(x.class),x,NSStringFromCGRect(x.frame),(unsigned long)x.subviews.count);if(v.window){id q=V(v.window.layer,@"context");L(@" WINDOW %@ level=%.1f ctxId=%@ displayId=%@ root=%@",NSStringFromClass(v.window.class),v.window.windowLevel,V(q,@"contextId"),V(q,@"displayId"),v.window.rootViewController?NSStringFromClass(v.window.rootViewController.class):@"nil");}}
%hook _UIScenePresentationView
-(void)didMoveToWindow{%orig;D((UIView*)self,@"Presentation didMoveToWindow");}
-(void)didMoveToSuperview{%orig;D((UIView*)self,@"Presentation didMoveToSuperview");}
%end
%hook _UIContextLayerHostView
-(void)didMoveToWindow{%orig;D((UIView*)self,@"ContextHost didMoveToWindow");}
-(void)didMoveToSuperview{%orig;D((UIView*)self,@"ContextHost didMoveToSuperview");}
%end
%ctor{@autoreleasepool{if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"])return;L(@"APPBRIDGE PRESENTATION TRACE 16.62 ACTIVE — READ ONLY");}}
