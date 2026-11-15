extends Node2D
## 游戏主控：状态机、时间倍率、生成/回收、画面反馈。
##
## 时间规则（核心）：
##   抓住球 / 停着 -> Engine.time_scale 缓动到 0.2
##   球在飞        -> Engine.time_scale 缓动到 1.0
## 因为所有实体都用 delta 移动，倍率一变，整个世界一起慢下来。
const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）
const PLAYER_SCENE := preload("res://scenes/player.tscn")  # 主角场景
const BOSS_SCENE := preload("res://scenes/boss.tscn")      # 1 号 Boss「环」
const BOSS2_SCENE := preload("res://scenes/boss2.tscn")  # 2 号 Boss「壁」
const BULLET_SCENE := preload("res://scenes/bullet.tscn") # 子弹
const ARENA_SCENE := preload("res://scenes/arena.tscn")   # TileMap 场地
const SELF_TEST := preload("res://scripts/selftest.gd")  # 机制自检模块
const I18N := preload("res://scripts/i18n.gd")        # 多语言
const SFX := preload("res://scripts/sfx.gd")          # 音效管理器

# ---- 场景节点 ----
@onready var world: Node2D = $World                     # 世界根节点（震屏时整体偏移）
@onready var bullets: Node2D = $World/Bullets           # 子弹容器
@onready var obstacles_root: Node2D = $World/Obstacles  # 场地容器（放 arena）
@onready var entities: Node2D = $World/Entities         # 玩家 / Boss 容器
@onready var fx = $World/FX                             # 粒子与冲击波
@onready var hud = $UI/HUD                              # 全部 UI

# ---- 局内状态 ----
var state := CFG.ST_TITLE      # 状态机：标题 / 战斗 / 胜利 / 失败
var difficulty := 1            # 难度下标：0 简单 / 1 普通 / 2 困难
var character := 0             # 角色下标：0 游球 / 1 盾球 / 2 虫球
var stage := 1                 # 本局打的是第几章（= boss_stage）
var boss_stage := 1            # 标题页选中的关卡：1 环 / 2 壁
var death_cause := "hit"       # 失败原因：hit 被弹幕打死 / cracked 停死碎裂
var sfx: Node = null           # 音效管理器
var player = null              # 主角节点
var boss = null                # 当前 Boss 节点
var obstacles: Array = []      # 实心物列表（现在只有一个 arena 节点）
var arena: Node2D = null       # TileMap 场地节点

# ---- 统计与计时 ----
var hits_taken := 0            # 受击次数（结算页显示）
var run_real := 0.0            # 现实用时（秒）
var run_world := 0.0           # 战场时间（秒，被慢放压缩过）
var end_timer := 0.0           # 结算画面已显示多久（秒）
var hurt_flash := 0.0          # 受击红屏强度（0~1）
var slow_amount := 1.0         # 慢放程度：1 = 完全慢放，0 = 全速
var shake := 0.0               # 当前震屏强度（px）

# ---- 截图 / 自测 ----
var paused := false            # 是否暂停（空格 / 失焦）
var pause_by_focus := false    # 这次暂停是不是失焦导致的
var resume_count := 0.0        # >0 表示正在 3 秒倒计时
var demo := false              # 是否处于截图模式
var debug_collision := false   # F3：显示地图碰撞箱
var demo_mouse := Vector2.ZERO # 截图模式下模拟的鼠标位置
var skip_drop := false         # 自检 / 截图时跳过入场空投

var _last_usec := 0            # 上一帧时间戳（用来算真实 dt）


func _ready() -> void:
	randomize()
	_load_settings()
	hud.game = self
	sfx = SFX.new()
	add_child(sfx)
	# 暂停：Main 与 UI 一直处理，世界里的东西跟着 get_tree().paused 停
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_last_usec = Time.get_ticks_usec()
	Engine.time_scale = CFG.SLOW_SCALE
	_show_title()
	if OS.get_cmdline_user_args().size() > 0:
		_run_cmdline.call_deferred()


