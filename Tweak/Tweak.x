// AWECommentAudioTweak - 抖音评论语音 hook
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECAHeaders.h"
#import "AWECAUtils.h"
#import "AWECADownloadManager.h"
#import "AWECAAudioReplacer.h"
#import "AWECAAudioPickerController.h"
#import "AWECATTSController.h"
#import <objc/runtime.h>
#import <objc/message.h>

// 前置声明，别急后面有实现
static void setupAudioIconElementHook(void);
static void setupAudioInputElementHook(void);
static void setupStackViewLayoutHook(void);

// === Hook 1: 录完就偷梁换柱 ===

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

// === Hook 2: 播放时顺手把 CDN 链接薅了 ===

%hook AWECommentAudioPlayerManager

- (void)playAudioWithVideoModel:(id)videoModel startTime:(double)startTime audioEffectExternInfo:(id)info {
    if (videoModel && [videoModel isKindOfClass:[NSString class]]) {
        NSString *jsonStr = (NSString *)videoModel;
        [[AWECADownloadManager shared] parseAndCacheVideoModelJSON:jsonStr];
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

// === Hook 3: 长按菜单加个保存语音的活 ===

%hook AWECommentLongPressPanelAdaptar

- (void)showLongPressPanelWithParam:(id)param config:(id)config showSheetCompletion:(id)showCompletion dismissSheetCompletion:(id)dismissCompletion {
    // 先让原生面板该弹弹
    %orig;

    // 看看有没有语音
    AWECommentModel *comment = nil;
    if ([param respondsToSelector:@selector(selectdComment)]) {
        comment = [(AWECommentLongPressPanelParam *)param selectdComment];
    }

    if (!comment || !comment.audioModel) {
        return;
    }

    // 等动画跑完再弹，不然打架
    AWECommentModel *savedComment = comment;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[AWECADownloadManager shared] showSaveDialogAndDownload:savedComment];
    });
}

%end

// === Hook 5: 上传前再换一波，双保险 ===

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


// === Hook 6: 预览气泡也得换，顺便修时长 ===

static void (*orig_generateAudioPreviewBubble)(id self, SEL _cmd, id recordedModel);
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
    if (!cls) {
        return;
    }
    SEL sel = @selector(generateAudioPreviewBubbleWithRecordedModel:);
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        orig_generateAudioPreviewBubble = (void (*)(id, SEL, id))method_getImplementation(method);
        method_setImplementation(method, (IMP)hook_generateAudioPreviewBubble);
    }
}

// === Hook 7: 语音按钮长按弹选择器，红点提示，AI按钮 ===

// AI按钮点击回调，打开TTS主页面
static void aweca_aiButtonTappedIMP(id self, SEL _cmd) {
    UIViewController *vc = [AWECAUtils topViewController];
    AWECATTSController *tts = [[AWECATTSController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:tts];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        if (sheet) {
            // 紧凑 + 全屏两档，默认紧凑
            UISheetPresentationControllerDetent *fit = [UISheetPresentationControllerDetent
                customDetentWithIdentifier:@"ttsCompact"
                resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) {
                    return 256;
                }];
            sheet.detents = @[fit, UISheetPresentationControllerDetent.largeDetent];
            sheet.selectedDetentIdentifier = @"ttsCompact";
            sheet.prefersGrabberVisible = YES;
        }
    } else if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                              UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
        }
    }
    [vc presentViewController:nav animated:YES completion:nil];
}

// 定位 AI 按钮：找可见的 Audio 按钮，动态算间距
static void aweca_updateAIButtonPosition(UIView *stackView) {
    UIView *aiContainer = [stackView viewWithTag:19528];
    if (!aiContainer) return;

    Class evClass = NSClassFromString(@"AWEBaseElementView");
    if (!evClass) return;

    // 通过红点 tag 找到可见的 Audio 按钮，跳过隐藏的
    UIView *audioElement = nil;
    for (UIView *sub in stackView.subviews) {
        if (![sub isKindOfClass:evClass]) continue;
        if (sub.hidden || sub.alpha < 0.01) continue;
        if ([sub viewWithTag:19527]) { audioElement = sub; break; }
    }

    if (!audioElement) {
        aiContainer.hidden = YES;
        aiContainer.alpha = 0.0;
        return;
    }

    CGFloat audioRight = CGRectGetMaxX(audioElement.frame);
    if (audioRight <= 0) {
        aiContainer.hidden = YES;
        aiContainer.alpha = 0.0;
        return;
    }

    // 动态算间距：收集可见按钮的 x，取相邻差值
    NSMutableArray *xs = [NSMutableArray array];
    for (UIView *sub in stackView.subviews) {
        if (![sub isKindOfClass:evClass]) continue;
        if (sub.hidden || sub.alpha < 0.01 || sub.frame.origin.x < 0) continue;
        [xs addObject:@(sub.frame.origin.x)];
    }
    [xs sortUsingSelector:@selector(compare:)];
    CGFloat gap = 16;
    if (xs.count >= 2) {
        CGFloat d = [xs[1] floatValue] - [xs[0] floatValue] - 24;
        if (d > 0) gap = d;
    }

    CGFloat aiX = audioRight + gap;
    aiContainer.frame = CGRectMake(aiX, 0, 24, 24);
    aiContainer.hidden = NO;
    aiContainer.alpha = 1.0;
}

