extends Control
## 全部 UI 用即时绘制完成：不依赖任何图片 / 主题资源。
## 中文字体走 SystemFont（雅黑 → 苹方 → 思源），没有则回退默认字体。

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）
const I18N := preload("res://scripts/i18n.gd")     # 多语言文案

var game = null                   # 由 Main 注入，用来读状态
var font_cn: SystemFont           # 中文字体（系统字体，回退链见 _ready）
var font_num: SystemFont          # 数字 / 英文等宽字体
var t := 0.0                      # 累计时间（呼吸、闪烁动画用）

# ---- 标题页：角色卡片（一行三张）----
const CHAR_W := 284.0             # 单张角色卡宽度（px）
const CHAR_H := 88.0              # 单张角色卡高度
const CHAR_GAP := 22.0            # 卡片间距
const CHAR_Y := 234.0             # 这一行的顶部 y

# ---- 标题页：难度卡片（一行三张）----
const CARD_W := 240.0             # 单张难度卡宽度
const CARD_H := 94.0              # 单张难度卡高度
const CARD_GAP := 22.0            # 卡片间距
const CARD_Y := 362.0             # 这一行的顶部 y

# ---- 标题页：关卡按钮（一行两个）----
const BOSS_W := 236.0             # 单个关卡按钮宽度
const BOSS_H := 40.0              # 单个关卡按钮高度
const BOSS_GAP := 20.0            # 两个按钮的间距
const BOSS_Y := 496.0             # 这一行的顶部 y

# ---- 标题页：右上角语言切换 ----
const LANG_W := 76.0              # 单个语言按钮宽度
const LANG_H := 30.0              # 按钮高度
const LANG_GAP := 10.0            # 两个按钮的间距
const LANG_Y := 34.0              # 按钮顶部 y


func _ready() -> void:
	# 暂停时也要继续画（暂停遮罩 / 呼吸动画）
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	font_cn = SystemFont.new()
	font_cn.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
		"Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei", "sans-serif",
	])
	font_cn.font_weight = 500

	font_num = SystemFont.new()
	font_num.font_names = PackedStringArray([
		"Consolas", "Cascadia Mono", "SF Mono", "DejaVu Sans Mono", "monospace",
	])


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


# ---------------------------------------------------------------------
# 绘制入口
# ---------------------------------------------------------------------
func _draw() -> void:
	if game == null:
		return
	if game.state == CFG.ST_TITLE:
		_draw_title()
	else:
		_draw_battle()
		if game.paused:
			_draw_pause()
		elif game.state == CFG.ST_WIN or game.state == CFG.ST_LOSE:
			_draw_panel(game.state == CFG.ST_WIN)


## 暂停遮罩：要么提示点击，要么显示 3 秒倒数
func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, CFG.VIEW_W, CFG.VIEW_H), Color(0.01, 0.02, 0.04, 0.62))
	var pulse := 0.5 + 0.5 * sin(t * 2.4)
	if game.resume_count > 0.0:
		# 倒数阶段：大数字 + 准备
		var n := int(ceil(game.resume_count))
		_txt_center(str(n), CFG.VIEW_W * 0.5, CFG.VIEW_H * 0.5 + 12.0, 96,
			Color(CFG.COL_ACCENT, 0.95))
		_txt_center(I18N.t("pause.ready"), CFG.VIEW_W * 0.5, CFG.VIEW_H * 0.5 + 64.0, 16,
			Color(CFG.COL_MUTED, 0.6 + 0.3 * pulse))
		return
	_txt_center(I18N.t("pause.title"), CFG.VIEW_W * 0.5, CFG.VIEW_H * 0.5 - 8.0, 44,
		Color(CFG.COL_ACCENT, 0.95))
	if game.pause_by_focus:
		_txt_center(I18N.t("pause.click"), CFG.VIEW_W * 0.5, CFG.VIEW_H * 0.5 + 34.0, 15,
			Color(CFG.COL_MUTED, 0.55 + 0.35 * pulse))
	else:
		_txt_center(I18N.t("pause.space"), CFG.VIEW_W * 0.5, CFG.VIEW_H * 0.5 + 34.0, 15,
			Color(CFG.COL_MUTED, 0.55 + 0.35 * pulse))


# ---------------------------------------------------------------------
# 文本工具
# ---------------------------------------------------------------------
func _txt_center(text: String, cx: float, cy: float, size_px: int, color: Color,
		font: Font = null, box: float = 900.0) -> void:
	var f: Font = font if font != null else font_cn
	var by := cy + (f.get_ascent(size_px) - f.get_descent(size_px)) * 0.5
	draw_string(f, Vector2(cx - box * 0.5, by), text, HORIZONTAL_ALIGNMENT_CENTER, box, size_px, color)