## 窗口失焦 → 自动暂停；重新获得焦点 → 自动继续
func _notification(what: int) -> void:
	# 无头模式 / 截图模式没有真正的窗口焦点，不要因此暂停
	if DisplayServer.get_name() == "headless" or demo:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == CFG.ST_PLAY and not paused:
			_set_pause(true, true)
	# 注：FOCUS_IN 时故意不自动恢复——要玩家点一下画面，再倒数 3 秒


func _set_pause(on: bool, by_focus: bool) -> void:
	if paused == on:
		return
	paused = on
	resume_count = 0.0
	pause_by_focus = by_focus and on
	get_tree().paused = on
	if sfx != null:
		sfx.play("ui", -4.0, 0.9 if on else 1.1)
	hud.queue_redraw()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------
# 每帧：时间倍率 / 震屏 / 计时
# ---------------------------------------------------------------------
func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := clampf(float(now - _last_usec) / 1000000.0, 0.0, 0.08)
	_last_usec = now

	if paused:
		# 暂停时只跑"点击后 3 秒倒计时"，不动世界
		if resume_count > 0.0:
			resume_count = maxf(0.0, resume_count - real_dt)
			if resume_count <= 0.0:
				_set_pause(false, false)
		hud.queue_redraw()
		return

	var want := CFG.SLOW_SCALE
	if state == CFG.ST_PLAY and player != null and is_instance_valid(player):
		# 虫球按住右键：把世界压到 0.05 倍
		if player.is_slow_field():
			want = CFG.BUG_SLOW_SCALE
		# 球在飞 = 你在动 = 世界全速；抓住球瞄准 = 世界慢放
		elif player.alive and player.is_flying():
			want = CFG.FAST_SCALE
	elif state == CFG.ST_WIN or state == CFG.ST_LOSE:
		want = CFG.OVER_SCALE
	Engine.time_scale = move_toward(Engine.time_scale, want, CFG.SCALE_LERP * real_dt)

	# 0.05 倍已经低于 SLOW_SCALE，这里改成分段的：越慢越"慢"
	slow_amount = 1.0 - clampf(
		(Engine.time_scale - CFG.BUG_SLOW_SCALE) / (CFG.FAST_SCALE - CFG.BUG_SLOW_SCALE), 0.0, 1.0)

	if state == CFG.ST_PLAY:
		run_real += real_dt
		run_world += real_dt * Engine.time_scale
	elif state == CFG.ST_WIN or state == CFG.ST_LOSE:
		end_timer += real_dt

	hurt_flash = maxf(0.0, hurt_flash - real_dt * 2.4)
	_update_shake(real_dt)

	if demo and player != null and is_instance_valid(player) and player.is_aiming():
		demo_mouse = player.aim_point

	hud.queue_redraw()


func _update_shake(real_dt: float) -> void:
	shake = move_toward(shake, 0.0, 34.0 * real_dt)
	if shake > 0.05:
		world.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	else:
		world.position = Vector2.ZERO


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


# ---------------------------------------------------------------------
# 鐘舵€佸垏鎹?# ---------------------------------------------------------------------
# ---------------------------------------------------------------------
# 设置（目前只有语言）
# ---------------------------------------------------------------------
const SETTINGS_PATH := "user://settings.cfg"


func _set_lang(code: String) -> void:
	I18N.set_lang(code)
	_save_settings()
	if hud != null:
		hud.queue_redraw()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	I18N.set_lang(str(cf.get_value("ui", "lang", "zh")))


func _save_settings() -> void:
	# 无头 / 受限环境写不了 user://，直接跳过
	if DisplayServer.get_name() == "headless":
		return
	var cf := ConfigFile.new()
	cf.set_value("ui", "lang", I18N.lang)
	cf.save(SETTINGS_PATH)


