// mcp-notify: Daemon + Unix Socket notification server
// Compile: clang -fobjc-arc -framework Foundation -framework AppKit -framework QuartzCore
//          -framework CoreGraphics -o mcp-notify main.m

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <sys/socket.h>
#import <sys/un.h>

// ── Constants ─────────────────────────────────────────────────────────────────

static const CGFloat kWindowWidth    = 380.0;
static const CGFloat kWindowHeight   = 100.0;
static const CGFloat kWindowSpacing  = 8.0;
static const CGFloat kMarginRight    = 16.0;
static const CGFloat kMarginTop      = 16.0;
static const CGFloat kCornerRadius   = 24.0;
static const CGFloat kIconSize       = 64.0;
static const CGFloat kSwipeDismissThreshold = 80.0;
static const NSTimeInterval kDefaultDuration = 5.0;
static const NSTimeInterval kAnimDuration    = 0.35;

static NSString *const kSocketPath = @"/tmp/mcp-notify.sock";

// ── Borderless key window (必须覆盖 canBecomeKeyWindow 才能接收鼠标事件) ─────

@interface BorderlessKeyWindow : NSWindow
@property (assign) CGFloat targetX;
@end

@implementation BorderlessKeyWindow {
    NSPoint _dragStart;
    BOOL _isDragging;
}
- (BOOL)canBecomeKeyWindow  { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }

- (void)sendEvent:(NSEvent *)event {
    switch (event.type) {
        case NSEventTypeLeftMouseDown: {
            _dragStart = [NSEvent mouseLocation];
            _isDragging = NO;
            // 按下柔和缩放（spring 动画）
            CASpringAnimation *press = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
            press.fromValue = @1.0;
            press.toValue   = @1.015;
            press.mass      = 1.0;
            press.stiffness = 300.0;
            press.damping   = 20.0;
            press.duration  = press.settlingDuration;
            press.fillMode  = kCAFillModeForwards;
            press.removedOnCompletion = NO;
            self.contentView.layer.transform = CATransform3DMakeScale(1.015, 1.015, 1.0);
            [self.contentView.layer addAnimation:press forKey:@"press"];
            return;
        }

        case NSEventTypeLeftMouseDragged: {
            NSPoint current = [NSEvent mouseLocation];
            CGFloat dx = current.x - _dragStart.x;
            if (fabs(dx) > 3) _isDragging = YES;

            if (_isDragging) {
                // 允许向左拖一点点（弹性感），但主要向右
                CGFloat offsetX = dx;
                if (dx < 0) offsetX = dx * 0.3; // 左拖有阻尼

                NSRect frame = self.frame;
                frame.origin.x = self.targetX + offsetX;
                [self setFrame:frame display:YES];

                // 只在向右拖时降低透明度
                CGFloat alpha = dx > 0 ? MAX(0.4, 1.0 - dx / 200.0) : 1.0;
                self.contentView.layer.opacity = (float)alpha;
                return;
            }
            break;
        }

        case NSEventTypeLeftMouseUp: {
            // 恢复缩放（spring 回弹）
            [self.contentView.layer removeAnimationForKey:@"press"];
            CASpringAnimation *release = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
            release.fromValue = @1.015;
            release.toValue   = @1.0;
            release.mass      = 1.0;
            release.stiffness = 300.0;
            release.damping   = 15.0;
            release.duration  = release.settlingDuration;
            release.fillMode  = kCAFillModeForwards;
            release.removedOnCompletion = NO;
            self.contentView.layer.transform = CATransform3DIdentity;
            [self.contentView.layer addAnimation:release forKey:@"release"];

            if (_isDragging) {
                NSPoint current = [NSEvent mouseLocation];
                CGFloat dx = current.x - _dragStart.x;
                if (dx > kSwipeDismissThreshold) {
                    [[NSNotificationCenter defaultCenter]
                     postNotificationName:@"MCPDismissWindow" object:self];
                } else {
                    // 弹回原位
                    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
                        ctx.duration = 0.25;
                        NSRect f = self.frame;
                        f.origin.x = self.targetX;
                        f.origin.y = self.frame.origin.y;
                        [[self animator] setFrame:f display:YES];
                    } completionHandler:nil];
                    self.contentView.layer.opacity = 1.0;
                }
                _isDragging = NO;
                return;
            }
            // 点击
            [[NSNotificationCenter defaultCenter]
             postNotificationName:@"MCPClickWindow" object:self];
            return;
        }

        default:
            break;
    }
    [super sendEvent:event];
}
@end

