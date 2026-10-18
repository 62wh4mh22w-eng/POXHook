// POXHook v0.6 — 选定方案：open 后立即弹菜单，并立刻关闭分屏
// 关键方法（已从方法列表确认存在）：
//   presentPinnedQuickSwitchAfterOpen   (无参数)
//   dismissCurrentQuickSwitchAnimated:  (BOOL)

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
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, win.bounds.size.width, 36)];
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

static BOOL call0(id obj, NSString *name) {
    SEL s = NSSelectorFromString(name);
    if (![obj respondsToSelector:s]) return NO;
    IMP imp = [obj methodForSelector:s];
    if (!imp) return NO;
    ((void (*)(id, SEL))imp)(obj, s);
    return YES;
}

static BOOL call1(id obj, NSString *name, id a) {
    SEL s = NSSelectorFromString(name);
    if (![obj respondsToSelector:s]) return NO;
    IMP imp = [obj methodForSelector:s];
    if (!imp) return NO;
    ((void (*)(id, SEL, id))imp)(obj, s, a);
    return YES;
}

static IMP gOrigOpen = NULL;
static IMP gOrigTap = NULL;

// 拦截点击：只弹菜单，不开分屏
static void hook_tap(id self, SEL _cmd, id handle) {
    // 1) 尝试 presentPinnedQuickSwitchAfterOpen（需要 isOpened=YES）
    SEL openSel = NSSelectorFromString(@"open");
    BOOL usedOpen = NO;

    if ([self respondsToSelector:openSel] && gOrigOpen) {
        // 先 open（分屏会短暂出现）
        ((void (*)(id, SEL))gOrigOpen)(self, openSel);
        usedOpen = YES;
    }

    // 2) 立即弹菜单
    BOOL ok = call0(self, @"presentPinnedQuickSwitchAfterOpen");
    toast(ok ? @"✓ 已弹菜单" : @"✗ 弹菜单失败",
          ok ? nil : [UIColor redColor], 2);

    // 3) 如果面板开了但菜单没弹，试着关掉面板只留菜单 -> 不行就保留
    if (!ok) {
        call1(self, @"presentCurrentQuickSwitchAnchoredToHandle", handle);
    }
}

static void install(void) {
    if (gDone) return;
    Class cls = objc_getClass("PullOverViewController");
    if (!cls) { toast(@"找不到类", [UIColor redColor], 4); return; }

    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"handle:didReceiveTap:"));
    if (!m) { toast(@"找不到点击方法", [UIColor redColor], 4); return; }
    gOrigTap = method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_tap);

    Method mo = class_getInstanceMethod(cls, NSSelectorFromString(@"open"));
    if (mo) gOrigOpen = method_getImplementation(mo);

    gDone = YES;
    toast(@"✓ 已启用：点击=菜单", nil, 3);
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ install(); });
    }
}