func _show_title() -> void:
	_set_pause(false, false)
	_clear_all()
	state = CFG.ST_TITLE
	run_real = 0.0
	run_world = 0.0
	end_timer = 0.0
	hits_taken = 0
	Engine.time_scale = CFG.SLOW_SCALE


func start_game(diff_index: int) -> void:
	_clear_all()
	difficulty = clampi(diff_index, 0, CFG.DIFFICULTIES.size() - 1)
	hits_taken = 0
	run_real = 0.0
	run_world = 0.0
	end_timer = 0.0
	hurt_flash = 0.0
	stage = boss_stage

	_build_arena()

	player = PLAYER_SCENE.instantiate()
	entities.add_child(player)
	player.setup(CFG.DIFFICULTIES[difficulty]["hp"], character)
	if skip_drop:
		player.dropping = false
		player.drop_t = 1.0
		player.drop_h = 0.0
		player.invuln = 0.0
		player.control_enabled = true
	player.global_position = CFG.PLAYER_SPAWN
	player.control_enabled = true
	player.obstacles = obstacles
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	player.bounced.connect(_on_player_bounced)
	player.launched.connect(_on_player_launched)
	player.shield_absorbed.connect(_on_shield_absorbed)
	player.landed.connect(_on_player_landed)
	player.upgraded.connect(_on_player_upgraded)
	player.tore_at.connect(_on_player_tore)
	player.shield_broken.connect(_on_shield_broken)

	if stage == 2:
		boss = BOSS2_SCENE.instantiate()
		entities.add_child(boss)
		boss.setup(CFG.BOSS2_HP, player, difficulty)
		boss.global_position = CFG.BOSS2_HOME
	else:
		boss = BOSS_SCENE.instantiate()
		entities.add_child(boss)
		boss.setup(CFG.BOSS_HP, player, CFG.ARROWS_BY_DIFFICULTY[difficulty])
		boss.global_position = CFG.BOSS_HOME
	boss.fire.connect(_on_boss_fire)
	boss.hp_changed.connect(_on_boss_hp_changed)
	boss.defeated.connect(_on_boss_defeated)

	state = CFG.ST_PLAY
	Engine.time_scale = CFG.SLOW_SCALE
	hud.queue_redraw()


func _clear_all() -> void:
	fx.clear_all()
	for node in [entities, bullets, obstacles_root]:
		for child in node.get_children():
			node.remove_child(child)
			child.queue_free()
	obstacles.clear()
	player = null
	boss = null
	world.position = Vector2.ZERO
	shake = 0.0


# ---------------------------------------------------------------------
# 场地：用 TileMap 地图（arena.tscn），墙格自动合并成碰撞矩形
# ---------------------------------------------------------------------
## F3 调试：把地图合并出的碰撞箱交给粒子层画（粒子层在最上面）
func _refresh_debug_rects() -> void:
	if fx == null:
		return
	if debug_collision and arena != null and is_instance_valid(arena):
		fx.set_debug_rects(arena.world_rects())
	else:
		fx.set_debug_rects([])


func _build_arena() -> void:
	for child in obstacles_root.get_children():
		obstacles_root.remove_child(child)
		child.queue_free()
	obstacles.clear()

	arena = ARENA_SCENE.instantiate()
	obstacles_root.add_child(arena)
	_refresh_debug_rects()
	# 与旧接口保持一致：把整张地图当成"一个障碍物"
	obstacles.append(arena)


