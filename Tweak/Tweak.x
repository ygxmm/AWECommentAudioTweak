// AWECommentAudioTweak - 全功能最终版（私信下载与评论区完全一致，颜色修正）
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECAHeaders.h"
#import "AWECAUtils.h"
#import "AWECADownloadManager.h"
#import "AWECAAudioReplacer.h"
#import "AWECAAudioPickerController.h"
#import "AWECATTSController.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

// 私信类声明
@interface AWEIMAudioRecordController : NSObject
@property (nonatomic, copy) NSString *recordFilePath;
@end

@interface AWEIMAudioEnginRecorder : NSObject
- (void)setCurrentTime:(double)currentTime;
@end

@interface AWEIMFormatAudioRecordController : NSObject
@end

@interface AWEIMEmojiReplyMenuView : UIView <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@end

// 前置声明
static void setupAudioIconElementHook(void);
static void setupAudioInputElementHook(void);
static void setupStackViewLayoutHook(void);
static UIView *findMorePanelElementView(UIView *stackView);
static double realAudioDuration(NSString *filePath);

// 获取真实时长
static double realAudioDuration(NSString *filePath) {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    CMTime time = asset.duration;
    if (CMTIME_IS_VALID(time)) return CMTimeGetSeconds(time);
    return 0.0;
}

// 评论区：查找更多面板按钮的父容器
static UIView *findMorePanelElementView(UIView *stackView) {
    Class evClass = NSClassFromString(@"AWEBaseElementView");
    if (!evClass) return nil;
    for (UIView *sub in stackView.subviews) {
        if (![sub isKindOfClass:evClass]) continue;
        for (UIView *child in sub.subviews) {
            if ([child isKindOfClass:[UIButton class]] && [child.accessibilityLabel isEqualToString:@"更多面板"]) {
                return sub;
            }
        }
    }
    return nil;
}

// ========== 评论区功能（保持不变） ==========
%hook AWECommentAudioRecorderController
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success error:(id)error {
    if (success && [AWECAAudioReplacer shared].enabled) {
        NSString *recorderURL = self.recorder.url.path;
        %orig;
        NSString *pathAfter = self.audioFilePath;
        if (pathAfter.length > 0) [[AWECAAudioReplacer shared] replaceAudioAtPath:pathAfter];
        else if (recorderURL.length > 0) [[AWECAAudioReplacer shared] replaceAudioAtPath:recorderURL];
        [AWECAUtils showToast:@"语音已替换"];
    } else %orig;
}
- (void)setAudioFilePath:(NSString *)audioFilePath {
    %orig;
    if (!audioFilePath.length || ![AWECAAudioReplacer shared].enabled) return;
    if ([[NSFileManager defaultManager] fileExistsAtPath:audioFilePath])
        [[AWECAAudioReplacer shared] replaceAudioAtPath:audioFilePath];
}
%end

%hook AWECommentAudioPlayerManager
- (void)playAudioWithVideoModel:(id)videoModel startTime:(double)startTime audioEffectExternInfo:(id)info {
    if (videoModel && [videoModel isKindOfClass:[NSString class]])
        [[AWECADownloadManager shared] parseAndCacheVideoModelJSON:(NSString *)videoModel];
    %orig;
}
- (void)playAudioWithVideoModel:(id)videoModel startTime:(double)startTime {
    if (videoModel && [videoModel isKindOfClass:[NSString class]])
        [[AWECADownloadManager shared] parseAndCacheVideoModelJSON:(NSString *)videoModel];
    %orig;
}
%end

%hook AWECommentLongPressPanelAdaptar
- (void)showLongPressPanelWithParam:(id)param config:(id)config showSheetCompletion:(id)showCompletion dismissSheetCompletion:(id)dismissCompletion {
    %orig;
    AWECommentModel *comment = [param respondsToSelector:@selector(selectdComment)] ? [(AWECommentLongPressPanelParam *)param selectdComment] : nil;
    if (!comment || !comment.audioModel) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[AWECADownloadManager shared] showSaveDialogAndDownload:comment];
    });
}
%end

