// POXHook v0.5 — 列出 PullOverViewController 所有方法（滚动面板）
// 同时拦截点击，阻断 open，并尝试所有可能的菜单方法

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gDone = NO;
static NSArray *gMenuCandidates = nil;

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

static void show_panel(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil; CGFloat best = 0;
        for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
            if (w.hidden) continue;
            CGFloat a = w.bounds.size.width * w.bounds.size.height;
            if (a > best) { best = a; win = w; }
        }
        if (!win) return;
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 145, win.bounds.size.width, win.bounds.size.height - 320)];
        tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.97];
        tv.textColor = [UIColor greenColor];
        tv.font = [UIFont fontWithName:@"Menlo" size:9.5];
        tv.editable = NO;
        tv.text = text;
        tv.tag = 77771;
        [win addSubview:tv];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(40 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [tv removeFromSuperview]; });
    });
}

// 点击：阻断 open，尝试所有菜单方法
static void hook_tap(id self, SEL _cmd, id handle) {
    // 尝试菜单方法
    NSMutableArray *tried = [NSMutableArray array];
    BOOL ok = NO;
    for (NSString *name in gMenuCandidates) {
        SEL s = NSSelectorFromString(name);
        if (![self respondsToSelector:s]) continue;
        IMP imp = [self methodForSelector:s];
        if (!imp) continue;
        BOOL called = NO;
        @try {
            void (*fn2)(id, SEL, id, BOOL) = (void (*)(id, SEL, id, BOOL))imp;
            fn2(self, s, handle, NO);
            called = YES;
            [tried addObject:[NSString stringWithFormat:@"✓%@(2)", name]];
        } @catch (NSException *e) {
            called = NO;
        }
        if (called) { ok = YES; break; }

        @try {
            void (*fn1)(id, SEL, id) = (void (*)(id, SEL, id))imp;
            fn1(self, s, handle);
            called = YES;
            [tried addObject:[NSString stringWithFormat:@"✓%@(1)", name]];
        } @catch (NSException *e) {
            called = NO;
        }
        if (called) { ok = YES; break; }

        @try {
            void (*fn0)(id, SEL) = (void (*)(id, SEL))imp;
            fn0(self, s);
            called = YES;
            [tried addObject:[NSString stringWithFormat:@"✓%@(0)", name]];
        } @catch (NSException *e) {
            called = NO;
        }
        if (called) { ok = YES; break; }

        [tried addObject:[NSString stringWithFormat:@"✗%@", name]];
    }
    toast(ok ? @"✓ 已调用菜单" : @"✗ 全部失败", ok ? nil : [UIColor redColor], 2);
}

static void install(void) {
    if (gDone) return;
    Class cls = objc_getClass("PullOverViewController");
    if (!cls) { toast(@"找不到类", [UIColor redColor], 4); return; }

    // 枚举所有方法
    unsigned int cnt = 0;
    Method *ms = class_copyMethodList(cls, &cnt);
    NSMutableArray *all = [NSMutableArray array];
    NSMutableArray *menu = [NSMutableArray array];
    for (unsigned int i = 0; i < cnt; i++) {
        NSString *n = NSStringFromSelector(method_getName(ms[i]));
        [all addObject:n];
        if ([n containsString:@"Menu"] || [n containsString:@"menu"] ||
            [n containsString:@"QuickSwitch"] || [n containsString:@"quickSwitch"] ||
            [n containsString:@"Pinned"] || [n containsString:@"pinned"] ||
            [n containsString:@"present"]) {
            [menu addObject:n];
        }
    }
    free(ms);
    gMenuCandidates = menu;

    // 装拦截
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"handle:didReceiveTap:"));
    if (m) method_setImplementation(m, (IMP)hook_tap);

    gDone = YES;

    NSString *txt = [NSString stringWithFormat:@"共 %u 个方法\n\n=== 菜单相关 ===\n%@\n\n=== 全部 ===\n%@",
                     cnt,
                     [menu componentsJoinedByString:@"\n"],
                     [all componentsJoinedByString:@"\n"]];
    show_panel(txt);
    toast([NSString stringWithFormat:@"候选菜单方法 %lu 个", (unsigned long)menu.count], nil, 3);
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ install(); });
    }
}