# ---------------------------------------------------------------------
# 瀹炰綋浜嬩欢
# ---------------------------------------------------------------------
func _on_boss_fire(origin: Vector2, dir: Vector2, speed: float, kind: int) -> void:
	sfx.play("shot", -5.0, 1.15 if kind == 3 else randf_range(0.9, 1.05))
	# 长方形快弹出膛：一点金色闪光
	if kind == 3:
		fx.ring(origin, Color(1.0, 0.84, 0.35), 8.0, 74.0, 0.24, 2.0)
		fx.burst(origin, Color(1.0, 0.84, 0.35), 9, 210.0, 2.2, 0.28)
	if bullets.get_child_count() >= CFG.BULLET_CAP:
		return
	var b = BULLET_SCENE.instantiate()
	bullets.add_child(b)
	b.obstacles = obstacles
	b.player_ref = player
	b.setup(origin, dir.normalized() * speed, kind)


func _on_player_launched(power: float) -> void:
	sfx.play("launch", -2.0, 0.9 + 0.25 * power)


func _on_player_bounced(pos: Vector2, normal: Vector2) -> void:
	sfx.play("bounce", -7.0, randf_range(0.92, 1.12))
	fx.burst(pos + normal * 10.0, CFG.COL_PLAYER, 6, 170.0, 2.2, 0.3)


func _on_shield_absorbed(kind: int, pos: Vector2) -> void:
	sfx.play("shield", -3.0, 0.95 + 0.1 * float(kind))
	var col := Color(0.55, 0.95, 0.75, 1.0)
	if kind == 1:
		col = Color(0.40, 1.0, 0.62, 1.0)
	elif kind == 2:
		col = Color(0.78, 0.98, 0.42, 1.0)
	elif kind == 3:
		col = Color(0.80, 0.55, 1.0, 1.0)
	fx.ring(pos, col, 24.0, 74.0, 0.30, 2.0)
	fx.burst(pos, col, 8, 200.0, 2.2, 0.35)


func _on_player_landed(pos: Vector2) -> void:
	add_shake(7.0)
	fx.ring(pos, CFG.COL_PLAYER, 10.0, 130.0, 0.45, 3.0)
	fx.burst(pos, CFG.COL_PLAYER, 14, 250.0, 2.6, 0.5)


func _on_player_upgraded(tier: int) -> void:
	sfx.play("upgrade", 0.0, 1.0 + 0.05 * float(tier))
	add_shake(9.0)
	var col := Color(0.35, 0.95, 0.55).lerp(Color(0.72, 0.35, 0.95),
		float(tier - 1) / float(maxi(1, CFG.BUG_MAX_TIER - 1)))
	fx.ring(player.global_position, col, 14.0, 190.0, 0.55, 3.5)
	fx.burst(player.global_position, col, 22, 320.0, 3.0, 0.6)


func _on_player_tore(pos: Vector2, normal: Vector2) -> void:
	fx.tear(pos, normal)
	fx.burst(pos, Color(1.0, 0.55, 0.85), 10, 260.0, 2.4, 0.35)
	add_shake(8.0)


func _on_shield_broken(pos: Vector2) -> void:
	sfx.play("break")
	add_shake(10.0)
	fx.ring(pos, Color(0.60, 0.98, 0.80), 26.0, 150.0, 0.35, 3.0)
	fx.burst(pos, Color(0.60, 0.98, 0.80), 20, 300.0, 2.6, 0.45)
	if player != null and is_instance_valid(player):
		var n: Vector2 = player.global_position - pos
		if n.length() > 0.1:
			fx.tear(player.global_position, n.normalized(), Color(0.60, 0.98, 0.80))


func _on_boss_hp_changed(hp: int, _max_hp: int) -> void:
	sfx.play("ram", 0.0, randf_range(0.94, 1.06))
	add_shake(15.0)
	var col_main: Color = CFG.COL_BOSS if stage == 1 else Color(0.58, 0.78, 1.0)
	var col_core: Color = CFG.COL_BOSS_CORE if stage == 1 else Color(0.90, 0.97, 1.0)
	fx.ring(boss.global_position, col_main, 44.0, 280.0, 0.5, 4.0)
	fx.burst(boss.global_position, col_main, 30, 430.0, 3.5, 0.7)
	fx.burst(boss.global_position, col_core, 14, 240.0, 2.5, 0.5)
	if hp > 0:
		fx.ring(boss.global_position, col_core, 30.0, 190.0, 0.35, 2.0)


