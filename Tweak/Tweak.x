// AWECommentAudioTweak - 增强调试版（递归遍历子视图）
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

static id g_lastLongPressedMessage = nil;

// 省略所有原有功能（评论区、语音替换、AI 按钮等），实际编译需保留

// ========== 增强调试 Hook：递归打印子视图 ==========
%hook AFDHoverableContainerView

- (void)didMoveToSuperview {
    %orig;
    NSLog(@"[DEBUG] AFDHoverableContainerView didMoveToSuperview, superview: %@, frame: %@",
          self.superview, NSStringFromCGRect(self.frame));
}

- (void)layoutSubviews {
    %orig;
    NSLog(@"[DEBUG] AFDHoverableContainerView layoutSubviews, frame: %@, bounds: %@",
          NSStringFromCGRect(self.frame), NSStringFromCGRect(self.bounds));
    // 递归遍历所有子视图，找到 UICollectionView 并打印其 frame 和 contentSize
    void (^logSubviews)(UIView *, int) = ^(UIView *view, int depth) {
        NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
        NSLog(@"%@[DEBUG] %@ frame: %@ contentSize: %@",
              indent,
              NSStringFromClass([view class]),
              NSStringFromCGRect(view.frame),
              [view isKindOfClass:[UICollectionView class]] ? NSStringFromCGSize(((UICollectionView *)view).contentSize) : @"N/A");
        for (UIView *sub in view.subviews) {
            logSubviews(sub, depth + 1);
        }
    };
    logSubviews(self, 0);
}

%end

// ========== 保留其他所有功能（评论区、下载等） ==========
// ... 此处省略，实际编译需包含完整实现

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [AWECAUtils ensureDirectoriesExist];
        [AWECAAudioReplacer shared];
    });
    setupAudioInputElementHook();
    setupAudioIconElementHook();
    setupStackViewLayoutHook();
}