func _txt_left(text: String, x: float, cy: float, size_px: int, color: Color,
		font: Font = null) -> void:
	var f: Font = font if font != null else font_cn
	var by := cy + (f.get_ascent(size_px) - f.get_descent(size_px)) * 0.5
	draw_string(f, Vector2(x, by), text, HORIZONTAL_ALIGNMENT_LEFT, 700.0, size_px, color)


func _txt_right(text: String, x: float, cy: float, size_px: int, color: Color,
		font: Font = null) -> void:
	var f: Font = font if font != null else font_cn
	var by := cy + (f.get_ascent(size_px) - f.get_descent(size_px)) * 0.5
	draw_string(f, Vector2(x - 700.0, by), text, HORIZONTAL_ALIGNMENT_RIGHT, 700.0, size_px, color)


func _text_width(text: String, size_px: int, font: Font) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x


func _vignette(alpha: float) -> void:
	if alpha <= 0.001:
		return
	for i in 26:
		var k := float(i) / 26.0
		var inset := float(i) * 5.0
		draw_rect(Rect2(inset, inset, CFG.VIEW_W - inset * 2.0, CFG.VIEW_H - inset * 2.0),
			Color(0.0, 0.0, 0.0, alpha * 0.055 * (1.0 - k)), false, 6.0)


# ---------------------------------------------------------------------
# 标题
# ---------------------------------------------------------------------
func _card_rect(i: int) -> Rect2:
	var total := CARD_W * 3.0 + CARD_GAP * 2.0
	var x0 := (CFG.VIEW_W - total) * 0.5
	return Rect2(x0 + float(i) * (CARD_W + CARD_GAP), CARD_Y, CARD_W, CARD_H)


## 取字段的当前语言版本：有 xxx_en 就用它，否则回落中文
func _tr(d: Dictionary, key: String) -> String:
	if I18N.is_en() and d.has(key + "_en"):
		return str(d[key + "_en"])
	return str(d.get(key, ""))


func _char_rect(i: int) -> Rect2:
	var total := CHAR_W * float(CFG.CHARS.size()) + CHAR_GAP * float(CFG.CHARS.size() - 1)
	var x0 := (CFG.VIEW_W - total) * 0.5
	return Rect2(x0 + float(i) * (CHAR_W + CHAR_GAP), CHAR_Y, CHAR_W, CHAR_H)


func diff_hit(pos: Vector2) -> int:
	for i in 3:
		if _card_rect(i).has_point(pos):
			return i
	return -1


func char_hit(pos: Vector2) -> int:
	for i in CFG.CHARS.size():
		if _char_rect(i).has_point(pos):
			return i
	return -1


func _lang_rect(i: int) -> Rect2:
	var total := LANG_W * 2.0 + LANG_GAP
	var x0 := CFG.VIEW_W - 44.0 - total
	return Rect2(x0 + float(i) * (LANG_W + LANG_GAP), LANG_Y, LANG_W, LANG_H)


func lang_hit(pos: Vector2) -> int:
	for i in 2:
		if _lang_rect(i).has_point(pos):
			return i
	return -1


func _boss_rect(i: int) -> Rect2:
	var total := BOSS_W * 2.0 + BOSS_GAP
	var x0 := (CFG.VIEW_W - total) * 0.5
	return Rect2(x0 + float(i) * (BOSS_W + BOSS_GAP), BOSS_Y, BOSS_W, BOSS_H)


func boss_hit(pos: Vector2) -> int:
	for i in 2:
		if _boss_rect(i).has_point(pos):
			return i
	return -1


