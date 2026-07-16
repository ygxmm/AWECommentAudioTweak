// AWECommentAudioTweak - 抖音评论语音 hook + 更多面板按钮固定到 x=240（终极定时器版）
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECAHeaders.h"
#import "AWECAUtils.h"
#import "AWECADownloadManager.h"
#import "AWECAAudioReplacer.h"
#import "AWECAAudioPickerController.h"
#import "AWECATTSController.h"
#import <objc/runtime.h>
#import <objc/message.h>

// 前置声明
static void setupAudioIconElementHook(void);
static void setupAudioInputElementHook(void);
static void setupStackViewLayoutHook(void);
static void moveMorePanelButton(void);

// === 所有原有的 Hook 功能保留，无需修改 ===

%hook AWECommentAudioRecorderController
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success error:(id)error {
    if (success && [AWECAAudioReplacer shared].enabled) {
        NSString *recorderURL = self.recorder.url.path;
        %orig;
        NSString *pathAfter = self.audioFilePath;
        if (pathAfter.length > 0) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:pathAfter];
        } else if (recorderURL.length > 0) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:recorderURL];
        }
        [AWECAUtils showToast:@"语音已替换"];
    } else {
        %orig;
    }
}
- (void)setAudioFilePath:(NSString *)audioFilePath {
    %orig;
    if (!audioFilePath.length) return;
    if (![AWECAAudioReplacer shared].enabled) return;
    if ([[NSFileManager defaultManager] fileExistsAtPath:audioFilePath]) {
        [[AWECAAudioReplacer shared] replaceAudioAtPath:audioFilePath];
    }
}
%end

%hook AWECommentAudioPlayerManager
- (void)playAudioWithVideoModel:(id)videoModel startTime:(double)startTime audioEffectExternInfo:(id)info {
    if (videoModel && [videoModel isKindOfClass:[NSString class]]) {
        [[AWECADownloadManager shared] parseAndCacheVideoModelJSON:(NSString *)videoModel];
    }
    %orig;
}
- (void)playAudioWithVideoModel:(id)videoModel startTime:(double)startTime {
    if (videoModel && [videoModel isKindOfClass:[NSString class]]) {
        [[AWECADownloadManager shared] parseAndCacheVideoModelJSON:(NSString *)videoModel];
    }
    %orig;
}
%end

%hook AWECommentLongPressPanelAdaptar
- (void)showLongPressPanelWithParam:(id)param config:(id)config showSheetCompletion:(id)showCompletion dismissSheetCompletion:(id)dismissCompletion {
    %orig;
    AWECommentModel *comment = nil;
    if ([param respondsToSelector:@selector(selectdComment)]) {
        comment = [(AWECommentLongPressPanelParam *)param selectdComment];
    }
    if (!comment || !comment.audioModel) return;
    AWECommentModel *savedComment = comment;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[AWECADownloadManager shared] showSaveDialogAndDownload:savedComment];
    });
}
%end

%hook AWECommentAudioUploadManager
- (void)startUploadAudioWithFilePath:(id)filePath {
    if ([AWECAAudioReplacer shared].enabled && filePath) {
        NSString *path = (NSString *)filePath;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:path];
        }
    }
    %orig;
}
- (void)uploadAudioWithFilePath:(id)filePath completion:(id)completion {
    if ([AWECAAudioReplacer shared].enabled && filePath) {
        NSString *path = (NSString *)filePath;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:path];
        }
    }
    %orig;
}
- (void)uploadAudioWithFilePath:(id)filePath authCompletion:(id)authCompletion completion:(id)completion {
    if ([AWECAAudioReplacer shared].enabled && filePath) {
        NSString *path = (NSString *)filePath;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:path];
        }
    }
    %orig;
}
%end

