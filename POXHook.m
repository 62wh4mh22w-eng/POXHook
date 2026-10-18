// POXHook — 诊断 + 修正 PullOver-X 点击行为
// 不修改 POX 本体，只通过 runtime hook 挂上去。
// 目标：点侧边 -> 只弹菜单，不自动开分屏。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static BOOL gDidPatch = NO;

// ---------- 可见诊断条 ----------
static void pox_show_toast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil;
        for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
            if (!w.hidden && w.windowLevel < UIWindowLevelAlert) { win = w; break; }
        }
        if (!win) return;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 80, win.bounds.size.width, 44)];
        l.backgroundColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:0.92];
        l.textColor = [UIColor blackColor];
        l.font = [UIFont boldSystemFontOfSize:14];
        l.textAlignment = NSTextAlignmentCenter;
        l.text = msg;
        l.numberOfLines = 2;
        [win addSubview:l];
        [win bringSubviewToFront:l];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [l removeFromSuperview]; });
    });
}

// ---------- hook: handle:didReceiveTap: ----------
static void (*orig_tap)(id, SEL, id);

static void hook_tap(id self, SEL _cmd, id handle) {
    pox_show_toast(@"POXHook 捕获点击 → 弹菜单");

    // 1) 先调用原方法（保留原行为基线）
    // 2) 再额外弹菜单
    if (orig_tap) orig_tap(self, _cmd, handle);

    SEL present = NSSelectorFromString(@"presentMenuAnchoredToHandle:pinned:");
    if ([self respondsToSelector:present]) {
        IMP imp = [self methodForSelector:present];
        if (imp) {
            void (*fn)(id, SEL, id, BOOL) = (void (*)(id, SEL, id, BOOL))imp;
            fn(self, present, handle, NO);
            pox_show_toast(@"POXHook 已调用菜单");
        } else {
            pox_show_toast(@"POXHook: 方法存在但 IMP 为空");
        }
    } else {
        pox_show_toast(@"POXHook: POX 无该菜单方法");
    }
}

static void pox_try_patch(void) {
    if (gDidPatch) return;
    Class cls = objc_getClass("PullOverXController");
    if (!cls) {
        // 类名猜不到就扫一遍
        unsigned int count = 0;
        Class *list = objc_copyClassList(&count);
        for (unsigned int i = 0; i < count; i++) {
            const char *n = class_getName(list[i]);
            if (!n) continue;
            NSString *name = [NSString stringWithUTF8String:n];
            if ([name hasPrefix:@"PullOver"] || [name hasPrefix:@"POX"]) {
                Method m = class_getInstanceMethod(list[i], NSSelectorFromString(@"handle:didReceiveTap:"));
                if (m) { cls = list[i]; break; }
            }
        }
        free(list);
    }
    if (!cls) { pox_show_toast(@"POXHook: 未找到 POX 控制器类"); return; }

    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"handle:didReceiveTap:"));
    if (!m) { pox_show_toast(@"POXHook: 未找到点击方法"); return; }

    orig_tap = (void (*)(id, SEL, id))method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_tap);
    gDidPatch = YES;

    pox_show_toast([NSString stringWithFormat:@"POXHook 已挂载: %s", class_getName(cls)]);
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ pox_try_patch(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ pox_try_patch(); });
    }
}
