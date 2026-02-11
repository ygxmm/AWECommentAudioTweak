// 音色列表页，火山300+/千问49音色随便挑
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import <UIKit/UIKit.h>
#import "AWECATTSManager.h"

@interface AWECATTSVoiceListController : UITableViewController <UISearchBarDelegate>

// 指定后端，决定显示哪套音色
@property (nonatomic, assign) AWECATTSProvider provider;

// 选完回调，带 voiceType 和 voiceName
@property (nonatomic, copy) void(^onVoiceSelected)(NSString *voiceType, NSString *voiceName);

@end
