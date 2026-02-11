// 音色列表impl，火山300+/千问49音色带搜索带试听
// @cookieodd | github.com/cookieodd | t.me/cookieodd

#import "AWECATTSVoiceListController.h"
#import "AWECATTSManager.h"
#import "AWECAUtils.h"
#import <objc/runtime.h>

// 持久化 key
#define kAWECARecommendedVoices @"AWECARecommendedVoices"
#define kAWECAQwenRecommendedVoices @"AWECAQwenRecommendedVoices"

// section 定义，砍掉自定义section
typedef NS_ENUM(NSInteger, AWECAVoiceSection) {
    AWECAVoiceSectionRecommended = 0,
    AWECAVoiceSectionAll,
    AWECAVoiceSectionCount
};

#define kCellFont [UIFont systemFontOfSize:15]

@interface AWECATTSVoiceListController ()
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recommendedVoices;
@property (nonatomic, strong) NSArray<NSDictionary *> *allVoices;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredRecommended;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredAll;
@property (nonatomic, copy) NSString *searchText;
@end

@implementation AWECATTSVoiceListController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // provider 此时已赋值，可以安全构建数据
    [self buildVoiceData];
    [self loadRecommended];

    self.title = (self.provider == AWECATTSProviderQwen) ? @"千问音色" : @"火山音色";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"vc"];

    // 搜索栏
    UISearchBar *sb = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    sb.placeholder = @"搜索音色...";
    sb.delegate = self;
    self.tableView.tableHeaderView = sb;
    self.searchBar = sb;

    self.filteredRecommended = [self.recommendedVoices mutableCopy];
    self.filteredAll = self.allVoices;
}

#pragma mark - 推荐音色持久化

- (NSArray<NSDictionary *> *)defaultRecommended {
    if (self.provider == AWECATTSProviderQwen) {
        return @[
            @{@"name": @"芊悦 Cherry", @"voiceType": @"Cherry"},
            @{@"name": @"晨煦 Ethan", @"voiceType": @"Ethan"},
            @{@"name": @"苏瑶 Serena", @"voiceType": @"Serena"},
            @{@"name": @"千雪 Chelsie", @"voiceType": @"Chelsie"},
            @{@"name": @"茉兔 Momo", @"voiceType": @"Momo"},
        ];
    }
    return @[
        @{@"name": @"灿灿", @"voiceType": @"BV700_V2_streaming"},
        @{@"name": @"通用女声", @"voiceType": @"BV001_V2_streaming"},
        @{@"name": @"通用男声", @"voiceType": @"BV002_V2_streaming"},
        @{@"name": @"云健", @"voiceType": @"BV113_streaming"},
        @{@"name": @"云夏", @"voiceType": @"BV102_streaming"},
        @{@"name": @"云希", @"voiceType": @"BV406_V2_streaming"},
        @{@"name": @"梓梓", @"voiceType": @"BV405_streaming"},
    ];
}

- (NSString *)recommendedKey {
    return (self.provider == AWECATTSProviderQwen) ? kAWECAQwenRecommendedVoices : kAWECARecommendedVoices;
}

- (void)loadRecommended {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:[self recommendedKey]];
    if (saved && saved.count > 0) {
        self.recommendedVoices = [saved mutableCopy];
    } else {
        self.recommendedVoices = [[self defaultRecommended] mutableCopy];
        [self saveRecommended];
    }
}

- (void)saveRecommended {
    [[NSUserDefaults standardUserDefaults] setObject:[self.recommendedVoices copy] forKey:[self recommendedKey]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - 搜索

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText;
    [self filterVoices];
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)filterVoices {
    if (!self.searchText || self.searchText.length == 0) {
        self.filteredRecommended = [self.recommendedVoices mutableCopy];
        self.filteredAll = self.allVoices;
        return;
    }
    NSString *q = self.searchText.lowercaseString;
    NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *v, NSDictionary *bindings) {
        return [[v[@"name"] lowercaseString] containsString:q] ||
               [[v[@"voiceType"] lowercaseString] containsString:q];
    }];
    self.filteredRecommended = [[self.recommendedVoices filteredArrayUsingPredicate:pred] mutableCopy];
    self.filteredAll = [self.allVoices filteredArrayUsingPredicate:pred];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return AWECAVoiceSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case AWECAVoiceSectionRecommended: return self.filteredRecommended.count;
        case AWECAVoiceSectionAll: return self.filteredAll.count;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case AWECAVoiceSectionRecommended: return @"推荐音色";
        case AWECAVoiceSectionAll: return [NSString stringWithFormat:@"全部音色 (%lu)", (unsigned long)self.filteredAll.count];
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"vc" forIndexPath:indexPath];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    NSArray *list = (indexPath.section == AWECAVoiceSectionRecommended) ? self.filteredRecommended : self.filteredAll;
    NSDictionary *voice = list[indexPath.row];
    NSString *name = voice[@"name"];
    NSString *type = voice[@"voiceType"];

    cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", name, type];
    cell.textLabel.font = [UIFont systemFontOfSize:14];

    // 当前选中打勾
    AWECATTSManager *mgr = [AWECATTSManager shared];
    NSString *cur = mgr.voiceType.length > 0 ? mgr.voiceType : @"BV700_V2_streaming";
    if ([type isEqualToString:cur]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }

    // 试听按钮
    UIButton *playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular];
    [playBtn setImage:[UIImage systemImageNamed:@"play.circle" withConfiguration:cfg] forState:UIControlStateNormal];
    playBtn.frame = CGRectMake(0, 0, 36, 36);
    objc_setAssociatedObject(playBtn, "voiceType", type, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [playBtn addTarget:self action:@selector(previewVoice:) forControlEvents:UIControlEventTouchUpInside];

    // 有勾就不设 accessoryView
    if (![type isEqualToString:cur]) {
        cell.accessoryView = playBtn;
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSArray *list = (indexPath.section == AWECAVoiceSectionRecommended) ? self.filteredRecommended : self.filteredAll;
    NSDictionary *voice = list[indexPath.row];

    AWECATTSManager *mgr = [AWECATTSManager shared];
    mgr.voiceType = voice[@"voiceType"];
    mgr.voiceName = voice[@"name"];
    mgr.ttsProvider = self.provider;
    [mgr saveConfig];

    if (self.onVoiceSelected) {
        self.onVoiceSelected(voice[@"voiceType"], voice[@"name"]);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - 左滑编辑（推荐移除 / 全部加入推荐）

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // 搜索时不让编辑，避免索引错乱
    if (self.searchText.length > 0) return NO;
    return YES;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.searchText.length > 0) return nil;

    if (indexPath.section == AWECAVoiceSectionRecommended) {
        // 推荐区左滑移除
        UIContextualAction *removeAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
            title:@"移除" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self.recommendedVoices removeObjectAtIndex:indexPath.row];
            [self saveRecommended];
            self.filteredRecommended = [self.recommendedVoices mutableCopy];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            completionHandler(YES);
        }];
        return [UISwipeActionsConfiguration configurationWithActions:@[removeAction]];

    } else if (indexPath.section == AWECAVoiceSectionAll) {
        // 全部区左滑加入推荐
        NSDictionary *voice = self.filteredAll[indexPath.row];
        // 已在推荐里就不显示
        NSString *vt = voice[@"voiceType"];
        for (NSDictionary *r in self.recommendedVoices) {
            if ([r[@"voiceType"] isEqualToString:vt]) return nil;
        }

        UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
            title:@"加入推荐" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self.recommendedVoices addObject:voice];
            [self saveRecommended];
            self.filteredRecommended = [self.recommendedVoices mutableCopy];
            NSIndexPath *newIP = [NSIndexPath indexPathForRow:self.recommendedVoices.count - 1 inSection:AWECAVoiceSectionRecommended];
            [tableView insertRowsAtIndexPaths:@[newIP] withRowAnimation:UITableViewRowAnimationAutomatic];
            [AWECAUtils showToast:[NSString stringWithFormat:@"已加入推荐: %@", voice[@"name"]]];
            completionHandler(YES);
        }];
        addAction.backgroundColor = [UIColor systemBlueColor];
        return [UISwipeActionsConfiguration configurationWithActions:@[addAction]];
    }
    return nil;
}

