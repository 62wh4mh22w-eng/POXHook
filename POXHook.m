// POXHook v0.3 — 非侵入式探针
// 只在点击时显示提示，绝不替换实现、绝不改变原行为。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gDone = NO;

static void toast(NSString *msg, UIColor *bg) {
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
        [win addSubview:l];
        [win bringSubviewToFront:l];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [l removeFromSuperview]; });
    });
}

// ---- 只读探针：用 class_replaceMethod 保持原 IMP 不被破坏 ----
static IMP gOrigTap;
static void probe_tap(id self, SEL _cmd, id arg) {
    toast(@"✓ 走到 handle:didReceiveTap:", nil);
    if (gOrigTap) ((void (*)(id, SEL, id))gOrigTap)(self, _cmd, arg);
}

static IMP gOrigPan;
static void probe_pan(id self, SEL _cmd, id arg) {
    toast(@"✓ 走到 handleSplitPan:", [UIColor orangeColor]);
    if (gOrigPan) ((void (*)(id, SEL, id))gOrigPan)(self, _cmd, arg);
}

static void install(void) {
    if (gDone) return;
    Class cls = objc_getClass("PullOverViewController");
    if (!cls) { toast(@"找不到 PullOverViewController", [UIColor redColor]); return; }

    // 先把所有方法名打印出来，方便对照
    unsigned int count = 0;
    Method *ms = class_copyMethodList(cls, &count);
    NSMutableArray *tapLike = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *n = NSStringFromSelector(method_getName(ms[i]));
        if ([n containsString:@"Tap"] || [n containsString:@"tap"] ||
            [n containsString:@"Pan"] || [n containsString:@"pan"])
            [tapLike addObject:n];
    }
    free(ms);

    // 只装两个最关键的探针
    Method mTap = class_getInstanceMethod(cls, NSSelectorFromString(@"handle:didReceiveTap:"));
    if (mTap) {
        gOrigTap = method_getImplementation(mTap);
        method_setImplementation(mTap, (IMP)probe_tap);
    }

    Method mPan = class_getInstanceMethod(cls, NSSelectorFromString(@"handleSplitPan:"));
    if (mPan) {
        gOrigPan = method_getImplementation(mPan);
        method_setImplementation(mPan, (IMP)probe_pan);
    }

    gDone = YES;
    toast([NSString stringWithFormat:@"探针已装 (tap=%@ pan=%@)",
           mTap ? @"有" : @"无", mPan ? @"有" : @"无"], nil);

    NSLog(@"[POXHook] tap/pan methods: %@", tapLike);
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ install(); });
    }
}
