extends Area2D
## Boss2「壁」· 6 滴血。
##
## 三块护盾板绕着它转（每块 2 点耐久），撞上去只会掉板的耐久，不会掉本体血。
## 招式：
##   直线快弹 —— 先亮 0.55 秒瞄准线，再打出一发 560 px/s 的长方形弹
##   扇形弹幕 —— 1 秒黄色扇形预警后打出 5 发（简单）/6（普通）/7（困难）
##   半血、三分之一血时各额外爆发 3 轮扇形
## 撞到玩家：弹开 + 减速 65% + 3 秒极速上限 80%

signal fire(origin: Vector2, dir: Vector2, speed: float, kind: int)
signal hp_changed(hp: int, max_hp: int)
signal plates_changed(alive: int)
signal defeated

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）
const Skins := preload("res://scripts/skins.gd")   # 手绘素材管线
const PLATE_SCRIPT := preload("res://scripts/plate.gd")

var hp := CFG.BOSS2_HP             # 当前血量
var max_hp := CFG.BOSS2_HP         # 血量上限（HUD 血条格数）
var body_radius := CFG.BOSS2_RADIUS # 本体半径（px），撞击判定用
var active := false                # 是否登场完毕、开始出招
var dying := false                 # 是否在播死亡缩小
var intro := CFG.BOSS2_INTRO       # 登场剩余时间（现实秒）
var invuln := 0.0                  # 受击无敌剩余（战场秒）
var flash := 0.0                   # 受击白闪（0~1）
var t := 0.0                       # 累计时间（漂移 / 旋转 / 动画）
var body_scale := 1.0              # 整体缩放（死亡时缩到 0）
var knock := Vector2.ZERO          # 被撞后的位移偏移
var target: Node2D = null          # 追踪目标（主角）

# ---- 环绕圣盾 ----
var plates: Array = []             # 三块圣盾节点
var plate_angle := 0.0             # 三块盾的整体旋转角（rad）
var plate_radius := CFG.BOSS2_PLATE_RADIUS  # 盾的旋转轨道半径（px）

# ---- 直线快弹 ----
var rail_t := 2.6                  # 距离下一次开火的倒计时（战场秒）
var aim_charge := 0.0              # 瞄准线剩余时间（>0 表示正在瞄准）
var aim_dir := Vector2.DOWN        # 瞄准线方向（持续跟踪主角）

# ---- 扇形弹幕 ----
var fan_t := 3.4                   # 下一次扇形的倒计时（战场秒）
var fan_windup := 0.0              # 扇形预警剩余（现实秒，>0 时画黄扇）
var fan_dir := Vector2.DOWN        # 扇形中心方向
var fan_half := 0.4                # 扇形半角（rad）
var fan_shots: Array = []          # 预警期间锁定的每一发方向

# ---- 阶段爆发（半血 / 三分之一血各连打 3 轮）----
var burst_left := 0                # 还剩几轮要打
var burst_t := 0.0                 # 下一轮的间隔倒计时
var phase_mark := 0                # 已经触发到第几个阶段（0/1/2）
var difficulty := 1                # 难度下标（决定扇形多发几枚）


func _ready() -> void:
	add_to_group("boss")
	add_to_group("boss2")
	z_index = 3
	queue_redraw()


func setup(hit_points: int, target_node: Node2D, diff: int = 1) -> void:
	max_hp = hit_points
	hp = hit_points
	target = target_node
	difficulty = clampi(diff, 0, 2)
	active = false
	intro = CFG.BOSS2_INTRO
	rail_t = 2.6
	fan_t = 3.4
	phase_mark = 0
	_build_plates()


func _build_plates() -> void:
	for p in plates:
		if is_instance_valid(p):
			p.queue_free()
	plates.clear()
	for i in CFG.BOSS2_PLATES:
		var p = PLATE_SCRIPT.new()
		add_child(p)
		p.boss = self
		p.body_radius = CFG.BOSS2_PLATE_R
		var a := TAU * float(i) / float(CFG.BOSS2_PLATES)
		p.position = Vector2.from_angle(a) * plate_radius
		p.facing = Vector2.from_angle(a)
		plates.append(p)


func alive_plates() -> int:
	var n := 0
	for p in plates:
		if is_instance_valid(p) and p.active:
			n += 1
	return n


func on_plate_broken() -> void:
	flash = maxf(flash, 0.5)
	plates_changed.emit(alive_plates())


func is_vulnerable() -> bool:
	return active and invuln <= 0.0 and hp > 0


