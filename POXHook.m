// POXHook v0.9 — 自动测试：枚举所有候选方法并报告哪些存在、哪些可调用
// 一次性把结论写在屏幕上，不用反复试错

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gDone = NO;

static UIWindow *mainWindow(void) {
    UIWindow *win = nil; CGFloat best = 0;
    for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
        if (w.hidden) continue;
        CGFloat a = w.bounds.size.width * w.bounds.size.height;
        if (a > best) { best = a; win = w; }
    }
    return win;
}

static void show_result(NSString *text, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = mainWindow();
        if (!win) return;
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 120, win.bounds.size.width, win.bounds.size.height - 260)];
        tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.97];
        tv.textColor = color ?: [UIColor greenColor];
        tv.font = [UIFont fontWithName:@"Menlo" size:10];
        tv.editable = NO;
        tv.text = text;
        [win addSubview:tv];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [tv removeFromSuperview]; });
    });
}

// 列出类的全部方法
static NSArray *all_methods(Class cls) {
    unsigned int cnt = 0;
    Method *ms = class_copyMethodList(cls, &cnt);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned int i = 0; i < cnt; i++) [out addObject:NSStringFromSelector(method_getName(ms[i]))];
    free(ms);
    return out;
}

static NSString *test_run(id self, NSString *selectorName) {
    SEL s = NSSelectorFromString(selectorName);
    if (![self respondsToSelector:s]) return [NSString stringWithFormat:@"✗ %@ (不存在)", selectorName];

    IMP imp = [self methodForSelector:s];
    if (!imp) return [NSString stringWithFormat:@"✗ %@ (IMP空)", selectorName];

    @try {
        ((void (*)(id, SEL))imp)(self, s);
        return [NSString stringWithFormat:@"✓ %@", selectorName];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"⚠ %@ (崩溃:%@)", selectorName, e.reason];
    }
}

static void run_test(id self) {
    NSMutableArray *lines = [NSMutableArray array];
    Class cls = [self class];

    [lines addObject:[NSString stringWithFormat:@"类: %s", class_getName(cls)]];
    [lines addObject:[NSString stringWithFormat:@"父类: %s", class_getName(class_getSuperclass(cls))]];

    // 1. 找所有与"关闭/收起"相关的方法
    NSMutableArray *closeLike = [NSMutableArray array];
    NSMutableArray *menuLike = [NSMutableArray array];
    for (NSString *n in all_methods(cls)) {
        NSString *low = [n lowercaseString];
        if ([low containsString:@"close"] || [low containsString:@"dismiss"] ||
            [low containsString:@"collapse"] || [low containsString:@"hide"] ||
            [low containsString:@"reset"] || [low containsString:@"minim"])
            [closeLike addObject:n];
        if ([low containsString:@"menu"] || [low containsString:@"quickswitch"] ||
            [low containsString:@"pinned"] || [low containsString:@"present"])
            [menuLike addObject:n];
    }

    [lines addObject:@""];
    [lines addObject:@"=== 关闭/收起类 ==="];
    [lines addObjectsFromArray:closeLike];

    [lines addObject:@""];
    [lines addObject:@"=== 菜单类 ==="];
    [lines addObjectsFromArray:menuLike];

    // 2. 自动实测：逐个调用"关闭"类方法，看哪个能收面板
    [lines addObject:@""];
    [lines addObject:@"=== 自动实测 ==="];
    for (NSString *n in closeLike) {
        // 只测无参数的
        if ([n containsString:@":"]) continue;
        [lines addObject:test_run(self, n)];
    }

    show_result([lines componentsJoinedByString:@"\n"], [UIColor greenColor]);
}

static void hook_tap(id self, SEL _cmd, id handle) {
    run_test(self);
}

static void install(void) {
    if (gDone) return;
    Class cls = objc_getClass("PullOverViewController");
    if (!cls) { show_result(@"找不到 PullOverViewController", [UIColor redColor]); return; }
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"handle:didReceiveTap:"));
    if (!m) { show_result(@"找不到点击方法", [UIColor redColor]); return; }
    method_setImplementation(m, (IMP)hook_tap);
    gDone = YES;

    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"✓ 自动测试器已启用\n\n"];
    [info appendFormat:@"点一下侧边开始测试\n\n"];
    [info appendFormat:@"方法总数: %lu", (unsigned long)all_methods(cls).count];
    show_result(info, nil);
}

__attribute__((constructor))
static void pox_init(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ install(); });
    }
}