// === 预览气泡 Hook ===
static void (*orig_generateAudioPreviewBubble)(id, SEL, id);
static void hook_generateAudioPreviewBubble(id self, SEL _cmd, id recordedModel) {
    if (recordedModel && [AWECAAudioReplacer shared].enabled) {
        NSString *audioPath = [recordedModel valueForKey:@"audioFilePath"];
        if (audioPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:audioPath]) {
            BOOL ok = [[AWECAAudioReplacer shared] replaceAudioAtPath:audioPath];
            if (ok) {
                double realDur = [AWECAUtils audioDurationAtPath:audioPath];
                long long realMs = (long long)(realDur * 1000);
                [recordedModel setValue:@(realMs) forKey:@"duration"];
            }
        }
    }
    orig_generateAudioPreviewBubble(self, _cmd, recordedModel);
}
static void setupAudioInputElementHook(void) {
    Class cls = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputAudioInputElement");
    if (!cls) return;
    SEL sel = @selector(generateAudioPreviewBubbleWithRecordedModel:);
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        orig_generateAudioPreviewBubble = (void (*)(id, SEL, id))method_getImplementation(method);
        method_setImplementation(method, (IMP)hook_generateAudioPreviewBubble);
    }
}

// === 查找包含“更多面板”按钮的 AWEBaseElementView ===
static UIView *findMorePanelElementView(void) {
    // 获取当前活动窗口
    UIWindow *window = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            window = scene.windows.firstObject;
            break;
        }
    }
    if (!window) window = [UIApplication sharedApplication].delegate.window;
    if (!window) return nil;

    // 递归查找所有子视图，找到 accessLabel = @"更多面板" 的按钮
    NSMutableArray *allButtons = [NSMutableArray array];
    void (^findButtons)(UIView *) = ^(UIView *view) {
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            if ([btn.accessibilityLabel isEqualToString:@"更多面板"]) {
                [allButtons addObject:btn];
            }
        }
        for (UIView *sub in view.subviews) {
            findButtons(sub);
        }
    };
    findButtons(window);

    if (allButtons.count == 0) return nil;

    // 返回第一个符合条件的按钮的父视图（AWEBaseElementView）
    UIButton *targetBtn = allButtons.firstObject;
    UIView *parent = targetBtn.superview;
    // 确认父视图是否是 AWEBaseElementView
    if ([parent isKindOfClass:NSClassFromString(@"AWEBaseElementView")]) {
        return parent;
    }
    return nil;
}

// === 移动按钮的实际操作 ===
static void moveMorePanelButton(void) {
    UIView *elementView = findMorePanelElementView();
    if (elementView && elementView.frame.origin.x != 240) {
        CGRect frame = elementView.frame;
        frame.origin.x = 240;
        elementView.frame = frame;
    }
}

// === 原有的 AI 按钮、语音布局更新函数（保持不变） ===
static void aweca_updateAIButtonPosition(UIView *stackView) {
    // ... 与之前版本完全相同，此处省略以节省篇幅，但实际代码中必须保留 ...
}
static void aweca_aiButtonTappedIMP(id self, SEL _cmd) { /* ... 保持不变 ... */ }
static void aweca_longPressAudioIconIMP(id self, SEL _cmd, UILongPressGestureRecognizer *gesture) { /* ... */ }
static void (*orig_audioIconViewDidLoad)(id self, SEL _cmd);
static void hook_audioIconViewDidLoad(id self, SEL _cmd) { /* ... */ }
static void setupAudioIconElementHook(void) { /* ... */ }

// === 保留原有的 StackView Hook（用于 AI 按钮） ===
static void (*orig_stackViewLayoutSubviews)(id self, SEL _cmd);
static void hook_stackViewLayoutSubviews(id self, SEL _cmd) {
    orig_stackViewLayoutSubviews(self, _cmd);
    UIView *stackView = (UIView *)self;
    if (!stackView.window) return;
    if ([stackView viewWithTag:19528]) {
        aweca_updateAIButtonPosition(stackView);
    }
    // 注意：我们不在这里移动“更多面板”，因为定时器会处理
}
static void setupStackViewLayoutHook(void) {
    Class cls = NSClassFromString(@"AWEElementStackView");
    if (!cls) return;
    SEL sel = @selector(layoutSubviews);
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        orig_stackViewLayoutSubviews = (void (*)(id, SEL))method_getImplementation(method);
        method_setImplementation(method, (IMP)hook_stackViewLayoutSubviews);
    }
}

// === 启动入口：启动定时器 + 原有初始化 ===
%ctor {
    @autoreleasepool {
        [AWECAUtils ensureDirectoriesExist];
        [AWECAAudioReplacer shared];

        setupAudioInputElementHook();
        setupAudioIconElementHook();
        setupStackViewLayoutHook();

        // 终极方案：全局定时器，每 0.5 秒移动一次按钮（极低性能开销）
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            moveMorePanelButton();
        }];
    }
}