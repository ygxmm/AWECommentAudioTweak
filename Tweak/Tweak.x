// AWECommentAudioTweak - 评论区 + 私信语音替换，更多面板按钮固定在 x=240
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECAHeaders.h"
#import "AWECAUtils.h"
#import "AWECADownloadManager.h"
#import "AWECAAudioReplacer.h"
#import "AWECAAudioPickerController.h"
#import "AWECATTSController.h"
#import <objc/runtime.h>
#import <objc/message.h>

// ==== 私信录音控制器声明 ====
@interface AWEIMAudioRecordController : NSObject
@property (nonatomic, copy) NSString *recordFilePath;
@end

@interface AWEIMFormatAudioRecordController : NSObject
@end

// 前置声明
static void setupAudioIconElementHook(void);
static void setupAudioInputElementHook(void);
static void setupStackViewLayoutHook(void);
static UIView *findMorePanelElementView(UIView *stackView);

// ========== 评论区：查找更多面板按钮的父容器 ==========
static UIView *findMorePanelElementView(UIView *stackView) {
    Class evClass = NSClassFromString(@"AWEBaseElementView");
    if (!evClass) return nil;
    for (UIView *sub in stackView.subviews) {
        if (![sub isKindOfClass:evClass]) continue;
        for (UIView *child in sub.subviews) {
            if ([child isKindOfClass:[UIButton class]] &&
                [child.accessibilityLabel isEqualToString:@"更多面板"]) {
                return sub;
            }
        }
    }
    return nil;
}

// ========== 评论区：录音后替换音频 ==========
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

// ========== 评论区：播放时缓存 CDN 链接 ==========
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

// ========== 评论区：长按菜单添加保存语音 ==========
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

// ========== 评论区：上传前替换音频 ==========
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

// ========== 评论区：预览气泡替换音频 ==========
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

// ========== 评论区：AI 按钮布局更新 ==========
static void aweca_updateAIButtonPosition(UIView *stackView) {
    UIView *aiContainer = [stackView viewWithTag:19528];
    if (!aiContainer) return;
    Class evClass = NSClassFromString(@"AWEBaseElementView");
    if (!evClass) return;

    UIView *audioElement = nil;
    for (UIView *sub in stackView.subviews) {
        if (![sub isKindOfClass:evClass]) continue;
        if ([sub viewWithTag:19527]) { audioElement = sub; break; }
    }
    if (!audioElement) {
        aiContainer.hidden = YES;
        aiContainer.alpha = 0.0;
    }

    NSMutableArray *buttons = [NSMutableArray array];
    for (UIView *sub in stackView.subviews) {
        if (![sub isKindOfClass:evClass]) continue;
        if (sub.hidden || sub.alpha < 0.01) continue;
        if (sub.frame.size.width == 0) continue;
        UIButton *btn = nil;
        for (UIView *child in sub.subviews) {
            if ([child isKindOfClass:[UIButton class]]) { btn = (UIButton *)child; break; }
        }
        NSString *type = @"unknown";
        if (btn && btn.accessibilityIdentifier) {
            if ([btn.accessibilityIdentifier containsString:@"Image"]) type = @"image";
            else if ([btn.accessibilityIdentifier containsString:@"At"]) type = @"at";
            else if ([btn.accessibilityIdentifier containsString:@"Emoji"]) type = @"emoji";
            else if ([btn.accessibilityIdentifier containsString:@"Poi"]) type = @"poi";
        }
        if (btn && [btn.accessibilityLabel isEqualToString:@"更多面板"]) type = @"more";
        if (sub == audioElement) type = @"audio";
        [buttons addObject:@{@"view": sub, @"type": type, @"originalX": @(sub.frame.origin.x)}];
    }
    [buttons sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"originalX"] compare:b[@"originalX"]];
    }];
    NSDictionary *targetPositions = @{
        @"image": @0, @"at": @40, @"emoji": @80, @"audio": @120, @"poi": @200
    };
    BOOL hasAudio = NO;
    for (NSDictionary *info in buttons) {
        NSString *type = info[@"type"];
        UIView *view = info[@"view"];
        NSNumber *targetX = targetPositions[type];
        if (targetX) {
            CGRect frame = view.frame;
            frame.origin.x = [targetX floatValue];
            view.frame = frame;
            if ([type isEqualToString:@"audio"]) hasAudio = YES;
        }
    }
    if (hasAudio && audioElement) {
        aiContainer.frame = CGRectMake(160, 0, 24, 24);
        aiContainer.hidden = NO;
        aiContainer.alpha = 1.0;
    } else {
        aiContainer.hidden = YES;
        aiContainer.alpha = 0.0;
    }
    UIButton *aiBtn = nil;
    for (UIView *sub in aiContainer.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) { aiBtn = (UIButton *)sub; break; }
    }
    if (aiBtn) {
        Class themeMgr = NSClassFromString(@"AWEUIThemeManager");
        BOOL isLight = themeMgr ? [themeMgr isLightTheme] : NO;
        aiBtn.tintColor = isLight ? [UIColor blackColor] : [UIColor whiteColor];
    }
}

