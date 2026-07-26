// AWECommentAudioTweak - 最终稳定版（群聊菜单加高 + 按钮正常，轻量查找）
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
@interface AWEIMMessageListViewController : UIViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message;
@end
@interface AFDHoverableContainerView : UIView
@end

// 前置声明
static void setupAudioIconElementHook(void);
static void setupAudioInputElementHook(void);
static void setupStackViewLayoutHook(void);
static UIView *findMorePanelElementView(UIView *stackView);
static double realAudioDuration(NSString *filePath);
static void showSaveDialogForURL(NSString *urlString, NSString *msgID);
static void downloadFromURL(NSString *urlStr, NSString *savePath);
static void showFolderPicker(NSString *fileName, NSString *cdnURL, UIViewController *vc);
static void doDownloadVoiceFromMenu(id menuView);
static void doVoiceSettings(id menuView);
static id getMessageFromMenuView(UIView *menuView);
static NSString *extractAudioURLFromMessage(id message);
static id extractMessageFromCell(UIView *cell);
static void aweca_groupDownloadAction(id self, SEL _cmd);
static void aweca_groupSettingsAction(id self, SEL _cmd);

// 存储最近长按的消息对象
static id g_lastLongPressedMessage = nil;

// 获取真实音频时长
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

// 从消息对象中提取音频 CDN 链接
static NSString *extractAudioURLFromMessage(id message) {
    if (!message) return nil;
    id content = [message valueForKey:@"content"];
    if (!content) return nil;
    id resourceUrl = [content valueForKey:@"resourceUrl"];
    if (!resourceUrl) return nil;
    NSArray *originList = [resourceUrl valueForKey:@"originURLList"];
    if (originList && originList.count > 0) return originList.firstObject;
    return [resourceUrl valueForKey:@"url"] ?: [resourceUrl valueForKey:@"urlString"];
}

