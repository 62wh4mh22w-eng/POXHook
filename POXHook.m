// POXHook v0.7 — 直接调 layoutMenu，绕过 open
// 目标：点侧边 -> 只弹菜单，不打开分屏

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gDone = NO;

static void toast(NSString *msg, UIColor *bg, CGFloat sec) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil; CGFloat best = 0;
        for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
            if (w.hidden) continue;
            CGFloat a = w.bounds.size.width * w.bounds.size.height;
            if (a > best) { best = a; win = w; }
        }
        if (!win) return;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, win.bounds.size.width, 40)];
        l.backgroundColor = bg ?: [UIColor colorWithRed:0.15 green:0.85 blue:0.3 alpha:0.95];
        l.textColor = [UIColor blackColor];
        l.font = [UIFont boldSystemFontOfSize:12];
        l.textAlignment = NSTextAlignmentCenter;
        l.text = msg;
        l.numberOfLines = 2;
        [win addSubview:l];
        [win bringSubviewToFront:l];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [l removeFromSuperview]; });
    });
}

// 直接用 objc_msgSend 发消息（不检查 respondsToSelector）
static void send_void3(id obj, SEL sel, id a1, BOOL a2, double a3) {
    typedef void (*Fn)(id, SEL, id, BOOL, double);
    ((Fn)objc_msgSend)(obj, sel, a1, a2, a3);
}

static void hook_tap(id self, SEL _cmd, id handle) {
    SEL layout = NSSelectorFromString(@"layoutMenuAnchoredToHandle:pinned:remainingOffset:coordinated");
    SEL present = NSSelectorFromString(@"presentMenuAnchoredToHandle:pinned:");

    // 方案 A: 直接调 presentMenu（2 参数）
    if ([self respondsToSelector:present]) {
        typedef void (*Fn)(id, SEL, id, BOOL);
        ((Fn)objc_msgSend)(self, present, handle, NO);
        toast(@"✓ A: presentMenu 已调用", nil, 3);
        return;
    }

    // 方案 B: 直接调 layoutMenu（4 参数）
    if ([self respondsToSelector:layout]) {
        send_void3(self, layout, handle, NO, 0.0);
        toast(@"✓ B: layoutMenu 已调用", nil, 3);
        return;
    }

    // 方案 C: 两个都不认，把 respondsToSelector 结果报出来
    toast([NSString stringWithFormat:@"✗ A=%@ B=%@",
           [self respondsToSelector:present] ? @"有" : @"无",
           [self respondsToSelector:layout] ? @"有" : @"无"], [UIColor redColor], 5);
}

static void install(void) {
    if (gDone) return;
    Class cls = objc_getClass("PullOverViewController");
    if (!cls) { toast(@"找不到类", [UIColor redColor], 4); return; }

    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"handle:didReceiveTap:"));
    if (!m) { toast(@"找不到点击方法", [UIColor redColor], 4); return; }
    method_setImplementation(m, (IMP)hook_tap);

    gDone = YES;
    toast(@"✓ v0.7 已启用", nil, 3);
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ install(); });
    }
}