func _draw_title() -> void:
	draw_rect(Rect2(0, 0, CFG.VIEW_W, CFG.VIEW_H), Color(0.016, 0.024, 0.039, 0.80))

	# 背景装饰：缓慢旋转的同心弧
	var c := Vector2(CFG.VIEW_W * 0.5, 236.0)
	for i in 3:
		var r := 170.0 + float(i) * 58.0
		var a0 := t * (0.10 + 0.04 * float(i)) + float(i) * 1.7
		draw_arc(c, r, a0, a0 + 2.1, 64, Color(CFG.COL_ACCENT, 0.07), 1.5, true)
	draw_circle(c, 6.0, Color(CFG.COL_ACCENT, 0.10))

	# 主标题 SLOW / BALL
	var s1 := "SLOW"
	var s2 := "BALL"
	var fs := 72
	var w1 := _text_width(s1, fs, font_num)
	var w2 := _text_width(s2, fs, font_num)
	var x1 := CFG.VIEW_W * 0.5 - (w1 + w2) * 0.5
	var by := 108.0
	draw_string(font_num, Vector2(x1, by), s1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CFG.COL_TEXT)
	draw_string(font_num, Vector2(x1 + w1, by), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CFG.COL_PLAYER)

	_txt_center(I18N.t("title.sub"), CFG.VIEW_W * 0.5, 144.0, 20, Color(CFG.COL_ACCENT, 0.95))
	draw_line(Vector2(CFG.VIEW_W * 0.5 - 160, 162), Vector2(CFG.VIEW_W * 0.5 + 160, 162),
		Color(CFG.COL_ACCENT, 0.18), 1.0)
	_txt_center(I18N.t("title.tagline"),
		CFG.VIEW_W * 0.5, 188.0, 15, CFG.COL_MUTED)

	# ---- 右上角：语言切换（加标签 + 选中反白，做得醒目一点）----
	var lmouse := get_local_mouse_position()
	var lhover := lang_hit(lmouse)
	var ltotal := LANG_W * 2.0 + LANG_GAP
	_txt_right(I18N.t("lang.label"), CFG.VIEW_W - 44.0 - ltotal - 14.0, LANG_Y + LANG_H * 0.5 + 5.0, 13,
		Color(CFG.COL_MUTED, 0.9))
	for i in 2:
		var code: String = I18N.LANGS[i]
		var lr := _lang_rect(i)
		var on: bool = I18N.lang == code
		var hov: bool = i == lhover
		if on:
			# 选中：外发光 + 实心强调色 + 深色字
			draw_rect(lr.grow(3.0), Color(CFG.COL_ACCENT, 0.14), true)
			draw_rect(lr.grow(1.5), Color(CFG.COL_ACCENT, 0.28), true)
			draw_rect(lr, Color(CFG.COL_ACCENT, 0.94), true)
			_txt_center(I18N.LANG_LABEL[code], lr.get_center().x, lr.get_center().y + 1.0, 15,
				Color(0.02, 0.06, 0.09, 0.95))
		else:
			draw_rect(lr, Color(0.06, 0.10, 0.14, 0.94), true)
			draw_rect(lr, Color(CFG.COL_ACCENT, 0.85 if hov else 0.45), false, 1.5)
			_txt_center(I18N.LANG_LABEL[code], lr.get_center().x, lr.get_center().y + 1.0, 15,
				CFG.COL_TEXT if hov else Color(0.74, 0.82, 0.90))

	var mouse := get_local_mouse_position()

	# ---- 角色 ----
	_txt_left(I18N.t("title.char"), 196.0, 226.0, 13, Color(CFG.COL_MUTED, 0.9))
	draw_line(Vector2(266, 226), Vector2(288, 226), Color(0.18, 0.24, 0.32), 1.0)
	var chover := char_hit(mouse)
	for i in CFG.CHARS.size():
		var cd: Dictionary = CFG.CHARS[i]
		var cr := _char_rect(i)
		var cchosen: bool = i == int(game.character)
		var chov: bool = i == chover
		var cedge := CFG.COL_ACCENT if cchosen else Color(0.20, 0.27, 0.36)
		if chov and not cchosen:
			cedge = Color(0.35, 0.48, 0.58)
		var cfill := Color(0.055, 0.085, 0.118, 0.92)
		if cchosen:
			cfill = Color(0.07, 0.14, 0.18, 0.96)
		elif chov:
			cfill = Color(0.07, 0.10, 0.14, 0.94)
		draw_rect(cr, cfill, true)
		draw_rect(cr, cedge, false, 1.5 if cchosen else 1.0)
		if cchosen:
			draw_rect(Rect2(cr.position.x, cr.position.y, cr.size.x, 3.0), CFG.COL_ACCENT, true)

		var ctext := CFG.COL_TEXT if cchosen else Color(0.72, 0.78, 0.86)
		_txt_left(cd["en"], cr.position.x + 16.0, cr.position.y + 16.0, 10,
			Color(CFG.COL_ACCENT, 0.75) if cchosen else CFG.COL_MUTED, font_num)
		_txt_left(_tr(cd, "name"), cr.position.x + 16.0, cr.position.y + 39.0, 20, ctext)
		_txt_left(_tr(cd, "note"), cr.position.x + 16.0, cr.position.y + 62.0, 11, CFG.COL_MUTED)
		_txt_left(_tr(cd, "note2"), cr.position.x + 16.0, cr.position.y + 78.0, 11,
			Color(CFG.COL_MUTED, 0.8))
		_player_icon(Vector2(cr.end.x - 28.0, cr.position.y + 38.0), i, cchosen)

	# ---- 难度 ----
	_txt_left(I18N.t("title.diff"), 196.0, 352.0, 13, Color(CFG.COL_MUTED, 0.9))
	draw_line(Vector2(266, 352), Vector2(288, 352), Color(0.18, 0.24, 0.32), 1.0)
	var dhover := diff_hit(mouse)
	for i in 3:
		var d: Dictionary = CFG.DIFFICULTIES[i]
		var r := _card_rect(i)
		var chosen: bool = i == int(game.difficulty)
		var is_hover: bool = i == dhover
		var edge := CFG.COL_ACCENT if chosen else Color(0.20, 0.27, 0.36)
		if is_hover and not chosen:
			edge = Color(0.35, 0.48, 0.58)
		var fill := Color(0.055, 0.085, 0.118, 0.92)
		if chosen:
			fill = Color(0.07, 0.14, 0.18, 0.96)
		elif is_hover:
			fill = Color(0.07, 0.10, 0.14, 0.94)
		draw_rect(r, fill, true)
		draw_rect(r, edge, false, 1.5 if chosen else 1.0)

		if chosen:
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), CFG.COL_ACCENT, true)
			for corner in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
					[r.end, Vector2(-1, -1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)]]:
				var p: Vector2 = corner[0]
				var dd: Vector2 = corner[1]
				draw_line(p, p + Vector2(9.0 * dd.x, 0), CFG.COL_ACCENT, 2.0)
				draw_line(p, p + Vector2(0, 9.0 * dd.y), CFG.COL_ACCENT, 2.0)

		var text_col := CFG.COL_TEXT if chosen else Color(0.72, 0.78, 0.86)
		_txt_left(d["en"], r.position.x + 18.0, r.position.y + 18.0, 10,
			Color(CFG.COL_ACCENT, 0.75) if chosen else CFG.COL_MUTED, font_num)
		_txt_left(_tr(d, "name"), r.position.x + 18.0, r.position.y + 44.0, 23, text_col)
		_txt_left(I18N.t("diff.hp") % d["hp"], r.position.x + 18.0, r.position.y + 68.0, 13,
			CFG.COL_MUTED)
		_txt_left(I18N.t("diff.arrows") % CFG.ARROWS_BY_DIFFICULTY[i], r.position.x + 112.0,
			r.position.y + 68.0, 11, Color(CFG.COL_MUTED, 0.8))

		# 血量珠
		for k in int(d["hp"]):
			var px := r.position.x + 20.0 + float(k) * 15.0
			var py := r.end.y - 11.0
			if px < r.end.x - 12.0:
				draw_circle(Vector2(px, py), 4.0, Color(CFG.COL_PLAYER, 0.85 if chosen else 0.45))

	# ---- 关卡（选 Boss）----
	_txt_left(I18N.t("title.stage"), 196.0, 482.0, 13, Color(CFG.COL_MUTED, 0.9))
	draw_line(Vector2(266, 482), Vector2(288, 482), Color(0.18, 0.24, 0.32), 1.0)
	var bhover := boss_hit(mouse)
	for i in 2:
		var br := _boss_rect(i)
		var bchosen: bool = i == int(game.boss_stage) - 1
		var bhov: bool = i == bhover
		var bedge := CFG.COL_ACCENT if bchosen else Color(0.20, 0.27, 0.36)
		if bhov and not bchosen:
			bedge = Color(0.35, 0.48, 0.58)
		var bfill := Color(0.055, 0.085, 0.118, 0.92)
		if bchosen:
			bfill = Color(0.07, 0.14, 0.18, 0.96)
		elif bhov:
			bfill = Color(0.07, 0.10, 0.14, 0.94)
		draw_rect(br, bfill, true)
		draw_rect(br, bedge, false, 1.5 if bchosen else 1.0)
		if bchosen:
			draw_rect(Rect2(br.position.x, br.position.y, 3.0, br.size.y), CFG.COL_ACCENT, true)
		var bname := I18N.t("stage.1") if i == 0 else I18N.t("stage.2")
		_txt_center(bname, br.get_center().x, br.get_center().y, 16,
			CFG.COL_TEXT if bchosen else Color(0.70, 0.76, 0.84))

	# 操作提示
	_txt_center(I18N.t("title.hint"),
		CFG.VIEW_W * 0.5, 566.0, 14, Color(CFG.COL_MUTED, 0.95))

	draw_line(Vector2(330, 588), Vector2(950, 588), Color(0.16, 0.22, 0.30), 1.0)

	# 玩法两条
	_txt_left(I18N.t("title.rule1"),
		300.0, 610.0, 14, Color(CFG.COL_MUTED, 0.9))
	_txt_left(I18N.t("title.rule2"),
		300.0, 634.0, 14, Color(CFG.COL_MUTED, 0.9))

	_txt_right("PROTOTYPE v0.13  ·  GODOT 4.7", CFG.VIEW_W - 40.0, 690.0, 12,
		Color(CFG.COL_MUTED, 0.6), font_num)