// 从 Cell 中提取消息对象
static id extractMessageFromCell(UIView *cell) {
    if (!cell) return nil;
    id msg = [cell valueForKey:@"message"];
    if (msg && [msg isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) return msg;
    NSArray *keys = @[@"item", @"model", @"data", @"audioMessage"];
    for (NSString *key in keys) {
        msg = [cell valueForKey:key];
        if ([msg isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) return msg;
    }
    id context = [cell valueForKey:@"currentContext"];
    if (context) {
        msg = [context valueForKey:@"message"];
        if ([msg isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) return msg;
    }
    return nil;
}

// 从菜单视图查找消息对象（轻量版，仅向上找 Cell）
static id getMessageFromMenuView(UIView *menuView) {
    UIView *current = menuView;
    while (current) {
        if ([current isKindOfClass:[UITableViewCell class]] || [current isKindOfClass:[UICollectionViewCell class]]) {
            id msg = extractMessageFromCell(current);
            if (msg) return msg;
            break;
        }
        current = current.superview;
    }
    return nil;
}

// ========== 评论区功能 ==========
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

// ========== 私信长按菜单回调 ==========
%hook AWEIMMessageListViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message {
    %orig;
    g_lastLongPressedMessage = message;
}
%end

// ========== 私信菜单注入（两行显示） ==========
%hook AWEIMEmojiReplyMenuView

- (void)layoutSubviews {
    %orig;
    if (g_lastLongPressedMessage && [g_lastLongPressedMessage isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) {
        for (UIView *sub in self.subviews) {
            if ([sub isKindOfClass:[UICollectionView class]]) {
                UICollectionView *cv = (UICollectionView *)sub;
                if (cv.contentSize.height > cv.frame.size.height) {
                    CGRect frame = cv.frame;
                    frame.size.height = cv.contentSize.height;
                    cv.frame = frame;
                }
                cv.scrollEnabled = NO;
                cv.clipsToBounds = NO;
                break;
            }
        }
    }
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSInteger originalCount = %orig;
    if (!g_lastLongPressedMessage) {
        g_lastLongPressedMessage = getMessageFromMenuView(self);
    }
    if (g_lastLongPressedMessage && [g_lastLongPressedMessage isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) {
        return originalCount + 2;
    }
    return originalCount;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger originalCount = [self collectionView:collectionView numberOfItemsInSection:0] - 2;
    if (indexPath.item >= originalCount) {
        UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AWEIMEmojiReplyMenuViewCell" forIndexPath:indexPath];
        for (UIView *sub in cell.subviews) { [sub removeFromSuperview]; }
        UIView *iconBg = [[UIView alloc] initWithFrame:CGRectMake(1, 4, 48, 48)];
        iconBg.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.9];
        iconBg.layer.cornerRadius = 10;
        [cell addSubview:iconBg];
        UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(12, 12, 24, 24)];
        NSString *iconName = (indexPath.item == originalCount) ? @"arrow.down.circle" : @"gearshape";
        iconView.image = [[UIImage systemImageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        iconView.tintColor = [UIColor colorWithWhite:0.8 alpha:1.0];
        [iconBg addSubview:iconView];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 52, 50, 15)];
        label.text = (indexPath.item == originalCount) ? @"下载" : @"设置";
        label.font = [UIFont systemFontOfSize:12];
        label.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
        label.textAlignment = NSTextAlignmentCenter;
        [cell addSubview:label];
        cell.accessibilityLabel = label.text;
        return cell;
    }
    return %orig;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger originalCount = [self collectionView:collectionView numberOfItemsInSection:0] - 2;
    if (indexPath.item >= originalCount) {
        if (indexPath.item == originalCount) doDownloadVoiceFromMenu(self);
        else doVoiceSettings(self);
        return;
    }
    %orig;
}

%end

// ========== 群聊菜单容器：加高并添加按钮 ==========
%hook AFDHoverableContainerView

- (void)layoutSubviews {
    %orig;

    // 防止重复添加按钮
    if ([self viewWithTag:30001]) return;

    // 获取消息对象（轻量查找）
    id message = g_lastLongPressedMessage;
    if (!message) {
        message = getMessageFromMenuView(self);
        if (message) g_lastLongPressedMessage = message;
    }
    if (!message || ![message isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) return;

    // 增加容器高度
    CGRect f = self.frame;
    f.size.height += 54;
    self.frame = f;

    // 在底部添加下载和设置按钮
    CGFloat centerX = self.bounds.size.width / 2;
    CGFloat y = self.bounds.size.height - 54 + 4;

    // 下载按钮
    UIView *downloadItem = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 50)];
    downloadItem.tag = 30001;
    downloadItem.center = CGPointMake(centerX - 40, y + 25);
    UIImageView *downloadIcon = [[UIImageView alloc] initWithFrame:CGRectMake(18, 4, 24, 24)];
    downloadIcon.image = [[UIImage systemImageNamed:@"arrow.down.circle"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    downloadIcon.tintColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    [downloadItem addSubview:downloadIcon];
    UILabel *downloadLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 30, 50, 15)];
    downloadLabel.text = @"下载";
    downloadLabel.font = [UIFont systemFontOfSize:12];
    downloadLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    downloadLabel.textAlignment = NSTextAlignmentCenter;
    [downloadItem addSubview:downloadLabel];
    UITapGestureRecognizer *tap1 = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(aweca_groupDownloadAction)];
    [downloadItem addGestureRecognizer:tap1];
    [self addSubview:downloadItem];

    // 设置按钮
    UIView *settingsItem = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 50)];
    settingsItem.tag = 30002;
    settingsItem.center = CGPointMake(centerX + 40, y + 25);
    UIImageView *settingsIcon = [[UIImageView alloc] initWithFrame:CGRectMake(18, 4, 24, 24)];
    settingsIcon.image = [[UIImage systemImageNamed:@"gearshape"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    settingsIcon.tintColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    [settingsItem addSubview:settingsIcon];
    UILabel *settingsLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 30, 50, 15)];
    settingsLabel.text = @"设置";
    settingsLabel.font = [UIFont systemFontOfSize:12];
    settingsLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    settingsLabel.textAlignment = NSTextAlignmentCenter;
    [settingsItem addSubview:settingsLabel];
    UITapGestureRecognizer *tap2 = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(aweca_groupSettingsAction)];
    [settingsItem addGestureRecognizer:tap2];
    [self addSubview:settingsItem];
}

%end

// ========== 群聊按钮回调 ==========
static void aweca_groupDownloadAction(id self, SEL _cmd) {
    doDownloadVoiceFromMenu(self);
}

static void aweca_groupSettingsAction(id self, SEL _cmd) {
    doVoiceSettings(self);
}

// ========== 下载和设置实现 ==========
static void doDownloadVoiceFromMenu(id menuView) {
    id message = g_lastLongPressedMessage;
    if (!message) message = getMessageFromMenuView((UIView *)menuView);
    if (!message) { [AWECAUtils showToast:@"无法获取消息对象"]; return; }
    NSString *audioURL = extractAudioURLFromMessage(message);
    if (!audioURL.length) { [AWECAUtils showToast:@"无法获取音频链接"]; return; }
    NSString *msgID = [message valueForKey:@"messageID"];
    showSaveDialogForURL(audioURL, msgID);
}