// ── Forward declarations ──────────────────────────────────────────────────────

@class NotifyWindowController;

// ── Window manager (singleton) ────────────────────────────────────────────────

@interface NotifyManager : NSObject
@property (strong) NSMutableArray<NotifyWindowController *> *controllers;
+ (instancetype)shared;
- (void)addController:(NotifyWindowController *)c;
- (void)removeController:(NotifyWindowController *)c;
- (void)rearrange;
- (CGFloat)nextTargetYOnScreen:(NSScreen *)screen;
- (NotifyWindowController *)findByNotifyId:(NSString *)nid;
- (NotifyWindowController *)findByTaskId:(NSString *)taskId;
- (NotifyWindowController *)findByGroup:(NSString *)group;
@end

// ── Draggable content view (interface only — implementation after NotifyWindowController) ──

@interface DraggableView : NSView
@property (weak) NotifyWindowController *controller;
@property (assign) NSPoint dragStart;
@property (assign) BOOL dragging;
@end

// ── Notification window controller ───────────────────────────────────────────

@interface NotifyWindowController : NSObject
@property (copy)   NSString    *notifyId;
@property (copy)   NSString    *taskId;
@property (copy)   NSString    *group;
@property (strong) NSWindow    *panel;
@property (strong) NSImageView *appIconView;
@property (strong) NSView      *contentView;
@property (strong) NSTextField *titleField;
@property (strong) NSTextField *msgField;
@property (copy)   NSString    *activateBundleId;
@property (assign) CGFloat      targetX;
@property (assign) CGFloat      targetY;
@property (assign) BOOL         isDismissed;
@property (assign) BOOL         persistent;

- (instancetype)initWithParams:(NSDictionary *)params;
- (void)show;
- (void)updateTitle:(NSString *)title message:(NSString *)message;
- (void)dismiss;
- (void)moveToY:(CGFloat)newY animated:(BOOL)animated;
@end

// ── NotifyManager ─────────────────────────────────────────────────────────────

@implementation NotifyManager