%hook AWECommentAudioUploadManager
- (void)startUploadAudioWithFilePath:(id)filePath {
    if ([AWECAAudioReplacer shared].enabled && filePath && [[NSFileManager defaultManager] fileExistsAtPath:(NSString *)filePath])
        [[AWECAAudioReplacer shared] replaceAudioAtPath:(NSString *)filePath];
    %orig;
}
- (void)uploadAudioWithFilePath:(id)filePath completion:(id)completion {
    if ([AWECAAudioReplacer shared].enabled && filePath && [[NSFileManager defaultManager] fileExistsAtPath:(NSString *)filePath])
        [[AWECAAudioReplacer shared] replaceAudioAtPath:(NSString *)filePath];
    %orig;
}
- (void)uploadAudioWithFilePath:(id)filePath authCompletion:(id)authCompletion completion:(id)completion {
    if ([AWECAAudioReplacer shared].enabled && filePath && [[NSFileManager defaultManager] fileExistsAtPath:(NSString *)filePath])
        [[AWECAAudioReplacer shared] replaceAudioAtPath:(NSString *)filePath];
    %orig;
}
%end

static void (*orig_generateAudioPreviewBubble)(id, SEL, id);
static void hook_generateAudioPreviewBubble(id self, SEL _cmd, id recordedModel) {
    if (recordedModel && [AWECAAudioReplacer shared].enabled) {
        NSString *audioPath = [recordedModel valueForKey:@"audioFilePath"];
        if (audioPath.length && [[NSFileManager defaultManager] fileExistsAtPath:audioPath]) {
            if ([[AWECAAudioReplacer shared] replaceAudioAtPath:audioPath]) {
                double dur = realAudioDuration(audioPath);
                [recordedModel setValue:@((long long)(dur * 1000)) forKey:@"duration"];
            }
        }
    }
    orig_generateAudioPreviewBubble(self, _cmd, recordedModel);
}
static void setupAudioInputElementHook(void) {
    Class cls = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputAudioInputElement");
    if (!cls) return;
    SEL sel = @selector(generateAudioPreviewBubbleWithRecordedModel:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        orig_generateAudioPreviewBubble = (void (*)(id, SEL, id))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_generateAudioPreviewBubble);
    }
}

// ========== AI 按钮布局更新 ==========
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
    if (!audioElement) { aiContainer.hidden = YES; aiContainer.alpha = 0.0; }
    NSMutableArray *buttons = [NSMutableArray array];
    for (UIView *sub in stackView.subviews) {
        if (![sub isKindOfClass:evClass] || sub.hidden || sub.alpha < 0.01 || sub.frame.size.width == 0) continue;
        UIButton *btn = nil;
        for (UIView *child in sub.subviews) if ([child isKindOfClass:[UIButton class]]) { btn = (UIButton *)child; break; }
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
    NSDictionary *targetPositions = @{@"image":@0, @"at":@40, @"emoji":@80, @"audio":@120, @"poi":@200};
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
        aiContainer.hidden = NO; aiContainer.alpha = 1.0;
    } else { aiContainer.hidden = YES; aiContainer.alpha = 0.0; }
    UIButton *aiBtn = nil;
    for (UIView *sub in aiContainer.subviews) if ([sub isKindOfClass:[UIButton class]]) { aiBtn = (UIButton *)sub; break; }
    if (aiBtn) {
        Class themeMgr = NSClassFromString(@"AWEUIThemeManager");
        aiBtn.tintColor = (themeMgr && [themeMgr isLightTheme]) ? [UIColor blackColor] : [UIColor whiteColor];
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
                customDetentWithIdentifier:@"ttsCompact" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) { return 256; }];
            sheet.detents = @[fit, UISheetPresentationControllerDetent.largeDetent];
            sheet.selectedDetentIdentifier = @"ttsCompact"; sheet.prefersGrabberVisible = YES;
        }
    } else if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        if (sheet) { sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent]; sheet.prefersGrabberVisible = YES; }
    }
    [vc presentViewController:nav animated:YES completion:nil];
}

