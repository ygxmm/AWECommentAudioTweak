// AWECommentAudioTweak - 全功能最终版（群聊直接下载修复）
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

// 群聊按钮回调
static void aweca_groupDownloadAction(id self, SEL _cmd) { doDownloadVoiceFromMenu(self); }
static void aweca_groupSettingsAction(id self, SEL _cmd) { doVoiceSettings(self); }

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

// 从 Cell 中尝试提取消息对象（扩展多种可能属性名）
static id extractMessageFromCell(UIView *cell) {
    if (!cell) return nil;
    // 常见属性名
    NSArray *keys = @[@"message", @"item", @"model", @"data", @"viewModel", @"audioMessage", @"voiceMessage", @"chatMessage"];
    for (NSString *key in keys) {
        id msg = [cell valueForKey:key];
        if (msg && [msg isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) return msg;
        if (msg && [msg respondsToSelector:@selector(content)]) {
            // 尝试检查 content 是否包含音频资源
            id content = [msg valueForKey:@"content"];
            if (content) {
                id resUrl = [content valueForKey:@"resourceUrl"];
                if (resUrl && ([resUrl valueForKey:@"originURLList"] || [resUrl valueForKey:@"url"])) {
                    return msg; // 只要有资源链接就认为是音频消息
                }
            }
        }
    }
    // 尝试通过 currentContext
    id context = [cell valueForKey:@"currentContext"];
    if (context) {
        for (NSString *key in @[@"message", @"item", @"data"]) {
            id msg = [context valueForKey:key];
            if ([msg isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) return msg;
        }
    }
    return nil;
}

// 增强版消息查找，支持 UITableView 和 UICollectionView
static id getMessageFromMenuView(UIView *menuView) {
    UIView *current = menuView;
    while (current) {
        if ([current isKindOfClass:[UITableView class]]) {
            UITableView *tv = (UITableView *)current;
            CGPoint menuCenter = [menuView convertPoint:CGPointMake(menuView.bounds.size.width/2, menuView.bounds.size.height/2) toView:tv];
            NSIndexPath *indexPath = [tv indexPathForRowAtPoint:menuCenter];
            if (indexPath) {
                UITableViewCell *cell = [tv cellForRowAtIndexPath:indexPath];
                id msg = extractMessageFromCell(cell);
                if (msg) return msg;
            }
            break;
        } else if ([current isKindOfClass:[UICollectionView class]]) {
            UICollectionView *cv = (UICollectionView *)current;
            CGPoint menuCenter = [menuView convertPoint:CGPointMake(menuView.bounds.size.width/2, menuView.bounds.size.height/2) toView:cv];
            NSIndexPath *indexPath = [cv indexPathForItemAtPoint:menuCenter];
            if (indexPath) {
                UICollectionViewCell *cell = [cv cellForItemAtIndexPath:indexPath];
                id msg = extractMessageFromCell(cell);
                if (msg) return msg;
            }
            break;
        }
        current = current.superview;
    }
    // 直接向上找 Cell
    current = menuView;
    while (current) {
        if ([current isKindOfClass:[UITableViewCell class]] || [current isKindOfClass:[UICollectionViewCell class]]) {
            id msg = extractMessageFromCell(current);
            if (msg) return msg;
        }
        current = current.superview;
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

static void aweca_aiButtonTappedIMP(id self, SEL _cmd) { /* ... */ }
static void aweca_longPressAudioIconIMP(id self, SEL _cmd, UILongPressGestureRecognizer *gesture) { /* ... */ }
static void (*orig_audioIconViewDidLoad)(id self, SEL _cmd);
static void hook_audioIconViewDidLoad(id self, SEL _cmd) { /* ... */ }
static void setupAudioIconElementHook(void) { /* ... */ }

// ========== StackView 布局 Hook ==========
static void (*orig_stackViewLayoutSubviews)(id, SEL);
static void hook_stackViewLayoutSubviews(id self, SEL _cmd) { /* ... */ }
static void setupStackViewLayoutHook(void) { /* ... */ }

// ========== 私信语音时长修正 ==========
%hook AWEIMAudioRecordController
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success action:(unsigned long long)action error:(id)error { /* ... */ }
- (BOOL)sendRecordMessageIfNeededWithFilePath:(id)filePath audioRecorder:(id)recorder { /* ... */ }
%end

%hook AWEIMFormatAudioRecordController
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success action:(unsigned long long)action error:(id)error { /* ... */ }
- (BOOL)sendRecordMessageIfNeededWithData:(id)data audioRecorder:(id)recorder { /* ... */ }
%end

// ========== 私信长按菜单回调 ==========
%hook AWEIMMessageListViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message {
    %orig;
    if (message) g_lastLongPressedMessage = message;
}
%end

// ========== 私信菜单注入 ==========
%hook AWEIMEmojiReplyMenuView
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSInteger originalCount = %orig;
    if (g_lastLongPressedMessage && [g_lastLongPressedMessage isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) {
        return originalCount + 2;
    }
    return originalCount;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath { /* ... */ }
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath { /* ... */ }
%end

// ========== 群聊菜单注入（强化消息获取） ==========
%hook AFDHoverableContainerView
- (void)didMoveToSuperview {
    %orig;
    if (self.superview && !g_lastLongPressedMessage) {
        // 菜单即将显示，立即从父视图链查找 Cell 并提取消息对象
        UIView *view = self.superview;
        while (view) {
            if ([view isKindOfClass:[UITableViewCell class]] || [view isKindOfClass:[UICollectionViewCell class]]) {
                id msg = extractMessageFromCell(view);
                if (msg) {
                    g_lastLongPressedMessage = msg;
                    break;
                }
            }
            view = view.superview;
        }
        // 如果仍未找到，尝试通过 getMessageFromMenuView 从 TableView/CollectionView 定位
        if (!g_lastLongPressedMessage) {
            g_lastLongPressedMessage = getMessageFromMenuView(self);
        }
    }
}

- (void)layoutSubviews {
    %orig;
    if ([self viewWithTag:30001]) return;

    id message = g_lastLongPressedMessage;
    if (!message) message = getMessageFromMenuView(self);

    if (!message || ![message isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) return;

    CGFloat menuH = self.bounds.size.height;
    CGFloat btnW = self.bounds.size.width - 32;

    UIButton *downloadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadBtn.tag = 30001;
    downloadBtn.frame = CGRectMake(16, menuH - 100, btnW, 44);
    [downloadBtn setTitle:@"📥 下载语音" forState:UIControlStateNormal];
    downloadBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.9];
    downloadBtn.layer.cornerRadius = 10;
    downloadBtn.tintColor = [UIColor whiteColor];
    [downloadBtn addTarget:self action:@selector(aweca_groupDownloadAction) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:downloadBtn];

    UIButton *settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsBtn.tag = 30002;
    settingsBtn.frame = CGRectMake(16, menuH - 50, btnW, 44);
    [settingsBtn setTitle:@"⚙️ 语音设置" forState:UIControlStateNormal];
    settingsBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.9];
    settingsBtn.layer.cornerRadius = 10;
    settingsBtn.tintColor = [UIColor whiteColor];
    [settingsBtn addTarget:self action:@selector(aweca_groupSettingsAction) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:settingsBtn];
}
%end

// ========== 下载和设置实现 ==========
static void doDownloadVoiceFromMenu(id menuView) {
    id message = g_lastLongPressedMessage;
    if (!message) message = getMessageFromMenuView((UIView *)menuView);
    if (!message) {
        [AWECAUtils showToast:@"无法获取消息对象"];
        return;
    }
    NSString *audioURL = extractAudioURLFromMessage(message);
    if (!audioURL.length) {
        [AWECAUtils showToast:@"无法获取音频链接，请先播放该语音"];
        return;
    }
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
        if (error || !tmpFile) {
            dispatch_async(dispatch_get_main_queue(), ^{ [AWECAUtils showToast:@"下载失败"]; });
            return;
        }
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

static void showFolderPicker(NSString *fileName, NSString *cdnURL, UIViewController *vc) { /* ... */ }

%ctor {
    [AWECAUtils ensureDirectoriesExist];
    [AWECAAudioReplacer shared];
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