+ (instancetype)shared {
    static NotifyManager *inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [[NotifyManager alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) _controllers = [NSMutableArray array];
    return self;
}

- (void)addController:(NotifyWindowController *)c {
    [_controllers addObject:c];
}

- (void)removeController:(NotifyWindowController *)c {
    [_controllers removeObject:c];
    [self rearrange];
}

// 重新排列：从上到下按顺序排列所有活跃通知
- (void)rearrange {
    NSScreen *screen = [self activeScreen];
    NSRect visibleFrame = screen.visibleFrame;
    CGFloat baseY = NSMaxY(visibleFrame) - kWindowHeight - kMarginTop;

    for (NSInteger i = 0; i < (NSInteger)_controllers.count; i++) {
        NotifyWindowController *c = _controllers[i];
        CGFloat newY = baseY - i * (kWindowHeight + kWindowSpacing);
        c.targetY = newY;
        [c moveToY:newY animated:YES];
    }
}

- (CGFloat)nextTargetYOnScreen:(NSScreen *)screen {
    NSRect visibleFrame = screen.visibleFrame;
    CGFloat baseY = NSMaxY(visibleFrame) - kWindowHeight - kMarginTop;
    NSInteger count = (NSInteger)_controllers.count;
    CGFloat y = baseY - count * (kWindowHeight + kWindowSpacing);
    FILE *f = fopen("/tmp/mcp-notify-debug.log", "a");
    if (f) { fprintf(f, "nextTargetY: count=%ld baseY=%.0f y=%.0f\n", (long)count, baseY, y); fflush(f); fclose(f); }
    return y;
}

- (NSScreen *)activeScreen {
    NSPoint mouseLoc = [NSEvent mouseLocation];
    for (NSScreen *s in [NSScreen screens]) {
        if (NSPointInRect(mouseLoc, s.frame)) return s;
    }
    return [NSScreen mainScreen];
}

- (NotifyWindowController *)findByNotifyId:(NSString *)nid {
    for (NotifyWindowController *c in _controllers) {
        if ([c.notifyId isEqualToString:nid]) return c;
    }
    return nil;
}

- (NotifyWindowController *)findByTaskId:(NSString *)taskId {
    for (NotifyWindowController *c in _controllers) {
        if ([c.taskId isEqualToString:taskId]) return c;
    }
    return nil;
}

- (NotifyWindowController *)findByGroup:(NSString *)group {
    // Returns first match; dismiss-group iterates all
    for (NotifyWindowController *c in _controllers) {
        if ([c.group isEqualToString:group]) return c;
    }
    return nil;
}

@end

// ── NotifyWindowController implementation ────────────────────────────────────

@implementation NotifyWindowController

- (instancetype)initWithParams:(NSDictionary *)params {
    self = [super init];
    if (!self) return nil;

    self.notifyId         = params[@"id"] ?: [[NSUUID UUID] UUIDString];
    self.taskId           = params[@"taskId"];
    self.group            = params[@"group"];
    self.activateBundleId = params[@"activate"];
    self.isDismissed      = NO;
    self.persistent       = [params[@"persistent"] boolValue];

    NSScreen *screen = [NotifyManager.shared activeScreen];
    NSRect visibleFrame = screen.visibleFrame;

    CGFloat targetX = NSMaxX(visibleFrame) - kWindowWidth - kMarginRight;
    CGFloat targetY = [NotifyManager.shared nextTargetYOnScreen:screen];
    self.targetX = targetX;
    self.targetY = targetY;

    // 同步给窗口（用于 sendEvent 拖拽计算）

    // Start offscreen right
    CGFloat startX = NSMaxX(visibleFrame) + kWindowWidth;
    NSRect startFrame = NSMakeRect(startX, targetY, kWindowWidth, kWindowHeight);

    self.panel = [[BorderlessKeyWindow alloc] initWithContentRect:startFrame
                                             styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    ((BorderlessKeyWindow *)self.panel).targetX = targetX;
    self.panel.level = NSStatusWindowLevel;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = NO;
    self.panel.ignoresMouseEvents = NO;
    [self.panel setAcceptsMouseMovedEvents:YES];
    [self.panel setMovableByWindowBackground:NO];
    [self.panel setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                      NSWindowCollectionBehaviorStationary |
                                      NSWindowCollectionBehaviorIgnoresCycle];

    NSView *contentView = self.panel.contentView;
    contentView.wantsLayer = YES;
    self.contentView = contentView;

    // 自定义阴影
    contentView.layer.shadowColor   = NSColor.blackColor.CGColor;
    contentView.layer.shadowOpacity = 0.4;
    contentView.layer.shadowRadius  = 20.0;
    contentView.layer.shadowOffset  = CGSizeMake(0, -4);

    NSRect bounds = NSMakeRect(0, 0, kWindowWidth, kWindowHeight);

    // 毛玻璃
    NSVisualEffectView *blur = [[NSVisualEffectView alloc] initWithFrame:bounds];
    blur.material     = NSVisualEffectMaterialHUDWindow;
    blur.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    blur.state        = NSVisualEffectStateActive;
    blur.wantsLayer   = YES;
    blur.layer.cornerRadius  = kCornerRadius;
    blur.layer.masksToBounds = YES;
    blur.autoresizingMask    = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:blur];

    // 深蓝叠加
    NSView *tint = [[NSView alloc] initWithFrame:bounds];
    tint.wantsLayer = YES;
    tint.layer.backgroundColor =
        [NSColor colorWithRed:4.0/255.0 green:24.0/255.0 blue:77.0/255.0 alpha:0.70].CGColor;
    tint.layer.cornerRadius  = kCornerRadius;
    tint.layer.masksToBounds = YES;
    tint.autoresizingMask    = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:tint];

    // 描边
    CAShapeLayer *border = [CAShapeLayer layer];
    border.frame       = bounds;
    border.path        = CGPathCreateWithRoundedRect(bounds, kCornerRadius, kCornerRadius, NULL);
    border.fillColor   = NULL;
    border.strokeColor = [NSColor colorWithWhite:1.0 alpha:0.15].CGColor;
    border.lineWidth   = 1.0;
    [contentView.layer addSublayer:border];

    // 底部微光
    CAGradientLayer *bottomGlow = [CAGradientLayer layer];
    bottomGlow.frame      = CGRectMake(0, 0, kWindowWidth, 1.0);
    bottomGlow.startPoint = CGPointMake(0, 0.5);
    bottomGlow.endPoint   = CGPointMake(1, 0.5);
    bottomGlow.colors = @[
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.45].CGColor,
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.0].CGColor,
    ];
    [contentView.layer addSublayer:bottomGlow];

    // App 图标
    CGFloat padding  = 12.0;
    CGFloat iconLeft = padding;
    CGFloat iconY    = (kWindowHeight - kIconSize) / 2.0;

    NSString *appIconPath = [[NSBundle mainBundle] pathForResource:@"notify-logo" ofType:@"png"];
    if (!appIconPath) appIconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
    NSImage *appIcon = appIconPath ? [[NSImage alloc] initByReferencingFile:appIconPath] : nil;
    if (appIcon) {
        NSImageView *iv = [[NSImageView alloc] initWithFrame:
                           NSMakeRect(iconLeft, iconY, kIconSize, kIconSize)];
        iv.image = appIcon;
        iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        iv.wantsLayer = YES;
        iv.layer.opacity   = 0.0;
        iv.layer.transform = CATransform3DMakeScale(0.5, 0.5, 1.0);
        [contentView addSubview:iv];
        self.appIconView = iv;
    }

    // 文字区域
    CGFloat textLeft  = iconLeft + kIconSize + 10.0;
    CGFloat textRight = kWindowWidth - padding;
    CGFloat textWidth = textRight - textLeft;

    NSString *title    = params[@"title"] ?: @"";
    NSString *message  = params[@"message"] ?: @"";
    NSString *subtitle = params[@"subtitle"];
    NSString *iconPath = params[@"icon"];

    BOOL    hasSubtitle   = (subtitle.length > 0);
    CGFloat titleSize     = 14.0;
    CGFloat subtitleSize  = 12.0;
    CGFloat messageSize   = 13.0;
    CGFloat brandIconSize = 18.0;

    CGFloat lineH  = titleSize + 4.0;
    CGFloat subH   = hasSubtitle ? (subtitleSize + 3.0) : 0.0;
    CGFloat msgH   = messageSize + 4.0;
    CGFloat totalH = lineH + subH + msgH;
    CGFloat textTop = (kWindowHeight + totalH) / 2.0;
    CGFloat curY = textTop;

    // Title 行：[品牌图标] 标题
    curY -= lineH;
    CGFloat titleX = textLeft;
    BOOL hasBrandIcon = (iconPath.length > 0);
    if (hasBrandIcon) {
        NSImage *brandIcon = [[NSImage alloc] initByReferencingFile:iconPath];
        if (brandIcon) {
            CGFloat brandY = curY + (lineH - brandIconSize) / 2.0;
            NSImageView *brandView = [[NSImageView alloc] initWithFrame:
                                      NSMakeRect(titleX, brandY, brandIconSize, brandIconSize)];
            brandView.image = brandIcon;
            brandView.imageScaling = NSImageScaleProportionallyUpOrDown;
            [contentView addSubview:brandView];
            titleX += brandIconSize + 4.0;
        }
    }
    NSTextField *titleField = [NSTextField labelWithString:title];
    titleField.frame = NSMakeRect(titleX, curY, textRight - titleX, lineH);
    titleField.font  = [NSFont boldSystemFontOfSize:titleSize];
    titleField.textColor = NSColor.whiteColor;
    titleField.backgroundColor = NSColor.clearColor;
    titleField.drawsBackground = NO;
    titleField.lineBreakMode = NSLineBreakByTruncatingTail;
    [contentView addSubview:titleField];
    self.titleField = titleField;

    if (hasSubtitle) {
        curY -= subH;
        NSTextField *subField = [NSTextField labelWithString:subtitle];
        subField.frame = NSMakeRect(textLeft, curY, textWidth, subH);
        subField.font  = [NSFont systemFontOfSize:subtitleSize];
        subField.textColor = [NSColor colorWithWhite:0.75 alpha:1.0];
        subField.backgroundColor = NSColor.clearColor;
        subField.drawsBackground = NO;
        subField.lineBreakMode = NSLineBreakByTruncatingTail;
        [contentView addSubview:subField];
    }

    curY -= msgH;
    NSTextField *msgField = [NSTextField labelWithString:message];
    msgField.frame = NSMakeRect(textLeft, curY, textWidth, msgH);
    msgField.font  = [NSFont systemFontOfSize:messageSize];
    msgField.textColor = NSColor.whiteColor;
    msgField.backgroundColor = NSColor.clearColor;
    msgField.drawsBackground = NO;
    msgField.lineBreakMode = NSLineBreakByTruncatingTail;
    [contentView addSubview:msgField];
    self.msgField = msgField;

    // 监听窗口级别的点击和拖拽dismiss
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(windowDismissed:) name:@"MCPDismissWindow" object:self.panel];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(windowClicked:) name:@"MCPClickWindow" object:self.panel];

    return self;
}

