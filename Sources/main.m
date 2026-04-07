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

// JSON 取值安全宏：NSNull → nil
static inline NSString *SafeString(id val) {
    return [val isKindOfClass:[NSString class]] ? val : nil;
}

// ── Stack mode ────────────────────────────────────────────────────────────────

typedef NS_ENUM(NSInteger, StackMode) {
    StackModeNormal,    // ≤5 条，正常排列
    StackModeCollapsed, // >5 条，只显示1条+数字角标
    StackModeHover,     // hover 预览堆叠
    StackModeExpanded,  // 点击展开滚动列表
};

// ── NotifyManager + NotifyWindowController forward declarations ───────────────

@class NotifyWindowController;

static const NSInteger kStackThreshold = 5;

@interface NotifyManager : NSObject
@property (strong) NSMutableArray<NotifyWindowController *> *controllers;
@property (assign) StackMode stackMode;
@property (assign) CGFloat   scrollOffset;
@property (strong) NSTimer  *collapseTimer;
@property (strong) NSWindow *badgeWindow;
@property (strong) NSWindow *clearAllWindow;
+ (instancetype)shared;
- (void)addController:(NotifyWindowController *)c;
- (void)removeController:(NotifyWindowController *)c;
- (void)rearrange;
- (CGFloat)nextTargetYOnScreen:(NSScreen *)screen;
- (void)enterHover;
- (void)leaveHover;
- (void)toggleExpanded;
- (void)collapseFromExpanded;
- (void)scrollByDelta:(CGFloat)dy;
- (void)dismissAll;
- (NSScreen *)activeScreen;
- (NotifyWindowController *)findByNotifyId:(NSString *)nid;
- (NotifyWindowController *)findByTaskId:(NSString *)taskId;
- (NotifyWindowController *)findByGroup:(NSString *)group;
@end

// ── Borderless key window ─────────────────────────────────────────────────────

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
                CGFloat offsetX = dx;
                if (dx < 0) offsetX = dx * 0.3;

                NSRect frame = self.frame;
                frame.origin.x = self.targetX + offsetX;
                [self setFrame:frame display:YES];

                CGFloat alpha = dx > 0 ? MAX(0.4, 1.0 - dx / 200.0) : 1.0;
                self.contentView.layer.opacity = (float)alpha;
                return;
            }
            break;
        }

        case NSEventTypeLeftMouseUp: {
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
            [[NSNotificationCenter defaultCenter]
             postNotificationName:@"MCPClickWindow" object:self];
            return;
        }

        case NSEventTypeMouseMoved:
        case NSEventTypeMouseEntered: {
            [[NSCursor pointingHandCursor] set];
            break;
        }

        case NSEventTypeScrollWheel: {
            // 展开模式下，滚轮整体偏移所有通知 Y 坐标
            if (NotifyManager.shared.stackMode == StackModeExpanded) {
                CGFloat dy = event.scrollingDeltaY;
                if (event.hasPreciseScrollingDeltas) dy *= 0.5; // 触摸板减速
                [NotifyManager.shared scrollByDelta:dy];
                return;
            }
            break;
        }

        default:
            break;
    }
    [super sendEvent:event];
}
@end

// ── DraggableView ─────────────────────────────────────────────────────────────

@interface DraggableView : NSView
@property (weak) NotifyWindowController *controller;
@end

// ── NotifyWindowController interface ─────────────────────────────────────────

@interface NotifyWindowController : NSObject
@property (copy)   NSString    *notifyId;
@property (copy)   NSString    *taskId;
@property (copy)   NSString    *group;
@property (copy)   NSString    *titleText;
@property (copy)   NSString    *messageText;
@property (copy)   NSString    *iconPath;
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
@property (assign) NSInteger    stackIndex;

- (instancetype)initWithParams:(NSDictionary *)params;
- (void)showWithDuration:(NSTimeInterval)duration;
- (void)updateTitle:(NSString *)title message:(NSString *)message;
- (void)dismiss;
- (void)moveToY:(CGFloat)newY animated:(BOOL)animated;
- (void)moveToXY:(CGFloat)x y:(CGFloat)y width:(CGFloat)w animated:(BOOL)animated;
@end

