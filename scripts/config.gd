extends RefCounted
## =====================================================================
## SLOWBALL · 全局数值配置
##
## 平衡、手感、配色全部集中在这里。改数字即可调游戏，不用翻业务代码。
## 每一行后面都注明了「单位 / 取值范围 / 改大了会怎样」。
## =====================================================================

# ---------------------------------------------------------------------
# 难度（只影响主角血量，其余一切相同）
#   key   : 存档 / 内部标识
#   name  : 界面上的中文名
#   en    : 卡片角标英文
#   hp    : 主角生命（整数；虫球的 0.5 抗伤会打出半血）
#   note  : 标题页副标题
# ---------------------------------------------------------------------
const DIFFICULTIES := [
	{"key": "easy", "name": "简单", "name_en": "EASY", "en": "EASY", "hp": 5, "note": "5 点生命 · 可以硬吃几次"},
	{"key": "normal", "name": "普通", "name_en": "NORMAL", "en": "NORMAL", "hp": 3, "note": "3 点生命 · 标准体验"},
	{"key": "hard", "name": "困难", "name_en": "HARD", "en": "HARD", "hp": 1, "note": "1 点生命 · 一颗子弹就结束"},
]

# ---------------------------------------------------------------------
# 时间控制（本作的核心机制）
#   球在飞 = FAST_SCALE（你在动，世界就动）
#   其余   = SLOW_SCALE（你停着瞄准，世界几乎静止）
# ---------------------------------------------------------------------
const SLOW_SCALE := 0.1          # 瞄准 / 静止时世界的流速；越小越"定格"
const FAST_SCALE := 1.0          # 球在飞时的流速；一般别改，1.0 = 正常
const SCALE_LERP := 12.0         # 倍率切换的平滑速度（越大越干脆、越小越黏）
const OVER_SCALE := 0.3          # 结算画面时的世界流速（纯观赏用）

# ---------------------------------------------------------------------
# 场地 / 视口
# ---------------------------------------------------------------------
const VIEW_W := 1280.0           # 逻辑分辨率宽（project.godot 里也要一致）
const VIEW_H := 720.0            # 逻辑分辨率高
const ARENA := Rect2(32.0, 40.0, 1216.0, 640.0)
## 球的反弹边界（不是地图墙，是"内缩后的可活动区"）。
## 必须和 arena.tscn 的墙内壁对齐：改地图尺寸时这里也要跟着改。

# ---------------------------------------------------------------------
# 主角：弹弓式发射
#   按下 → 进入瞄准（球不停，照常飞）
#   拖动 → 方向 = 球→鼠标，力度 = 距离
#   松开 → 按该矢量发射
# ---------------------------------------------------------------------
const PLAYER_RADIUS := 17.0      # 基准半径（虫球会乘 0.7）；改大整体判定都变大
const DRAG_MAX := 230.0          # 拖动多远算满力（px）；越大越难满力
const DRAG_DEADZONE := 24.0      # 小于此距离视为取消（px）
const LAUNCH_MIN_SPEED := 320.0  # 力度 0 时的出膛速度（px/s）
const LAUNCH_MAX_SPEED := 980.0  # 力度 1 时的出膛速度（px/s）
const FLY_FRICTION := 215.0      # 空中线性减速（px/s²）；越大停得越快
const SETTLE_SPEED := 80.0       # 低于此速度算停稳（px/s），会回到 IDLE
const CRACK_TIME := 1.2          # 停死（速度 0 + 变向 0）后多久碎裂判负（现实秒）
const WALL_DAMP := 0.95          # 撞墙后保留的速度比例（0~1）；越大反弹损耗越小
const RAM_BOUNCE := 0.88         # 撞 Boss 后保留的速度比例（0~1）

const PLAYER_IFRAME := 1.1       # 受击后的无敌时间（战场秒）；越小越硬核
const PLAYER_SPAWN := Vector2(640.0, 596.0)   # 出生点（也是空投落点）

# 空中变向：每次发射自带 1 次；撞墙 / 撞障碍 / 撞 Boss 各 +1
const AIR_CHANGE_BASE := 1       # 每次发射自带的变向次数
const AIR_CHANGE_MAX := 3        # 常规角色的变向上限（虫球用自己的 5）

