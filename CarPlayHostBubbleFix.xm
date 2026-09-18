#import <Foundation/Foundation.h>

// CarPlayHostBubbleFix.xm
// NO-OP isolation build.
// Purpose: verify whether DuoDash conflict comes from HostBubbleFix/probe logic.
// This file intentionally creates no timers, windows, views, hooks, notifications,
// scene enumeration, logging, or runtime mutations.

%ctor {
    // Intentionally empty.
}