static void aweca_longPressAudioIconIMP(id self, SEL _cmd, UILongPressGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [[AWECAAudioPickerController shared] showPickerFromViewController:[AWECAUtils topViewController]];
}

static void (*orig_audioIconViewDidLoad)(id self, SEL _cmd);
static void hook_audioIconViewDidLoad(id self, SEL _cmd) {
    orig_audioIconViewDidLoad(self, _cmd);
    UIView *elementView = [self respondsToSelector:@selector(view)] ? [self performSelector:@selector(view)] : nil;
    if (!elementView) return;
    elementView.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:elementView action:@selector(aweca_longPressAudioIcon:)];
    lp.minimumPressDuration = 0.5; [elementView addGestureRecognizer:lp];
    UIView *redDot = [[UIView alloc] initWithFrame:CGRectMake(elementView.bounds.size.width - 8, 2, 6, 6)];
    redDot.backgroundColor = [UIColor redColor]; redDot.layer.cornerRadius = 3;
    redDot.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    redDot.hidden = ![AWECAAudioReplacer shared].enabled; redDot.tag = 19527;
    [elementView addSubview:redDot];
    UIView *stackView = elementView.superview;
    if (!stackView || [stackView viewWithTag:19528]) return;
    UIView *aiContainer = [[UIView alloc] initWithFrame:CGRectZero];
    aiContainer.tag = 19528; aiContainer.userInteractionEnabled = YES;
    [stackView addSubview:aiContainer];
    UIButton *aiBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular];
    [aiBtn setImage:[UIImage systemImageNamed:@"icloud.circle" withConfiguration:cfg] forState:UIControlStateNormal];
    Class themeMgr = NSClassFromString(@"AWEUIThemeManager");
    aiBtn.tintColor = (themeMgr && [themeMgr isLightTheme]) ? [UIColor blackColor] : [UIColor whiteColor];
    aiBtn.frame = CGRectMake(0, 0, 24, 24);
    [aiBtn addTarget:stackView action:@selector(aweca_aiButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [aiContainer addSubview:aiBtn];
}

static void setupAudioIconElementHook(void) {
    Class cls = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentAudioIconElement");
    if (!cls) return;
    SEL sel = @selector(viewDidLoad);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        orig_audioIconViewDidLoad = (void (*)(id, SEL))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_audioIconViewDidLoad);
    }
    Class viewClass = NSClassFromString(@"AWEBaseElementView") ?: [UIView class];
    if (!class_respondsToSelector(viewClass, @selector(aweca_longPressAudioIcon:)))
        class_addMethod(viewClass, @selector(aweca_longPressAudioIcon:), (IMP)aweca_longPressAudioIconIMP, "v@:@");
    Class stackClass = NSClassFromString(@"AWEElementStackView") ?: [UIView class];
    if (!class_respondsToSelector(stackClass, @selector(aweca_aiButtonTapped)))
        class_addMethod(stackClass, @selector(aweca_aiButtonTapped), (IMP)aweca_aiButtonTappedIMP, "v@:");
}

// ========== StackView 布局 Hook ==========
static void (*orig_stackViewLayoutSubviews)(id, SEL);
static void hook_stackViewLayoutSubviews(id self, SEL _cmd) {
    orig_stackViewLayoutSubviews(self, _cmd);
    UIView *stackView = (UIView *)self;
    if (!stackView.window) return;
    if ([stackView viewWithTag:19528]) aweca_updateAIButtonPosition(stackView);
    UIView *more = findMorePanelElementView(stackView);
    if (more && more.frame.origin.x != 240) { CGRect f = more.frame; f.origin.x = 240; more.frame = f; }
}
static void setupStackViewLayoutHook(void) {
    Class cls = NSClassFromString(@"AWEElementStackView");
    if (!cls) return;
    SEL sel = @selector(layoutSubviews);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        orig_stackViewLayoutSubviews = (void (*)(id, SEL))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_stackViewLayoutSubviews);
    }
}

