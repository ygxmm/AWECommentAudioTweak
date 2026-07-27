// AWECommentAudioTweak - 完整版（修复 keyWindow 编译错误）
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

// ---------- 私信/群聊相关类声明 ----------
@interface AWEIMAudioRecordController : NSObject
@property (nonatomic, copy) NSString *recordFilePath;
@end
@interface AWEIMAudioEnginRecorder : NSObject
- (void)setCurrentTime:(double)currentTime;
@end
@interface AWEIMFormatAudioRecordController : NSObject
@end

// 🔧 占位菜单类 – 运行后根据日志替换此类名
@interface AWEIMMessageLongPressMenuView : UIView <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@end
@interface AWEIMMessageLongPressMenuViewCell : UICollectionViewCell
- (void)configWithMenuItem:(id)menuItem;
@end

@interface AWEIMMessageListViewController : UIViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message;
- (void)awe_scanCollectionViews:(UIView *)view depth:(int)depth; // 调试用
@end
@interface AFDHoverableContainerView : UIView
@end

// ---------- 前置声明 ----------
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

// 全局消息对象
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

// 提取音频 CDN 链接
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

// 从 Cell 提取消息对象
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

// 从菜单视图查找消息（轻量）
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

// 创建一个 AWEIMCustomMenuModel 实例（修复图标显示问题）
static id createMenuItem(NSString *title, NSString *iconSystemName) {
    Class modelClass = NSClassFromString(@"AWEIMCustomMenuModel");
    if (!modelClass) return nil;
    id item = [[modelClass alloc] init];
    [item setValue:title forKey:@"title"];
    UIImage *icon = [UIImage systemImageNamed:iconSystemName];
    if (icon) {
        @try { [item setValue:icon forKey:@"icon"]; } @catch (NSException *e) {}
        @try { [item setValue:icon forKey:@"iconImage"]; } @catch (NSException *e) {}
        @try { [item setValue:icon forKey:@"image"]; } @catch (NSException *e) {}
    }
    return item;
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

// ========== 长按消息记录（含调试扫描） ==========
%hook AWEIMMessageListViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message {
    %orig;
    g_lastLongPressedMessage = message;
    NSLog(@"[AWE] 长按消息已记录：%@", [message class]);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 忽略 keyWindow 弃用警告
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
        [self awe_scanCollectionViews:window depth:0];
    });
}

- (void)awe_scanCollectionViews:(UIView *)view depth:(int)depth {
    if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)view;
        NSLog(@"🎯 找到菜单 CollectionView: %p\n  superview: %@ (%@)\n  delegate: %@\n  dataSource: %@\n  items: %ld",
              cv, cv.superview, NSStringFromClass([cv.superview class]),
              cv.delegate, cv.dataSource,
              (long)[cv numberOfItemsInSection:0]);
    }
    for (UIView *sub in view.subviews) {
        [self awe_scanCollectionViews:sub depth:depth+1];
    }
}
%end

// ========== 核心：Hook 菜单视图（需替换为调试得到的类名） ==========
%hook AWEIMMessageLongPressMenuView

- (void)layoutSubviews {
    %orig;
    if (g_lastLongPressedMessage && [g_lastLongPressedMessage isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) {
        for (UIView *sub in self.subviews) {
            if ([sub isKindOfClass:[UICollectionView class]]) {
                UICollectionView *cv = (UICollectionView *)sub;
                [cv reloadData];
                CGFloat contentH = cv.contentSize.height;
                if (contentH > cv.frame.size.height) {
                    CGRect frame = cv.frame;
                    frame.size.height = contentH;
                    cv.frame = frame;
                }
                cv.scrollEnabled = NO;
                cv.clipsToBounds = NO;

                UIView *parent = self.superview;
                if ([parent isKindOfClass:NSClassFromString(@"AFDHoverableContainerView")]) {
                    CGRect parentFrame = parent.frame;
                    CGFloat neededHeight = CGRectGetMaxY(cv.frame) + 8;
                    if (neededHeight > parentFrame.size.height) {
                        parentFrame.size.height = neededHeight;
                        parent.frame = parentFrame;
                        parent.clipsToBounds = NO;
                    }
                }
                break;
            }
        }
    }
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSInteger originalCount = %orig;
    if (g_lastLongPressedMessage && [g_lastLongPressedMessage isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) {
        return originalCount + 2;
    }
    return originalCount;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger originalCount = [self collectionView:collectionView numberOfItemsInSection:0] - 2;
    if (indexPath.item >= originalCount) {
        static NSString *cellReuseID = nil;
        if (!cellReuseID) {
            if (originalCount > 0) {
                UICollectionViewCell *firstCell = [collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
                cellReuseID = firstCell.reuseIdentifier;
            }
            if (!cellReuseID) {
                cellReuseID = @"AWEIMMessageLongPressMenuViewCell"; // 兜底
            }
        }
        id cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellReuseID forIndexPath:indexPath];
        id menuItem = nil;
        if (indexPath.item == originalCount) {
            menuItem = createMenuItem(@"下载", @"arrow.down.circle");
        } else {
            menuItem = createMenuItem(@"设置", @"gearshape");
        }
        if ([cell respondsToSelector:@selector(configWithMenuItem:)]) {
            [cell configWithMenuItem:menuItem];
        }
        return cell;
    }
    return %orig;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger originalCount = [self collectionView:collectionView numberOfItemsInSection:0] - 2;
    if (indexPath.item >= originalCount) {
        if (g_lastLongPressedMessage && [g_lastLongPressedMessage isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) {
            if (indexPath.item == originalCount) doDownloadVoiceFromMenu(self);
            else doVoiceSettings(self);
        } else {
            [AWECAUtils showToast:@"仅语音消息支持"];
        }
        return;
    }
    %orig;
}

%end

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
}