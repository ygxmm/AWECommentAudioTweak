// TTS 管理器impl，火山引擎API一把梭
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECATTSManager.h"
#import "AWECAUtils.h"
#import "AWECAAudioReplacer.h"

// 无默认凭证，用户必须在配置页填写
#define kDefaultCluster     @"volcano_tts"
#define kDefaultVoiceType   @"BV700_V2_streaming"
#define kDefaultVoiceName   @"灿灿"

// 火山 API 地址
#define kTTSAPIURL @"https://openspeech.bytedance.com/api/v1/tts"
// 千问 API 地址
#define kQwenTTSAPIURL @"https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"

@interface AWECATTSManager ()
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, copy, readwrite) NSString *lastSynthesizedPath;
@end

@implementation AWECATTSManager

+ (instancetype)shared {
    static AWECATTSManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AWECATTSManager alloc] init];
        [instance loadConfig];
    });
    return instance;
}

#pragma mark - 合成语音，核心逻辑

- (void)synthesizeText:(NSString *)text
            completion:(void(^)(BOOL success, NSString *audioPath, NSString *error))completion {
    if (!text || text.length == 0) {
        if (completion) completion(NO, nil, @"请输入要合成的文字");
        return;
    }

    // 根据后端分发
    if (self.ttsProvider == AWECATTSProviderQwen) {
        [self synthesizeWithQwen:text completion:completion];
        return;
    }

    // === 火山引擎合成 ===

    // 凭证必填，没配就拦住
    if (self.appID.length == 0 || self.accessToken.length == 0) {
        if (completion) completion(NO, nil, @"请先在配置页填写 App ID 和 Access Token");
        return;
    }

    NSString *appid = self.appID;
    NSString *token = self.accessToken;
    NSString *cluster = (self.cluster.length > 0) ? self.cluster : kDefaultCluster;
    NSString *voice = (self.voiceType.length > 0) ? self.voiceType : kDefaultVoiceType;

    // 构造请求体
    NSDictionary *body = @{
        @"app": @{
            @"appid": appid,
            @"token": token,
            @"cluster": cluster
        },
        @"user": @{
            @"uid": @"aweca_user"
        },
        @"audio": @{
            @"voice_type": voice,
            @"encoding": @"mp3",
            @"speed_ratio": @(self.speedRatio > 0 ? self.speedRatio : 1.0),
            @"volume_ratio": @(self.volumeRatio > 0 ? self.volumeRatio : 1.0),
            @"pitch_ratio": @(self.pitchRatio > 0 ? self.pitchRatio : 1.0)
        },
        @"request": @{
            @"reqid": [[NSUUID UUID] UUIDString],
            @"text": text,
            @"text_type": @"plain",
            @"operation": @"query"
        }
    };

    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (jsonErr || !jsonData) {
        if (completion) completion(NO, nil, @"请求构造失败");
        return;
    }

    // 构造 HTTP 请求
    NSURL *url = [NSURL URLWithString:kTTSAPIURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = jsonData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    // 认证头，格式: Bearer;{token}
    NSString *authHeader = [NSString stringWithFormat:@"Bearer;%@", token];
    [request setValue:authHeader forHTTPHeaderField:@"Authorization"];
    request.timeoutInterval = 30;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, nil, [NSString stringWithFormat:@"网络错误: %@", error.localizedDescription]);
            });
            return;
        }

        if (!data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, nil, @"服务器无响应");
            });
            return;
        }

        [self parseResponse:data completion:completion];
    }] resume];
}

#pragma mark - 解析响应

- (void)parseResponse:(NSData *)data
           completion:(void(^)(BOOL success, NSString *audioPath, NSString *error))completion {
    NSError *jsonErr = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];

    if (jsonErr || !json) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, nil, @"响应解析失败");
        });
        return;
    }

    NSInteger code = [json[@"code"] integerValue];
    if (code != 3000) {
        NSString *msg = json[@"message"] ?: @"未知错误";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, nil, [NSString stringWithFormat:@"API错误(%ld): %@", (long)code, msg]);
        });
        return;
    }

    NSString *b64Data = json[@"data"];
    if (!b64Data || b64Data.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, nil, @"音频数据为空");
        });
        return;
    }

    // base64 解码
    NSData *audioData = [[NSData alloc] initWithBase64EncodedString:b64Data options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!audioData || audioData.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, nil, @"音频解码失败");
        });
        return;
    }

    // 写入文件
    [AWECAUtils ensureDirectoriesExist];
    NSString *savePath = [[AWECAUtils audioSavePath] stringByAppendingPathComponent:@"tts_result.mp3"];
    BOOL writeOK = [audioData writeToFile:savePath atomically:YES];

    if (!writeOK) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, nil, @"音频保存失败");
        });
        return;
    }

    // 保存路径
    self.lastSynthesizedPath = savePath;
    [self saveConfig];

    dispatch_async(dispatch_get_main_queue(), ^{
        // 先存到 ttsAudioPath
        AWECAAudioReplacer *replacer = [AWECAAudioReplacer shared];
        replacer.ttsAudioPath = savePath;
        [replacer saveState];

        // 检测是否有普通音频冲突
        BOOL hasNormalAudio = replacer.enabled && replacer.replacementAudioPath.length > 0 && !replacer.isUsingTTS;
        if (hasNormalAudio) {
            // 有冲突，弹选择器
            [self showTTSConflictAlertWithPath:savePath completion:completion];
        } else {
            // 无冲突，直接设为替换
            [replacer setReplacementFromPath:savePath completion:^(BOOL ok) {
                if (completion) {
                    if (ok) {
                        double dur = [AWECAUtils audioDurationAtPath:savePath];
                        completion(YES, savePath, [NSString stringWithFormat:@"语音合成成功 (%.1f秒)", dur]);
                    } else {
                        completion(NO, savePath, @"合成成功但设置替换失败");
                    }
                }
            }];
        }
    });
}