// ── update ────────────────────────────────────────────────────────────────────

- (void)updateTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (title)   self.titleField.stringValue = title;
        if (message) self.msgField.stringValue   = message;
    });
}

// ── Effects ───────────────────────────────────────────────────────────────────

- (void)playShimmer {
    CALayer *root = self.contentView.layer;
    CGFloat W = kWindowWidth, H = kWindowHeight, sw = W * 0.4;

    CAGradientLayer *shimmer = [CAGradientLayer layer];
    shimmer.frame = CGRectMake(-sw, 0, sw, H);
    shimmer.startPoint = CGPointMake(0, 0.5);
    shimmer.endPoint   = CGPointMake(1, 0.5);
    shimmer.colors = @[
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.18].CGColor,
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.0].CGColor,
    ];
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = CGPathCreateWithRoundedRect(CGRectMake(0,0,W,H), kCornerRadius, kCornerRadius, NULL);
    shimmer.mask = mask;
    [root addSublayer:shimmer];

    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"position.x"];
    anim.fromValue = @(-sw / 2.0);
    anim.toValue   = @(W + sw / 2.0);
    anim.duration  = 0.65;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    anim.fillMode  = kCAFillModeForwards;
    anim.removedOnCompletion = NO;
    [shimmer addAnimation:anim forKey:@"sweep"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [shimmer removeFromSuperlayer]; });
}