func _on_boss_defeated() -> void:
	add_shake(22.0)
	fx.ring(boss.global_position, Color(0.58, 0.78, 1.0), 50.0, 520.0, 0.9, 6.0)
	fx.burst(boss.global_position, Color(0.58, 0.78, 1.0), 60, 560.0, 4.0, 1.0)
	for b in bullets.get_children():
		fx.burst(b.global_position, CFG.COL_BULLET, 2, 90.0, 2.0, 0.4)
		b.queue_free()

	if stage == 1:
		fx.burst(boss.global_position, CFG.COL_BOSS, 40, 420.0, 3.5, 0.9)
	else:
		fx.burst(boss.global_position, Color(0.58, 0.78, 1.0), 30, 460.0, 3.0, 0.9)

	# 每局只有一只 Boss，打掉就结算
	sfx.play("break", 2.0, 0.8)
	sfx.play("win", -1.0)
	state = CFG.ST_WIN
	end_timer = 0.0
	if player != null and is_instance_valid(player):
		player.control_enabled = false
		player.invuln = 999.0
		player.reset_to_idle()


func _on_player_damaged(_hp_left: float) -> void:
	sfx.play("hurt")
	hits_taken += 1
	hurt_flash = 1.0
	add_shake(11.0)
	fx.ring(player.global_position, CFG.COL_PLAYER, 18.0, 170.0, 0.5, 3.5)
	fx.burst(player.global_position, CFG.COL_PLAYER, 22, 330.0, 3.0, 0.6)
	fx.burst(player.global_position, Color(1, 1, 1), 8, 180.0, 2.0, 0.35)
	# 受击清弹：否则无敌帧一结束就会被第二发打死
	_clear_bullets_near(player.global_position, 150.0)


func _on_player_died() -> void:
	# 死亡：先来一记炸裂般碎裂音（+4dB），再垫一层失败的底
	sfx.play("death", 4.0)
	sfx.play("crack" if (player != null and is_instance_valid(player) and player.cracked) else "hurt", 0.0, 0.85)
	sfx.play("lose", -7.0, 0.95)
	state = CFG.ST_LOSE
	end_timer = 0.0
	death_cause = "cracked" if (player != null and is_instance_valid(player) and player.cracked) else "hit"
	add_shake(18.0)
	if player != null and is_instance_valid(player):
		var was_cracked: bool = player.cracked
		player.control_enabled = false
		player.reset_to_idle()
		if was_cracked:
			player.crack_t = 1.0
			fx.burst(player.global_position, Color(0.80, 0.88, 0.96), 34, 300.0, 3.0, 0.8)
			fx.ring(player.global_position, Color(1.0, 0.36, 0.30), 10.0, 240.0, 0.6, 4.0)
		else:
			fx.ring(player.global_position, CFG.COL_PLAYER, 16.0, 300.0, 0.8, 5.0)
			fx.burst(player.global_position, CFG.COL_PLAYER, 46, 460.0, 4.0, 0.9)
			fx.burst(player.global_position, Color(1, 1, 1), 18, 260.0, 3.0, 0.5)


func _clear_bullets_near(pos: Vector2, radius: float) -> void:
	for b in bullets.get_children():
		if b.global_position.distance_to(pos) <= radius:
			fx.burst(b.global_position, CFG.COL_BULLET, 3, 120.0, 2.0, 0.35)
			b.queue_free()