static void aweca_aiButtonTappedIMP(id self, SEL _cmd) {
    UIViewController *vc = [AWECAUtils topViewController];
    AWECATTSController *tts = [[AWECATTSController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:tts];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        if (sheet) {
            UISheetPresentationControllerDetent *fit = [UISheetPresentationControllerDetent
                customDetentWithIdentifier:@"ttsCompact"
                resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) { return 256; }];
            sheet.detents = @[fit, UISheetPresentationControllerDetent.largeDetent];
            sheet.selectedDetentIdentifier = @"ttsCompact";
            sheet.prefersGrabberVisible = YES;
        }
    } else if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
        }
    }
    [vc presentViewController:nav animated:YES completion:nil];
}

static void aweca_longPressAudioIconIMP(id self, SEL _cmd, UILongPressGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIViewController *vc = [AWECAUtils topViewController];
    [[AWECAAudioPickerController shared] showPickerFromViewController:vc];
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
    Class themeMgr = NSClassFromString(@"AWEUIThemeManager");
    BOOL isLight = themeMgr ? [themeMgr isLightTheme] : NO;
    aiBtn.tintColor = isLight ? [UIColor blackColor] : [UIColor whiteColor];
    aiBtn.frame = CGRectMake(0, 0, 24, 24);
    [aiBtn addTarget:stackView action:@selector(aweca_aiButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [aiContainer addSubview:aiBtn];
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

// ========== 评论区：StackView 布局 Hook，移动更多面板按钮到 x=240 ==========
static void (*orig_stackViewLayoutSubviews)(id self, SEL _cmd);
static void hook_stackViewLayoutSubviews(id self, SEL _cmd) {
    orig_stackViewLayoutSubviews(self, _cmd);
    UIView *stackView = (UIView *)self;
    if (!stackView.window) return;

    if ([stackView viewWithTag:19528]) {
        aweca_updateAIButtonPosition(stackView);
    }

    UIView *moreElementView = findMorePanelElementView(stackView);
    if (moreElementView && moreElementView.frame.origin.x != 240) {
        CGRect frame = moreElementView.frame;
        frame.origin.x = 240;
        moreElementView.frame = frame;
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

// ========== 私信语音替换（修正时长） ==========

%hook AWEIMAudioRecordController
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success action:(unsigned long long)action error:(id)error {
    %orig;
    if (success && [AWECAAudioReplacer shared].enabled) {
        NSString *filePath = self.recordFilePath;
        if (filePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:filePath];
            double realDuration = [AWECAUtils audioDurationAtPath:filePath];
            if (realDuration > 0) {
                @try {
                    [self setValue:@(realDuration) forKey:@"totalTime"];
                } @catch (NSException *e) {
                    @try {
                        [self setValue:@(realDuration) forKey:@"duration"];
                    } @catch (NSException *e2) {}
                }
            }
            [AWECAUtils showToast:@"私信语音已替换"];
        }
    }
}

- (BOOL)sendRecordMessageIfNeededWithFilePath:(id)filePath audioRecorder:(id)recorder {
    if ([AWECAAudioReplacer shared].enabled && filePath) {
        NSString *path = (NSString *)filePath;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:path];
        }
    }
    return %orig;
}
%end

%hook AWEIMFormatAudioRecordController
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success action:(unsigned long long)action error:(id)error {
    %orig;
    if (success && [AWECAAudioReplacer shared].enabled) {
        NSString *filePath = nil;
        if ([recorder respondsToSelector:@selector(url)]) {
            filePath = [[recorder valueForKey:@"url"] path];
        }
        if (filePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:filePath];
            double realDuration = [AWECAUtils audioDurationAtPath:filePath];
            if (realDuration > 0) {
                @try {
                    [self setValue:@(realDuration) forKey:@"totalTime"];
                } @catch (NSException *e) {
                    @try {
                        [self setValue:@(realDuration) forKey:@"duration"];
                    } @catch (NSException *e2) {}
                }
            }
            [AWECAUtils showToast:@"格式语音已替换"];
        }
    }
}

- (BOOL)sendRecordMessageIfNeededWithData:(id)data audioRecorder:(id)recorder {
    if ([AWECAAudioReplacer shared].enabled && [recorder respondsToSelector:@selector(url)]) {
        NSURL *url = [recorder valueForKey:@"url"];
        if (url) {
            NSString *path = url.path;
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [[AWECAAudioReplacer shared] replaceAudioAtPath:path];
            }
        }
    }
    return %orig;
}
%end

// ========== 启动入口 ==========
%ctor {
    @autoreleasepool {
        [AWECAUtils ensureDirectoriesExist];
        [AWECAAudioReplacer shared];

        setupAudioInputElementHook();
        setupAudioIconElementHook();
        setupStackViewLayoutHook();
    }
}