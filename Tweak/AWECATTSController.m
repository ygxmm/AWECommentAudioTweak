// TTS 主页面impl，合成语音的主战场
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECATTSController.h"
#import "AWECATTSManager.h"
#import "AWECATTSVoiceListController.h"
#import "AWECAUtils.h"

#define kTextMaxLength 300
#define kCellFont [UIFont systemFontOfSize:15]

@interface AWECATTSController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, assign) BOOL isSynthesizing;
@end

@implementation AWECATTSController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self setupUI];
    [self updateTitleView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateTitleView];
    // 回到主页面时缩回紧凑高度
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *sheet = self.navigationController.sheetPresentationController;
        if (sheet) {
            [sheet animateChanges:^{
                sheet.selectedDetentIdentifier = @"ttsCompact";
            }];
        }
    }
}

#pragma mark - 标题: 音色: xxx

- (void)updateTitleView {
    AWECATTSManager *mgr = [AWECATTSManager shared];
    NSString *name = mgr.voiceName.length > 0 ? mgr.voiceName : @"灿灿";
    NSString *tag = (mgr.ttsProvider == AWECATTSProviderQwen) ? @"千问" : @"火山";
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = [NSString stringWithFormat:@"音色: %@ (%@)", name, tag];
    titleLabel.font = [UIFont systemFontOfSize:13];
    titleLabel.textColor = [UIColor secondaryLabelColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleLabel sizeToFit];
    self.navigationItem.titleView = titleLabel;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - 布局: textView + 按钮行

- (void)setupUI {
    // 键入框容器，带边框
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    container.layer.cornerRadius = 8;
    container.layer.borderWidth = 0.5;
    container.layer.borderColor = [UIColor separatorColor].CGColor;
    [self.view addSubview:container];

    // textView
    UITextView *tv = [[UITextView alloc] init];
    tv.font = kCellFont;
    tv.backgroundColor = [UIColor clearColor];
    tv.delegate = self;
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    // 键盘上方加"完成"按钮
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    bar.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)]
    ];
    tv.inputAccessoryView = bar;
    [container addSubview:tv];
    self.textView = tv;

    // placeholder
    UILabel *ph = [[UILabel alloc] init];
    ph.text = @"在这里输入要合成的文字...";
    ph.font = kCellFont;
    ph.textColor = [UIColor placeholderTextColor];
    ph.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:ph];
    self.placeholderLabel = ph;

    // 合成替换按钮
    UIButton *synthBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [synthBtn setTitle:@"合成替换" forState:UIControlStateNormal];
    synthBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [synthBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    synthBtn.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    synthBtn.layer.cornerRadius = 8;
    synthBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [synthBtn addTarget:self action:@selector(synthesize)
        forControlEvents:UIControlEventTouchUpInside];

    // 音色选择按钮
    UIButton *voiceBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [voiceBtn setTitle:@"音色选择" forState:UIControlStateNormal];
    voiceBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [voiceBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    voiceBtn.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    voiceBtn.layer.cornerRadius = 8;
    voiceBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [voiceBtn addTarget:self action:@selector(pushVoiceList)
        forControlEvents:UIControlEventTouchUpInside];

    // 水平排列
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[synthBtn, voiceBtn]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    // 约束
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        // 容器距顶部 8pt
        [container.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [container.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [container.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [container.heightAnchor constraintEqualToConstant:120],
        // textView 填满容器
        [tv.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [tv.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        [tv.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4],
        [tv.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
        // placeholder
        [ph.topAnchor constraintEqualToAnchor:tv.topAnchor constant:8],
        [ph.leadingAnchor constraintEqualToAnchor:tv.leadingAnchor constant:5],
        // 按钮行距容器 8pt
        [stack.topAnchor constraintEqualToAnchor:container.bottomAnchor constant:8],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [stack.heightAnchor constraintEqualToConstant:44],
    ]];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    self.placeholderLabel.hidden = textView.text.length > 0;
    if (textView.text.length > kTextMaxLength) {
        textView.text = [textView.text substringToIndex:kTextMaxLength];
    }
}

#pragma mark - 合成逻辑

- (void)synthesize {
    NSString *text = self.textView.text;
    if (!text || text.length == 0) {
        [AWECAUtils showToast:@"请输入要合成的文字"];
        return;
    }
    if (self.isSynthesizing) return;
    self.isSynthesizing = YES;
    [AWECAUtils showToast:@"正在合成..."];

    [[AWECATTSManager shared] synthesizeText:text completion:^(BOOL success, NSString *audioPath, NSString *error) {
        self.isSynthesizing = NO;
        if (success) {
            // 先收自己的键盘
            [self.view endEditing:YES];
            [self dismissViewControllerAnimated:YES completion:^{
                // dismiss 后遍历所有 window 收键盘，防止抖音输入框重新获取焦点
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                            [w endEditing:YES];
                        }
                    }
                }
            }];
        } else {
            [AWECAUtils showToast:error ?: @"合成失败"];
        }
    }];
}

#pragma mark - 跳转音色列表

- (void)pushVoiceList {
    // 弹出选择后端的 ActionSheet
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择音色来源"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"火山引擎 (300+ 音色)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self pushVoiceListWithProvider:AWECATTSProviderVolcano];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"千问 TTS (49 音色)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self pushVoiceListWithProvider:AWECATTSProviderQwen];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pushVoiceListWithProvider:(AWECATTSProvider)provider {
    // push 前切到 large，给音色列表足够空间
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *sheet = self.navigationController.sheetPresentationController;
        if (sheet) {
            [sheet animateChanges:^{
                sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
            }];
        }
    }
    AWECATTSVoiceListController *vc = [[AWECATTSVoiceListController alloc] init];
    vc.provider = provider;
    __weak typeof(self) weakSelf = self;
    vc.onVoiceSelected = ^(NSString *voiceType, NSString *voiceName) {
        AWECATTSManager *mgr = [AWECATTSManager shared];
        mgr.voiceType = voiceType;
        mgr.voiceName = voiceName;
        mgr.ttsProvider = provider;
        [mgr saveConfig];
        [weakSelf updateTitleView];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

@end