# ---------------------------------------------------------------------
# 杈撳叆
# ---------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_click(get_global_mouse_position())
		return

	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_1:
				if state == CFG.ST_TITLE:
					difficulty = 0
					hud.queue_redraw()
			KEY_2:
				if state == CFG.ST_TITLE:
					difficulty = 1
					hud.queue_redraw()
			KEY_3:
				if state == CFG.ST_TITLE:
					difficulty = 2
					hud.queue_redraw()
			KEY_SPACE:
				if state == CFG.ST_TITLE:
					start_game(difficulty)
				elif state == CFG.ST_PLAY:
					if not paused:
						_set_pause(true, false)
					elif resume_count <= 0.0:
						resume_count = 3.0
			KEY_ENTER:
				if state == CFG.ST_TITLE:
					start_game(difficulty)
			KEY_R:
				if state == CFG.ST_PLAY or state == CFG.ST_WIN or state == CFG.ST_LOSE:
					start_game(difficulty)
			KEY_ESCAPE:
				if state != CFG.ST_TITLE:
					_show_title()
			KEY_Q:
				if state == CFG.ST_TITLE:
					character = maxi(0, character - 1)
			KEY_E:
				if state == CFG.ST_TITLE:
					character = mini(CFG.CHARS.size() - 1, character + 1)
			KEY_TAB:
				if state == CFG.ST_TITLE:
					boss_stage = 3 - boss_stage
			KEY_L:
				# 中 / 英 切换（标题页与战斗中都能用）
				_set_lang(I18N.next_lang())
			KEY_F3:
				# 调试：把地图合并出来的碰撞箱画出来，方便对照自己涂的墙
				debug_collision = not debug_collision
				_refresh_debug_rects()
				queue_redraw()


func _on_click(pos: Vector2) -> void:
	if paused:
		if resume_count <= 0.0:
			resume_count = 3.0
			sfx.play("ui", -3.0, 0.9)
		return
	sfx.play("ui", -6.0)
	match state:
		CFG.ST_TITLE:
			var c: int = hud.char_hit(pos)
			if c >= 0:
				character = c
				return
			var lsel: int = hud.lang_hit(pos)
			if lsel >= 0:
				_set_lang(I18N.LANGS[lsel])
				return
			var bsel: int = hud.boss_hit(pos)
			if bsel >= 0:
				boss_stage = bsel + 1
				return
			var idx: int = hud.diff_hit(pos)
			if idx >= 0:
				start_game(idx)
		CFG.ST_WIN, CFG.ST_LOSE:
			if end_timer < 0.25:
				return
			var action: String = hud.panel_hit(pos)
			if action == "retry":
				start_game(difficulty)
			elif action == "title":
				_show_title()


# ---------------------------------------------------------------------
# 场景底板（静态，只画一次）
# ---------------------------------------------------------------------
func _draw() -> void:
	var a := CFG.ARENA
	draw_rect(a, Color(0.043, 0.063, 0.094), true)

	# 缃戞牸
	var step := 64.0
	var x := a.position.x
	while x <= a.end.x:
		draw_line(Vector2(x, a.position.y), Vector2(x, a.end.y), Color(CFG.COL_GRID, 0.20), 1.0)
		x += step
	var y := a.position.y
	while y <= a.end.y:
		draw_line(Vector2(a.position.x, y), Vector2(a.end.x, y), Color(CFG.COL_GRID, 0.20), 1.0)
		y += step

	# 涓績鍗佸瓧
	var c := a.get_center()
	draw_line(c - Vector2(18, 0), c + Vector2(18, 0), Color(CFG.COL_ACCENT, 0.10), 1.0)
	draw_line(c - Vector2(0, 18), c + Vector2(0, 18), Color(CFG.COL_ACCENT, 0.10), 1.0)

	# 杈规 + 鍥涜
	draw_rect(a, Color(CFG.COL_ACCENT, 0.14), false, 1.0)
	var L := 34.0
	var corners := [
		[a.position, Vector2(1, 1)],
		[Vector2(a.end.x, a.position.y), Vector2(-1, 1)],
		[a.position + Vector2(0, a.size.y), Vector2(1, -1)],
		[a.end, Vector2(-1, -1)],
	]
	for cdata in corners:
		var p: Vector2 = cdata[0]
		var d: Vector2 = cdata[1]
		draw_line(p, p + Vector2(L * d.x, 0), Color(CFG.COL_ACCENT, 0.55), 2.0)
		draw_line(p, p + Vector2(0, L * d.y), Color(CFG.COL_ACCENT, 0.55), 2.0)

	# F3 调试：把"可活动区"的边界也标出来，和地图碰撞箱对照
	if debug_collision:
		draw_rect(a, Color(0.35, 0.95, 1.0, 0.85), false, 2.0)


