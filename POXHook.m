// POXHook v0.4 — 真正实现「点侧边只弹菜单」
// 原理：hook handle:didReceiveTap:，绕过原实现（原实现会调 open 开分屏），
//       改为直接调用 presentMenuAnchoredToHandle:pinned:

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gDone = NO;

static void toast(NSString *msg, UIColor *bg, CGFloat seconds) {
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
        l.font = [UIFont boldSystemFontOfSize:13];
        l.textAlignment = NSTextAlignmentCenter;
        l.text = msg;
        l.numberOfLines = 2;
        [win addSubview:l];
        [win bringSubviewToFront:l];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [l removeFromSuperview]; });
    });
}

// 只弹菜单，不 open
static void show_menu(id self, id handle) {
    SEL sel = NSSelectorFromString(@"presentMenuAnchoredToHandle:pinned:");
    if (![self respondsToSelector:sel]) {
        toast(@"✗ 无 presentMenuAnchoredToHandle:pinned:", [UIColor redColor], 3);
        return;
    }
    IMP imp = [self methodForSelector:sel];
    void (*fn)(id, SEL, id, BOOL) = (void (*)(id, SEL, id, BOOL))imp;
    fn(self, sel, handle, NO);
    toast(@"✓ 已弹菜单（未开分屏）", nil, 2);
}

static void hook_tap(id self, SEL _cmd, id handle) {
    toast(@"点击 → 只弹菜单", [UIColor orangeColor], 1.5);
    show_menu(self, handle);
}

static IMP gOrigTap = NULL;
static IMP gOrigTap2 = NULL;

static void install(void) {
    if (gDone) return;
    Class cls = objc_getClass("PullOverViewController");
    if (!cls) { toast(@"找不到 PullOverViewController", [UIColor redColor], 4); return; }

    // 尝试多个可能的 selector 名称
    NSArray *cands = @[@"handle:didReceiveTap:", @"handleDidReceiveTap:",
                       @"handleTapped:", @"didTapHandle:", @"handleTap:"];
    NSString *found = nil;
    for (NSString *c in cands) {
        Method m = class_getInstanceMethod(cls, NSSelectorFromString(c));
        if (m) { found = c; break; }
    }
    if (!found) {
        // 遍历所有方法找最像的
        unsigned int cnt = 0;
        Method *ms = class_copyMethodList(cls, &cnt);
        for (unsigned int i = 0; i < cnt; i++) {
            NSString *n = NSStringFromSelector(method_getName(ms[i]));
            if ([n containsString:@"Tap"] || [n containsString:@"tap"]) {
                found = n; break;
            }
        }
        free(ms);
    }
    if (!found) { toast(@"✗ 未找到点击方法", [UIColor redColor], 4); return; }

    Method m = class_getInstanceMethod(cls, NSSelectorFromString(found));
    gOrigTap = method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_tap);
    gDone = YES;

    toast([NSString stringWithFormat:@"✓ 拦截 %@", found], nil, 3);
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ install(); });
    }
}
