extends RefCounted
## 多语言（中文 / English）
##
## 所有界面文字都从这里取：I18N.t("key")。
## 想加语言：在 S 里每一条加一个字段（比如 "ja": "..."），再把 LANGS 加进去。
## 想改文案：直接改下面的 zh / en 字符串，不用翻 HUD 代码。

const LANGS := ["zh", "en"]
const LANG_LABEL := {"zh": "中文", "en": "EN"}

static var lang := "zh"


static func is_en() -> bool:
	return lang == "en"


## 取翻译；缺 key 时直接把 key 显示出来，方便发现漏翻
static func t(key: String) -> String:
	var e: Dictionary = S.get(key, {})
	if e.is_empty():
		return key
	return e.get(lang, e.get("zh", key))


## 临时双语文本（用于带格式的数字/名字）
static func pick(zh: String, en: String) -> String:
	return en if lang == "en" else zh


static func set_lang(code: String) -> void:
	lang = code if code in LANGS else "zh"


static func next_lang() -> String:
	var i := LANGS.find(lang)
	return LANGS[(i + 1) % LANGS.size()]


# =====================================================================
# 文案表
# =====================================================================
const S := {
	# ---------------- 标题页 ----------------
	"title.sub": {"zh": "慢 球", "en": "S L O W   B A L L"},
	"title.tagline": {
		"zh": "抓住球，世界就慢下来；松手飞出去，世界就快起来。",
		"en": "Hold the ball and the world slows down. Let go and it snaps back.",
	},
	"title.char": {"zh": "角色", "en": "CHARACTER"},
	"title.diff": {"zh": "难度", "en": "DIFFICULTY"},
	"title.stage": {"zh": "关卡", "en": "STAGE"},
	"diff.hp": {"zh": "生命 × %d", "en": "HP × %d"},
	"diff.arrows": {"zh": "箭头 × %d", "en": "ARROWS × %d"},
	"stage.1": {"zh": "第一章 ·「环」", "en": "I · RING"},
	"stage.2": {"zh": "第二章 ·「壁」", "en": "II · WALL"},
	"title.hint": {
		"zh": "点卡片选择：角色 / 难度 / 关卡    ·    1 2 3 选难度    ·    Q E 换角色    ·    空格开始",
		"en": "Click to pick: character / difficulty / stage    ·    1-3 difficulty    ·    Q E character    ·    Space to start",
	},
	"title.rule1": {
		"zh": "①  按住左键瞄准（世界 0.1×）：方向 = 球→鼠标，力度 = 距离；松手发射",
		"en": "1  Hold LMB to aim (world at 0.1×): direction = ball→mouse, power = distance. Release to fire",
	},
	"title.rule2": {
		"zh": "②  撞 Boss 一次 1 血；滞空只能变向一次，撞墙 / 障碍物各储存一次",
		"en": "2  Ramming the boss deals 1 damage. You get one mid-air redirect; walls and obstacles each bank one",
	},
	"title.lang": {"zh": "语言", "en": "LANG"},

	# ---------------- 战斗 HUD ----------------
	"hud.charges": {"zh": "变向 ×%d", "en": "REDIRECT ×%d"},
	"hud.power": {"zh": "力度 %d%%", "en": "POWER %d%%"},
	"hud.stacks": {"zh": "加速 +%d%%（%d/%d）", "en": "SPEED +%d%% (%d/%d)"},
	"hud.cracking": {"zh": "球体正在碎裂 —— 立刻发射！", "en": "THE BALL IS CRACKING — FIRE NOW!"},
	"hud.cracking.sub": {"zh": "速度 0 · 变向 0", "en": "Speed 0 · Redirects 0"},
	"hud.timescale": {"zh": "时间流速", "en": "TIME SCALE"},
	"hud.flying": {"zh": "飞行 · 全速", "en": "FLYING · FULL SPEED"},
	"hud.aiming": {"zh": "瞄准 · 慢放", "en": "AIMING · SLOWED"},
	"hud.hits": {"zh": "受击 %d", "en": "HITS %d"},
	"hud.keys": {"zh": "R 重开    Esc 标题", "en": "R restart    Esc title"},
	"hud.tip.default": {
		"zh": "按住后把鼠标拉离球（越远越快） · 松手发射 · 空中还能再抓一次",
		"en": "Drag away from the ball (farther = faster) · release to fire · you can grab again mid-air",
	},
	"hud.tip.shield": {
		"zh": "按住右键维持护盾（可扛 4 发），松手回充；绿色弧面接弹可续时间",
		"en": "Hold RMB for the shield (blocks 4 shots). Release to recharge; catching bullets on the green arc extends it",
	},
	"hud.tip.bug": {
		"zh": "按住右键把世界压到 0.05×（有充能） · 每碰 5 次进化一档",
		"en": "Hold RMB to slow the world to 0.05× (limited charge) · 5 bumps per evolution tier",
	},

	# ---------------- Boss 名字 / 横幅 ----------------
	"boss1.name": {"zh": "环  ·  守门者", "en": "RING  ·  GATEKEEPER"},
	"boss2.name": {"zh": "壁  ·  守门者", "en": "WALL  ·  GATEKEEPER"},
	"boss1.banner.sub": {"zh": "三滴血。撞它三次。", "en": "Three hit points. Ram it three times."},
	"boss2.banner.sub": {
		"zh": "六滴血 · 三块护盾 · 撞它会被减速",
		"en": "Six hit points · three shields · ramming slows you",
	},

	# ---------------- 暂停 ----------------
	"pause.title": {"zh": "已暂停", "en": "PAUSED"},
	"pause.click": {"zh": "点击画面继续 · 倒数 3 秒", "en": "Click to resume · 3-second countdown"},
	"pause.space": {"zh": "空格 继续（倒数 3 秒）    ·    Esc 标题", "en": "Space to resume (3s countdown)    ·    Esc title"},
	"pause.ready": {"zh": "准备…", "en": "GET READY…"},

	# ---------------- 语言开关 ----------------
	"lang.label": {"zh": "语言", "en": "LANGUAGE"},
	# ---------------- 结算面板 ----------------
	"end.win": {"zh": "目标清除", "en": "CLEARED"},
	"end.win.boss1": {"zh": "「环」停止了转动。", "en": "The Ring has stopped turning."},
	"end.win.boss2": {"zh": "「壁」的护盾全部熄灭。", "en": "Every shield of the Wall has gone dark."},
	"end.lose.hit": {"zh": "球体破碎", "en": "BALL SHATTERED"},
	"end.lose.hit.sub": {"zh": "你被弹幕拆成了像素。", "en": "The bullets took you apart, pixel by pixel."},
	"end.lose.crack": {"zh": "球体碎裂", "en": "BALL CRACKED"},
	"end.lose.crack.sub": {
		"zh": "你停得太久 —— 它从内部裂开了。",
		"en": "You stood still too long — it split open from within.",
	},
	"end.difficulty": {"zh": "难度", "en": "Difficulty"},
	"end.difficulty.value": {"zh": "%s（生命 %d）", "en": "%s (HP %d)"},
	"end.hits": {"zh": "受击次数", "en": "Hits taken"},
	"end.hits.value": {"zh": "%d 次", "en": "%d"},
	"end.real": {"zh": "现实用时", "en": "Real time"},
	"end.world": {"zh": "战场时间", "en": "Battle time"},
	"end.retry": {"zh": "再来一次  R", "en": "RETRY  R"},
	"end.title": {"zh": "返回标题  Esc", "en": "TITLE  Esc"},
}