- (void)playIconSpringIn {
    if (!self.appIconView) return;
    CALayer *iconLayer = self.appIconView.layer;

    CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeIn.fromValue = @0.0; fadeIn.toValue = @1.0;
    fadeIn.duration = 0.25;
    fadeIn.fillMode = kCAFillModeForwards; fadeIn.removedOnCompletion = NO;

    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    spring.fromValue = @0.5; spring.toValue = @1.0;
    spring.mass = 1.0; spring.stiffness = 200.0; spring.damping = 14.0;
    spring.duration = spring.settlingDuration;
    spring.fillMode = kCAFillModeForwards; spring.removedOnCompletion = NO;

    iconLayer.opacity   = 1.0;
    iconLayer.transform = CATransform3DIdentity;
    [iconLayer addAnimation:fadeIn  forKey:@"iconFade"];
    [iconLayer addAnimation:spring forKey:@"iconSpring"];
}

// ── Show / Dismiss / Move ─────────────────────────────────────────────────────

- (void)show {
    [self showWithDuration:kDefaultDuration];
}

- (void)showWithDuration:(NSTimeInterval)duration {
    NSRect targetFrame = NSMakeRect(self.targetX, self.targetY, kWindowWidth, kWindowHeight);

    [self.panel makeKeyAndOrderFront:nil];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = kAnimDuration;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [[self.panel animator] setFrame:targetFrame display:YES];
    } completionHandler:^{
        [self playShimmer];
        [self playIconSpringIn];

        if (!self.persistent && duration > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self dismiss]; });
        }
    }];
}

