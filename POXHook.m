// POXHook v0.8 — 点侧边：open 之后立刻收回分屏，只留菜单
// 依据方法列表：presentPinnedQuickSwitchAfterOpen / dismissCurrentQuickSwitchAnimated:
//              animatePanelToOffset:opening: / closePanel ...

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gDone = NO;
static IMP gOrigOpen = NULL;

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

static IMP imp_of(id obj, NSString *name) {
    SEL s = NSSelectorFromString(name);
    if (![obj respondsToSelector:s]) return NULL;
    return [obj methodForSelector:s];
}

// 关闭分屏面板，但保留菜单
static void close_panel_keep_menu(id self) {
    // 1) 先把菜单弹出来（锚在把手位置）
    IMP p = imp_of(self, @"presentPinnedQuickSwitchAfterOpen");
    if (p) ((void (*)(id, SEL))p)(self, NSSelectorFromString(@"presentPinnedQuickSwitchAfterOpen"));

    // 2) 收起面板（分屏）
    IMP c = imp_of(self, @"closePanel");
    if (c) {
        ((void (*)(id, SEL))c)(self, NSSelectorFromString(@"closePanel"));
        toast(@"✓ closePanel", nil, 2.5);
        return;
    }
    IMP c2 = imp_of(self, @"closePanelAnimated:");
    if (c2) {
        ((void (*)(id, SEL, BOOL))c2)(self, NSSelectorFromString(@"closePanelAnimated:"), NO);
        toast(@"✓ closePanelAnimated", nil, 2.5);
        return;
    }
    IMP c3 = imp_of(self, @"collpasePanel");
    if (c3) { ((void (*)(id, SEL))c3)(self, NSSelectorFromString(@"collpasePanel")); return; }
    IMP c4 = imp_of(self, @"dismissPanel");
    if (c4) { ((void (*)(id, SEL))c4)(self, NSSelectorFromString(@"dismissPanel")); return; }

    toast(@"✗ 没找到关闭面板的方法", [UIColor redColor], 4);
}

static void hook_open(id self, SEL _cmd) {
    // 执行原 open（分屏会出来）
    if (gOrigOpen) ((void (*)(id, SEL))gOrigOpen)(self, _cmd);

    // 马上弹菜单 + 收面板
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        close_panel_keep_menu(self);
    });
}

static void install(void) {
    if (gDone) return;
    Class cls = objc_getClass("PullOverViewController");
    if (!cls) { toast(@"找不到类", [UIColor redColor], 4); return; }

    Method mo = class_getInstanceMethod(cls, NSSelectorFromString(@"open"));
    if (mo) {
        gOrigOpen = method_getImplementation(mo);
        method_setImplementation(mo, (IMP)hook_open);
    }

    gDone = YES;
    toast([NSString stringWithFormat:@"✓ v0.8 已启用 (open=%@)", mo ? @"有" : @"无"], nil, 3);
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ install(); });
    }
}