#pragma mark - 千问合成

- (void)synthesizeWithQwen:(NSString *)text
                completion:(void(^)(BOOL success, NSString *audioPath, NSString *error))completion {
    if (self.qwenAPIKey.length == 0) {
        if (completion) completion(NO, nil, @"请先在配置页填写千问 API Key");
        return;
    }

    NSString *voice = (self.voiceType.length > 0) ? self.voiceType : @"Cherry";

    // 构造请求体
    NSDictionary *body = @{
        @"model": @"qwen3-tts-flash",
        @"input": @{
            @"text": text,
            @"voice": voice
        }
    };

    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (jsonErr || !jsonData) {
        if (completion) completion(NO, nil, @"请求构造失败");
        return;
    }

    NSURL *url = [NSURL URLWithString:kQwenTTSAPIURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = jsonData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.qwenAPIKey] forHTTPHeaderField:@"Authorization"];
    request.timeoutInterval = 30;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, nil, [NSString stringWithFormat:@"网络错误: %@", error.localizedDescription]);
            });
            return;
        }
        if (!data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, nil, @"服务器无响应");
            });
            return;
        }
        [self parseQwenResponse:data completion:completion];
    }] resume];
}

- (void)parseQwenResponse:(NSData *)data
               completion:(void(^)(BOOL success, NSString *audioPath, NSString *error))completion {
    NSError *jsonErr = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];

    if (jsonErr || !json) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, nil, @"响应解析失败");
        });
        return;
    }

    // 检查错误码
    NSString *code = json[@"code"];
    if (code) {
        NSString *msg = json[@"message"] ?: @"未知错误";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, nil, [NSString stringWithFormat:@"千问错误: %@", msg]);
        });
        return;
    }

    // 拿音频 URL: output.audio.url
    NSDictionary *output = json[@"output"];
    NSDictionary *audio = output[@"audio"];
    NSString *audioURL = audio[@"url"];

    if (!audioURL || audioURL.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, nil, @"音频地址为空");
        });
        return;
    }

    // 下载音频文件
    NSURL *downloadURL = [NSURL URLWithString:audioURL];
    NSURLSessionConfiguration *dlConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *dlSession = [NSURLSession sessionWithConfiguration:dlConfig];

    [[dlSession dataTaskWithURL:downloadURL completionHandler:^(NSData *audioData, NSURLResponse *resp, NSError *dlErr) {
        if (dlErr || !audioData || audioData.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, nil, @"音频下载失败");
            });
            return;
        }

        // 保存到本地
        [AWECAUtils ensureDirectoriesExist];
        NSString *savePath = [[AWECAUtils audioSavePath] stringByAppendingPathComponent:@"qwen_tts_result.wav"];
        BOOL writeOK = [audioData writeToFile:savePath atomically:YES];

        if (!writeOK) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, nil, @"音频保存失败");
            });
            return;
        }

        self.lastSynthesizedPath = savePath;
        [self saveConfig];

        dispatch_async(dispatch_get_main_queue(), ^{
            // 先存到 ttsAudioPath
            AWECAAudioReplacer *replacer = [AWECAAudioReplacer shared];
            replacer.ttsAudioPath = savePath;
            [replacer saveState];

            // 检测是否有普通音频冲突
            BOOL hasNormalAudio = replacer.enabled && replacer.replacementAudioPath.length > 0 && !replacer.isUsingTTS;
            if (hasNormalAudio) {
                [self showTTSConflictAlertWithPath:savePath completion:completion];
            } else {
                [replacer setReplacementFromPath:savePath completion:^(BOOL ok) {
                    if (completion) {
                        if (ok) {
                            double dur = [AWECAUtils audioDurationAtPath:savePath];
                            completion(YES, savePath, [NSString stringWithFormat:@"语音合成成功 (%.1f秒)", dur]);
                        } else {
                            completion(NO, savePath, @"合成成功但设置替换失败");
                        }
                    }
                }];
            }
        });
    }] resume];
}