// ── NotifyManager implementation ──────────────────────────────────────────────

@implementation NotifyManager

+ (instancetype)shared {
    static NotifyManager *inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [[NotifyManager alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _controllers  = [NSMutableArray array];
        _stackMode    = StackModeNormal;
        _scrollOffset = 0;
    }
    return self;
}

- (void)addController:(NotifyWindowController *)c {
    [_controllers addObject:c];
    if (_stackMode == StackModeExpanded) {
        [self collapseFromExpanded];
    }
    // 添加后立即 rearrange，确保 Collapsed 模式下多余的卡片被隐藏
    [self rearrange];
}

- (void)removeController:(NotifyWindowController *)c {
    [_controllers removeObject:c];
    if ((NSInteger)_controllers.count <= kStackThreshold &&
        (_stackMode == StackModeCollapsed || _stackMode == StackModeHover)) {
        _stackMode = StackModeNormal;
    }
    if (_stackMode == StackModeExpanded && _controllers.count == 0) {
        [self collapseFromExpanded];
        return;
    }
    [self rearrange];
}

// ── rearrange ─────────────────────────────────────────────────────────────────

- (void)rearrange {
    NSInteger count = (NSInteger)_controllers.count;

    // 数量超限时自动切换到 Collapsed（仅 Normal 时）
    if (count > kStackThreshold && _stackMode == StackModeNormal) {
        _stackMode = StackModeCollapsed;
    }
    // 数量降回阈值以内时退出堆叠
    if (count <= kStackThreshold &&
        (_stackMode == StackModeCollapsed || _stackMode == StackModeHover)) {
        _stackMode = StackModeNormal;
    }

    if (count == 0) {
        [self hideBadge];
        [self hideClearAll];
        return;
    }

    NSScreen *screen = [self activeScreen];
    CGFloat baseY  = NSMaxY(screen.visibleFrame) - kWindowHeight - kMarginTop;
    CGFloat fullX  = NSMaxX(screen.visibleFrame) - kWindowWidth - kMarginRight;

    if (_stackMode == StackModeNormal) {
        [self hideBadge];
        [self hideClearAll];
        for (NSInteger i = 0; i < count; i++) {
            NotifyWindowController *c = _controllers[i];
            CGFloat newY = baseY - i * (kWindowHeight + kWindowSpacing);
            c.targetX = fullX;
            c.targetY = newY;
            [c moveToY:newY animated:YES];
            [c.panel orderFront:nil];
            c.panel.alphaValue = 1.0;
        }

    } else if (_stackMode == StackModeCollapsed || _stackMode == StackModeHover) {
        // 折叠和hover是同一组卡片的不同位移：
        // Collapsed: peek=0（卡片完全重叠在 index 0 后面）
        // Hover: peek>0（卡片拉开露出边缘）
        [self hideClearAll];

        static const CGFloat kHoverPeeks[]  = {0, 12, 10, 8};
        static const CGFloat kHoverScales[] = {1.0, 0.92, 0.84, 0.76};
        static const NSInteger kStackCards  = 4;

        BOOL isHover = (_stackMode == StackModeHover);

        // hover: card 0 下移 20px，card 1/2 留在原位上方（露出顶部边缘）
        CGFloat card0Drop  = isHover ? 20.0 : 0.0;
        // card 1/2 的 Y 偏移（相对 baseY 向上）
        static const CGFloat kPeekUp[] = {0, 0, 6};  // card1=baseY, card2=baseY+6

        // ── card 0（最前面，最大）──
        NotifyWindowController *c0 = _controllers[0];
        CGFloat c0Y = baseY - card0Drop;
        c0.targetX = fullX;
        c0.targetY = c0Y;
        ((BorderlessKeyWindow *)c0.panel).targetX = fullX;
        c0.panel.alphaValue = 1.0;
        [c0.panel orderFront:nil];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.3;
            ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [[c0.panel animator] setFrame:NSMakeRect(fullX, c0Y, kWindowWidth, kWindowHeight) display:YES];
        } completionHandler:nil];

        // ── card 1 (92%) 和 card 2 (84%) ──
        static const CGFloat kStackScales[] = {1.0, 0.92, 0.84};
        for (NSInteger i = 1; i <= 2 && i < count; i++) {
            NotifyWindowController *c = _controllers[i];
            CGFloat scale   = kStackScales[i];
            CGFloat scaledW = kWindowWidth * scale;
            CGFloat centeredX = fullX + (kWindowWidth - scaledW) / 2.0;
            CGFloat cardY   = baseY + kPeekUp[i];

            c.targetX = centeredX;
            c.targetY = cardY;
            c.panel.alphaValue = 1.0;

            if (isHover) {
                if (!c.panel.isVisible) {
                    // 初始在 card 0 后方（同位置）
                    [c.panel setFrame:NSMakeRect(fullX, baseY, kWindowWidth, kWindowHeight) display:NO];
                }
                [c.panel orderFront:nil];
                // card 1 在 card 0 后面，card 2 在 card 1 后面
                NSWindow *abovePanel = (i == 1) ? c0.panel : _controllers[i-1].panel;
                [c.panel orderWindow:NSWindowBelow relativeTo:abovePanel.windowNumber];
                // 动画到目标位（缩小+上移）
                [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
                    ctx.duration = 0.3;
                    ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                    [[c.panel animator] setFrame:NSMakeRect(centeredX, cardY, scaledW, kWindowHeight) display:YES];
                } completionHandler:nil];
            } else {
                [c.panel orderOut:nil];
            }
        }

        // 其余全部隐藏
        for (NSInteger i = 3; i < count; i++) {
            [_controllers[i].panel orderOut:nil];
        }

        [self showBadgeCount:count atTopCard:c0];

    } else if (_stackMode == StackModeExpanded) {
        // 正常排列，所有通知显示，应用 scrollOffset
        [self hideBadge];
        for (NSInteger i = 0; i < count; i++) {
            NotifyWindowController *c = _controllers[i];
            CGFloat newY = baseY - i * (kWindowHeight + kWindowSpacing) + _scrollOffset;
            c.targetX = fullX;
            c.targetY = newY;
            if (!c.panel.isVisible) {
                // 从隐藏状态出现：确保图标可见
                if (c.appIconView) {
                    c.appIconView.layer.opacity = 1.0;
                    c.appIconView.layer.transform = CATransform3DIdentity;
                }
                c.panel.alphaValue = 0.0;
                [c.panel setFrame:NSMakeRect(fullX, baseY, kWindowWidth, kWindowHeight) display:NO];
                [c.panel orderFront:nil];
                [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
                    ctx.duration = 0.3;
                    ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                    [[c.panel animator] setFrame:NSMakeRect(fullX, newY, kWindowWidth, kWindowHeight) display:YES];
                    [[c.panel animator] setAlphaValue:1.0];
                } completionHandler:nil];
            } else {
                [c.panel orderFront:nil];
                [c moveToXY:fullX y:newY width:kWindowWidth animated:YES];
                c.panel.alphaValue = 1.0;
            }
        }
        // 显示清除全部按钮
        [self showClearAllNearTopCard];
    }
}

