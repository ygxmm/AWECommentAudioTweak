// AWECommentAudioTweak - 终极调试版（打印所有窗口视图树）
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

// 🔧 占位菜单类（待替换）
@interface AWEIMMessageLongPressMenuView : UIView <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@end
@interface AWEIMMessageLongPressMenuViewCell : UICollectionViewCell
- (void)configWithMenuItem:(id)menuItem;
@end

@interface AWEIMMessageListViewController : UIViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message;
- (void)awe_dumpAllWindows; // 调试用
- (void)awe_dumpView:(UIView *)view depth:(int)depth maxDepth:(int)maxDepth;
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

static id g_lastLongPressedMessage = nil;

// 获取真实音频时长
static double realAudioDuration(NSString *filePath) {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    CMTime time = asset.duration;
    if (CMTIME_IS_VALID(time)) return CMTimeGetSeconds(time);
    return 0.0;
}

// 评论区功能...（保持不变，这里省略，见前文完整版）
// 为节省篇幅，此处只展示关键调试修改，实际文件需保留所有其他代码

// ========== 私信语音时长修正 ==========
// ...（同上）

// ========== 长按消息记录（含终极调试） ==========
%hook AWEIMMessageListViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message {
    %orig;
    g_lastLongPressedMessage = message;
    NSLog(@"[AWE] 长按消息已记录：%@", [message class]);

    // 延时 0.8 秒，确保菜单已完全显示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self awe_dumpAllWindows];
    });
}

- (void)awe_dumpAllWindows {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        NSLog(@"=== 窗口: %@ (hidden=%d) ===", window, window.hidden);
        [self awe_dumpView:window depth:0 maxDepth:3];
    }
}

- (void)awe_dumpView:(UIView *)view depth:(int)depth maxDepth:(int)maxDepth {
    if (depth > maxDepth) return;
    NSLog(@"%*s%@", depth * 2, "", NSStringFromClass([view class]));
    for (UIView *sub in view.subviews) {
        [self awe_dumpView:sub depth:depth+1 maxDepth:maxDepth];
    }
}
%end

// ========== 以下 Hook 占位菜单类（等类名确定后替换） ==========
%hook AWEIMMessageLongPressMenuView
// ...（原布局、数据源、点击回调代码保留，但暂时不会生效）
%end

// 下载和设置实现...（保留）

%ctor {
    // 初始化...
}