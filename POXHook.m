// POXHook v0.2 — 枚举 + 全量 hook 探针
// 目标：找出点侧边真正触发的方法

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gPatched = NO;
static NSMutableArray *gHooked = nil;

// ---------- 顶部提示 ----------
static void toast(NSString *msg, UIColor *bg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil;
        CGFloat best = 0;
        for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
            if (w.hidden) continue;
            CGFloat a = w.bounds.size.width * w.bounds.size.height;
            if (a > best) { best = a; win = w; }
        }
        if (!win) return;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, win.bounds.size.width, 40)];
        l.backgroundColor = bg ?: [UIColor colorWithRed:0.15 green:0.85 blue:0.3 alpha:0.95];
        l.textColor = [UIColor blackColor];
        l.font = [UIFont boldSystemFontOfSize:13];
        l.textAlignment = NSTextAlignmentCenter;
        l.text = msg;
        [win addSubview:l];
        [win bringSubviewToFront:l];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [l removeFromSuperview]; });
    });
}

// ---------- 通用 hook ----------
static void (*gOrig)(id, SEL, ...) = NULL;

static void generic_hook(id self, SEL _cmd, ...) {
    NSString *name = NSStringFromSelector(_cmd);
    toast([NSString stringWithFormat:@"命中: %@", name], nil);
    NSLog(@"[POXHook] HIT %@", name);
}

static void patch_method(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP old = method_getImplementation(m);
    if (old == (IMP)generic_hook) return;
    method_setImplementation(m, (IMP)generic_hook);
    if (!gHooked) gHooked = [NSMutableArray array];
    [gHooked addObject:NSStringFromSelector(sel)];
}

static void pox_patch(void) {
    if (gPatched) return;
    Class cls = objc_getClass("PullOverViewController");
    if (!cls) { toast(@"找不到 PullOverViewController", [UIColor redColor]); return; }

    // 枚举所有方法，凡是名字里带 tap/pan/handle/longpress/gesture 的全都挂上
    unsigned int count = 0;
    Method *ms = class_copyMethodList(cls, &count);
    NSMutableArray *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *n = NSStringFromSelector(method_getName(ms[i]));
        [names addObject:n];
        BOOL hit = NO;
        for (NSString *k in @[@"Tap", @"tap", @"Pan", @"pan", @"handle:", @"LongPress", @"Gesture", @"gesture"]) {
            if ([n rangeOfString:k].location != NSNotFound) { hit = YES; break; }
        }
        if (hit) patch_method(cls, method_getName(ms[i]));
    }
    free(ms);

    gPatched = YES;
    NSLog(@"[POXHook] all methods: %@", names);
    toast([NSString stringWithFormat:@"已挂 %lu 个方法（共 %u）",
           (unsigned long)gHooked.count, count], nil);

    // 同时打印方法全名到屏幕（分屏显示）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *win = nil; CGFloat best = 0;
        for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
            if (w.hidden) continue;
            CGFloat a = w.bounds.size.width * w.bounds.size.height;
            if (a > best) { best = a; win = w; }
        }
        if (!win) return;
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 140, win.bounds.size.width, 260)];
        tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        tv.textColor = [UIColor greenColor];
        tv.font = [UIFont fontWithName:@"Menlo" size:9];
        tv.editable = NO;
        tv.text = [names componentsJoinedByString:@"\n"];
        [win addSubview:tv];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [tv removeFromSuperview]; });
    });
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ pox_patch(); });
    }
}