- (CGFloat)nextTargetYOnScreen:(NSScreen *)screen {
    NSInteger count = (NSInteger)_controllers.count;
    NSRect visibleFrame = screen.visibleFrame;
    CGFloat baseY = NSMaxY(visibleFrame) - kWindowHeight - kMarginTop;

    if (_stackMode == StackModeNormal || _stackMode == StackModeExpanded) {
        return baseY - count * (kWindowHeight + kWindowSpacing);
    } else {
        // Collapsed/Hover：新通知出现在顶部
        return baseY;
    }
}

// ── 数字角标（附在最新通知右上角旁边）──────────────────────────────────────

- (void)showBadgeCount:(NSInteger)count atTopCard:(NotifyWindowController *)top {
    CGFloat badgeW = 24.0, badgeH = 24.0;
    NSRect cardFrame = top.panel.frame;
    // 右上角，略微叠出
    CGFloat badgeX = NSMaxX(cardFrame) - badgeW / 2.0 - 8.0;
    CGFloat badgeY = NSMaxY(cardFrame) - badgeH / 2.0 - 8.0;
    NSRect frame = NSMakeRect(badgeX, badgeY, badgeW, badgeH);

    if (!_badgeWindow) {
        _badgeWindow = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        _badgeWindow.level = NSStatusWindowLevel;
        _badgeWindow.opaque = NO;
        _badgeWindow.backgroundColor = NSColor.clearColor;
        _badgeWindow.hasShadow = NO;
        _badgeWindow.ignoresMouseEvents = YES;
        [_badgeWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                            NSWindowCollectionBehaviorStationary];

        NSView *cv = _badgeWindow.contentView;
        cv.wantsLayer = YES;
        cv.layer.backgroundColor = [NSColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0].CGColor;
        cv.layer.cornerRadius = badgeW / 2.0;
        cv.layer.masksToBounds = YES;
    }

    [_badgeWindow setFrame:frame display:YES];

    NSView *cv = _badgeWindow.contentView;
    for (NSView *v in [cv.subviews copy]) [v removeFromSuperview];

    NSTextField *lbl = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", (long)count]];
    lbl.frame = NSMakeRect(0, (badgeH - 14.0) / 2.0, badgeW, 14.0);
    lbl.alignment = NSTextAlignmentCenter;
    lbl.font = [NSFont boldSystemFontOfSize:11.0];
    lbl.textColor = NSColor.whiteColor;
    lbl.backgroundColor = NSColor.clearColor;
    lbl.drawsBackground = NO;
    [cv addSubview:lbl];

    [_badgeWindow orderFront:nil];
}

