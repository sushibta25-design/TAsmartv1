#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// CarPlayHostBubbleFix.xm
// TA Runtime API Probe 16.40
// READ ONLY. Dumps runtime methods/properties/ivars for CAContext and CALayerHost.
// No timers, windows, views, contexts, layers, mirrors, or bubble mutations.

static NSString * const HBLogPath = @"/var/mobile/VMLHostSniffer.txt";

static BOOL HBIsCarPlayApp(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"];
}

static void HBLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[TA-API-16.40] %@\n", msg ?: @""];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:HBLogPath];
    if (!fh) {
        [line writeToFile:HBLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    @try {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (__unused NSException *e) {}
}

static NSString *HBMethodList(Class cls) {
    if (!cls) return @"<nil>";
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);
        [items addObject:[NSString stringWithFormat:@"%@ {%s}", NSStringFromSelector(sel), types ?: "?"]];
    }
    if (methods) free(methods);
    [items sortUsingSelector:@selector(compare:)];
    return [items componentsJoinedByString:@" | "];
}

static NSString *HBPropertyList(Class cls) {
    if (!cls) return @"<nil>";
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(cls, &count);
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int i = 0; i < count; i++) {
        const char *n = property_getName(props[i]);
        const char *a = property_getAttributes(props[i]);
        [items addObject:[NSString stringWithFormat:@"%s {%s}", n ?: "?", a ?: "?"]];
    }
    if (props) free(props);
    [items sortUsingSelector:@selector(compare:)];
    return [items componentsJoinedByString:@" | "];
}

static NSString *HBIvarList(Class cls) {
    if (!cls) return @"<nil>";
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int i = 0; i < count; i++) {
        const char *n = ivar_getName(ivars[i]);
        const char *t = ivar_getTypeEncoding(ivars[i]);
        [items addObject:[NSString stringWithFormat:@"%s {%s}", n ?: "?", t ?: "?"]];
    }
    if (ivars) free(ivars);
    [items sortUsingSelector:@selector(compare:)];
    return [items componentsJoinedByString:@" | "];
}

static void HBDumpClass(NSString *name) {
    Class cls = NSClassFromString(name);
    HBLog(@"===== CLASS %@ ptr=%p superclass=%@ =====", name, cls,
          cls ? NSStringFromClass(class_getSuperclass(cls)) : @"nil");
    if (!cls) return;

    HBLog(@"INSTANCE METHODS %@ => %@", name, HBMethodList(cls));
    HBLog(@"PROPERTIES %@ => %@", name, HBPropertyList(cls));
    HBLog(@"IVARS %@ => %@", name, HBIvarList(cls));

    Class meta = object_getClass(cls);
    HBLog(@"CLASS METHODS %@ => %@", name, HBMethodList(meta));
    HBLog(@"===== END CLASS %@ =====", name);
}

%ctor {
    @autoreleasepool {
        if (!HBIsCarPlayApp()) return;
        HBLog(@"TA RUNTIME API PROBE 16.40 ACTIVE — READ ONLY");
        HBDumpClass(@"CAContext");
        HBDumpClass(@"CALayerHost");
        HBDumpClass(@"_UIContextLayerHostView");
        HBDumpClass(@"UIScenePresentationContext");
        HBLog(@"TA RUNTIME API PROBE 16.40 COMPLETE");
    }
}