## 标题卡片右上角的小头像
func _player_icon(c: Vector2, ci: int, chosen: bool) -> void:
	var r := 13.0
	draw_circle(c, r, Color(CFG.COL_PLAYER, 0.75 if chosen else 0.42))
	draw_circle(c, r * 0.62, Color(CFG.COL_PLAYER_CORE, 0.85 if chosen else 0.5))
	if ci == 1:
		var socket := Rect2(c.x - r * 0.64, c.y - r * 0.30, r * 1.28, r * 0.60)
		draw_rect(socket, Color(0.03, 0.07, 0.06, 0.92), true)
		draw_rect(Rect2(c.x - r * 0.19, c.y - r * 0.19, r * 0.38, r * 0.38),
			Color(0.36, 1.0, 0.62, 0.95 if chosen else 0.55), true)
	elif ci == 2:
		# 复眼
		draw_circle(c, r * 0.52, Color(0.04, 0.09, 0.11, 0.9))
		for i in 6:
			var ang := TAU * float(i) / 6.0 + 0.3
			draw_circle(c + Vector2.from_angle(ang) * r * 0.28, r * 0.15,
				Color(0.62, 0.98, 1.0, 0.85 if chosen else 0.45))
	else:
		draw_circle(c + Vector2(r * 0.14, 0), r * 0.26, Color(0.02, 0.05, 0.08, 0.9))