- (void)hideBadge {
    [_badgeWindow orderOut:nil];
}

// ── hover ─────────────────────────────────────────────────────────────────────

- (void)enterHover {
    if (_stackMode == StackModeCollapsed) {
        [_collapseTimer invalidate];
        _collapseTimer = nil;
        _stackMode = StackModeHover;
        [self rearrange];
    }
}

- (void)leaveHover {
    if (_stackMode == StackModeHover) {
        // 0.5 秒后回到折叠
        // 延迟后收回（给足时间在卡片间移动）
        _collapseTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                         target:self
                                                       selector:@selector(collapseToFolded)
                                                       userInfo:nil
                                                        repeats:NO];
    }
}

- (void)collapseToFolded {
    _collapseTimer = nil;
    if (_stackMode != StackModeHover) return;

    // 如果鼠标还在任何可见卡片上，不折叠
    NSPoint mouse = [NSEvent mouseLocation];
    for (NotifyWindowController *c in _controllers) {
        if (c.panel.isVisible && NSPointInRect(mouse, c.panel.frame)) {
            return;
        }
    }
    // 也检查角标窗口
    if (_badgeWindow.isVisible && NSPointInRect(mouse, _badgeWindow.frame)) {
        return;
    }

    NSScreen *screen = [self activeScreen];
    CGFloat baseY = NSMaxY(screen.visibleFrame) - kWindowHeight - kMarginTop;
    CGFloat fullX = NSMaxX(screen.visibleFrame) - kWindowWidth - kMarginRight;

    NSArray<NotifyWindowController *> *copy = [_controllers copy];

    // card 0：动画回到原位（上移回去）
    if (copy.count > 0) {
        NotifyWindowController *c0 = copy[0];
        c0.targetY = baseY;
        ((BorderlessKeyWindow *)c0.panel).targetX = fullX;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.3;
            ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [[c0.panel animator] setFrame:NSMakeRect(fullX, baseY, kWindowWidth, kWindowHeight) display:YES];
        } completionHandler:nil];
    }

    // cards 1-2：动画收回到 card 0 后方，然后 orderOut
    for (NSInteger i = 1; i < (NSInteger)copy.count && i <= 2; i++) {
        NotifyWindowController *c = copy[i];
        NSWindow *panel = c.panel;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.3;
            ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
            [[panel animator] setFrame:NSMakeRect(fullX, baseY, kWindowWidth, kWindowHeight) display:YES];
        } completionHandler:^{
            [panel orderOut:nil];
        }];
    }

    // 切换状态，等动画结束（0.3s）后再更新角标位置
    _stackMode = StackModeCollapsed;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self->_stackMode == StackModeCollapsed && self->_controllers.count > 0) {
            [self showBadgeCount:(NSInteger)self->_controllers.count
                     atTopCard:self->_controllers[0]];
        }
    });
    _collapseTimer = nil;
}