- (void)moveToY:(CGFloat)newY animated:(BOOL)animated {
    if (self.isDismissed) return;
    NSRect newFrame = NSMakeRect(self.targetX, newY, kWindowWidth, kWindowHeight);
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.3;
            ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [[self.panel animator] setFrame:newFrame display:YES];
        } completionHandler:nil];
    } else {
        [self.panel setFrame:newFrame display:YES];
    }
}

- (void)dismiss {
    if (self.isDismissed) return;
    self.isDismissed = YES;

    [NotifyManager.shared removeController:self];

    NSScreen *screen = [NotifyManager.shared activeScreen];
    CGFloat offscreenX = NSMaxX(screen.visibleFrame) + kWindowWidth;
    CGFloat currentY   = self.panel.frame.origin.y;
    NSRect hideFrame   = NSMakeRect(offscreenX, currentY, kWindowWidth, kWindowHeight);

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = kAnimDuration;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        [[self.panel animator] setFrame:hideFrame display:YES];
    } completionHandler:^{
        [self.panel orderOut:nil];
    }];
}

- (void)windowDismissed:(NSNotification *)n { [self dismiss]; }
- (void)windowClicked:(NSNotification *)n  { [self handleClick:nil]; }

- (void)handleClick:(id)sender {
    if (self.activateBundleId) {
        NSURL *appURL = [[NSWorkspace sharedWorkspace]
                         URLForApplicationWithBundleIdentifier:self.activateBundleId];
        if (appURL) {
            [[NSWorkspace sharedWorkspace]
             openApplicationAtURL:appURL
             configuration:[NSWorkspaceOpenConfiguration configuration]
             completionHandler:nil];
        }
    }
    [self dismiss];
}

@end

// ── DraggableView implementation ─────────────────────────────────────────────

@implementation DraggableView
// 光标显示小手
- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}
@end

// ── Socket daemon ─────────────────────────────────────────────────────────────

// 处理单个连接收到的完整 JSON 行
static void handleMessage(NSString *jsonStr, int clientFd) {

    NSData *data = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];

    NSString *responseStr;
    if (!msg || err) {
        responseStr = @"{\"ok\":false,\"error\":\"invalid JSON\"}\n";
    } else {
        NSString *action = msg[@"action"] ?: @"send";

        if ([action isEqualToString:@"send"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NotifyWindowController *c = [[NotifyWindowController alloc] initWithParams:msg];
                NSTimeInterval dur = msg[@"duration"] ? [msg[@"duration"] doubleValue] : kDefaultDuration;
                if ([msg[@"persistent"] boolValue]) dur = 0;
                c.persistent = (dur == 0);

                // 播放声音
                NSString *soundName = msg[@"sound"];
                if (soundName.length > 0) {
                    NSSound *sound = [NSSound soundNamed:soundName];
                    [sound play];
                }

                [NotifyManager.shared addController:c];
                [c showWithDuration:dur];
            });
            responseStr = [NSString stringWithFormat:@"{\"ok\":true,\"id\":\"%@\"}\n", msg[@"id"] ?: @""];

        } else if ([action isEqualToString:@"update"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NotifyWindowController *c = nil;
                if (msg[@"taskId"]) c = [NotifyManager.shared findByTaskId:msg[@"taskId"]];
                if (!c && msg[@"id"]) c = [NotifyManager.shared findByNotifyId:msg[@"id"]];
                if (c) {
                    [c updateTitle:msg[@"title"] message:msg[@"message"]];
                } else {
                    // 不存在则新建
                    NotifyWindowController *nc = [[NotifyWindowController alloc] initWithParams:msg];
                    NSTimeInterval dur = msg[@"duration"] ? [msg[@"duration"] doubleValue] : kDefaultDuration;
                    nc.persistent = [msg[@"persistent"] boolValue];
                    [NotifyManager.shared addController:nc];
                    [nc showWithDuration:dur];
                }
            });
            responseStr = [NSString stringWithFormat:@"{\"ok\":true,\"id\":\"%@\"}\n", msg[@"id"] ?: @""];

        } else if ([action isEqualToString:@"dismiss"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NotifyWindowController *c = nil;
                if (msg[@"id"])     c = [NotifyManager.shared findByNotifyId:msg[@"id"]];
                if (!c && msg[@"taskId"]) c = [NotifyManager.shared findByTaskId:msg[@"taskId"]];
                [c dismiss];
            });
            responseStr = @"{\"ok\":true}\n";

        } else if ([action isEqualToString:@"dismiss-group"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *grp = msg[@"group"];
                NSArray *copy = [NotifyManager.shared.controllers copy];
                for (NotifyWindowController *c in copy) {
                    if ([c.group isEqualToString:grp]) [c dismiss];
                }
            });
            responseStr = @"{\"ok\":true}\n";

        } else if ([action isEqualToString:@"ping"]) {
            responseStr = @"{\"ok\":true,\"pong\":true}\n";

        } else {
            responseStr = @"{\"ok\":false,\"error\":\"unknown action\"}\n";
        }
    }

    const char *resp = [responseStr UTF8String];
    write(clientFd, resp, strlen(resp));
    close(clientFd);
}