# ---------------------------------------------------------------------
# 行为
# ---------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta * 3.0)
	queue_redraw()

	if dying:
		body_scale = move_toward(body_scale, 0.0, delta * 1.4)
		if body_scale <= 0.01:
			visible = false
		return

	if intro > 0.0:
		intro = maxf(0.0, intro - delta)
		_drift(delta, 0.45)
		if intro <= 0.0:
			active = true
		return

	_drift(delta, 1.0)
	invuln = maxf(0.0, invuln - delta)
	_rotate_plates(delta)

	if not active:
		return

	_tick_attacks(delta)
	_check_phase()


func _drift(delta: float, rate: float) -> void:
	knock = knock.lerp(Vector2.ZERO, minf(1.0, delta * 6.0))
	var k: float = CFG.BOSS2_DRIFT
	var base := CFG.BOSS2_HOME + Vector2(
		sin(t * 0.55 * k) * 232.0 * k,
		sin(t * 0.83 * k + 1.1) * 74.0 * k
	) + knock
	global_position = global_position.lerp(base, clampf(delta * 4.0 * rate, 0.0, 1.0))


func _rotate_plates(delta: float) -> void:
	var spin := CFG.BOSS2_PLATE_SPIN
	if hp <= 2:
		spin *= 1.35
	elif hp <= 3:
		spin *= 1.15
	plate_angle += spin * delta
	for i in plates.size():
		var p = plates[i]
		if not is_instance_valid(p):
			continue
		var a := plate_angle + TAU * float(i) / float(plates.size())
		var off := Vector2.from_angle(a) * plate_radius
		p.position = off
		p.facing = off.normalized()


func _tick_attacks(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.02)

	# ---- 直线快弹：先瞄准，再开火 ----
	if aim_charge > 0.0:
		aim_charge -= delta
		if target != null and is_instance_valid(target):
			var to := target.global_position - global_position
			if to.length() > 1.0:
				aim_dir = to.normalized()
		if aim_charge <= 0.0:
			_shoot(aim_dir, CFG.BOSS2_RAIL_SPEED, 3)
			rail_t = CFG.BOSS2_RAIL_INTERVAL
	else:
		rail_t -= delta
		if rail_t <= 0.0 and fan_windup <= 0.0:
			aim_charge = CFG.BOSS2_AIM_TIME

	# ---- 扇形 ----
	if fan_windup > 0.0:
		fan_windup -= real_dt
		if fan_windup <= 0.0:
			fan_windup = 0.0
			_release_fan()
	else:
		fan_t -= delta
		if fan_t <= 0.0 and burst_left <= 0:
			fan_t = CFG.BOSS2_FAN_INTERVAL
			_begin_fan()

	# ---- 阶段爆发 ----
	if burst_left > 0:
		burst_t -= delta
		if burst_t <= 0.0:
			burst_left -= 1
			burst_t = 0.22
			_begin_fan()
			fan_windup = minf(fan_windup, 0.25)


func _check_phase() -> void:
	if phase_mark < 1 and hp <= 3:
		phase_mark = 1
		_start_burst()
	elif phase_mark < 2 and hp <= 2:
		phase_mark = 2
		_start_burst()


func _start_burst() -> void:
	burst_left = 3
	burst_t = 0.05


# ---------------------------------------------------------------------
# 弹幕
# ---------------------------------------------------------------------
func _begin_fan() -> void:
	var to := Vector2.DOWN
	if target != null and is_instance_valid(target):
		var d := target.global_position - global_position
		if d.length() > 1.0:
			to = d.normalized()
	var count := CFG.BOSS2_FAN_BASE + int(_fan_bonus())
	fan_dir = to
	fan_half = float(count - 1) * CFG.BOSS2_FAN_SPREAD * 0.5 + 0.12
	fan_shots.clear()
	for i in count:
		var off := (float(i) - float(count - 1) * 0.5) * CFG.BOSS2_FAN_SPREAD
		fan_shots.append(to.rotated(off))
	fan_windup = CFG.BOSS2_FAN_WINDUP


func _fan_bonus() -> int:
	return [0, 1, 2][clampi(difficulty, 0, 2)]


func _release_fan() -> void:
	for d in fan_shots:
		_shoot(d, CFG.BOSS2_FAN_SPEED, 1)
	fan_shots.clear()
	flash = maxf(flash, 0.55)


func _shoot(dir: Vector2, speed: float, kind: int) -> void:
	var d := dir.normalized()
	fire.emit(global_position + d * (body_radius - 6.0), d, speed, kind)


# ---------------------------------------------------------------------
# 受击
# ---------------------------------------------------------------------
func try_ram() -> bool:
	if not is_vulnerable():
		return false
	hp -= 1
	invuln = CFG.BOSS2_IFRAME
	flash = 1.0
	if target != null and is_instance_valid(target):
		knock = (global_position - target.global_position).normalized() * 40.0
	emit_signal("hp_changed", hp, max_hp)
	if hp <= 0:
		active = false
		dying = true
		for p in plates:
			if is_instance_valid(p):
				p.queue_free()
		plates.clear()
		set_deferred("monitorable", false)
		emit_signal("defeated")
	return true