// ── 展开/折叠 ─────────────────────────────────────────────────────────────────

- (void)toggleExpanded {
    if (_stackMode == StackModeExpanded) {
        [self collapseFromExpanded];
    } else {
        [_collapseTimer invalidate];
        _collapseTimer = nil;
        _scrollOffset = 0;
        _stackMode = StackModeExpanded;
        [self hideBadge];
        [self rearrange];
        // 10 秒无操作自动折叠
        _collapseTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                         target:self
                                                       selector:@selector(autoCollapseExpanded)
                                                       userInfo:nil
                                                        repeats:NO];
    }
}

- (void)autoCollapseExpanded {
    if (_stackMode == StackModeExpanded) {
        [self collapseFromExpanded];
    }
    _collapseTimer = nil;
}

- (void)collapseFromExpanded {
    [_collapseTimer invalidate];
    _collapseTimer = nil;
    _scrollOffset = 0;
    [self hideClearAll];
    _stackMode = (NSInteger)_controllers.count > kStackThreshold
                 ? StackModeCollapsed : StackModeNormal;
    [self rearrange];
}

// ── 滚轮滚动 ──────────────────────────────────────────────────────────────────

- (void)scrollByDelta:(CGFloat)dy {
    if (_stackMode != StackModeExpanded) return;

    NSInteger count = (NSInteger)_controllers.count;
    if (count == 0) return;

    NSScreen *screen = [self activeScreen];
    CGFloat baseY    = NSMaxY(screen.visibleFrame) - kWindowHeight - kMarginTop;
    // 列表最底部的 Y（最后一条通知的 origin.y）
    CGFloat bottomY  = baseY - (count - 1) * (kWindowHeight + kWindowSpacing) + _scrollOffset;
    // 最大允许向上滚（让最底部通知贴屏幕底边 + 一点余量）
    CGFloat minBottom = screen.visibleFrame.origin.y + kWindowSpacing;
    // 最大允许向下滚（让最顶部通知回到 baseY）
    CGFloat maxOffset = 0;
    CGFloat minOffset = minBottom - (baseY - (count - 1) * (kWindowHeight + kWindowSpacing));
    // minOffset 若为正说明所有通知都在屏幕内，无需滚动
    if (minOffset > 0) minOffset = 0;

    CGFloat newOffset = MAX(minOffset, MIN(maxOffset, _scrollOffset + dy));
    if (fabs(newOffset - _scrollOffset) < 0.5) return;
    _scrollOffset = newOffset;

    // 直接更新各窗口位置（不动画，响应要快）
    CGFloat fullX = NSMaxX(screen.visibleFrame) - kWindowWidth - kMarginRight;
    for (NSInteger i = 0; i < count; i++) {
        NotifyWindowController *c = _controllers[i];
        CGFloat newY = baseY - i * (kWindowHeight + kWindowSpacing) + _scrollOffset;
        c.targetX = fullX;
        c.targetY = newY;
        [c moveToXY:fullX y:newY width:kWindowWidth animated:NO];
    }
    [self showClearAllNearTopCard];

    // 重置 10 秒自动折叠计时器
    [_collapseTimer invalidate];
    _collapseTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                     target:self
                                                   selector:@selector(autoCollapseExpanded)
                                                   userInfo:nil
                                                    repeats:NO];
}

// ── 清除全部按钮（展开时浮于最顶部通知右上方）────────────────────────────────

