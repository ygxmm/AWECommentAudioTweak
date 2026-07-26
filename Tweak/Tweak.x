// AWECommentAudioTweak - 调试版（打印群聊菜单布局信息）
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

// 私信类声明（保持原样）
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

// 前置声明（保留原有功能）
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

// ... 保留所有原有函数实现（此处省略，实际编译时需包含完整实现）

// ========== 群聊菜单调试 Hook ==========
%hook AFDHoverableContainerView

- (void)didMoveToSuperview {
    %orig;
    NSLog(@"[DEBUG] AFDHoverableContainerView didMoveToSuperview, superview: %@, frame: %@",
          self.superview, NSStringFromCGRect(self.frame));
}

- (void)layoutSubviews {
    %orig;
    NSLog(@"[DEBUG] AFDHoverableContainerView layoutSubviews called, frame: %@, bounds: %@",
          NSStringFromCGRect(self.frame), NSStringFromCGRect(self.bounds));
    for (UIView *sub in self.subviews) {
        NSLog(@"[DEBUG]   subview: %@, frame: %@, contentSize: %@",
              NSStringFromClass([sub class]),
              NSStringFromCGRect(sub.frame),
              [sub isKindOfClass:[UICollectionView class]] ? NSStringFromCGSize(((UICollectionView *)sub).contentSize) : @"N/A");
    }
}

%end

// ========== 其余原有 Hook 保持不变 ==========
// ... 包括评论区、私信菜单、下载设置等所有功能（此处省略，实际编译需保留）

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
        // 注入群聊按钮回调（如有需要）
        if (!class_respondsToSelector(hoverClass, @selector(aweca_groupDownloadAction))) {
            class_addMethod(hoverClass, @selector(aweca_groupDownloadAction), (IMP)aweca_groupDownloadAction, "v@:");
        }
        if (!class_respondsToSelector(hoverClass, @selector(aweca_groupSettingsAction))) {
            class_addMethod(hoverClass, @selector(aweca_groupSettingsAction), (IMP)aweca_groupSettingsAction, "v@:");
        }
    }
}