# 游球被动：每反弹一次 +2% 极限速度，最多 20 层（+40%）；保持 4 秒后每 0.2 秒掉一层
const ROAM_STACK_BONUS := 0.02    # 每层加多少极限速度（+2%）
const ROAM_STACK_MAX := 20        # 最多叠几层（满层 +40%）
const ROAM_STACK_HOLD := 4.0      # 叠好后保持多久（现实秒）
const ROAM_STACK_DECAY := 0.2     # 之后每掉一层耗时（现实秒）

# ---------------------------------------------------------------------
# Boss 漂移区（这块区域不放墙，避免 Boss 贴墙出弹被吃掉）
# ---------------------------------------------------------------------
const BOSS_ZONE := Rect2(340.0, 148.0, 600.0, 306.0)

# ---------------------------------------------------------------------
# 角色表
#   radius       : 半径倍率（1.0 = 基准 17px）
#   max_changes  : 变向上限
#   speed        : 出膛速度倍率
#   wall         : 撞墙 / 障碍物的速度保留倍率
#   ram          : 撞 Boss 的速度保留倍率
#   shield       : 是否有右键护盾（盾球）
#   slow_field   : 是否是右键慢放（虫球）
# ---------------------------------------------------------------------
const CHARS := [
	{
		"key": "roamer", "name": "游球", "name_en": "Ranger Ball", "en": "RANGER",
		"note": "标准速度 · 反弹损耗小", "note_en": "Standard speed · low bounce loss", "note2": "无技能", "note2_en": "No ability",
		"radius": 1.0, "max_changes": 3,
		"speed": 1.0, "wall": 1.0, "ram": 1.0, "shield": false, "slow_field": false,
	},
	{
		"key": "aegis", "name": "盾球", "name_en": "Aegis Ball", "en": "AEGIS",
		"note": "0.9× 速度 · 反弹损耗更大", "note_en": "0.9× speed · heavier bounce loss", "note2": "右键护盾 · 弧面接弹回充", "note2_en": "RMB shield · catch bullets on the arc to refill",
		"radius": 1.0, "max_changes": 3,
		"speed": 0.9, "wall": 0.89, "ram": 0.90, "shield": true, "slow_field": false,
	},
	{
		"key": "bug", "name": "虫球", "name_en": "Instar Ball", "en": "INSTAR",
		"note": "70% 体积 · 5 次变向", "note_en": "70% size · 5 redirects", "note2": "右键 0.05× 慢放 · 碰 5 次进化", "note2_en": "RMB 0.05× slow · 5 bumps per evolution",
		"radius": 0.7, "max_changes": 5,
		"speed": 1.0, "wall": 0.96, "ram": 0.96, "shield": false, "slow_field": true,
	},
]

# ---------------------------------------------------------------------
# 虫球：右键慢放 + 五段进化
#   每碰（撞墙 / 撞障碍 / 撞 Boss）5 次 → 进化一档，共 5 档
#   满级后：0.5 抗伤护盾（6 秒回复）+ 撞敌人撕裂 + 撞完加速 20%
# ---------------------------------------------------------------------
const BUG_SLOW_SCALE := 0.05      # 按住右键时的时间流速；0.05 = 几乎定格
const BUG_SLOW_FIELD_MAX := 2.5   # 慢放场充能上限（秒）；按住最多撑这么久
const BUG_SLOW_FIELD_REFILL := 0.5 # 松手后每秒回复多少秒充能（0.5 → 5 秒充满）
const BUG_SLOW_FIELD_PER_TIER := 1.3  # 每进化一档，慢放场最大持续时间 ×1.3（相对上一档）
const BUG_MAX_TIER := 5           # 进化档数上限（也是球下进度条的格数）
const BUG_HITS_PER_TIER := 5      # 每进化一档需要碰撞几次
const BUG_SHIELD_CD := 6.0        # 满级抗伤护盾的回复间隔（秒）
const BUG_SHIELD_ABSORB := 0.5    # 每次挡掉多少伤害（1 = 全免，0.5 = 只吃半血）
const BUG_RUSH_BOOST := 1.2       # 撞到敌人后的速度倍率（1.2 = 加速 20%）
const BUG_RUSH_CAP := 1500.0      # 冲刺加速的速度上限（px/s），防止无限叠加