# ---------------------------------------------------------------------
# 开发用入口：
#   --shot=title|play|fast|win|lose|phase3|windup   自动截图后退出
#   --selftest                                       机制自检，失败返回非零退出码
# ---------------------------------------------------------------------
func _run_cmdline() -> void:
	var shot := ""
	var want_test := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a == "--selftest":
			want_test = true

	if want_test:
		_run_selftest()
		return
	if shot == "":
		return

	demo = true
	skip_drop = true
	await get_tree().process_frame

	match shot:
		"title":
			_show_title()
		"title_zh":
			I18N.set_lang("zh")
			_show_title()
		"title_en":
			I18N.set_lang("en")
			_show_title()
		"intro":
			start_game(1)
		"drop":
			skip_drop = false
			start_game(1)
		"boss2":
			boss_stage = 2
			start_game(1)
			_prep_boss2_scene()
		"resume":
			start_game(1)
			_prep_demo_scene("play", 3)
			_set_pause(true, true)
			resume_count = 2.35
		"stacks":
			character = 0
			start_game(1)
			_prep_demo_scene("play", 3)
			player.speed_stacks = 12
		"pause":
			start_game(1)
			_prep_demo_scene("play", 3)
			_set_pause(true, true)
		"rail":
			start_game(1)
			_prep_demo_scene("play", 3)
			_on_boss_fire(Vector2(430.0, 300.0), Vector2(1.0, 0.55).normalized(), 300.0, 3)
			_on_boss_fire(Vector2(880.0, 620.0), Vector2(-0.85, -0.5).normalized(), 300.0, 3)
		"collision":
			start_game(1)
			debug_collision = true
			_refresh_debug_rects()
			_prep_demo_scene("play", 3)
		"crack", "lose2":
			character = 0
			start_game(1)
			_prep_demo_scene("play", 3)
			player.control_enabled = false
			player.reset_to_idle()
			player.charges = 0
			player.crack_t = 0.62 if shot == "crack" else 1.0
			if shot == "lose2":
				player.alive = false
				player.cracked = true
				_on_player_died()
				run_real = 36.7
				run_world = 12.2
				hits_taken = 2
		"play", "fast", "win", "lose", "phase3", "windup", "shield", "fanwind", "bug":
			character = 1 if shot == "shield" else (2 if shot == "bug" else 0)
			start_game(1)
			_prep_demo_scene(shot, 1 if shot == "phase3" else 3)
			if shot == "win":
				stage = 2
				_on_boss_defeated()
				run_real = 71.4
				run_world = 23.8
				hits_taken = 2
			elif shot == "lose":
				player.hp = 0
				player.alive = false
				_on_player_died()
				run_real = 48.2
				run_world = 16.0
				hits_taken = 3

	var frames := 24
	if shot == "win" or shot == "lose" or shot == "lose2":
		frames = 90
	elif shot == "phase3":
		frames = 150
	elif shot == "crack":
		frames = 4
	elif shot == "drop":
		frames = 13
	for i in frames:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://shots/%s.png" % shot
	var err := img.save_png(path)
	print("SHOT %s -> %s (err %d)" % [shot, path, err])
	get_tree().quit()