// ========== 私信语音时长修正 ==========
%hook AWEIMAudioRecordController
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success action:(unsigned long long)action error:(id)error {
    if (success && [AWECAAudioReplacer shared].enabled) {
        NSString *filePath = self.recordFilePath;
        if (filePath.length && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:filePath];
            double realSec = realAudioDuration(filePath);
            if (realSec > 0) {
                @try { [recorder setValue:@(realSec) forKey:@"currentTime"]; } @catch (NSException *e) {}
                id engineRecorder = [recorder valueForKey:@"recorder"];
                if (engineRecorder && [engineRecorder isKindOfClass:NSClassFromString(@"AWEIMAudioEnginRecorder")]) {
                    [(AWEIMAudioEnginRecorder *)engineRecorder setCurrentTime:realSec];
                }
            }
            [AWECAUtils showToast:@"私信语音已替换"];
        }
    }
    %orig;
}
- (BOOL)sendRecordMessageIfNeededWithFilePath:(id)filePath audioRecorder:(id)recorder {
    if ([AWECAAudioReplacer shared].enabled && filePath) {
        NSString *path = (NSString *)filePath;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:path];
            double realSec = realAudioDuration(path);
            if (realSec > 0) {
                @try { [recorder setValue:@(realSec) forKey:@"currentTime"]; } @catch (NSException *e) {}
                id engineRecorder = [recorder valueForKey:@"recorder"];
                if (engineRecorder && [engineRecorder isKindOfClass:NSClassFromString(@"AWEIMAudioEnginRecorder")]) {
                    [(AWEIMAudioEnginRecorder *)engineRecorder setCurrentTime:realSec];
                }
            }
        }
    }
    return %orig;
}
%end

%hook AWEIMFormatAudioRecordController
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success action:(unsigned long long)action error:(id)error {
    if (success && [AWECAAudioReplacer shared].enabled) {
        NSString *path = [[recorder valueForKey:@"url"] path];
        if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:path];
            double realSec = realAudioDuration(path);
            if (realSec > 0) {
                @try { [recorder setValue:@(realSec) forKey:@"currentTime"]; } @catch (NSException *e) {}
                id engineRecorder = [recorder valueForKey:@"recorder"];
                if (engineRecorder && [engineRecorder isKindOfClass:NSClassFromString(@"AWEIMAudioEnginRecorder")]) {
                    [(AWEIMAudioEnginRecorder *)engineRecorder setCurrentTime:realSec];
                }
            }
            [AWECAUtils showToast:@"格式语音已替换"];
        }
    }
    %orig;
}
- (BOOL)sendRecordMessageIfNeededWithData:(id)data audioRecorder:(id)recorder {
    if ([AWECAAudioReplacer shared].enabled && [recorder respondsToSelector:@selector(url)]) {
        NSString *path = [[recorder valueForKey:@"url"] path];
        if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[AWECAAudioReplacer shared] replaceAudioAtPath:path];
            double realSec = realAudioDuration(path);
            if (realSec > 0) {
                @try { [recorder setValue:@(realSec) forKey:@"currentTime"]; } @catch (NSException *e) {}
                id engineRecorder = [recorder valueForKey:@"recorder"];
                if (engineRecorder && [engineRecorder isKindOfClass:NSClassFromString(@"AWEIMAudioEnginRecorder")]) {
                    [(AWEIMAudioEnginRecorder *)engineRecorder setCurrentTime:realSec];
                }
            }
        }
    }
    return %orig;
}
%end

// ========== 私信原生菜单注入（下载 & 设置） ==========