#pragma mark - 冲突选择器

- (void)showTTSConflictAlertWithPath:(NSString *)ttsPath
                          completion:(void(^)(BOOL success, NSString *audioPath, NSString *error))completion {
    UIViewController *topVC = [AWECAUtils topViewController];
    if (!topVC) {
        // 没VC就直接覆盖，别卡死
        [[AWECAAudioReplacer shared] setReplacementFromPath:ttsPath completion:^(BOOL ok) {
            if (completion) completion(ok, ttsPath, ok ? @"语音合成成功" : @"设置替换失败");
        }];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"当前已选择普通语音替换"
                                                                  message:@"是否切换为Ai合成语音?"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"使用Ai" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[AWECAAudioReplacer shared] setReplacementFromPath:ttsPath completion:^(BOOL ok) {
            if (completion) {
                if (ok) {
                    double dur = [AWECAUtils audioDurationAtPath:ttsPath];
                    completion(YES, ttsPath, [NSString stringWithFormat:@"语音合成成功 (%.1f秒)", dur]);
                } else {
                    completion(NO, ttsPath, @"合成成功但设置替换失败");
                }
            }
        }];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"不使用Ai" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // ttsAudioPath 已存好，不动 replacementAudioPath
        if (completion) completion(YES, ttsPath, @"合成已保存，当前使用普通语音");
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (completion) completion(YES, ttsPath, @"合成已保存");
    }]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = topVC.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width / 2, topVC.view.bounds.size.height, 0, 0);
    }

    [topVC presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 试听播放

- (void)playAudioAtPath:(NSString *)path {
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [AWECAUtils showToast:@"音频文件不存在"];
        return;
    }

    [self stopPlayback];

    NSError *err = nil;
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&err];
    if (err || !self.player) {
        [AWECAUtils showToast:@"播放失败"];
        return;
    }

    self.player.delegate = self;

    // 设置音频会话，混合播放不打断别人
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers
                        error:nil];
    [audioSession setActive:YES error:nil];

    [self.player play];
}

- (void)stopPlayback {
    if (self.player && self.player.isPlaying) {
        [self.player stop];
    }
    self.player = nil;
}

- (BOOL)isPlaying {
    return self.player && self.player.isPlaying;
}

// 播完了自动清理
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    self.player = nil;
}

#pragma mark - 持久化

- (void)saveConfig {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // 后端选择
    [d setInteger:self.ttsProvider forKey:kAWECATTSProvider];
    // 火山引擎
    if (self.appID) [d setObject:self.appID forKey:kAWECATTSAppID];
    if (self.accessToken) [d setObject:self.accessToken forKey:kAWECATTSAccessToken];
    if (self.cluster) [d setObject:self.cluster forKey:kAWECATTSCluster];
    // 千问
    if (self.qwenAPIKey) [d setObject:self.qwenAPIKey forKey:kAWECATTSQwenAPIKey];
    // 通用
    if (self.voiceType) [d setObject:self.voiceType forKey:kAWECATTSVoiceType];
    if (self.voiceName) [d setObject:self.voiceName forKey:kAWECATTSVoiceName];
    [d setFloat:self.speedRatio forKey:kAWECATTSSpeedRatio];
    [d setFloat:self.volumeRatio forKey:kAWECATTSVolumeRatio];
    [d setFloat:self.pitchRatio forKey:kAWECATTSPitchRatio];
    if (self.lastSynthesizedPath) [d setObject:self.lastSynthesizedPath forKey:kAWECATTSLastPath];
    [d synchronize];
}

- (void)loadConfig {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // 后端选择
    self.ttsProvider = [d integerForKey:kAWECATTSProvider];
    // 火山引擎
    self.appID = [d objectForKey:kAWECATTSAppID];
    self.accessToken = [d objectForKey:kAWECATTSAccessToken];
    self.cluster = [d objectForKey:kAWECATTSCluster];
    // 千问
    self.qwenAPIKey = [d objectForKey:kAWECATTSQwenAPIKey];
    // 通用
    self.voiceType = [d objectForKey:kAWECATTSVoiceType];
    self.voiceName = [d objectForKey:kAWECATTSVoiceName];

    float sp = [d floatForKey:kAWECATTSSpeedRatio];
    float vo = [d floatForKey:kAWECATTSVolumeRatio];
    float pi = [d floatForKey:kAWECATTSPitchRatio];
    // 没存过就给默认值
    self.speedRatio = (sp > 0.01) ? sp : 1.0;
    self.volumeRatio = (vo > 0.01) ? vo : 1.0;
    self.pitchRatio = (pi > 0.01) ? pi : 1.0;

    self.lastSynthesizedPath = [d objectForKey:kAWECATTSLastPath];
}

@end