static void (*orig_audioIconViewDidLoad)(id self, SEL _cmd);
static void hook_audioIconViewDidLoad(id self, SEL _cmd) {
    orig_audioIconViewDidLoad(self, _cmd);

    UIView *elementView = nil;
    if ([self respondsToSelector:@selector(view)]) {
        elementView = [self performSelector:@selector(view)];
    }
    if (!elementView) return;

    elementView.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                                         initWithTarget:elementView
                                         action:@selector(aweca_longPressAudioIcon:)];
    lp.minimumPressDuration = 0.5;
    [elementView addGestureRecognizer:lp];

    UIView *redDot = [[UIView alloc] initWithFrame:CGRectMake(elementView.bounds.size.width - 8, 2, 6, 6)];
    redDot.backgroundColor = [UIColor redColor];
    redDot.layer.cornerRadius = 3;
    redDot.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    redDot.hidden = ![AWECAAudioReplacer shared].enabled;
    redDot.tag = 19527;
    [elementView addSubview:redDot];

    // 在语音按钮旁边加 AI 按钮
    UIView *stackView = elementView.superview;
    if (!stackView) return;
    if ([stackView viewWithTag:19528]) return;

    UIView *aiContainer = [[UIView alloc] initWithFrame:CGRectZero];
    aiContainer.tag = 19528;
    aiContainer.userInteractionEnabled = YES;
    [stackView addSubview:aiContainer];

    UIButton *aiBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular];
    UIImage *aiIcon = [UIImage systemImageNamed:@"icloud.circle" withConfiguration:cfg];
    [aiBtn setImage:aiIcon forState:UIControlStateNormal];
    aiBtn.tintColor = [UIColor labelColor];  // 自动适配深浅
    aiBtn.frame = CGRectMake(0, 0, 24, 24);
    [aiBtn addTarget:stackView action:@selector(aweca_aiButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [aiContainer addSubview:aiBtn];

    // AI按钮创建完成，layoutSubviews hook 会自动定位
}

static void aweca_longPressAudioIconIMP(id self, SEL _cmd, UILongPressGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIViewController *vc = [AWECAUtils topViewController];
    [[AWECAAudioPickerController shared] showPickerFromViewController:vc];
}

static void setupAudioIconElementHook(void) {
    Class cls = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentAudioIconElement");
    if (!cls) return;
    SEL sel = @selector(viewDidLoad);
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        orig_audioIconViewDidLoad = (void (*)(id, SEL))method_getImplementation(method);
        method_setImplementation(method, (IMP)hook_audioIconViewDidLoad);
    }

    Class viewClass = NSClassFromString(@"AWEBaseElementView");
    if (!viewClass) viewClass = [UIView class];
    SEL lpSel = @selector(aweca_longPressAudioIcon:);
    if (!class_respondsToSelector(viewClass, lpSel)) {
        class_addMethod(viewClass, lpSel, (IMP)aweca_longPressAudioIconIMP, "v@:@");
    }

    Class stackClass = NSClassFromString(@"AWEElementStackView");
    if (!stackClass) stackClass = [UIView class];
    SEL aiSel = @selector(aweca_aiButtonTapped);
    if (!class_respondsToSelector(stackClass, aiSel)) {
        class_addMethod(stackClass, aiSel, (IMP)aweca_aiButtonTappedIMP, "v@:");
    }
}

// === Hook 8: StackView layoutSubviews，每次布局都重新定位 AI 按钮 ===

static void (*orig_stackViewLayoutSubviews)(id self, SEL _cmd);
static void hook_stackViewLayoutSubviews(id self, SEL _cmd) {
    orig_stackViewLayoutSubviews(self, _cmd);
    // 有 AI 按钮才处理，避免无关 stackView 白跑
    UIView *sv = (UIView *)self;
    if ([sv viewWithTag:19528]) {
        aweca_updateAIButtonPosition(sv);
    }
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

// === %ctor 搞定收工，插件启动 ===

%ctor {
    @autoreleasepool {
        [AWECAUtils ensureDirectoriesExist];

        [AWECAAudioReplacer shared];

        // 别问为啥手动hook，问就是Swift类runtime搞不定
        setupAudioInputElementHook();
        setupAudioIconElementHook();
        setupStackViewLayoutHook();
    }
}
