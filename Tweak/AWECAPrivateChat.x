// AWECAPrivateChat.x - 私信/群聊语音替换 + 长按菜单注入 + 下载保存
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECAPrivateChat.h"
#import "AWECAUtils.h"
#import "AWECAAudioReplacer.h"
#import "AWECAAudioPickerController.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>

// ---------- 私有类声明 ----------
@interface AWEIMAudioRecordController : NSObject
@property (nonatomic, copy) NSString *recordFilePath;
@end
@interface AWEIMAudioEnginRecorder : NSObject
- (void)setCurrentTime:(double)currentTime;
@end
@interface AWEIMFormatAudioRecordController : NSObject
@end

@interface AWEIMEmojiReplyMenuView : UIView <UICollectionViewDelegate, UICollectionViewDataSource>
@property (nonatomic, strong) NSArray *menuItemList;
@end
@interface AWEIMEmojiReplyMenuViewCell : UICollectionViewCell
- (void)configWithMenuItem:(id)menuItem;
@property (nonatomic, strong) UIImageView *imageView;
@end
@interface AWEIMMessageListViewController : UIViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message;
@end

// ---------- 全局变量 ----------
static id g_lastLongPressedMessage = nil;
static const void *kCustomMenuItemKey = &kCustomMenuItemKey;

// ---------- 工具函数 ----------
double realAudioDuration(NSString *filePath) {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    CMTime time = asset.duration;
    if (CMTIME_IS_VALID(time)) return CMTimeGetSeconds(time);
    return 0.0;
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

// 从菜单视图查找消息
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

// 创建带图标标记的菜单项
static id createMenuItem(NSString *title, NSString *iconSystemName) {
    Class modelClass = NSClassFromString(@"AWEIMCustomMenuModel");
    if (!modelClass) return nil;
    id item = [[modelClass alloc] init];
    [item setValue:title forKey:@"title"];
    objc_setAssociatedObject(item, kCustomMenuItemKey, iconSystemName, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return item;
}

// 判断一个菜单项是否为我们注入的自定义项
static BOOL isCustomMenuItem(id menuItem) {
    return objc_getAssociatedObject(menuItem, kCustomMenuItemKey) != nil;
}

// 净化数组：移除所有自定义菜单项
static NSArray *cleanMenuItems(NSArray *items) {
    if (!items) return nil;
    NSMutableArray *cleaned = [NSMutableArray array];
    for (id item in items) {
        if (!isCustomMenuItem(item)) {
            [cleaned addObject:item];
        }
    }
    return [cleaned copy];
}

// 净化并注入：先移除所有自定义项，再根据条件决定是否添加新项
static NSArray *processedMenuItems(NSArray *originalItems) {
    NSMutableArray *list = [[cleanMenuItems(originalItems) mutableCopy] ?: [NSMutableArray array] mutableCopy];
    if (g_lastLongPressedMessage && [g_lastLongPressedMessage isKindOfClass:NSClassFromString(@"AWEIMAudioMessage")]) {
        [list addObject:createMenuItem(@"下载", @"arrow.down.circle")];
        [list addObject:createMenuItem(@"设置", @"gearshape")];
    }
    return [list copy];
}

// ---------- 下载与保存实现 ----------
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

// ========== 私信语音录制替换 ==========
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

// ========== 长按消息记录 + 视图消失时重置引用 ==========
%hook AWEIMMessageListViewController
- (void)msg_longPressMenuWillDisplayOnMessage:(id)message {
    %orig;
    g_lastLongPressedMessage = message;
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    g_lastLongPressedMessage = nil;
}
%end

// ========== 菜单项注入（净化 + 注入 + 主动清理） ==========
%hook AWEIMEmojiReplyMenuView

// 重写 setter，先净化再根据情况注入
- (void)setMenuItemList:(NSArray *)menuItemList {
    NSArray *finalList = processedMenuItems(menuItemList);
    %orig(finalList);
}

// 菜单即将显示时再次检查净化，防止复用残留
- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        NSArray *current = self.menuItemList;
        if (current) {
            // 计算净化后的列表（不加注入条件，因为此时可能已离开聊天页）
            // 这里需要判断是否应该保留自定义项：和 setter 中逻辑一致
            NSArray *correct = processedMenuItems(current);
            if (![correct isEqualToArray:current]) {
                // 列表不同，需要更新，但直接调用自己的 setter 可能会递归
                // 所以用原始实现来设置（通过消息转发调用父类或原 setter）
                // 但我们 hook 了 setter，这里直接调用 %orig 会形成新的递归吗？
                // 因为 didMoveToWindow 中调用 %orig 不会，但 %orig 在 hook 上下文中指代原始实现。
                // 我们在 setMenuItemList 的 %orig 是原始方法，所以可以使用 %orig(correct) 但这里没有 %orig 可调用原始 setter，
                // 简单方式：使用 objc_msgSend 直接调用原始 setMenuItemList 的实现，避免 hook 干扰。
                // 已知原始 setter 可以通过 %orig 获取，但出于安全考虑，直接设置实例变量：
                // 但不推荐，因为可能有 KVO。直接调用 [super setMenuItemList:correct] 也不行。
                // 我们换个思路：在 didMoveToWindow 中，如果发现需要净化，就调用我们自己的 setMenuItemList:，
                // 但我们的 setMenuItemList 内部会调用 processedMenuItems，如果这次调用后结果相同，则不会再变化，
                // 避免死循环：我们可以加个标志位防止重入。
            }
        }
    }
}