# ---------------------------------------------------------------------
# 战斗 HUD
# ---------------------------------------------------------------------
func _draw_battle() -> void:
	var p = game.player
	var b = game.boss

	# 慢放时压一层冷色 + 暗角，用视觉直接说明"时间变慢了"
	var slow: float = game.slow_amount
	if slow > 0.01:
		draw_rect(Rect2(0, 0, CFG.VIEW_W, CFG.VIEW_H),
			Color(0.10, 0.26, 0.44, 0.10 * slow))
		_vignette(0.55 + 0.45 * slow)

	# 受击红屏
	if game.hurt_flash > 0.01:
		draw_rect(Rect2(0, 0, CFG.VIEW_W, CFG.VIEW_H),
			Color(CFG.COL_DANGER, 0.22 * game.hurt_flash))

	if p == null or not is_instance_valid(p):
		return

	# ---------- 左上：难度 + 主角血量 ----------
	var diff: Dictionary = CFG.DIFFICULTIES[game.difficulty]
	_txt_left("%s · %s" % [diff["name"], CFG.CHARS[game.character]["name"]], 48.0, 40.0, 15,
		CFG.COL_MUTED)
	_txt_left("HP", 48.0, 62.0, 11, Color(CFG.COL_MUTED, 0.7), font_num)
	for i in p.max_hp:
		var px := 76.0 + float(i) * 24.0
		var py := 62.0
		var v := clampf(p.hp - float(i), 0.0, 1.0)
		if v >= 0.75:
			var pulse := 1.0 + 0.12 * sin(t * 5.0)
			draw_circle(Vector2(px, py), 8.0 * pulse, Color(CFG.COL_PLAYER, 0.12))
			draw_circle(Vector2(px, py), 7.0, Color(CFG.COL_PLAYER, 0.95))
			draw_circle(Vector2(px, py), 3.0, Color(1, 1, 1, 0.9))
		elif v > 0.2:
			# 半格（虫球的 0.5 抗伤会打出半血）
			draw_circle(Vector2(px, py), 7.0, Color(CFG.COL_PLAYER, 0.35))
			draw_circle(Vector2(px, py), 4.0, Color(CFG.COL_PLAYER, 0.95))
		else:
			draw_arc(Vector2(px, py), 6.5, 0, TAU, 24, Color(CFG.COL_MUTED, 0.45), 1.2, true)

	# 空中变向次数
	var charge_col := CFG.COL_ACCENT if p.charges > 0 else Color(CFG.COL_MUTED, 0.6)
	_txt_left(I18N.t("hud.charges") % p.charges, 48.0, 94.0, 12, Color(charge_col, 0.85))
	# 游球被动：反弹叠层
	if p.char_id == 0 and p.speed_stacks > 0:
		# 衰退阶段（保持时间用完）变暗，提示正在往下掉
		var s_col := Color(CFG.COL_PLAYER, 0.9) if p.stack_hold > 0.0 else Color(1.0, 0.62, 0.35, 0.9)
		var s_pct := int(round(p.speed_stacks * CFG.ROAM_STACK_BONUS * 100.0))
		_txt_left(I18N.t("hud.stacks") % [s_pct, p.speed_stacks, CFG.ROAM_STACK_MAX],
			48.0, 114.0, 12, s_col)
	if not p.is_flying() and p.power > 0.02:
		_txt_left(I18N.t("hud.power") % int(round(p.power * 100.0)), 176.0 if I18N.is_en() else 122.0, 94.0, 12,
			Color(CFG.COL_PLAYER, 0.9 if p.is_aiming() else 0.55))

	# 停死警告
	if p.crack_t > 0.0:
		var k: float = p.crack_t
		var blink := 0.55 + 0.45 * sin(t * 16.0)
		draw_rect(Rect2(CFG.VIEW_W * 0.5 - 190.0, 178.0, 380.0, 40.0),
			Color(0.30, 0.10, 0.06, 0.45 * k), true)
		_txt_center(I18N.t("hud.cracking"), CFG.VIEW_W * 0.5, 196.0, 20,
			Color(1.0, 0.55, 0.32, (0.55 + 0.45 * blink) * k))
		_txt_center(I18N.t("hud.cracking.sub"), CFG.VIEW_W * 0.5, 214.0, 12,
			Color(1.0, 0.72, 0.55, 0.55 * k))

	# ---------- 顶部中央：Boss ----------
	if b != null and is_instance_valid(b):
		var is_b2: bool = game.stage == 2
		var bcol: Color = CFG.COL_BOSS if not is_b2 else Color(0.58, 0.78, 1.0)
		var bname: String = I18N.t("boss1.name") if not is_b2 else I18N.t("boss2.name")
		_txt_center(bname, CFG.VIEW_W * 0.5, 38.0, 16,
			Color(0.86, 0.62, 0.66) if not is_b2 else Color(0.66, 0.78, 0.96))
		var seg_w := clampf(560.0 / float(b.max_hp) - 6.0, 40.0, 92.0)
		var gap := 6.0
		var total := seg_w * float(b.max_hp) + gap * float(b.max_hp - 1)
		var x0 := CFG.VIEW_W * 0.5 - total * 0.5
		for i in b.max_hp:
			var r := Rect2(x0 + float(i) * (seg_w + gap), 52.0, seg_w, 9.0)
			draw_rect(r, Color(0.12, 0.06, 0.09, 0.85) if not is_b2 else Color(0.07, 0.09, 0.14, 0.85), true)
			if i < b.hp:
				draw_rect(r, Color(bcol, 0.85), true)
				draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 2.0),
					Color(1.0, 0.62, 0.68, 0.9) if not is_b2 else Color(0.85, 0.95, 1.0, 0.9), true)
			draw_rect(r, Color(bcol, 0.35), false, 1.0)

		# Boss2 的环绕护盾：3 块，每块 2 点耐久
		var plist: Variant = b.get("plates")
		if plist != null:
			var plates: Array = plist
			var pw := 18.0
			var pgap := 10.0
			var ptotal := pw * float(plates.size()) + pgap * float(maxi(0, plates.size() - 1))
			var px0 := CFG.VIEW_W * 0.5 - ptotal * 0.5
			for i in plates.size():
				var plate = plates[i]
				var ph := 0
				if is_instance_valid(plate) and plate.active:
					ph = int(plate.hp)
				var rect := Rect2(px0 + float(i) * (pw + pgap), 67.0, pw, 4.0)
				draw_rect(rect, Color(0.07, 0.09, 0.14, 0.9), true)
				if ph > 0:
					draw_rect(Rect2(rect.position, Vector2(pw * float(ph) / 2.0, rect.size.y)),
						Color(0.60, 0.82, 1.0, 0.9), true)
				draw_rect(rect, Color(0.35, 0.50, 0.70, 0.5), false, 1.0)

	# ---------- 右上：时间流速 ----------
	var scale_val: float = Engine.time_scale
	var fast := scale_val > 0.6
	var tcol: Color = CFG.COL_PLAYER if fast else Color(0.62, 0.86, 1.0)
	_txt_right(I18N.t("hud.timescale"), CFG.VIEW_W - 44.0, 34.0, 13, CFG.COL_MUTED)
	_txt_right("%.2f×" % scale_val, CFG.VIEW_W - 44.0, 64.0, 32, tcol, font_cn)
	_txt_right(I18N.t("hud.flying") if fast else I18N.t("hud.aiming"), CFG.VIEW_W - 44.0, 90.0, 13,
		Color(tcol, 0.75))
	var bar := Rect2(CFG.VIEW_W - 214.0, 102.0, 170.0, 4.0)
	draw_rect(bar, Color(0.18, 0.24, 0.32, 0.8), true)
	var k: float = clampf((scale_val - CFG.SLOW_SCALE) / (CFG.FAST_SCALE - CFG.SLOW_SCALE), 0.0, 1.0)
	draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x * k, bar.size.y), tcol, true)

	# ---------- 底部：提示 ----------
	var hint_alpha: float = clampf(1.0 - game.run_real / 14.0, 0.0, 1.0)
	if hint_alpha > 0.01 and game.state == CFG.ST_PLAY:
		_txt_center(I18N.t("hud.tip.default"),
			CFG.VIEW_W * 0.5, 636.0, 15, Color(CFG.COL_MUTED, 0.9 * hint_alpha))
		if p.shield_enabled:
			_txt_center(I18N.t("hud.tip.shield"),
				CFG.VIEW_W * 0.5, 612.0, 13, Color(0.42, 0.95, 0.70, 0.85 * hint_alpha))
		elif p.is_bug:
			_txt_center(I18N.t("hud.tip.bug"),
				CFG.VIEW_W * 0.5, 612.0, 13, Color(0.72, 0.55, 0.98, 0.85 * hint_alpha))

	_txt_left(I18N.t("hud.hits") % game.hits_taken, 48.0, 660.0, 12, Color(CFG.COL_MUTED, 0.7))
	_txt_right(I18N.t("hud.keys"), CFG.VIEW_W - 48.0, 660.0, 12, Color(CFG.COL_MUTED, 0.7))

	# Boss 登场横幅（空投过场期间先不画，免得压在球上）
	if b != null and is_instance_valid(b) and b.intro > 0.0 and (p == null or not p.dropping):
		var a: float = clampf(b.intro / maxf(CFG.BOSS_INTRO, 0.01), 0.0, 1.0)
		if game.stage == 2:
			a = clampf(b.intro / maxf(CFG.BOSS2_INTRO, 0.01), 0.0, 1.0)
			_txt_center(I18N.t("boss2.name"), CFG.VIEW_W * 0.5, 440.0, 32, Color(0.58, 0.78, 1.0, a))
			_txt_center(I18N.t("boss2.banner.sub"), CFG.VIEW_W * 0.5, 472.0, 14,
				Color(CFG.COL_MUTED, a))
		else:
			_txt_center(I18N.t("boss1.name"), CFG.VIEW_W * 0.5, 440.0, 32, Color(CFG.COL_BOSS, a))
			_txt_center(I18N.t("boss1.banner.sub"), CFG.VIEW_W * 0.5, 472.0, 14,
				Color(CFG.COL_MUTED, a))

	# 准星
	if game.state == CFG.ST_PLAY:
		_draw_reticle()


