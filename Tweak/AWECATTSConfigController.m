// API 配置页impl，三个输入框搞定
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECATTSConfigController.h"
#import "AWECATTSManager.h"
#import "AWECAUtils.h"

@interface AWECATTSConfigController ()
@property (nonatomic, strong) UITextField *appIDField;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UITextField *clusterField;
@property (nonatomic, strong) UITextField *qwenKeyField;
@end

@implementation AWECATTSConfigController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    // 右上角保存按钮
    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithTitle:@"保存"
        style:UIBarButtonItemStylePlain target:self action:@selector(saveAndPop)];
    saveBtn.tintColor = [UIColor labelColor];
    self.navigationItem.rightBarButtonItem = saveBtn;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;  // 火山: AppID/Token/Cluster
    return 1;                     // 千问: API Key
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"火山引擎";
    return @"千问 TTS";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    AWECATTSManager *mgr = [AWECATTSManager shared];

    // 用 section*10+row 做 tag，区分不同输入框
    NSInteger tag = indexPath.section * 10 + indexPath.row;

    NSString *label = @"";
    NSString *placeholder = @"";
    NSString *value = @"";
    BOOL secure = NO;
    UIKeyboardType kbType = UIKeyboardTypeDefault;

    if (indexPath.section == 0) {
        // 火山引擎
        switch (indexPath.row) {
            case 0:
                label = @"App ID";
                placeholder = @"你的 App ID";
                value = mgr.appID ?: @"";
                kbType = UIKeyboardTypeNumberPad;
                break;
            case 1:
                label = @"Access Token";
                placeholder = @"你的 Access Token";
                value = mgr.accessToken ?: @"";
                secure = YES;
                break;
            case 2:
                label = @"Cluster";
                placeholder = @"不需要就留空";
                value = (mgr.cluster.length > 0) ? mgr.cluster : @"";
                break;
        }
    } else {
        // 千问
        label = @"API Key";
        placeholder = @"sk-xxx";
        value = mgr.qwenAPIKey ?: @"";
        secure = YES;
    }

    cell.textLabel.text = label;
    cell.textLabel.font = [UIFont systemFontOfSize:15];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectZero];
    tf.font = [UIFont systemFontOfSize:14];
    tf.textColor = [UIColor secondaryLabelColor];
    tf.textAlignment = NSTextAlignmentRight;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.tag = tag;
    tf.placeholder = placeholder;
    tf.text = value;
    tf.secureTextEntry = secure;
    tf.keyboardType = kbType;
    [tf addTarget:self action:@selector(textFieldChanged:) forControlEvents:UIControlEventEditingChanged];

    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    bar.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKB)]
    ];
    tf.inputAccessoryView = bar;
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:tf];

    [NSLayoutConstraint activateConstraints:@[
        [tf.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [tf.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [tf.widthAnchor constraintEqualToConstant:200]
    ]];

    // 缓存引用
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0: self.appIDField = tf; break;
            case 1: self.tokenField = tf; break;
            case 2: self.clusterField = tf; break;
        }
    } else {
        self.qwenKeyField = tf;
    }

    return cell;
}

#pragma mark - 实时保存

- (void)textFieldChanged:(UITextField *)tf {
    AWECATTSManager *mgr = [AWECATTSManager shared];
    // tag = section*10 + row
    switch (tf.tag) {
        case 0: mgr.appID = tf.text; break;        // 火山 AppID
        case 1: mgr.accessToken = tf.text; break;   // 火山 Token
        case 2: mgr.cluster = tf.text; break;        // 火山 Cluster
        case 10: mgr.qwenAPIKey = tf.text; break;    // 千问 API Key
    }
    [mgr saveConfig];
}

- (void)dismissKB {
    [self.view endEditing:YES];
}

- (void)saveAndPop {
    [self.view endEditing:YES];
    [[AWECATTSManager shared] saveConfig];
    [AWECAUtils showToast:@"已保存"];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
