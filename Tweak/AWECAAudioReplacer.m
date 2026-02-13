// 音频替换器impl，录音？不存在的
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECAAudioReplacer.h"
#import "AWECAUtils.h"

// ttsAudioPath 持久化 key
#define kAWECATTSAudioPath @"AWECATTSAudioPath"

@implementation AWECAAudioReplacer

+ (instancetype)shared {
    static AWECAAudioReplacer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AWECAAudioReplacer alloc] init];
        [instance loadState];
    });
    return instance;
}

#pragma mark - 设置替换

// 当前生效的是不是AI合成的
- (BOOL)isUsingTTS {
    if (!self.enabled || !self.replacementAudioPath || !self.ttsAudioPath) return NO;
    return [self.replacementAudioPath isEqualToString:self.ttsAudioPath];
}

- (void)setReplacementFromPath:(NSString *)path completion:(void(^)(BOOL success))completion {
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (completion) completion(NO);
        return;
    }

    NSString *ext = path.pathExtension.lowercaseString;

    // m4a/aac直接上，其他的转一下
    if ([ext isEqualToString:@"m4a"] || [ext isEqualToString:@"aac"]) {
        self.replacementAudioPath = path;
        self.enabled = YES;
        [self saveState];
        if (completion) completion(YES);
    } else {
        // 格式不对，转码走起
        [AWECAUtils ensureDirectoriesExist];
        NSString *outputName = [NSString stringWithFormat:@"converted_%.0f.m4a",
                                [[NSDate date] timeIntervalSince1970]];
        NSString *outputPath = [[AWECAUtils importPath] stringByAppendingPathComponent:outputName];

        [AWECAUtils convertAudioAtPath:path toOutputPath:outputPath completion:^(BOOL success, NSError *error) {
            if (success) {
                self.replacementAudioPath = outputPath;
                self.enabled = YES;
                [self saveState];
                [AWECAUtils showToast:@"音频已转码并设置"];
            } else {
                [AWECAUtils showToast:@"音频转码失败"];
            }
            if (completion) completion(success);
        }];
    }
}

#pragma mark - TTS专用替换，转码+命名+清理

- (void)setReplacementFromTTSPath:(NSString *)path
                             text:(NSString *)text
                        voiceName:(NSString *)voiceName
                         provider:(NSInteger)provider
                       completion:(void(^)(BOOL success))completion {
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (completion) completion(NO);
        return;
    }

    [AWECAUtils ensureDirectoriesExist];

    // 根据后端选目录
    NSString *destDir = (provider == 1) ? [AWECAUtils ttsQwenPath] : [AWECAUtils ttsVolcanoPath];

    // 拼文件名: 文字-音色.m4a
    NSString *cleanText = [AWECAUtils sanitizeFilename:text maxLength:20];
    NSString *cleanVoice = [AWECAUtils sanitizeFilename:voiceName maxLength:20];
    NSString *fileName = [NSString stringWithFormat:@"%@-%@.m4a", cleanText, cleanVoice];
    NSString *outputPath = [destDir stringByAppendingPathComponent:fileName];

    // 重名加时间戳
    if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
        fileName = [NSString stringWithFormat:@"%@-%@_%.0f.m4a", cleanText, cleanVoice, [[NSDate date] timeIntervalSince1970]];
        outputPath = [destDir stringByAppendingPathComponent:fileName];
    }

    NSString *ext = path.pathExtension.lowercaseString;
    NSString *originalPath = [path copy];

    if ([ext isEqualToString:@"m4a"] || [ext isEqualToString:@"aac"]) {
        // 本来就是m4a，直接copy过去
        [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
        NSError *err = nil;
        BOOL ok = [[NSFileManager defaultManager] copyItemAtPath:path toPath:outputPath error:&err];
        if (ok) {
            // 删原始文件
            [[NSFileManager defaultManager] removeItemAtPath:originalPath error:nil];
            self.replacementAudioPath = outputPath;
            self.enabled = YES;
            [self saveState];
        }
        if (completion) completion(ok);
    } else {
        // 转码走起
        [AWECAUtils convertAudioAtPath:path toOutputPath:outputPath completion:^(BOOL success, NSError *error) {
            if (success) {
                // 转码成功，删原始mp3/wav
                [[NSFileManager defaultManager] removeItemAtPath:originalPath error:nil];
                self.replacementAudioPath = outputPath;
                self.enabled = YES;
                [self saveState];
            } else {
                [AWECAUtils showToast:@"音频转码失败"];
            }
            if (completion) completion(success);
        }];
    }
}

#pragma mark - 清除

- (void)clearReplacement {
    self.enabled = NO;
    self.replacementAudioPath = nil;
    [self saveState];
    [AWECAUtils showToast:@"已关闭语音替换"];
}

#pragma mark - 执行替换

- (BOOL)replaceAudioAtPath:(NSString *)targetPath {
    if (!self.enabled || !self.replacementAudioPath) {
        return NO;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:self.replacementAudioPath]) {
        [self clearReplacement];
        return NO;
    }

    NSError *error = nil;
    // 干掉原始录音
    [[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
    // 替换音频copy过去
    BOOL ok = [[NSFileManager defaultManager] copyItemAtPath:self.replacementAudioPath
                                                      toPath:targetPath
                                                       error:&error];
    return ok;
}

#pragma mark - 持久化

- (void)saveState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.enabled forKey:kAWECAReplacementEnabled];
    [defaults setObject:self.replacementAudioPath forKey:kAWECAReplacementAudioPath];
    [defaults setObject:self.ttsAudioPath forKey:kAWECATTSAudioPath];
    [defaults synchronize];
}

- (void)loadState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.enabled = [defaults boolForKey:kAWECAReplacementEnabled];
    self.replacementAudioPath = [defaults objectForKey:kAWECAReplacementAudioPath];
    self.ttsAudioPath = [defaults objectForKey:kAWECATTSAudioPath];

    // 路径没了就自动关掉
    if (self.replacementAudioPath && ![[NSFileManager defaultManager] fileExistsAtPath:self.replacementAudioPath]) {
        self.enabled = NO;
        self.replacementAudioPath = nil;
        [self saveState];
    }
    // ttsAudioPath 文件没了也清掉
    if (self.ttsAudioPath && ![[NSFileManager defaultManager] fileExistsAtPath:self.ttsAudioPath]) {
        self.ttsAudioPath = nil;
        [self saveState];
    }
}

@end