- (void)showClearAllNearTopCard {
    if (_controllers.count == 0) { [self hideClearAll]; return; }
    NotifyWindowController *top = _controllers[0];
    NSRect cardFrame = top.panel.frame;

    CGFloat btnW = 90.0, btnH = 28.0;
    CGFloat btnX = NSMaxX(cardFrame) - btnW;
    CGFloat btnY = NSMaxY(cardFrame) + 6.0;
    NSRect frame = NSMakeRect(btnX, btnY, btnW, btnH);

    if (!_clearAllWindow) {
        _clearAllWindow = [[NSWindow alloc] initWithContentRect:frame
                                                      styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        _clearAllWindow.level = NSStatusWindowLevel;
        _clearAllWindow.opaque = NO;
        _clearAllWindow.backgroundColor = NSColor.clearColor;
        _clearAllWindow.hasShadow = NO;
        [_clearAllWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                               NSWindowCollectionBehaviorStationary];

        NSView *cv = _clearAllWindow.contentView;
        cv.wantsLayer = YES;
        cv.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.6].CGColor;
        cv.layer.cornerRadius    = 12.0;
        cv.layer.masksToBounds   = YES;

        NSButton *btn = [NSButton buttonWithTitle:@"清除全部"
                                           target:self
                                           action:@selector(dismissAll)];
        btn.frame = NSMakeRect(0, 0, btnW, btnH);
        btn.bordered = NO;
        btn.attributedTitle = [[NSAttributedString alloc]
            initWithString:@"清除全部"
                attributes:@{
                    NSFontAttributeName:            [NSFont systemFontOfSize:11.0],
                    NSForegroundColorAttributeName: NSColor.whiteColor,
                }];
        btn.alignment = NSTextAlignmentCenter;
        [cv addSubview:btn];
    }

    [_clearAllWindow setFrame:frame display:YES];
    [_clearAllWindow orderFront:nil];
}

- (void)hideClearAll {
    [_clearAllWindow orderOut:nil];
}

// ── 清除全部 ──────────────────────────────────────────────────────────────────

- (void)dismissAll {
    [_collapseTimer invalidate];
    _collapseTimer = nil;
    [self hideClearAll];
    [self hideBadge];

    NSArray<NotifyWindowController *> *copy = [_controllers copy];
    _stackMode = StackModeNormal;  // 先切状态，避免 dismiss 触发 rearrange 展开逻辑
    _scrollOffset = 0;
    dispatch_queue_t main = dispatch_get_main_queue();
    for (NSInteger i = 0; i < (NSInteger)copy.count; i++) {
        NotifyWindowController *c = copy[i];
        int64_t delayNs = (int64_t)(i * 0.08 * NSEC_PER_SEC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayNs), main, ^{
            [c dismiss];
        });
    }
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

    self.notifyId         = SafeString(params[@"id"]) ?: [[NSUUID UUID] UUIDString];
    self.taskId           = SafeString(params[@"taskId"]);
    self.group            = SafeString(params[@"group"]);
    self.activateBundleId = SafeString(params[@"activate"]);
    self.isDismissed      = NO;
    self.persistent       = [params[@"persistent"] boolValue];
    self.titleText        = SafeString(params[@"title"]) ?: @"";
    self.messageText      = SafeString(params[@"message"]) ?: @"";
    self.iconPath         = SafeString(params[@"icon"]);

    NSScreen *screen = [NotifyManager.shared activeScreen];
    NSRect visibleFrame = screen.visibleFrame;

    CGFloat targetX = NSMaxX(visibleFrame) - kWindowWidth - kMarginRight;
    CGFloat targetY = [NotifyManager.shared nextTargetYOnScreen:screen];
    self.targetX = targetX;
    self.targetY = targetY;

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
        // 默认可见（弹入动画在 showWithDuration 里处理）
        iv.layer.opacity   = 1.0;
        [contentView addSubview:iv];
        self.appIconView = iv;
    }

    // 文字
    CGFloat textLeft  = iconLeft + kIconSize + 10.0;
    CGFloat textRight = kWindowWidth - padding;
    CGFloat textWidth = textRight - textLeft;

    NSString *subtitle = SafeString(params[@"subtitle"]);
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

    // Title 行
    curY -= lineH;
    CGFloat titleX = textLeft;
    if (self.iconPath.length > 0) {
        NSImage *brandIcon = [[NSImage alloc] initByReferencingFile:self.iconPath];
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
    NSTextField *titleField = [NSTextField labelWithString:self.titleText];
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
    NSTextField *msgField = [NSTextField labelWithString:self.messageText];
    msgField.frame = NSMakeRect(textLeft, curY, textWidth, msgH);
    msgField.font  = [NSFont systemFontOfSize:messageSize];
    msgField.textColor = NSColor.whiteColor;
    msgField.backgroundColor = NSColor.clearColor;
    msgField.drawsBackground = NO;
    msgField.lineBreakMode = NSLineBreakByTruncatingTail;
    [contentView addSubview:msgField];
    self.msgField = msgField;

    // hover tracking area
    NSTrackingArea *track = [[NSTrackingArea alloc]
        initWithRect:contentView.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
               owner:self
            userInfo:nil];
    [contentView addTrackingArea:track];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(windowDismissed:) name:@"MCPDismissWindow" object:self.panel];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(windowClicked:) name:@"MCPClickWindow" object:self.panel];

    return self;
}