// 接受一个客户端连接，在后台队列中同步读取一行数据，处理后关闭连接
static void acceptClient(int clientFd) {
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(q, ^{
        NSMutableData *buf = [NSMutableData data];
        uint8_t tmp[4096];

        for (;;) {
            // 先扫描已有 buf 里有没有 \n
            const uint8_t *bytes = (const uint8_t *)buf.bytes;
            for (NSUInteger i = 0; i < buf.length; i++) {
                if (bytes[i] == '\n') {
                    NSString *line = [[NSString alloc] initWithBytes:bytes
                                                              length:i
                                                            encoding:NSUTF8StringEncoding];
                    handleMessage([line stringByTrimmingCharactersInSet:
                                   [NSCharacterSet whitespaceCharacterSet]], clientFd);
                    return;
                }
            }
            // 需要更多数据
            ssize_t n = read(clientFd, tmp, sizeof(tmp));
            if (n <= 0) break;
            [buf appendBytes:tmp length:(NSUInteger)n];
        }
        // EOF 前没找到 \n，尝试把整个 buf 当作 JSON 处理（允许不带换行的消息）
        if (buf.length > 0) {
            NSString *line = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
            if (line) {
                handleMessage([line stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceCharacterSet]], clientFd);
                return;
            }
        }
        close(clientFd);
    });
}

static void startSocketServer(void) {
    // 清理残留 sock 文件
    unlink([kSocketPath fileSystemRepresentation]);

    int serverFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (serverFd < 0) {
        fprintf(stderr, "mcp-notify: socket() failed errno=%d\n", errno);
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, [kSocketPath fileSystemRepresentation], sizeof(addr.sun_path));

    if (bind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "mcp-notify: bind() failed errno=%d\n", errno);
        close(serverFd);
        return;
    }
    if (listen(serverFd, 16) < 0) {
        fprintf(stderr, "mcp-notify: listen() failed errno=%d\n", errno);
        close(serverFd);
        return;
    }

    // 用专用后台线程做 accept loop（GCD dispatch_source 对 Unix socket 不可靠）
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(q, ^{
        for (;;) {
            int clientFd = accept(serverFd, NULL, NULL);
            if (clientFd < 0) {
                if (errno == EINTR) continue;
                break;
            }
            acceptClient(clientFd);
        }
    });
}

// ── Main ──────────────────────────────────────────────────────────────────────

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app activateIgnoringOtherApps:YES];

        startSocketServer();

        [app run];
    }
    return 0;
}
