// TTS 核心管理器，API调用+播放一把梭
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// 持久化 key - 火山引擎
#define kAWECATTSAppID        @"AWECATTSAppID"
#define kAWECATTSAccessToken  @"AWECATTSAccessToken"
#define kAWECATTSCluster      @"AWECATTSCluster"
#define kAWECATTSVoiceType    @"AWECATTSVoiceType"
#define kAWECATTSVoiceName    @"AWECATTSVoiceName"
#define kAWECATTSSpeedRatio   @"AWECATTSSpeedRatio"
#define kAWECATTSVolumeRatio  @"AWECATTSVolumeRatio"
#define kAWECATTSPitchRatio   @"AWECATTSPitchRatio"
#define kAWECATTSLastPath     @"AWECATTSLastPath"

// 持久化 key - 千问
#define kAWECATTSProvider     @"AWECATTSProvider"
#define kAWECATTSQwenAPIKey   @"AWECATTSQwenAPIKey"

// TTS 后端枚举
typedef NS_ENUM(NSInteger, AWECATTSProvider) {
    AWECATTSProviderVolcano = 0,  // 火山引擎
    AWECATTSProviderQwen    = 1,  // 千问
};

@interface AWECATTSManager : NSObject <AVAudioPlayerDelegate>

+ (instancetype)shared;

// 当前后端
@property (nonatomic, assign) AWECATTSProvider ttsProvider;

// 火山引擎三件套
@property (nonatomic, copy) NSString *appID;
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) NSString *cluster;

// 千问凭证
@property (nonatomic, copy) NSString *qwenAPIKey;

// 当前音色
@property (nonatomic, copy) NSString *voiceType;
@property (nonatomic, copy) NSString *voiceName;

// 语音参数，0.2~3.0，默认1.0
@property (nonatomic, assign) float speedRatio;
@property (nonatomic, assign) float volumeRatio;
@property (nonatomic, assign) float pitchRatio;

// 上次合成的音频路径
@property (nonatomic, copy, readonly) NSString *lastSynthesizedPath;

// 合成语音，回调在主线程
- (void)synthesizeText:(NSString *)text
            completion:(void(^)(BOOL success, NSString *audioPath, NSString *error))completion;

// 试听三件套
- (void)playAudioAtPath:(NSString *)path;
- (void)stopPlayback;
- (BOOL)isPlaying;

// 持久化
- (void)saveConfig;
- (void)loadConfig;

@end