func _draw_reticle() -> void:
	var m: Vector2 = get_local_mouse_position()
	if game.demo:
		m = game.demo_mouse
	var on: bool = game.player != null and is_instance_valid(game.player) and game.player.is_aiming()
	var col: Color = CFG.COL_PLAYER if on else Color(0.75, 0.85, 0.95)
	var r: float = 9.0 if on else 13.0
	draw_arc(m, r, 0, TAU, 36, Color(col, 0.9), 1.6, true)
	draw_circle(m, 1.8, Color(col, 0.95))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		draw_line(m + Vector2.from_angle(a) * (r + 3.0), m + Vector2.from_angle(a) * (r + 8.0),
			Color(col, 0.45), 1.3, true)


# ---------------------------------------------------------------------
# 结算面板
# ---------------------------------------------------------------------
func _retry_rect() -> Rect2:
	return Rect2(436.0, 468.0, 192.0, 52.0)


func _title_button_rect() -> Rect2:
	return Rect2(652.0, 468.0, 192.0, 52.0)


func panel_hit(pos: Vector2) -> String:
	if _retry_rect().has_point(pos):
		return "retry"
	if _title_button_rect().has_point(pos):
		return "title"
	return ""


func _fmt_time(seconds: float) -> String:
	var m := int(seconds) / 60
	var s := fmod(seconds, 60.0)
	return "%02d:%04.1f" % [m, s]