# ---------------------------------------------------------------------
# 护盾（只有盾球有）
#   右键开启，按住维持；松手立刻关盾并开始回充
#   0.0–0.3s  只有球壳，无扇形
#   0.3–0.5s  绿色扇形出现，扇内被命中 +0.5s 持续时间
#   0.5–1.0s  黄绿色，扇形缩小到 0.8×，扇内被命中 -0.5s 冷却
#   1.0–1.5s  红色，只挡子弹
# ---------------------------------------------------------------------
const SHIELD_DURATION := 1.5      # 满充能能维持多久（秒）
const SHIELD_CD := 2.0            # 注释用：0 → 满 的冷却时长（由 REFILL 推出）
const SHIELD_REFILL := 0.75       # 每秒回复多少秒充能（0.75 → 2 秒充满）
const SHIELD_ARC_THICK := 11.0    # 弧面判定厚度（px）；越大越好接弹
const SHIELD_SHOTS := 4           # 一次开盾能扛几发；挡满就碎
const SHIELD_BREAK_IFRAME := 0.1  # 护盾破碎瞬间给的无敌（秒）

const SHIELD_S1 := 0.3            # 阶段 1 起始时间（绿）
const SHIELD_S2 := 0.5            # 阶段 2 起始时间（黄绿）
const SHIELD_S3 := 1.0            # 阶段 3 起始时间（红）
const SHIELD_FAN_RADIUS := 96.0   # 扇形半径（px）
const SHIELD_FAN_HALF := 0.52     # 扇形半角（rad，0.52 ≈ 30°）
const SHIELD_FAN_SHRINK := 0.8    # 二阶段扇形缩小的倍率
const SHIELD_ABSORB_TIME := 0.5   # 一阶段接住子弹：回复多少秒持续时间
const SHIELD_ABSORB_CD := 0.5     # 二阶段接住子弹：回复多少秒冷却

# 难度 → Boss 反击箭头数量（简单/普通/困难）
const ARROWS_BY_DIFFICULTY := [3, 4, 5]

# 入场空投（按现实时间播，不受慢放影响）
const DROP_TIME := 0.55           # 从出现到落地用多久（秒）
const DROP_HEIGHT := 170.0        # 起始"高度"（px），决定放大与下落的幅度

# ---------------------------------------------------------------------
# Boss ·「环」（第一章，3 滴血）
# ---------------------------------------------------------------------
const BOSS_HP := 3                # 血量（撞击次数）
const BOSS_IFRAME := 0.45         # 被撞后的无敌（战场秒）；只防同帧连撞，别调太大
const BOSS_INTRO := 0.7           # 登场时间（现实秒），期间不出招
const BOSS_STAGGER := 0.5         # 受击后的硬直（战场秒），暂停出招
const BOSS_WINDUP := 1.5          # 圆形弹幕的预警时长（现实秒）
const BOSS_FAN_WINDUP := 1.0      # 扇形弹幕的预警时长（现实秒）

# 四向反击：身上常驻几个箭头一直在转，被撞时朝这几个方向各打 1 发
const BOSS_ARROW_COUNT := 4       # 箭头数量（会被难度覆盖，见 ARROWS_BY_DIFFICULTY）
const BOSS_ARROW_SPIN := 1.15     # 箭头整体旋转速度（rad/s）
const BOSS_ARROW_WOBBLE := 0.30   # 每个箭头的独立摆动幅度（rad）
const BOSS_COUNTER_SPEED := 145.0 # 反击弹速度（px/s）
const BOSS_HOME := Vector2(640.0, 292.0)   # 漂移中心点
const BOSS_RADIUS := 54.0         # 本体半径（px），影响撞击判定与绘制

# ---------------------------------------------------------------------
# Boss2 ·「壁」（第二章，6 滴血）
#   3 块环绕弧形圣盾（每块 2 点耐久）；直线快弹 + 扇形弹幕
#   撞到玩家：弹开 + 减速 45% + 3 秒极速上限 80%
# ---------------------------------------------------------------------
const BOSS2_HP := 6               # 血量
const BOSS2_RADIUS := 58.0        # 本体半径（px）
const BOSS2_HOME := Vector2(640.0, 286.0)  # 漂移中心点
const BOSS2_INTRO := 1.2          # 登场时间（现实秒）
const BOSS2_IFRAME := 0.45        # 被撞后的无敌（战场秒）
const BOSS2_DRIFT := 0.75         # 移速倍率（振幅与频率都乘它）