#pragma mark - 试听

- (void)previewVoice:(UIButton *)btn {
    NSString *type = objc_getAssociatedObject(btn, "voiceType");
    if (!type) return;

    AWECATTSManager *mgr = [AWECATTSManager shared];

    // 正在播就停
    if ([mgr isPlaying]) {
        [mgr stopPlayback];
        return;
    }

    // 临时用这个音色合成试听
    NSString *origType = mgr.voiceType;
    NSString *origName = mgr.voiceName;
    mgr.voiceType = type;

    [AWECAUtils showToast:@"正在试听..."];
    [mgr synthesizeText:@"你好，这是语音试听" completion:^(BOOL success, NSString *audioPath, NSString *error) {
        // 恢复原音色
        mgr.voiceType = origType;
        mgr.voiceName = origName;

        if (success && audioPath) {
            [mgr playAudioAtPath:audioPath];
        } else {
            [AWECAUtils showToast:error ?: @"试听失败"];
        }
    }];
}

#pragma mark - 音色数据，完整300+条

- (void)buildVoiceData {
    // 千问模式走单独的音色表
    if (self.provider == AWECATTSProviderQwen) {
        [self buildQwenVoiceData];
        return;
    }
    // 火山引擎 - 全部音色，从火山引擎官方文档提取
    self.allVoices = @[
        // ====== 豆包语音合成模型2.0 (saturn/uranus) ======
        @{@"name": @"Vivi 2.0", @"voiceType": @"zh_female_vv_uranus_bigtts"},
        @{@"name": @"小何 2.0", @"voiceType": @"zh_female_xiaohe_uranus_bigtts"},
        @{@"name": @"云舟 2.0", @"voiceType": @"zh_male_m191_uranus_bigtts"},
        @{@"name": @"小天 2.0", @"voiceType": @"zh_male_taocheng_uranus_bigtts"},
        @{@"name": @"儿童绘本", @"voiceType": @"zh_female_xueayi_saturn_bigtts"},
        @{@"name": @"大壹", @"voiceType": @"zh_male_dayi_saturn_bigtts"},
        @{@"name": @"黑猫侦探社咪", @"voiceType": @"zh_female_mizai_saturn_bigtts"},
        @{@"name": @"鸡汤女", @"voiceType": @"zh_female_jitangnv_saturn_bigtts"},
        @{@"name": @"魅力女友", @"voiceType": @"zh_female_meilinvyou_saturn_bigtts"},
        @{@"name": @"流畅女声", @"voiceType": @"zh_female_santongyongns_saturn_bigtts"},
        @{@"name": @"儒雅逸辰", @"voiceType": @"zh_male_ruyayichen_saturn_bigtts"},
        @{@"name": @"可爱女生 2.0", @"voiceType": @"saturn_zh_female_keainvsheng_tob"},
        @{@"name": @"调皮公主 2.0", @"voiceType": @"saturn_zh_female_tiaopigongzhu_tob"},
        @{@"name": @"爽朗少年 2.0", @"voiceType": @"saturn_zh_male_shuanglangshaonian_tob"},
        @{@"name": @"天才同桌 2.0", @"voiceType": @"saturn_zh_male_tiancaitongzhuo_tob"},
        @{@"name": @"知性灿灿 2.0", @"voiceType": @"saturn_zh_female_cancan_tob"},
        @{@"name": @"轻盈朵朵 2.0", @"voiceType": @"saturn_zh_female_qingyingduoduo_cs_tob"},
        @{@"name": @"温婉珊珊 2.0", @"voiceType": @"saturn_zh_female_wenwanshanshan_cs_tob"},
        @{@"name": @"热情艾娜 2.0", @"voiceType": @"saturn_zh_female_reqingaina_cs_tob"},
        @{@"name": @"Tim", @"voiceType": @"en_male_tim_uranus_bigtts"},
        @{@"name": @"Dacey", @"voiceType": @"en_female_dacey_uranus_bigtts"},
        @{@"name": @"Stokie", @"voiceType": @"en_female_stokie_uranus_bigtts"},
        // ====== 端到端实时语音大模型-O版本 (jupiter) ======
        @{@"name": @"vivi (O)", @"voiceType": @"zh_female_vv_jupiter_bigtts"},
        @{@"name": @"小何 (O)", @"voiceType": @"zh_female_xiaohe_jupiter_bigtts"},
        @{@"name": @"云舟 (O)", @"voiceType": @"zh_male_yunzhou_jupiter_bigtts"},
        @{@"name": @"小天 (O)", @"voiceType": @"zh_male_xiaotian_jupiter_bigtts"},
        // ====== 1.0 - 多情感 (mars emo) ======
        @{@"name": @"冷酷哥哥(多情感)", @"voiceType": @"zh_male_lengkugege_emo_v2_mars_bigtts"},
        @{@"name": @"甜心小美(多情感)", @"voiceType": @"zh_female_tianxinxiaomei_emo_v2_mars_bigtts"},
        @{@"name": @"高冷御姐(多情感)", @"voiceType": @"zh_female_gaolengyujie_emo_v2_mars_bigtts"},
        @{@"name": @"傲娇霸总(多情感)", @"voiceType": @"zh_male_aojiaobazong_emo_v2_mars_bigtts"},
        @{@"name": @"广州德哥(多情感)", @"voiceType": @"zh_male_guangzhoudege_emo_mars_bigtts"},
        @{@"name": @"京腔侃爷(多情感)", @"voiceType": @"zh_male_jingqiangkanye_emo_mars_bigtts"},
        @{@"name": @"邻居阿姨(多情感)", @"voiceType": @"zh_female_linjuayi_emo_v2_mars_bigtts"},
        @{@"name": @"优柔公子(多情感)", @"voiceType": @"zh_male_yourougongzi_emo_v2_mars_bigtts"},
        @{@"name": @"儒雅男友(多情感)", @"voiceType": @"zh_male_ruyayichen_emo_v2_mars_bigtts"},
        @{@"name": @"俊朗男友(多情感)", @"voiceType": @"zh_male_junlangnanyou_emo_v2_mars_bigtts"},
        @{@"name": @"北京小爷(多情感)", @"voiceType": @"zh_male_beijingxiaoye_emo_v2_mars_bigtts"},
        @{@"name": @"柔美女友(多情感)", @"voiceType": @"zh_female_roumeinvyou_emo_v2_mars_bigtts"},
        @{@"name": @"阳光青年(多情感)", @"voiceType": @"zh_male_yangguangqingnian_emo_v2_mars_bigtts"},
        @{@"name": @"魅力女友(多情感)", @"voiceType": @"zh_female_meilinvyou_emo_v2_mars_bigtts"},
        @{@"name": @"爽快思思(多情感)", @"voiceType": @"zh_female_shuangkuaisisi_emo_v2_mars_bigtts"},
        @{@"name": @"Candice", @"voiceType": @"en_female_candice_emo_v2_mars_bigtts"},
        @{@"name": @"Serena", @"voiceType": @"en_female_skye_emo_v2_mars_bigtts"},
        @{@"name": @"Glen", @"voiceType": @"en_male_glen_emo_v2_mars_bigtts"},
        @{@"name": @"Sylus", @"voiceType": @"en_male_sylus_emo_v2_mars_bigtts"},
        @{@"name": @"Corey", @"voiceType": @"en_male_corey_emo_v2_mars_bigtts"},
        @{@"name": @"Nadia", @"voiceType": @"en_female_nadia_tips_emo_v2_mars_bigtts"},
        @{@"name": @"深夜播客(多情感)", @"voiceType": @"zh_male_shenyeboke_emo_v2_mars_bigtts"},
        // ====== 1.0 - 教育/通用场景 ======
        @{@"name": @"Tina老师", @"voiceType": @"zh_female_yingyujiaoyu_mars_bigtts"},
        @{@"name": @"温柔女神", @"voiceType": @"ICL_zh_female_wenrounvshen_239eff5e8ffa_tob"},
        @{@"name": @"Vivi", @"voiceType": @"zh_female_vv_mars_bigtts"},
        @{@"name": @"亲切女声", @"voiceType": @"zh_female_qinqienvsheng_moon_bigtts"},
        @{@"name": @"机灵小伙", @"voiceType": @"ICL_zh_male_shenmi_v1_tob"},
        @{@"name": @"元气甜妹", @"voiceType": @"ICL_zh_female_wuxi_tob"},
        @{@"name": @"知心姐姐", @"voiceType": @"ICL_zh_female_wenyinvsheng_v1_tob"},
        @{@"name": @"阳光阿辰", @"voiceType": @"zh_male_qingyiyuxuan_mars_bigtts"},
        @{@"name": @"快乐小东", @"voiceType": @"zh_male_xudong_conversation_wvae_bigtts"},
        @{@"name": @"冷酷哥哥", @"voiceType": @"ICL_zh_male_lengkugege_v1_tob"},
        @{@"name": @"纯澈女生", @"voiceType": @"ICL_zh_female_feicui_v1_tob"},
        @{@"name": @"初恋女友", @"voiceType": @"ICL_zh_female_yuxin_v1_tob"},
        @{@"name": @"贴心闺蜜", @"voiceType": @"ICL_zh_female_xnx_tob"},
        @{@"name": @"温柔白月光", @"voiceType": @"ICL_zh_female_yry_tob"},
        @{@"name": @"炀炀", @"voiceType": @"ICL_zh_male_BV705_streaming_cs_tob"},
        @{@"name": @"开朗学长", @"voiceType": @"en_male_jason_conversation_wvae_bigtts"},
        @{@"name": @"魅力苏菲", @"voiceType": @"zh_female_sophie_conversation_wvae_bigtts"},
        @{@"name": @"贴心妹妹", @"voiceType": @"ICL_zh_female_yilin_tob"},
        @{@"name": @"甜美桃子", @"voiceType": @"zh_female_tianmeitaozi_mars_bigtts"},
        @{@"name": @"清新女声", @"voiceType": @"zh_female_qingxinnvsheng_mars_bigtts"},
        @{@"name": @"知性女声", @"voiceType": @"zh_female_zhixingnvsheng_mars_bigtts"},
        @{@"name": @"清爽男大", @"voiceType": @"zh_male_qingshuangnanda_mars_bigtts"},
        @{@"name": @"邻家女孩", @"voiceType": @"zh_female_linjianvhai_moon_bigtts"},
        @{@"name": @"渊博小叔", @"voiceType": @"zh_male_yuanboxiaoshu_moon_bigtts"},
        @{@"name": @"阳光青年", @"voiceType": @"zh_male_yangguangqingnian_moon_bigtts"},
        @{@"name": @"甜美小源", @"voiceType": @"zh_female_tianmeixiaoyuan_moon_bigtts"},
        @{@"name": @"清澈梓梓", @"voiceType": @"zh_female_qingchezizi_moon_bigtts"},
        @{@"name": @"解说小明", @"voiceType": @"zh_male_jieshuoxiaoming_moon_bigtts"},
        @{@"name": @"开朗姐姐", @"voiceType": @"zh_female_kailangjiejie_moon_bigtts"},
        @{@"name": @"邻家男孩", @"voiceType": @"zh_male_linjiananhai_moon_bigtts"},
        @{@"name": @"甜美悦悦", @"voiceType": @"zh_female_tianmeiyueyue_moon_bigtts"},
        @{@"name": @"心灵鸡汤", @"voiceType": @"zh_female_xinlingjitang_moon_bigtts"},
        @{@"name": @"知性温婉", @"voiceType": @"ICL_zh_female_zhixingwenwan_tob"},
        @{@"name": @"暖心体贴", @"voiceType": @"ICL_zh_male_nuanxintitie_tob"},
        @{@"name": @"开朗轻快", @"voiceType": @"ICL_zh_male_kailangqingkuai_tob"},
        @{@"name": @"活泼爽朗", @"voiceType": @"ICL_zh_male_huoposhuanglang_tob"},
        @{@"name": @"率真小伙", @"voiceType": @"ICL_zh_male_shuaizhenxiaohuo_tob"},
        @{@"name": @"温柔小哥", @"voiceType": @"zh_male_wenrouxiaoge_mars_bigtts"},
        @{@"name": @"灿灿/Shiny", @"voiceType": @"zh_female_cancan_mars_bigtts"},
        @{@"name": @"爽快思思/Skye", @"voiceType": @"zh_female_shuangkuaisisi_moon_bigtts"},
        @{@"name": @"温暖阿虎/Alvin", @"voiceType": @"zh_male_wennuanahu_moon_bigtts"},
        @{@"name": @"少年梓辛/Brayan", @"voiceType": @"zh_male_shaonianzixin_moon_bigtts"},
        @{@"name": @"温柔文雅", @"voiceType": @"ICL_zh_female_wenrouwenya_tob"},
        // ====== 1.0 - IP仿音 ======
        @{@"name": @"沪普男", @"voiceType": @"zh_male_hupunan_mars_bigtts"},
        @{@"name": @"鲁班七号", @"voiceType": @"zh_male_lubanqihao_mars_bigtts"},
        @{@"name": @"林潇", @"voiceType": @"zh_female_yangmi_mars_bigtts"},
        @{@"name": @"玲玲姐姐", @"voiceType": @"zh_female_linzhiling_mars_bigtts"},
        @{@"name": @"春日部姐姐", @"voiceType": @"zh_female_jiyejizi2_mars_bigtts"},
        @{@"name": @"唐僧", @"voiceType": @"zh_male_tangseng_mars_bigtts"},
        @{@"name": @"庄周", @"voiceType": @"zh_male_zhuangzhou_mars_bigtts"},
        @{@"name": @"猪八戒", @"voiceType": @"zh_male_zhubajie_mars_bigtts"},
        @{@"name": @"感冒电音姐姐", @"voiceType": @"zh_female_ganmaodianyin_mars_bigtts"},
        @{@"name": @"直率英子", @"voiceType": @"zh_female_naying_mars_bigtts"},
        @{@"name": @"女雷神", @"voiceType": @"zh_female_leidian_mars_bigtts"},
        // ====== 1.0 - 趣味口音 ======
        @{@"name": @"粤语小溏", @"voiceType": @"zh_female_yueyunv_mars_bigtts"},
        @{@"name": @"豫州子轩", @"voiceType": @"zh_male_yuzhouzixuan_moon_bigtts"},
        @{@"name": @"呆萌川妹", @"voiceType": @"zh_female_daimengchuanmei_moon_bigtts"},
        @{@"name": @"广西远舟", @"voiceType": @"zh_male_guangxiyuanzhou_moon_bigtts"},
        @{@"name": @"双节棍小哥", @"voiceType": @"zh_male_zhoujielun_emo_v2_mars_bigtts"},
        @{@"name": @"湾湾小何", @"voiceType": @"zh_female_wanwanxiaohe_moon_bigtts"},
        @{@"name": @"湾区大叔", @"voiceType": @"zh_female_wanqudashu_moon_bigtts"},
        @{@"name": @"广州德哥", @"voiceType": @"zh_male_guozhoudege_moon_bigtts"},
        @{@"name": @"浩宇小哥", @"voiceType": @"zh_male_haoyuxiaoge_moon_bigtts"},
        @{@"name": @"北京小爷", @"voiceType": @"zh_male_beijingxiaoye_moon_bigtts"},
        @{@"name": @"京腔侃爷/Harmony", @"voiceType": @"zh_male_jingqiangkanye_moon_bigtts"},
        @{@"name": @"妹坨洁儿", @"voiceType": @"zh_female_meituojieer_moon_bigtts"},
        // ====== 1.0 - 角色扮演 ======
        @{@"name": @"纯真少女", @"voiceType": @"ICL_zh_female_chunzhenshaonv_e588402fb8ad_tob"},
        @{@"name": @"奶气小生", @"voiceType": @"ICL_zh_male_xiaonaigou_edf58cf28b8b_tob"},
        @{@"name": @"精灵向导", @"voiceType": @"ICL_zh_female_jinglingxiangdao_1beb294a9e3e_tob"},
        @{@"name": @"闷油瓶小哥", @"voiceType": @"ICL_zh_male_menyoupingxiaoge_ffed9fc2fee7_tob"},
        @{@"name": @"黯刃秦主", @"voiceType": @"ICL_zh_male_anrenqinzhu_cd62e63dcdab_tob"},
        @{@"name": @"霸道总裁", @"voiceType": @"ICL_zh_male_badaozongcai_v1_tob"},
        @{@"name": @"妩媚可人", @"voiceType": @"ICL_zh_female_ganli_v1_tob"},
        @{@"name": @"邪魅御姐", @"voiceType": @"ICL_zh_female_xiangliangya_v1_tob"},
        @{@"name": @"嚣张小哥", @"voiceType": @"ICL_zh_male_ms_tob"},
        @{@"name": @"油腻大叔", @"voiceType": @"ICL_zh_male_you_tob"},
        @{@"name": @"孤傲公子", @"voiceType": @"ICL_zh_male_guaogongzi_v1_tob"},
        @{@"name": @"胡子叔叔", @"voiceType": @"ICL_zh_male_huzi_v1_tob"},
        @{@"name": @"性感魅惑", @"voiceType": @"ICL_zh_female_luoqing_v1_tob"},
        @{@"name": @"病弱公子", @"voiceType": @"ICL_zh_male_bingruogongzi_tob"},
        @{@"name": @"邪魅女王", @"voiceType": @"ICL_zh_female_bingjiao3_tob"},
        @{@"name": @"傲慢青年", @"voiceType": @"ICL_zh_male_aomanqingnian_tob"},
        @{@"name": @"醋精男生", @"voiceType": @"ICL_zh_male_cujingnansheng_tob"},
        @{@"name": @"爽朗少年", @"voiceType": @"ICL_zh_male_shuanglangshaonian_tob"},
        @{@"name": @"撒娇男友", @"voiceType": @"ICL_zh_male_sajiaonanyou_tob"},
        @{@"name": @"温柔男友", @"voiceType": @"ICL_zh_male_wenrounanyou_tob"},
        @{@"name": @"温顺少年", @"voiceType": @"ICL_zh_male_wenshunshaonian_tob"},
        @{@"name": @"粘人男友", @"voiceType": @"ICL_zh_male_naigounanyou_tob"},
        @{@"name": @"撒娇男生", @"voiceType": @"ICL_zh_male_sajiaonansheng_tob"},
        @{@"name": @"活泼男友", @"voiceType": @"ICL_zh_male_huoponanyou_tob"},
        @{@"name": @"甜系男友", @"voiceType": @"ICL_zh_male_tianxinanyou_tob"},
        @{@"name": @"活力青年", @"voiceType": @"ICL_zh_male_huoliqingnian_tob"},
        @{@"name": @"开朗青年", @"voiceType": @"ICL_zh_male_kailangqingnian_tob"},
        @{@"name": @"冷漠兄长", @"voiceType": @"ICL_zh_male_lengmoxiongzhang_tob"},
        @{@"name": @"天才同桌", @"voiceType": @"ICL_zh_male_tiancaitongzhuo_tob"},
        @{@"name": @"翩翩公子", @"voiceType": @"ICL_zh_male_pianpiangongzi_tob"},
        @{@"name": @"懵懂青年", @"voiceType": @"ICL_zh_male_mengdongqingnian_tob"},
        @{@"name": @"冷脸兄长", @"voiceType": @"ICL_zh_male_lenglianxiongzhang_tob"},
        @{@"name": @"病娇少年", @"voiceType": @"ICL_zh_male_bingjiaoshaonian_tob"},
        @{@"name": @"病娇男友", @"voiceType": @"ICL_zh_male_bingjiaonanyou_tob"},
        @{@"name": @"病弱少年", @"voiceType": @"ICL_zh_male_bingruoshaonian_tob"},
        @{@"name": @"意气少年", @"voiceType": @"ICL_zh_male_yiqishaonian_tob"},
        @{@"name": @"干净少年", @"voiceType": @"ICL_zh_male_ganjingshaonian_tob"},
        @{@"name": @"冷漠男友", @"voiceType": @"ICL_zh_male_lengmonanyou_tob"},
        @{@"name": @"精英青年", @"voiceType": @"ICL_zh_male_jingyingqingnian_tob"},
        @{@"name": @"热血少年", @"voiceType": @"ICL_zh_male_rexueshaonian_tob"},
        @{@"name": @"清爽少年", @"voiceType": @"ICL_zh_male_qingshuangshaonian_tob"},
        @{@"name": @"中二青年", @"voiceType": @"ICL_zh_male_zhongerqingnian_tob"},
        @{@"name": @"凌云青年", @"voiceType": @"ICL_zh_male_lingyunqingnian_tob"},
        @{@"name": @"自负青年", @"voiceType": @"ICL_zh_male_zifuqingnian_tob"},
        @{@"name": @"不羁青年", @"voiceType": @"ICL_zh_male_bujiqingnian_tob"},
        @{@"name": @"儒雅君子", @"voiceType": @"ICL_zh_male_ruyajunzi_tob"},
        @{@"name": @"低音沉郁", @"voiceType": @"ICL_zh_male_diyinchenyu_tob"},
        @{@"name": @"冷脸学霸", @"voiceType": @"ICL_zh_male_lenglianxueba_tob"},
        @{@"name": @"儒雅总裁", @"voiceType": @"ICL_zh_male_ruyazongcai_tob"},
        @{@"name": @"深沉总裁", @"voiceType": @"ICL_zh_male_shenchenzongcai_tob"},
        @{@"name": @"小侯爷", @"voiceType": @"ICL_zh_male_xiaohouye_tob"},
        @{@"name": @"孤高公子", @"voiceType": @"ICL_zh_male_gugaogongzi_tob"},
        @{@"name": @"仗剑君子", @"voiceType": @"ICL_zh_male_zhangjianjunzi_tob"},
        @{@"name": @"温润学者", @"voiceType": @"ICL_zh_male_wenrunxuezhe_tob"},
        @{@"name": @"亲切青年", @"voiceType": @"ICL_zh_male_qinqieqingnian_tob"},
        @{@"name": @"温柔学长", @"voiceType": @"ICL_zh_male_wenrouxuezhang_tob"},
        @{@"name": @"高冷总裁", @"voiceType": @"ICL_zh_male_gaolengzongcai_tob"},
        @{@"name": @"冷峻高智", @"voiceType": @"ICL_zh_male_lengjungaozhi_tob"},
        @{@"name": @"孱弱少爷", @"voiceType": @"ICL_zh_male_chanruoshaoye_tob"},
        @{@"name": @"自信青年", @"voiceType": @"ICL_zh_male_zixinqingnian_tob"},
        @{@"name": @"青涩青年", @"voiceType": @"ICL_zh_male_qingseqingnian_tob"},
        @{@"name": @"学霸同桌", @"voiceType": @"ICL_zh_male_xuebatongzhuo_tob"},
        @{@"name": @"冷傲总裁", @"voiceType": @"ICL_zh_male_lengaozongcai_tob"},
        @{@"name": @"元气少年", @"voiceType": @"ICL_zh_male_yuanqishaonian_tob"},
        @{@"name": @"洒脱青年", @"voiceType": @"ICL_zh_male_satuoqingnian_tob"},
        @{@"name": @"直率青年", @"voiceType": @"ICL_zh_male_zhishuaiqingnian_tob"},
        @{@"name": @"斯文青年", @"voiceType": @"ICL_zh_male_siwenqingnian_tob"},
        @{@"name": @"俊逸公子", @"voiceType": @"ICL_zh_male_junyigongzi_tob"},
        @{@"name": @"仗剑侠客", @"voiceType": @"ICL_zh_male_zhangjianxiake_tob"},
        @{@"name": @"机甲智能", @"voiceType": @"ICL_zh_male_jijiaozhineng_tob"},
        @{@"name": @"奶气萌娃", @"voiceType": @"zh_male_naiqimengwa_mars_bigtts"},
        @{@"name": @"婆婆", @"voiceType": @"zh_female_popo_mars_bigtts"},
        @{@"name": @"高冷御姐", @"voiceType": @"zh_female_gaolengyujie_moon_bigtts"},
        @{@"name": @"傲娇霸总", @"voiceType": @"zh_male_aojiaobazong_moon_bigtts"},
        @{@"name": @"魅力女友", @"voiceType": @"zh_female_meilinvyou_moon_bigtts"},
        @{@"name": @"深夜播客", @"voiceType": @"zh_male_shenyeboke_moon_bigtts"},
        @{@"name": @"柔美女友", @"voiceType": @"zh_female_sajiaonvyou_moon_bigtts"},
        @{@"name": @"撒娇学妹", @"voiceType": @"zh_female_yuanqinvyou_moon_bigtts"},
        @{@"name": @"病弱少女", @"voiceType": @"ICL_zh_female_bingruoshaonv_tob"},
        @{@"name": @"活泼女孩", @"voiceType": @"ICL_zh_female_huoponvhai_tob"},
        @{@"name": @"东方浩然", @"voiceType": @"zh_male_dongfanghaoran_moon_bigtts"},
        @{@"name": @"绿茶小哥", @"voiceType": @"ICL_zh_male_lvchaxiaoge_tob"},
        @{@"name": @"娇弱萝莉", @"voiceType": @"ICL_zh_female_jiaoruoluoli_tob"},
        @{@"name": @"冷淡疏离", @"voiceType": @"ICL_zh_male_lengdanshuli_tob"},
        @{@"name": @"憨厚敦实", @"voiceType": @"ICL_zh_male_hanhoudunshi_tob"},
        @{@"name": @"活泼刁蛮", @"voiceType": @"ICL_zh_female_huopodiaoman_tob"},
        @{@"name": @"固执病娇", @"voiceType": @"ICL_zh_male_guzhibingjiao_tob"},
        @{@"name": @"撒娇粘人", @"voiceType": @"ICL_zh_male_sajiaonianren_tob"},
        @{@"name": @"傲慢娇声", @"voiceType": @"ICL_zh_female_aomanjiaosheng_tob"},
        @{@"name": @"潇洒随性", @"voiceType": @"ICL_zh_male_xiaosasuixing_tob"},
        @{@"name": @"诡异神秘", @"voiceType": @"ICL_zh_male_guiyishenmi_tob"},
        @{@"name": @"儒雅才俊", @"voiceType": @"ICL_zh_male_ruyacaijun_tob"},
        @{@"name": @"正直青年", @"voiceType": @"ICL_zh_male_zhengzhiqingnian_tob"},
        @{@"name": @"娇憨女王", @"voiceType": @"ICL_zh_female_jiaohannvwang_tob"},
        @{@"name": @"病娇萌妹", @"voiceType": @"ICL_zh_female_bingjiaomengmei_tob"},
        @{@"name": @"青涩小生", @"voiceType": @"ICL_zh_male_qingsenaigou_tob"},
        @{@"name": @"纯真学弟", @"voiceType": @"ICL_zh_male_chunzhenxuedi_tob"},
        @{@"name": @"优柔帮主", @"voiceType": @"ICL_zh_male_youroubangzhu_tob"},
        @{@"name": @"优柔公子", @"voiceType": @"ICL_zh_male_yourougongzi_tob"},
        @{@"name": @"调皮公主", @"voiceType": @"ICL_zh_female_tiaopigongzhu_tob"},
        @{@"name": @"贴心男友", @"voiceType": @"ICL_zh_male_tiexinnanyou_tob"},
        @{@"name": @"少年将军", @"voiceType": @"ICL_zh_male_shaonianjiangjun_tob"},
        @{@"name": @"病娇哥哥", @"voiceType": @"ICL_zh_male_bingjiaogege_tob"},
        @{@"name": @"学霸男同桌", @"voiceType": @"ICL_zh_male_xuebanantongzhuo_tob"},
        @{@"name": @"幽默叔叔", @"voiceType": @"ICL_zh_male_youmoshushu_tob"},
        @{@"name": @"假小子", @"voiceType": @"ICL_zh_female_jiaxiaozi_tob"},
        @{@"name": @"温柔男同桌", @"voiceType": @"ICL_zh_male_wenrounantongzhuo_tob"},
        @{@"name": @"幽默大爷", @"voiceType": @"ICL_zh_male_youmodaye_tob"},
        @{@"name": @"枕边低语", @"voiceType": @"ICL_zh_male_asmryexiu_tob"},
        @{@"name": @"神秘法师", @"voiceType": @"ICL_zh_male_shenmifashi_tob"},
        @{@"name": @"娇喘女声", @"voiceType": @"zh_female_jiaochuan_mars_bigtts"},
        @{@"name": @"开朗弟弟", @"voiceType": @"zh_male_livelybro_mars_bigtts"},
        @{@"name": @"谄媚女声", @"voiceType": @"zh_female_flattery_mars_bigtts"},
        @{@"name": @"冷峻上司", @"voiceType": @"ICL_zh_male_lengjunshangsi_tob"},
        @{@"name": @"寡言小哥", @"voiceType": @"ICL_zh_male_xiaoge_v1_tob"},
        @{@"name": @"清朗温润", @"voiceType": @"ICL_zh_male_renyuwangzi_v1_tob"},
        @{@"name": @"潇洒随性 v1", @"voiceType": @"ICL_zh_male_xiaosha_v1_tob"},
        @{@"name": @"清冷矜贵", @"voiceType": @"ICL_zh_male_liyisheng_v1_tob"},
        @{@"name": @"沉稳优雅", @"voiceType": @"ICL_zh_male_qinglen_v1_tob"},
        @{@"name": @"清逸苏感", @"voiceType": @"ICL_zh_male_chongqingzhanzhan_v1_tob"},
        @{@"name": @"温柔内敛", @"voiceType": @"ICL_zh_male_xingjiwangzi_v1_tob"},
        @{@"name": @"低沉缱绻", @"voiceType": @"ICL_zh_male_sigeshiye_v1_tob"},
        @{@"name": @"蓝银草魂师", @"voiceType": @"ICL_zh_male_lanyingcaohunshi_v1_tob"},
        @{@"name": @"清冷高雅", @"voiceType": @"ICL_zh_female_liumengdie_v1_tob"},
        @{@"name": @"甜美娇俏", @"voiceType": @"ICL_zh_female_linxueying_v1_tob"},
        @{@"name": @"柔骨魂师", @"voiceType": @"ICL_zh_female_rouguhunshi_v1_tob"},
        @{@"name": @"甜美活泼", @"voiceType": @"ICL_zh_female_tianmei_v1_tob"},
        @{@"name": @"成熟温柔", @"voiceType": @"ICL_zh_female_chengshu_v1_tob"},
        @{@"name": @"贴心闺蜜 v1", @"voiceType": @"ICL_zh_female_xnx_v1_tob"},
        @{@"name": @"温柔白月光 v1", @"voiceType": @"ICL_zh_female_yry_v1_tob"},
        @{@"name": @"高冷沉稳", @"voiceType": @"zh_male_bv139_audiobook_ummv3_bigtts"},
        // ====== 1.0 - 角色扮演/S2S-SC ======
        @{@"name": @"醋精男友", @"voiceType": @"ICL_zh_male_cujingnanyou_tob"},
        @{@"name": @"风发少年", @"voiceType": @"ICL_zh_male_fengfashaonian_tob"},
        @{@"name": @"磁性男嗓", @"voiceType": @"ICL_zh_male_cixingnansang_tob"},
        @{@"name": @"成熟总裁", @"voiceType": @"ICL_zh_male_chengshuzongcai_tob"},
        @{@"name": @"傲娇精英", @"voiceType": @"ICL_zh_male_aojiaojingying_tob"},
        @{@"name": @"傲娇公子", @"voiceType": @"ICL_zh_male_aojiaogongzi_tob"},
        @{@"name": @"霸道少爷", @"voiceType": @"ICL_zh_male_badaoshaoye_tob"},
        @{@"name": @"腹黑公子", @"voiceType": @"ICL_zh_male_fuheigongzi_tob"},
        @{@"name": @"暖心学姐", @"voiceType": @"ICL_zh_female_nuanxinxuejie_tob"},
        @{@"name": @"可爱女生", @"voiceType": @"ICL_zh_female_keainvsheng_tob"},
        @{@"name": @"成熟姐姐", @"voiceType": @"ICL_zh_female_chengshujiejie_tob"},
        @{@"name": @"病娇姐姐", @"voiceType": @"ICL_zh_female_bingjiaojiejie_tob"},
        @{@"name": @"妩媚御姐", @"voiceType": @"ICL_zh_female_wumeiyujie_tob"},
        @{@"name": @"傲娇女友", @"voiceType": @"ICL_zh_female_aojiaonvyou_tob"},
        @{@"name": @"贴心女友", @"voiceType": @"ICL_zh_female_tiexinnvyou_tob"},
        @{@"name": @"性感御姐", @"voiceType": @"ICL_zh_female_xingganyujie_tob"},
        @{@"name": @"病娇弟弟", @"voiceType": @"ICL_zh_male_bingjiaodidi_tob"},
        @{@"name": @"傲慢少爷", @"voiceType": @"ICL_zh_male_aomanshaoye_tob"},
        @{@"name": @"傲气凌人", @"voiceType": @"ICL_zh_male_aiqilingren_tob"},
        @{@"name": @"病娇白莲", @"voiceType": @"ICL_zh_male_bingjiaobailian_tob"},
        // ====== 1.0 - 多语种 ======
        @{@"name": @"Lauren", @"voiceType": @"en_female_lauren_moon_bigtts"},
        @{@"name": @"Energetic Male II", @"voiceType": @"en_male_campaign_jamal_moon_bigtts"},
        @{@"name": @"Gotham Hero", @"voiceType": @"en_male_chris_moon_bigtts"},
        @{@"name": @"Flirty Female", @"voiceType": @"en_female_product_darcie_moon_bigtts"},
        @{@"name": @"Peaceful Female", @"voiceType": @"en_female_emotional_moon_bigtts"},
        @{@"name": @"Nara", @"voiceType": @"en_female_nara_moon_bigtts"},
        @{@"name": @"Bruce", @"voiceType": @"en_male_bruce_moon_bigtts"},
        @{@"name": @"Michael", @"voiceType": @"en_male_michael_moon_bigtts"},
        @{@"name": @"Cartoon Chef", @"voiceType": @"ICL_en_male_cc_sha_v1_tob"},
        @{@"name": @"Lucas", @"voiceType": @"zh_male_M100_conversation_wvae_bigtts"},
        @{@"name": @"Sophie", @"voiceType": @"zh_female_sophie_conversation_wvae_bigtts"},
        @{@"name": @"Daisy", @"voiceType": @"en_female_dacey_conversation_wvae_bigtts"},
        @{@"name": @"Owen", @"voiceType": @"en_male_charlie_conversation_wvae_bigtts"},
        @{@"name": @"Luna", @"voiceType": @"en_female_sarah_new_conversation_wvae_bigtts"},
        @{@"name": @"Michael (ICL)", @"voiceType": @"ICL_en_male_michael_tob"},
        @{@"name": @"Charlie", @"voiceType": @"ICL_en_female_cc_cm_v1_tob"},
        @{@"name": @"Big Boogie", @"voiceType": @"ICL_en_male_oogie2_tob"},
        @{@"name": @"Frosty Man", @"voiceType": @"ICL_en_male_frosty1_tob"},
        @{@"name": @"The Grinch", @"voiceType": @"ICL_en_male_grinch2_tob"},
        @{@"name": @"Zayne", @"voiceType": @"ICL_en_male_zayne_tob"},
        @{@"name": @"Jigsaw", @"voiceType": @"ICL_en_male_cc_jigsaw_tob"},
        @{@"name": @"Chucky", @"voiceType": @"ICL_en_male_cc_chucky_tob"},
        @{@"name": @"Clown Man", @"voiceType": @"ICL_en_male_cc_penny_v1_tob"},
        @{@"name": @"Kevin McCallister", @"voiceType": @"ICL_en_male_kevin2_tob"},
        @{@"name": @"Xavier", @"voiceType": @"ICL_en_male_xavier1_v1_tob"},
        @{@"name": @"Noah", @"voiceType": @"ICL_en_male_cc_dracula_v1_tob"},
        @{@"name": @"Adam", @"voiceType": @"en_male_adam_mars_bigtts"},
        @{@"name": @"Amanda", @"voiceType": @"en_female_amanda_mars_bigtts"},
        @{@"name": @"Jackson", @"voiceType": @"en_male_jackson_mars_bigtts"},
        @{@"name": @"Delicate Girl", @"voiceType": @"en_female_daisy_moon_bigtts"},
        @{@"name": @"Dave", @"voiceType": @"en_male_dave_moon_bigtts"},
        @{@"name": @"Hades", @"voiceType": @"en_male_hades_moon_bigtts"},
        @{@"name": @"Onez", @"voiceType": @"en_female_onez_moon_bigtts"},
        @{@"name": @"Emily", @"voiceType": @"en_female_emily_mars_bigtts"},
        @{@"name": @"Daniel", @"voiceType": @"zh_male_xudong_conversation_wvae_bigtts"},
        @{@"name": @"Alastor", @"voiceType": @"ICL_en_male_cc_alastor_tob"},
        @{@"name": @"Smith", @"voiceType": @"en_male_smith_mars_bigtts"},
        @{@"name": @"Anna", @"voiceType": @"en_female_anna_mars_bigtts"},
        @{@"name": @"Ethan", @"voiceType": @"ICL_en_male_aussie_v1_tob"},
        @{@"name": @"Sarah", @"voiceType": @"en_female_sarah_mars_bigtts"},
        @{@"name": @"Dryw", @"voiceType": @"en_male_dryw_mars_bigtts"},
        @{@"name": @"Diana (西语)", @"voiceType": @"multi_female_maomao_conversation_wvae_bigtts"},
        @{@"name": @"Lucia (西语)", @"voiceType": @"multi_male_M100_conversation_wvae_bigtts"},
        @{@"name": @"Sofia (西语)", @"voiceType": @"multi_female_sophie_conversation_wvae_bigtts"},
        @{@"name": @"Daniel (西语)", @"voiceType": @"multi_male_xudong_conversation_wvae_bigtts"},
        @{@"name": @"ひかる(光)", @"voiceType": @"multi_zh_male_youyoujunzi_moon_bigtts"},
        @{@"name": @"さとみ(智美)", @"voiceType": @"multi_female_sophie_conversation_wvae_bigtts"},
        @{@"name": @"まさお(正男)", @"voiceType": @"multi_male_xudong_conversation_wvae_bigtts"},
        @{@"name": @"つき(月)", @"voiceType": @"multi_female_maomao_conversation_wvae_bigtts"},
        @{@"name": @"あけみ(朱美)", @"voiceType": @"multi_female_gaolengyujie_moon_bigtts"},
        @{@"name": @"かずね(和音)", @"voiceType": @"multi_male_jingqiangkanye_moon_bigtts"},
        @{@"name": @"はるこ(晴子)", @"voiceType": @"multi_female_shuangkuaisisi_moon_bigtts"},
        @{@"name": @"ひろし(広志)", @"voiceType": @"multi_male_wanqudashu_moon_bigtts"},
        // ====== 1.0 - 客服场景 ======
        @{@"name": @"理性圆子", @"voiceType": @"ICL_zh_female_lixingyuanzi_cs_tob"},
        @{@"name": @"清甜桃桃", @"voiceType": @"ICL_zh_female_qingtiantaotao_cs_tob"},
        @{@"name": @"清晰小雪", @"voiceType": @"ICL_zh_female_qingxixiaoxue_cs_tob"},
        @{@"name": @"清甜莓莓", @"voiceType": @"ICL_zh_female_qingtianmeimei_cs_tob"},
        @{@"name": @"开朗婷婷", @"voiceType": @"ICL_zh_female_kailangtingting_cs_tob"},
        @{@"name": @"清新沐沐", @"voiceType": @"ICL_zh_male_qingxinmumu_cs_tob"},
        @{@"name": @"爽朗小阳", @"voiceType": @"ICL_zh_male_shuanglangxiaoyang_cs_tob"},
        @{@"name": @"清新波波", @"voiceType": @"ICL_zh_male_qingxinbobo_cs_tob"},
        @{@"name": @"温婉珊珊", @"voiceType": @"ICL_zh_female_wenwanshanshan_cs_tob"},
        @{@"name": @"甜美小雨", @"voiceType": @"ICL_zh_female_tianmeixiaoyu_cs_tob"},
        @{@"name": @"热情艾娜", @"voiceType": @"ICL_zh_female_reqingaina_cs_tob"},
        @{@"name": @"甜美小橘", @"voiceType": @"ICL_zh_female_tianmeixiaoju_cs_tob"},
        @{@"name": @"沉稳明仔", @"voiceType": @"ICL_zh_male_chenwenmingzai_cs_tob"},
        @{@"name": @"亲切小卓", @"voiceType": @"ICL_zh_male_qinqiexiaozhuo_cs_tob"},
        @{@"name": @"灵动欣欣", @"voiceType": @"ICL_zh_female_lingdongxinxin_cs_tob"},
        @{@"name": @"乖巧可儿", @"voiceType": @"ICL_zh_female_guaiqiaokeer_cs_tob"},
        @{@"name": @"暖心茜茜", @"voiceType": @"ICL_zh_female_nuanxinqianqian_cs_tob"},
        @{@"name": @"软萌团子", @"voiceType": @"ICL_zh_female_ruanmengtuanzi_cs_tob"},
        @{@"name": @"阳光洋洋", @"voiceType": @"ICL_zh_male_yangguangyangyang_cs_tob"},
        @{@"name": @"软萌糖糖", @"voiceType": @"ICL_zh_female_ruanmengtangtang_cs_tob"},
        @{@"name": @"秀丽倩倩", @"voiceType": @"ICL_zh_female_xiuliqianqian_cs_tob"},
        @{@"name": @"开心小鸿", @"voiceType": @"ICL_zh_female_kaixinxiaohong_cs_tob"},
        @{@"name": @"轻盈朵朵", @"voiceType": @"ICL_zh_female_qingyingduoduo_cs_tob"},
        @{@"name": @"暖阳女声", @"voiceType": @"zh_female_kefunvsheng_mars_bigtts"},
        // ====== 1.0 - 视频配音 ======
        @{@"name": @"悠悠君子", @"voiceType": @"zh_male_M100_conversation_wvae_bigtts"},
        @{@"name": @"文静毛毛", @"voiceType": @"zh_female_maomao_conversation_wvae_bigtts"},
        @{@"name": @"倾心少女", @"voiceType": @"ICL_zh_female_qiuling_v1_tob"},
        @{@"name": @"醇厚低音", @"voiceType": @"ICL_zh_male_buyan_v1_tob"},
        @{@"name": @"咆哮小哥", @"voiceType": @"ICL_zh_male_BV144_paoxiaoge_v1_tob"},
        @{@"name": @"和蔼奶奶", @"voiceType": @"ICL_zh_female_heainainai_tob"},
        @{@"name": @"邻居阿姨", @"voiceType": @"ICL_zh_female_linjuayi_tob"},
        @{@"name": @"温柔小雅", @"voiceType": @"zh_female_wenrouxiaoya_moon_bigtts"},
        @{@"name": @"天才童声", @"voiceType": @"zh_male_tiancaitongsheng_mars_bigtts"},
        @{@"name": @"猴哥", @"voiceType": @"zh_male_sunwukong_mars_bigtts"},
        @{@"name": @"熊二", @"voiceType": @"zh_male_xionger_mars_bigtts"},
        @{@"name": @"佩奇猪", @"voiceType": @"zh_female_peiqi_mars_bigtts"},
        @{@"name": @"武则天", @"voiceType": @"zh_female_wuzetian_mars_bigtts"},
        @{@"name": @"顾姐", @"voiceType": @"zh_female_gujie_mars_bigtts"},
        @{@"name": @"樱桃丸子", @"voiceType": @"zh_female_yingtaowanzi_mars_bigtts"},
        @{@"name": @"广告解说", @"voiceType": @"zh_male_chunhui_mars_bigtts"},
        @{@"name": @"少儿故事", @"voiceType": @"zh_female_shaoergushi_mars_bigtts"},
        @{@"name": @"四郎", @"voiceType": @"zh_male_silang_mars_bigtts"},
        @{@"name": @"俏皮女声", @"voiceType": @"zh_female_qiaopinvsheng_mars_bigtts"},
        @{@"name": @"懒音绵宝", @"voiceType": @"zh_male_lanxiaoyang_mars_bigtts"},
        @{@"name": @"亮嗓萌仔", @"voiceType": @"zh_male_dongmanhaimian_mars_bigtts"},
        @{@"name": @"磁性解说男声/Morgan", @"voiceType": @"zh_male_jieshuonansheng_mars_bigtts"},
        @{@"name": @"鸡汤妹妹/Hope", @"voiceType": @"zh_female_jitangmeimei_mars_bigtts"},
        @{@"name": @"贴心女声/Candy", @"voiceType": @"zh_female_tiexinnvsheng_mars_bigtts"},
        @{@"name": @"萌丫头/Cutey", @"voiceType": @"zh_female_mengyatou_mars_bigtts"},
        // ====== 1.0 - 有声阅读 ======
        @{@"name": @"内敛才俊", @"voiceType": @"ICL_zh_male_neiliancaijun_e991be511569_tob"},
        @{@"name": @"温暖少年", @"voiceType": @"ICL_zh_male_yangyang_v1_tob"},
        @{@"name": @"儒雅公子", @"voiceType": @"ICL_zh_male_flc_v1_tob"},
        @{@"name": @"悬疑解说", @"voiceType": @"zh_male_changtianyi_mars_bigtts"},
        @{@"name": @"儒雅青年", @"voiceType": @"zh_male_ruyaqingnian_mars_bigtts"},
        @{@"name": @"霸气青叔", @"voiceType": @"zh_male_baqiqingshu_mars_bigtts"},
        @{@"name": @"擎苍", @"voiceType": @"zh_male_qingcang_mars_bigtts"},
        @{@"name": @"活力小哥", @"voiceType": @"zh_male_yangguangqingnian_mars_bigtts"},
        @{@"name": @"古风少御", @"voiceType": @"zh_female_gufengshaoyu_mars_bigtts"},
        @{@"name": @"温柔淑女", @"voiceType": @"zh_female_wenroushunv_mars_bigtts"},
        @{@"name": @"反卷青年", @"voiceType": @"zh_male_fanjuanqingnian_mars_bigtts"},
    ];
}

