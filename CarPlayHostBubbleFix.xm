#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
static NSString*const P=@"/var/mobile/VMLHostSniffer.txt";static UIView*g=nil;
static void L(NSString*f,...){va_list a;va_start(a,f);NSString*m=[[NSString alloc]initWithFormat:f arguments:a];va_end(a);NSString*s=[NSString stringWithFormat:@"[TA-INHOST-16.63] %@\n",m?:@""];NSFileHandle*h=[NSFileHandle fileHandleForWritingAtPath:P];if(!h)[s writeToFile:P atomically:YES encoding:NSUTF8StringEncoding error:nil];else @try{[h seekToEndOfFile];[h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];}@catch(__unused NSException*e){}}
static void Put(UIView*host){if(!host.window||g)return;CGRect b=host.bounds;if(b.size.width<150||b.size.height<150)return;g=[[UIView alloc]initWithFrame:CGRectMake(MAX(4,b.size.width-90),8,82,82)];g.backgroundColor=UIColor.systemYellowColor;g.layer.cornerRadius=41;g.layer.borderWidth=7;g.layer.borderColor=UIColor.systemGreenColor.CGColor;g.userInteractionEnabled=NO;UILabel*l=[[UILabel alloc]initWithFrame:g.bounds];l.text=@"63";l.textAlignment=NSTextAlignmentCenter;l.font=[UIFont boldSystemFontOfSize:27];l.textColor=UIColor.blackColor;[g addSubview:l];[host addSubview:g];[host bringSubviewToFront:g];g.layer.zPosition=1000000;L(@"ATTACHED host=%@ frame=%@ window=%@",NSStringFromClass(host.class),NSStringFromCGRect(host.frame),NSStringFromClass(host.window.class));}
%hook _UITouchPassthroughView
-(void)didMoveToWindow{%orig;if(((UIView*)self).window)Put((UIView*)self);}
%end
%hook _UISceneLayerHostContainerView
-(void)didMoveToWindow{%orig;if(((UIView*)self).window)Put((UIView*)self);}
%end
%ctor{@autoreleasepool{if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"])return;L(@"IN-HOST CONTAINER TEST 16.63 ACTIVE");}}