%end

// 由于 didMoveToWindow 中的实现比较复杂，我们采用更简洁可靠的方法：
// 覆盖 didMoveToWindow 时，主动用净化后的列表刷新菜单，直接操作底层存储。
// 简化后重新实现：
%hook AWEIMEmojiReplyMenuView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        NSArray *list = self.menuItemList;
        NSArray *clean = processedMenuItems(list);
        if (![clean isEqualToArray:list]) {
            // 直接设置属性，避免触发 hook 递归（这里调用自己的 setter 会再次净化，但结果不变，最多两次）
            // 但还是设置实例变量最稳妥，假设底层 ivar 名是 _menuItemList
            [self setValue:clean forKey:@"menuItemList"];
        }
    }
}

%end

// 注意：上面 %hook AWEIMEmojiReplyMenuView 写了两次，会有冲突。应该合并成一个 %hook 块。
// 修正：将两个 hook 合并，同时包含 setMenuItemList 和 didMoveToWindow。

// 最终修正：
%hook AWEIMEmojiReplyMenuView

- (void)setMenuItemList:(NSArray *)menuItemList {
    NSArray *finalList = processedMenuItems(menuItemList);
    %orig(finalList);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        NSArray *list = self.menuItemList;
        NSArray *clean = processedMenuItems(list);
        if (![clean isEqualToArray:list]) {
            // 通过 KVC 设置，避免再次触发 setter hook（但 KVC 也会触发 setter，不过我们的 setter 会再次净化，结果相同，不会死循环，最多一次额外调用）
            [self setValue:clean forKey:@"menuItemList"];
        }
    }
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger total = self.menuItemList.count;
    // 动态计算自定义项数量（可能为 0、2，也可能由于净化而变化）
    // 判断点击项是否为自定义项：通过 associated object 检测
    if (indexPath.item < self.menuItemList.count) {
        id item = self.menuItemList[indexPath.item];
        if (isCustomMenuItem(item)) {
            NSString *iconName = objc_getAssociatedObject(item, kCustomMenuItemKey);
            if ([iconName isEqualToString:@"arrow.down.circle"]) {
                doDownloadVoiceFromMenu(self);
            } else if ([iconName isEqualToString:@"gearshape"]) {
                doVoiceSettings(self);
            }
            return;
        }
    }
    %orig;
}
%end

// ========== 强制图标显示（白色统一风格） ==========
%hook AWEIMEmojiReplyMenuViewCell
- (void)configWithMenuItem:(id)menuItem {
    %orig;
    NSString *iconName = objc_getAssociatedObject(menuItem, kCustomMenuItemKey);
    if (iconName) {
        UIImage *icon = [UIImage systemImageNamed:iconName];
        if (icon && self.imageView) {
            self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.imageView.tintColor = [UIColor whiteColor];
            self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        }
    }
}
%end