func _draw_panel(win: bool) -> void:
	var a: float = clampf((game.end_timer - 0.15) / 0.35, 0.0, 1.0)
	if a <= 0.001:
		return
	var cracked: bool = (not win) and game.death_cause == "cracked"
	var col: Color = CFG.COL_PLAYER if win else (Color(1.0, 0.66, 0.32) if cracked else CFG.COL_DANGER)

	draw_rect(Rect2(0, 0, CFG.VIEW_W, CFG.VIEW_H), Color(0.0, 0.0, 0.0, 0.55 * a))
	var card := Rect2(340.0, 170.0, 600.0, 380.0)

	# 碎裂战败：卡片背后铺一层放射状裂纹
	if cracked:
		var rng := RandomNumberGenerator.new()
		rng.seed = 777
		var c := card.get_center()
		for i in 9:
			var ang := TAU * float(i) / 9.0 + rng.randf_range(-0.2, 0.2)
			var pts := PackedVector2Array()
			var d := 20.0
			var aa := ang
			pts.append(c)
			for seg in 5:
				d += 60.0 + rng.randf_range(-18.0, 26.0)
				aa += rng.randf_range(-0.16, 0.16)
				pts.append(c + Vector2.from_angle(aa) * d)
			draw_polyline(pts, Color(1.0, 0.45, 0.28, 0.20 * a), 2.0, true)

	draw_rect(card, Color(0.028, 0.043, 0.067, 0.96 * a), true)
	if cracked:
		draw_rect(card, Color(0.35, 0.16, 0.09, 0.55 * a), true)
	draw_rect(card, Color(col, 0.45 * a), false, 1.5)
	draw_rect(Rect2(card.position.x, card.position.y, card.size.x, 3.0), Color(col, 0.85 * a), true)

	var title := I18N.t("end.win") if win else (I18N.t("end.lose.crack") if cracked else I18N.t("end.lose.hit"))
	_txt_center(title, CFG.VIEW_W * 0.5, 232.0, 44, Color(col, a))
	var sub := I18N.t("end.win.boss1") if win else I18N.t("end.lose.hit.sub")
	if win and game.stage == 2:
		sub = I18N.t("end.win.boss2")
	elif cracked:
		sub = I18N.t("end.lose.crack.sub")
	_txt_center(sub, CFG.VIEW_W * 0.5, 274.0, 15, Color(CFG.COL_MUTED, a))
	draw_line(Vector2(396, 300), Vector2(884, 300), Color(0.16, 0.22, 0.30, a), 1.0)

	var diff: Dictionary = CFG.DIFFICULTIES[game.difficulty]
	var rows := [
		[I18N.t("title.diff"), I18N.t("end.difficulty.value") % [_tr(diff, "name"), diff["hp"]]],
		[I18N.t("end.hits"), I18N.t("end.hits.value") % game.hits_taken],
		[I18N.t("end.real"), _fmt_time(game.run_real)],
		[I18N.t("end.world"), _fmt_time(game.run_world)],
	]
	for i in rows.size():
		var ry := 330.0 + float(i) * 30.0
		_txt_left(rows[i][0], 396.0, ry, 14, Color(CFG.COL_MUTED, a))
		_txt_right(rows[i][1], 884.0, ry, 17, Color(CFG.COL_TEXT, a))

	var mouse := get_local_mouse_position()
	_draw_button(_retry_rect(), I18N.t("end.retry"), col, a, _retry_rect().has_point(mouse))
	_draw_button(_title_button_rect(), I18N.t("end.title"), Color(0.55, 0.62, 0.72), a,
		_title_button_rect().has_point(mouse))


func _draw_button(r: Rect2, label: String, col: Color, a: float, hovered: bool) -> void:
	if hovered:
		draw_rect(r, Color(col, 0.16 * a), true)
	draw_rect(r, Color(col, 0.55 * a), false, 1.2)
	_txt_center(label, r.get_center().x, r.get_center().y, 17, Color(col, a))