static void doVoiceSettings(id menuView) {
    [[AWECAAudioPickerController shared] showPickerFromViewController:[AWECAUtils topViewController]];
}

static void showSaveDialogForURL(NSString *urlString, NSString *msgID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [AWECAUtils topViewController];
        if (!topVC) return;
        NSString *defaultName = [NSString stringWithFormat:@"语音_%@", msgID ?: @((int)[[NSDate date] timeIntervalSince1970])];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存语音" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.text = defaultName; tf.placeholder = @"文件名(不含扩展名)"; tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存到默认目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *fileName = alert.textFields.firstObject.text ?: defaultName;
            downloadFromURL(urlString, [[AWECAUtils audioSavePath] stringByAppendingPathComponent:[fileName stringByAppendingPathExtension:@"m4a"]]);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"选择文件夹" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *fileName = alert.textFields.firstObject.text ?: defaultName;
            showFolderPicker(fileName, urlString, topVC);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

static void downloadFromURL(NSString *urlStr, NSString *savePath) {
    [AWECAUtils showToast:@"正在下载..."];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { [AWECAUtils showToast:@"URL 无效"]; return; }
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    [[session downloadTaskWithURL:url completionHandler:^(NSURL *tmpFile, NSURLResponse *response, NSError *error) {
        if (error || !tmpFile) { dispatch_async(dispatch_get_main_queue(), ^{ [AWECAUtils showToast:@"下载失败"]; }); return; }
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [savePath stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [fm removeItemAtPath:savePath error:nil];
        BOOL ok = [fm moveItemAtURL:tmpFile toURL:[NSURL fileURLWithPath:savePath] error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [AWECAUtils showToast: ok ? [NSString stringWithFormat:@"已保存 %@", savePath.lastPathComponent] : @"保存失败"];
        });
    }] resume];
}

static void showFolderPicker(NSString *fileName, NSString *cdnURL, UIViewController *vc) {
    NSString *baseDir = [AWECAUtils audioSavePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:baseDir error:nil];
    NSMutableArray *folders = [NSMutableArray array];
    for (NSString *item in contents) {
        BOOL isDir = NO;
        NSString *fullPath = [baseDir stringByAppendingPathComponent:item];
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) [folders addObject:item];
    }
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"选择保存位置" message:baseDir preferredStyle:UIAlertControllerStyleActionSheet];
    [picker addAction:[UIAlertAction actionWithTitle:@"默认目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        downloadFromURL(cdnURL, [baseDir stringByAppendingPathComponent:[fileName stringByAppendingPathExtension:@"m4a"]]);
    }]];
    for (NSString *folder in folders) {
        [picker addAction:[UIAlertAction actionWithTitle:folder style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *dir = [baseDir stringByAppendingPathComponent:folder];
            downloadFromURL(cdnURL, [dir stringByAppendingPathComponent:[fileName stringByAppendingPathExtension:@"m4a"]]);
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"新建文件夹" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建文件夹" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"文件夹名称"; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"创建并保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *folderName = alert.textFields.firstObject.text;
            if (!folderName.length) { [AWECAUtils showToast:@"文件夹名不能为空"]; return; }
            NSString *newDir = [baseDir stringByAppendingPathComponent:folderName];
            [fm createDirectoryAtPath:newDir withIntermediateDirectories:YES attributes:nil error:nil];
            downloadFromURL(cdnURL, [newDir stringByAppendingPathComponent:[fileName stringByAppendingPathExtension:@"m4a"]]);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:alert animated:YES completion:nil];
    }]];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (picker.popoverPresentationController) {
        picker.popoverPresentationController.sourceView = vc.view;
        picker.popoverPresentationController.sourceRect = CGRectMake(vc.view.bounds.size.width / 2, vc.view.bounds.size.height, 0, 0);
    }
    [vc presentViewController:picker animated:YES completion:nil];
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [AWECAUtils ensureDirectoriesExist];
        [AWECAAudioReplacer shared];
    });
    setupAudioInputElementHook();
    setupAudioIconElementHook();
    setupStackViewLayoutHook();

    Class hoverClass = NSClassFromString(@"AFDHoverableContainerView");
    if (hoverClass) {
        if (!class_respondsToSelector(hoverClass, @selector(aweca_groupDownloadAction))) {
            class_addMethod(hoverClass, @selector(aweca_groupDownloadAction), (IMP)aweca_groupDownloadAction, "v@:");
        }
        if (!class_respondsToSelector(hoverClass, @selector(aweca_groupSettingsAction))) {
            class_addMethod(hoverClass, @selector(aweca_groupSettingsAction), (IMP)aweca_groupSettingsAction, "v@:");
        }
    }
}