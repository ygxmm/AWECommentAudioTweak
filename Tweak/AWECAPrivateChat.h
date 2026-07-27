// AWECAPrivateChat.h
#import <UIKit/UIKit.h>

// 全局消息对象（跨文件访问）
extern id g_lastLongPressedMessage;

// 创建菜单项（标题 + 图标名）
extern id createMenuItem(NSString *title, NSString *iconSystemName);

// 下载与设置回调
extern void doDownloadVoiceFromMenu(id menuView);
extern void doVoiceSettings(id menuView);

// 音频时长获取
extern double realAudioDuration(NSString *filePath);

// 保存对话框及下载函数（如果其他模块需要，也可声明，本例只在私信模块内部使用）
extern void showSaveDialogForURL(NSString *urlString, NSString *msgID);
extern void downloadFromURL(NSString *urlStr, NSString *savePath);
extern void showFolderPicker(NSString *fileName, NSString *cdnURL, UIViewController *vc);