const BOSS2_PLATES := 3           # 环绕圣盾数量
const BOSS2_PLATE_HP := 2         # 每块圣盾的耐久（撞几下碎）
const BOSS2_PLATE_RADIUS := 112.0 # 圣盾绕本体旋转的轨道半径（px）
const BOSS2_PLATE_R := 65.0       # 单块圣盾的半径（px）；越大越难绕过去
const BOSS2_PLATE_SPIN := 0.75    # 圣盾基础转速（rad/s）

const BOSS2_RAIL_SPEED := 1120.0  # 直线快弹速度（px/s）；很快，不开慢放很难躲
const BOSS2_RAIL_LEN := 34.0      # 长方形弹体长度（px，绘制用）
const BOSS2_RAIL_THICK := 7.8     # 长方形弹体厚度（px，绘制用）
const BOSS2_RAIL_INTERVAL := 2.8  # 直线弹的发射间隔（战场秒）
const BOSS2_AIM_TIME := 0.55      # 开火前的瞄准线时长（战场秒）

const BOSS2_FAN_BASE := 5         # 扇形基础弹数（难度再加 0/+1/+2）
const BOSS2_FAN_SPREAD := 0.17    # 相邻两发的夹角（rad）
const BOSS2_FAN_SPEED := 215.0    # 扇形弹速度（px/s）
const BOSS2_FAN_INTERVAL := 3.2   # 扇形弹幕的间隔（战场秒）
const BOSS2_FAN_WINDUP := 1.0     # 扇形预警时长（现实秒）

const BOSS2_SLOW_FACTOR := 0.75   # 撞到盾牌/本体后速度剩多少（0.75 = 减速 25%）
const BOSS2_SPEED_CAP := 0.5      # 3 秒内出膛极速的倍率（0.5 = 只剩 50%）
const BOSS2_CAP_TIME := 3.0       # 极速上限持续多久（现实秒）
const BOSS2_RAIL_CAP := 0.65      # 被长方形快弹命中后，极速压到 65%

# ---------------------------------------------------------------------
# 子弹
# ---------------------------------------------------------------------
const BULLET_RADIUS := 7.5        # 基础半径（px）
const BULLET_LIFE := 12.0         # 存活时间（战场秒）
const BULLET_CAP := 180           # 同屏子弹上限，保护性能

# ---------------------------------------------------------------------
# 配色
# ---------------------------------------------------------------------
const COL_BG := Color(0.027, 0.039, 0.063)          # 背景
const COL_GRID := Color(0.11, 0.16, 0.23)           # 背景网格
const COL_PLAYER := Color(0.494, 0.941, 1.0)        # 主角球体（青）
const COL_PLAYER_CORE := Color(0.85, 0.99, 1.0)     # 主角内芯
const COL_BOSS := Color(1.0, 0.302, 0.427)          # 1 号 Boss（红）
const COL_BOSS_CORE := Color(1.0, 0.706, 0.760)     # 1 号 Boss 核心
const COL_BULLET := Color(1.0, 0.635, 0.302)        # 普通弹（橙）
const COL_BULLET_FAST := Color(1.0, 0.839, 0.400)   # 快速弹（黄）
const COL_BULLET_BIG := Color(1.0, 0.420, 0.545)    # 大弹（粉红）
const COL_ACCENT := Color(0.553, 0.910, 0.988)      # 界面强调色
const COL_TEXT := Color(0.878, 0.933, 0.980)        # 正文
const COL_MUTED := Color(0.400, 0.470, 0.570)       # 次要文字
const COL_DANGER := Color(1.0, 0.353, 0.420)        # 危险 / 失败

# ---------------------------------------------------------------------
# 状态机（Main.state 与 HUD 共用）
# ---------------------------------------------------------------------
const ST_TITLE := 0               # 标题页
const ST_PLAY := 1                # 战斗中
const ST_WIN := 2                 # 胜利结算
const ST_LOSE := 3                # 失败结算