- (void)buildQwenVoiceData {
    // 千问 TTS 49 个系统音色，从阿里云官方文档提取
    self.allVoices = @[
        // 普通话 - Instruct + Flash 通用
        @{@"name": @"芊悦 Cherry", @"voiceType": @"Cherry"},
        @{@"name": @"苏瑶 Serena", @"voiceType": @"Serena"},
        @{@"name": @"晨煦 Ethan", @"voiceType": @"Ethan"},
        @{@"name": @"千雪 Chelsie", @"voiceType": @"Chelsie"},
        @{@"name": @"茉兔 Momo", @"voiceType": @"Momo"},
        @{@"name": @"十三 Vivian", @"voiceType": @"Vivian"},
        @{@"name": @"月白 Moon", @"voiceType": @"Moon"},
        @{@"name": @"四月 Maia", @"voiceType": @"Maia"},
        @{@"name": @"凯 Kai", @"voiceType": @"Kai"},
        @{@"name": @"不吃鱼 Nofish", @"voiceType": @"Nofish"},
        @{@"name": @"萌宝 Bella", @"voiceType": @"Bella"},
        @{@"name": @"沧明子 Eldric Sage", @"voiceType": @"Eldric Sage"},
        @{@"name": @"乖小妹 Mia", @"voiceType": @"Mia"},
        @{@"name": @"沙小弥 Mochi", @"voiceType": @"Mochi"},
        @{@"name": @"燕铮莺 Bellona", @"voiceType": @"Bellona"},
        @{@"name": @"田叔 Vincent", @"voiceType": @"Vincent"},
        @{@"name": @"萌小姬 Bunny", @"voiceType": @"Bunny"},
        @{@"name": @"阿闻 Neil", @"voiceType": @"Neil"},
        @{@"name": @"墨讲师 Elias", @"voiceType": @"Elias"},
        @{@"name": @"徐大爷 Arthur", @"voiceType": @"Arthur"},
        @{@"name": @"邻家妹妹 Nini", @"voiceType": @"Nini"},
        @{@"name": @"诡婆婆 Ebona", @"voiceType": @"Ebona"},
        @{@"name": @"小婉 Seren", @"voiceType": @"Seren"},
        @{@"name": @"顽屁小孩 Pip", @"voiceType": @"Pip"},
        @{@"name": @"少女阿月 Stella", @"voiceType": @"Stella"},
        // Flash 专属
        @{@"name": @"詹妮弗 Jennifer", @"voiceType": @"Jennifer"},
        @{@"name": @"甜茶 Ryan", @"voiceType": @"Ryan"},
        @{@"name": @"卡捷琳娜 Katerina", @"voiceType": @"Katerina"},
        @{@"name": @"艾登 Aiden", @"voiceType": @"Aiden"},
        @{@"name": @"安德雷 Andre", @"voiceType": @"Andre"},
        // 多语种
        @{@"name": @"博德加 Bodega (西语)", @"voiceType": @"Bodega"},
        @{@"name": @"索尼莎 Sonrisa (西语)", @"voiceType": @"Sonrisa"},
        @{@"name": @"阿列克 Alek (俄语)", @"voiceType": @"Alek"},
        @{@"name": @"多尔切 Dolce (意语)", @"voiceType": @"Dolce"},
        @{@"name": @"素熙 Sohee (韩语)", @"voiceType": @"Sohee"},
        @{@"name": @"小野杏 Ono Anna (日语)", @"voiceType": @"Ono Anna"},
        @{@"name": @"莱恩 Lenn (德语)", @"voiceType": @"Lenn"},
        @{@"name": @"埃米尔安 Emilien (法语)", @"voiceType": @"Emilien"},
        @{@"name": @"拉迪奥戈尔 Radio Gol (葡语)", @"voiceType": @"Radio Gol"},
        // 方言
        @{@"name": @"上海阿珍 Jada (上海话)", @"voiceType": @"Jada"},
        @{@"name": @"北京晓东 Dylan (北京话)", @"voiceType": @"Dylan"},
        @{@"name": @"南京老李 Li (南京话)", @"voiceType": @"Li"},
        @{@"name": @"陕西秦川 Marcus (陕西话)", @"voiceType": @"Marcus"},
        @{@"name": @"闽南阿杰 Roy (闽南语)", @"voiceType": @"Roy"},
        @{@"name": @"天津李彼得 Peter (天津话)", @"voiceType": @"Peter"},
        @{@"name": @"四川晴儿 Sunny (四川话)", @"voiceType": @"Sunny"},
        @{@"name": @"四川程川 Eric (四川话)", @"voiceType": @"Eric"},
        @{@"name": @"粤语阿强 Rocky (粤语)", @"voiceType": @"Rocky"},
        @{@"name": @"粤语阿清 Kiki (粤语)", @"voiceType": @"Kiki"},
    ];
}

@end