func _prep_boss2_scene() -> void:
	boss.intro = 0.0
	boss.active = true
	boss.hp = 5
	player.global_position = Vector2(642.0, 566.0)
	player.debug_aim_at(Vector2(642.0, 566.0), Vector2(642.0, 566.0) + Vector2(96.0, -150.0))
	demo_mouse = player.aim_point
	# 打掉一块板的一层耐久，顺便展示板碎对比
	if boss.plates.size() > 0 and is_instance_valid(boss.plates[0]):
		boss.plates[0].hp = 1
	boss._begin_fan()
	boss.fan_windup = 0.55


func _prep_demo_scene(kind: String, boss_hp: int = 3) -> void:
	if player == null or boss == null:
		return
	boss.hp = boss_hp
	boss.intro = 0.0
	boss.active = true
	boss.ring_t = 0.55
	player.hp = 2
	hits_taken = 1
	run_real = 9.0
	run_world = 3.1
	# 截图不需要空投过场
	player.dropping = false
	player.drop_h = 0.0
	player.drop_t = 1.0
	player.invuln = 0.0

	if kind == "fly":
		player.global_position = Vector2(520.0, 566.0)
		player.debug_launch(Vector2(0.72, -0.69), 880.0)
		demo_mouse = player.global_position + Vector2(0.72, -0.69) * 210.0
	elif kind == "shield":
		player.global_position = Vector2(620.0, 545.0)
		player.debug_aim_at(Vector2(620.0, 545.0), Vector2(620.0, 545.0) + Vector2(120.0, -120.0))
		player.fan_lock = Vector2(0.72, -0.69)
		player.shield_hold = true
		player.open_shield()
		player.shield_time = 0.33
		player.shield_charge = 1.05
		demo_mouse = player.global_position + Vector2(0.72, -0.69) * 190.0
		return
	elif kind == "bug":
		player.global_position = Vector2(642.0, 540.0)
		player.debug_aim_at(Vector2(642.0, 540.0), Vector2(642.0, 540.0) + Vector2(110.0, -140.0))
		player.tier = 2
		player.tier_hits = 3
		demo_mouse = player.aim_point
		return
	elif kind == "fanwind":
		player.global_position = Vector2(642.0, 566.0)
		player.debug_aim_at(Vector2(642.0, 566.0), Vector2(642.0, 566.0) + Vector2(-110.0, -150.0))
		demo_mouse = player.aim_point
		boss._begin_fan_windup(1)
		boss.fan_windup = 0.90
		return
	elif kind == "windup":
		# 预警截图：让 1.5 秒的蓄力走到大约 77%，弹道线拉到 250px 左右
		player.global_position = Vector2(642.0, 566.0)
		player.debug_aim_at(Vector2(642.0, 566.0), Vector2(642.0, 566.0) + Vector2(-120.0, -150.0))
		demo_mouse = player.aim_point
		boss._begin_ring_windup(1)
		boss.windup = 0.75
		return
	else:
		player.global_position = Vector2(642.0, 520.0)
		player.debug_aim_at(Vector2(642.0, 520.0), Vector2(642.0, 520.0) + Vector2(150.0, -126.0))
		demo_mouse = player.aim_point

	# 场上的弹幕（用阶段 1 的真实密度，方便看画面）
	for i in 9:
		var ang := TAU * float(i) / 9.0
		_on_boss_fire(boss.global_position + Vector2.from_angle(ang) * 88.0,
			Vector2.from_angle(ang + 0.4), 118.0, 0)
	for i in 4:
		var ang2 := TAU * float(i) / 4.0 + 0.35
		_on_boss_fire(Vector2(642.0, 420.0) + Vector2.from_angle(ang2) * 200.0,
			Vector2.from_angle(ang2), 126.0, 1)



# ---------------------------------------------------------------------
# 机制自检（实现在 selftest.gd）
# ---------------------------------------------------------------------
var _selftest = null


func _run_selftest() -> void:
	_selftest = SELF_TEST.new(self)
	_selftest.run()