// ── hover tracking ────────────────────────────────────────────────────────────

- (void)mouseEntered:(NSEvent *)event {
    [[NSCursor pointingHandCursor] push];
    [NotifyManager.shared enterHover];
}

- (void)mouseExited:(NSEvent *)event {
    [NSCursor pop];
    [NotifyManager.shared leaveHover];
}

// ── update ────────────────────────────────────────────────────────────────────

- (void)updateTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (title) {
            self.titleText = title;
            self.titleField.stringValue = title;
        }
        if (message) {
            self.messageText = message;
            self.msgField.stringValue = message;
        }
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

    // 先设为不可见，再弹入
    iconLayer.opacity = 0.0;
    iconLayer.transform = CATransform3DMakeScale(0.5, 0.5, 1.0);

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

- (void)showWithDuration:(NSTimeInterval)duration {
    // Collapsed 模式下，只有 index 0 的通知才显示
    NotifyManager *mgr = [NotifyManager shared];
    if (mgr.stackMode == StackModeCollapsed || mgr.stackMode == StackModeHover) {
        NSInteger idx = [mgr.controllers indexOfObject:self];
        if (idx != 0 && idx != NSNotFound) {
            // 不是最新通知，不显示
            return;
        }
    }

    NSRect targetFrame = NSMakeRect(self.targetX, self.targetY, kWindowWidth, kWindowHeight);

    [self.panel makeKeyAndOrderFront:nil];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = kAnimDuration;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [[self.panel animator] setFrame:targetFrame display:YES];
    } completionHandler:^{
        [self playShimmer];
        [self playIconSpringIn];
        [NotifyManager.shared rearrange];

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

- (void)moveToXY:(CGFloat)x y:(CGFloat)y width:(CGFloat)w animated:(BOOL)animated {
    if (self.isDismissed) return;
    NSRect newFrame = NSMakeRect(x, y, w, kWindowHeight);
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

- (void)windowClicked:(NSNotification *)n {
    StackMode mode = NotifyManager.shared.stackMode;
    NSInteger count = (NSInteger)NotifyManager.shared.controllers.count;

    if (count > kStackThreshold &&
        (mode == StackModeCollapsed || mode == StackModeHover)) {
        // 折叠或 hover 状态下点击 → 展开滚动列表
        [NotifyManager.shared toggleExpanded];
    } else if (mode == StackModeNormal) {
        [self handleClick:nil];
    }
}

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
- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}
@end

// ── Socket daemon ─────────────────────────────────────────────────────────────

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

                id soundVal = msg[@"sound"];
                NSString *soundName = ([soundVal isKindOfClass:[NSString class]]) ? soundVal : nil;
                if (soundName.length > 0) {
                    [[NSSound soundNamed:soundName] play];
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

static void acceptClient(int clientFd) {
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(q, ^{
        NSMutableData *buf = [NSMutableData data];
        uint8_t tmp[4096];

        for (;;) {
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
            ssize_t n = read(clientFd, tmp, sizeof(tmp));
            if (n <= 0) break;
            [buf appendBytes:tmp length:(NSUInteger)n];
        }
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