# ---------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------
func _draw() -> void:
	var r := body_radius * body_scale
	if r < 0.5:
		return

	# 扇形预警
	if fan_windup > 0.0 and not fan_shots.is_empty():
		var prog := 1.0 - fan_windup / maxf(CFG.BOSS2_FAN_WINDUP, 0.001)
		var rad := lerpf(110.0, 470.0, prog)
		var seg := 16
		var poly := PackedVector2Array()
		var arc := PackedVector2Array()
		poly.append(Vector2.ZERO)
		for i in seg + 1:
			var ang := fan_dir.angle() - fan_half + 2.0 * fan_half * float(i) / float(seg)
			var p := Vector2.from_angle(ang) * rad
			poly.append(p)
			arc.append(p)
		draw_colored_polygon(poly, Color(1.0, 0.90, 0.30, 0.14 + 0.16 * prog))
		draw_polyline(arc, Color(1.0, 0.88, 0.32, 0.35 + 0.45 * prog), 2.0, true)
		draw_line(Vector2.ZERO, arc[0], Color(1.0, 0.88, 0.32, 0.30), 1.2, true)
		draw_line(Vector2.ZERO, arc[arc.size() - 1], Color(1.0, 0.88, 0.32, 0.30), 1.2, true)

	# 直线快弹的瞄准线
	if aim_charge > 0.0:
		var k := 1.0 - aim_charge / maxf(CFG.BOSS2_AIM_TIME, 0.001)
		var end := aim_dir * 900.0
		draw_line(Vector2.ZERO, end, Color(0.85, 0.94, 1.0, 0.10 + 0.35 * k), 1.5 + 2.0 * k, true)
		draw_circle(aim_dir * (r + 6.0), 4.0 + 3.0 * k, Color(1, 1, 1, 0.5 * k))

	# 外圈光环
	for i in 5:
		draw_circle(Vector2.ZERO, r * (1.55 - 0.13 * i), Color(0.45, 0.66, 1.0, 0.035))

	# 本体：六边形装甲（有手绘素材就用图片，装饰照样叠在上面）
	var hex := PackedVector2Array()
	for i in 6:
		hex.append(Vector2.from_angle(TAU * float(i) / 6.0 + t * 0.25) * r)
	if not Skins.blit(self, "boss2_body", Rect2(-r, -r, r * 2.0, r * 2.0), 0.0):
		draw_colored_polygon(hex, Color(0.11, 0.16, 0.25))
		var inner := PackedVector2Array()
		for p in hex:
			inner.append(p * 0.66)
		draw_colored_polygon(inner, Color(0.18, 0.26, 0.38))
		var edge := hex.duplicate()
		edge.append(hex[0])
		draw_polyline(edge, Color(0.58, 0.78, 1.0, 0.85), 2.5, true)

	# 核心
	draw_circle(Vector2.ZERO, r * 0.34, Color(0.70, 0.88, 1.0, 0.85))
	draw_circle(Vector2.ZERO, r * 0.20, Color(0.95, 1.0, 1.0, 0.95))

	# 神圣装饰：外环金线 + 顶点金钉 + 核心十字
	var halo := t * 0.42
	for i in 3:
		var a0h := halo + TAU * float(i) / 3.0
		draw_arc(Vector2.ZERO, r * 1.26, a0h, a0h + 0.85, 20,
			Color(1.0, 0.85, 0.48, 0.30), 2.0, true)
	for pnt in hex:
		draw_circle(pnt, 2.2, Color(1.0, 0.88, 0.55, 0.85))
	draw_line(Vector2(0.0, -r * 0.24), Vector2(0.0, r * 0.24), Color(1.0, 0.92, 0.66, 0.85), 2.0, true)
	draw_line(Vector2(-r * 0.15, -r * 0.05), Vector2(r * 0.15, -r * 0.05),
		Color(1.0, 0.92, 0.66, 0.85), 2.0, true)

	# 剩余血量：内圈弧
	var spin := t * 0.9
	for i in hp:
		var a0 := spin + TAU * float(i) / float(max_hp)
		draw_arc(Vector2.ZERO, r * 0.86, a0, a0 + 0.7, 20,
			Color(0.75, 0.92, 1.0, 0.75), 3.0, true)

	# 受击白闪
	if flash > 0.0 and not dying:
		draw_circle(Vector2.ZERO, r * 1.05, Color(1, 1, 1, 0.25 * flash))