// 下载：缓存链接 + 弹出评论区同款对话框
static void doDownloadVoice(id menuView) {
    id message = [menuView valueForKey:@"message"];
    if (!message) { [AWECAUtils showToast:@"未找到语音消息"]; return; }

    NSString *audioURL = nil;
    NSNumber *durationMs = nil;
    id content = [message valueForKey:@"content"];
    if (content) {
        id resourceUrl = [content valueForKey:@"resourceUrl"];
        if (resourceUrl) {
            audioURL = [resourceUrl valueForKey:@"url"] ?: [resourceUrl valueForKey:@"urlString"];
        }
        durationMs = [content valueForKey:@"duration"];
    }
    if (!audioURL.length) { [AWECAUtils showToast:@"未获取到音频链接"]; return; }

    // 生成唯一 vID 并缓存链接（与评论区一致）
    NSString *vID = [NSString stringWithFormat:@"im_voice_%@", @([[NSDate date] timeIntervalSince1970])];
    [[AWECADownloadManager shared] cacheURL:audioURL forVID:vID];

    // 构造 AWECommentModel
    Class commentClass = NSClassFromString(@"AWECommentModel");
    Class audioClass = NSClassFromString(@"AWECommentAudioModel");
    if (!commentClass || !audioClass) {
        // 保底分享
        NSURL *url = [NSURL URLWithString:audioURL];
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        [[AWECAUtils topViewController] presentViewController:share animated:YES completion:nil];
        return;
    }

    id commentModel = [[commentClass alloc] init];
    id audioModel = [[audioClass alloc] init];

    // 评论区 AudioModel 的属性通常是 vID / playURL / duration
    @try {
        [audioModel setValue:vID forKey:@"vID"];
        [audioModel setValue:durationMs ?: @(0) forKey:@"duration"];
        // 备用：部分版本可能使用 playURL
        [audioModel setValue:audioURL forKey:@"playURL"];
        [commentModel setValue:audioModel forKey:@"audioModel"];
        [commentModel setValue:vID forKey:@"commentID"];
    } @catch (NSException *e) {
        // 构造失败则分享
        NSURL *url = [NSURL URLWithString:audioURL];
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        [[AWECAUtils topViewController] presentViewController:share animated:YES completion:nil];
        return;
    }

    // 调用下载管理器
    [[AWECADownloadManager shared] showSaveDialogAndDownload:commentModel];
}

// 语音设置
static void doVoiceSettings(id menuView) {
    [[AWECAAudioPickerController shared] showPickerFromViewController:[AWECAUtils topViewController]];
}

%hook AWEIMEmojiReplyMenuView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSInteger originalCount = %orig;
    id message = [self valueForKey:@"message"];
    if (message && [message isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) {
        return originalCount + 2;
    }
    return originalCount;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger originalCount = [self collectionView:collectionView numberOfItemsInSection:0] - 2;
    if (indexPath.item >= originalCount) {
        UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AWEIMEmojiReplyMenuViewCell" forIndexPath:indexPath];
        // 颜色修正为浅灰（与原生菜单一致）
        cell.tintColor = [UIColor colorWithWhite:0.8 alpha:1.0];
        for (UIView *sub in cell.subviews) {
            for (UIView *inner in sub.subviews) {
                if ([inner isKindOfClass:[UIImageView class]]) {
                    UIImageView *imageView = (UIImageView *)inner;
                    UIImage *icon = (indexPath.item == originalCount) ? [UIImage systemImageNamed:@"arrow.down.circle"]
                                                                      : [UIImage systemImageNamed:@"gearshape"];
                    if (icon) imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                }
                if ([inner isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)inner;
                    label.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
                    label.text = (indexPath.item == originalCount) ? @"下载" : @"设置";
                    cell.accessibilityLabel = label.text;
                }
            }
        }
        return cell;
    }
    return %orig;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger originalCount = [self collectionView:collectionView numberOfItemsInSection:0] - 2;
    if (indexPath.item >= originalCount) {
        if (indexPath.item == originalCount) {
            doDownloadVoice(self);
        } else {
            doVoiceSettings(self);
        }
        return;
    }
    %orig;
}

%end

%ctor {
    [AWECAUtils ensureDirectoriesExist];
    [AWECAAudioReplacer shared];
    setupAudioInputElementHook();
    setupAudioIconElementHook();
    setupStackViewLayoutHook();
}