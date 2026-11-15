extends Area2D
## Boss「环」· 3 滴血。
##
## 每次被撞掉 1 点血，同时升级一个阶段：
##   阶段 1（3 血）：环形弹幕 + 三连瞄准
##   阶段 2（2 血）：加上螺旋弹流
##   阶段 3（1 血）：全部加速、加密
## 受击瞬间会炸出一圈反向弹，逼玩家撞完立刻撤离。

signal fire(origin: Vector2, dir: Vector2, speed: float, kind: int)
signal hp_changed(hp: int, max_hp: int)
signal defeated

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）
const Skins := preload("res://scripts/skins.gd")   # 手绘素材管线

var hp := 3                        # 当前血量（撞击次数）
var max_hp := 3                    # 血量上限（HUD 血条格数）
var active := false                # 是否已登场完毕、开始出招
var dying := false                 # 是否正在播放死亡缩小动画
var intro := CFG.BOSS_INTRO        # 登场剩余时间（现实秒），期间不出招
var invuln := 0.0                  # 受击无敌剩余（战场秒）
var stagger := 0.0                 # 受击硬直剩余（战场秒），暂停出招
var flash := 0.0                   # 受击白闪（0~1）
var t := 0.0                       # 累计时间（漂移、旋转、呼吸都靠它）
var body_scale := 1.0              # 整体缩放（死亡时缩到 0）

var target: Node2D = null          # 追踪目标（主角）
var knock := Vector2.ZERO          # 被撞后的位置偏移（会自己回弹）
var arrow_flash := 0.0             # 反击箭头的高亮（0~1）
var arrow_count := 4               # 反击箭头数量（由难度写入）

# 三种招式的冷却计时（战场秒）
var ring_t := 3.6                  # 下一次环形弹幕的倒计时
var fan_t := 2.4                   # 下一次扇形弹幕的倒计时
var spiral_t := 0.0                # 下一次螺旋弹的倒计时
var spiral_angle := 0.0            # 螺旋当前角度（rad）

# 圆形弹幕的预警：先把每条弹道算好、画出来，1.5 秒后才真的发射
var windup := 0.0                  # 预警剩余时间（现实秒）
var windup_total := 1.0            # 预警总时长（算进度用）
var windup_shots: Array = []       # 预警期间锁定的发射方向列表

# 扇形弹幕的预警：1 秒前先画出黄色扇形
var fan_windup := 0.0              # 扇形预警剩余时间（现实秒）
var fan_windup_dir := Vector2.DOWN # 扇形中心方向
var fan_windup_half := 0.32        # 扇形半角（rad）
var fan_windup_shots: Array = []   # 锁定的每一发方向


func _ready() -> void:
	add_to_group("boss")
	z_index = 3
	queue_redraw()


func setup(hit_points: int, target_node: Node2D, arrows: int = 4) -> void:
	max_hp = hit_points
	hp = hit_points
	target = target_node
	arrow_count = clampi(arrows, 3, 6)
	active = false
	intro = CFG.BOSS_INTRO
	ring_t = 3.6
	fan_t = 2.4
	windup = 0.0
	fan_windup = 0.0
	windup_shots.clear()
	fan_windup_shots.clear()


func phase() -> int:
	return clampi(4 - hp, 1, 3)


func is_vulnerable() -> bool:
	return active and invuln <= 0.0 and hp > 0


# ---------------------------------------------------------------------
# 行为
# ---------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta * 3.0)
	arrow_flash = maxf(0.0, arrow_flash - delta * 2.2)
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

	# 预警计时按现实时间推进（在硬直判断之前，不能被受击卡住）
	_update_windup(delta)

	invuln = maxf(0.0, invuln - delta)
	stagger = maxf(0.0, stagger - delta)
	if stagger > 0.0:
		return

	var ph := phase()
	ring_t -= delta
	fan_t -= delta

	if ring_t <= 0.0 and windup <= 0.0:
		ring_t = [0.0, 3.60, 3.10, 2.60][ph]
		_begin_ring_windup(ph)

	if fan_t <= 0.0 and fan_windup <= 0.0:
		fan_t = [0.0, 2.90, 2.40, 2.00][ph]
		_begin_fan_windup(ph)

	if ph >= 2:
		spiral_t -= delta
		if spiral_t <= 0.0:
			spiral_t = 0.30 if ph == 2 else 0.24
			_fire_spiral(ph)


func _drift(delta: float, rate: float) -> void:
	knock = knock.lerp(Vector2.ZERO, minf(1.0, delta * 6.0))
	var base := CFG.BOSS_HOME + Vector2(
		sin(t * 0.55) * 232.0,
		sin(t * 0.83 + 1.1) * 74.0
	) + knock
	global_position = global_position.lerp(base, clampf(delta * 4.0 * rate, 0.0, 1.0))


# ---------------------------------------------------------------------
# 弹幕
# ---------------------------------------------------------------------
func _begin_ring_windup(ph: int) -> void:
	var count: int = [0, 9, 12, 15][ph]
	var speed: float = [0.0, 124.0, 134.0, 146.0][ph]
	var spin := t * 0.9
	windup_shots.clear()
	for i in count:
		var a := TAU * float(i) / float(count) + spin
		windup_shots.append({"dir": Vector2.from_angle(a), "speed": speed})
	windup = CFG.BOSS_WINDUP
	windup_total = CFG.BOSS_WINDUP


## 预警按现实时间走：不管当前是 0.2× 还是 1.0×，都是实打实的固定秒数
func _update_windup(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.02)
	if windup > 0.0:
		windup -= real_dt
		if windup <= 0.0:
			windup = 0.0
			_release_windup()
	if fan_windup > 0.0:
		fan_windup -= real_dt
		if fan_windup <= 0.0:
			fan_windup = 0.0
			_release_fan_windup()


func _release_windup() -> void:
	for s in windup_shots:
		_shoot(s["dir"], s["speed"], 0)
	windup_shots.clear()
	flash = maxf(flash, 0.85)


## 第 i 个反击箭头的朝向。整体匀速旋转 + 各自小幅摆动，
## 所以四个箭头一直在变朝向，而且不会永远保持十字。
func arrow_angle(i: int) -> float:
	return t * CFG.BOSS_ARROW_SPIN \
		+ TAU * float(i) / float(arrow_count) \
		+ sin(t * 0.9 + float(i) * 1.7) * CFG.BOSS_ARROW_WOBBLE


## 受击反击：只朝当前箭头指的方向各打一发
func _fire_counter() -> void:
	for i in arrow_count:
		_shoot(Vector2.from_angle(arrow_angle(i)), CFG.BOSS_COUNTER_SPEED, 2, 92.0)
	arrow_flash = 1.0


## 扇形预警：先把瞄准方向锁死，画出黄色扇形，1 秒后沿原方向打出去
func _begin_fan_windup(ph: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var to := (target.global_position - global_position).normalized()
	if to == Vector2.ZERO:
		to = Vector2.DOWN
	var count: int = [0, 3, 4, 5][ph]
	var spread: float = [0.0, 0.26, 0.24, 0.22][ph]
	var speed: float = [0.0, 195.0, 205.0, 220.0][ph]

	fan_windup_dir = to
	fan_windup_half = float(count - 1) * spread * 0.5 + 0.10
	fan_windup_shots.clear()
	for i in count:
		var off := (float(i) - float(count - 1) * 0.5) * spread
		fan_windup_shots.append({"dir": to.rotated(off), "speed": speed})
	fan_windup = CFG.BOSS_FAN_WINDUP


func _release_fan_windup() -> void:
	for s in fan_windup_shots:
		_shoot(s["dir"], s["speed"], 1)
	fan_windup_shots.clear()
	flash = maxf(flash, 0.55)


func _fire_spiral(ph: int) -> void:
	var arms := 2 if ph >= 3 else 1
	for k in arms:
		var a := spiral_angle + TAU * float(k) / float(arms)
		_shoot(Vector2.from_angle(a), 148.0, 0)
	spiral_angle += 0.46


func _shoot(dir: Vector2, speed: float, kind: int, offset: float = -1.0) -> void:
	var d := dir.normalized()
	if offset < 0.0:
		offset = CFG.BOSS_RADIUS - 8.0
	fire.emit(global_position + d * offset, d, speed, kind)


# ---------------------------------------------------------------------
# 受击
# ---------------------------------------------------------------------
func try_ram() -> bool:
	if not is_vulnerable():
		return false

	hp -= 1
	invuln = CFG.BOSS_IFRAME
	stagger = CFG.BOSS_STAGGER
	flash = 1.0
	if target != null and is_instance_valid(target):
		knock = (global_position - target.global_position).normalized() * 46.0

	# 四向反击：只朝四个箭头当前指的方向各打一发，不再是无死角爆环
	_fire_counter()

	emit_signal("hp_changed", hp, max_hp)
	if hp <= 0:
		active = false
		dying = true
		set_deferred("monitorable", false)
		emit_signal("defeated")
	return true


# ---------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------
func _draw() -> void:
	var r := CFG.BOSS_RADIUS * body_scale
	if r < 0.5:
		return
	var ph := phase()
	var dim := 1.0 if not dying else 0.6
	var core := CFG.COL_BOSS.lerp(CFG.COL_BOSS_CORE, 0.0)

	# 圆形弹幕预警：1.5 秒前把每一条弹道画出来，线走完就发弹
	if windup > 0.0 and not windup_shots.is_empty():
		var prog := 1.0 - windup / maxf(windup_total, 0.001)
		var reach := lerpf(64.0, 330.0, prog)
		var alpha := 0.16 + 0.52 * prog
		var spd: float = windup_shots[0]["speed"]
		# 1 秒后这些弹会到达的位置
		draw_arc(Vector2.ZERO, r + spd, 0.0, TAU, 80,
			Color(1.0, 0.30, 0.34, 0.07 + 0.09 * prog), 1.5, true)
		for s in windup_shots:
			var d: Vector2 = s["dir"]
			var from := d * r * 1.22
			var to := d * (r + reach)
			_dashed_line(from, to, Color(1.0, 0.34, 0.38, alpha), 2.0)
			draw_circle(to, 2.5 + 2.5 * prog, Color(1.0, 0.42, 0.46, alpha))

	# 扇形预警：黄色扇形区域，1 秒内逐渐变亮变长
	if fan_windup > 0.0:
		var fprog := 1.0 - fan_windup / maxf(CFG.BOSS_FAN_WINDUP, 0.001)
		var frad := lerpf(110.0, 470.0, fprog)
		var fseg := 16
		var fpoly := PackedVector2Array()
		var farc := PackedVector2Array()
		fpoly.append(Vector2.ZERO)
		for i in fseg + 1:
			var ang := fan_windup_dir.angle() - fan_windup_half + 2.0 * fan_windup_half * float(i) / float(fseg)
			var p := Vector2.from_angle(ang) * frad
			fpoly.append(p)
			farc.append(p)
		draw_colored_polygon(fpoly, Color(1.0, 0.90, 0.30, 0.14 + 0.16 * fprog))
		draw_polyline(farc, Color(1.0, 0.88, 0.32, 0.35 + 0.45 * fprog), 2.0, true)
		draw_line(Vector2.ZERO, farc[0], Color(1.0, 0.88, 0.32, 0.30), 1.2, true)
		draw_line(Vector2.ZERO, farc[farc.size() - 1], Color(1.0, 0.88, 0.32, 0.30), 1.2, true)

	# 光晕
	for i in 7:
		draw_circle(Vector2.ZERO, r * (1.85 - 0.14 * i), Color(CFG.COL_BOSS, 0.030 * dim))

	# 外壳（有手绘素材就用图片，没有就用代码画的圆）
	if not Skins.blit(self, "boss1_body", Rect2(-r, -r, r * 2.0, r * 2.0), 0.0):
		draw_circle(Vector2.ZERO, r, Color(CFG.COL_BOSS, 0.16 * dim))
		draw_circle(Vector2.ZERO, r * 0.88, Color(CFG.COL_BOSS, 0.42 * dim))
		draw_circle(Vector2.ZERO, r * 0.60, Color(core, 0.75 * dim))
		draw_circle(Vector2.ZERO, r * 0.44, Color(CFG.COL_BOSS_CORE, 0.92 * dim))

	# 四向反击箭头：一直在转，决定受击时从哪四个方向还手
	if active and not dying:
		var orbit := r * 1.88
		# 一圈很淡的轨道，把这四个箭头和子弹区分开
		draw_arc(Vector2.ZERO, orbit, 0.0, TAU, 72,
			Color(1.0, 0.42, 0.545, 0.07 + 0.05 * arrow_flash), 1.0, true)
		for i in arrow_count:
			var ad := Vector2.from_angle(arrow_angle(i))
			var p := ad * orbit
			var tip := p + ad * 13.0
			var base := p - ad * 5.0
			var side := ad.orthogonal() * 7.0
			var acol := Color(1.0, 0.46, 0.58, 0.55 + 0.45 * arrow_flash)
			draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), acol)

	# 剩余血量 → 环绕的弧，掉一滴血少一条
	var spin := t * (0.7 + 0.35 * float(ph))
	for i in hp:
		var a0 := spin + TAU * float(i) / float(max_hp)
		draw_arc(Vector2.ZERO, r * 1.20, a0, a0 + 1.45, 40,
			Color(CFG.COL_BOSS, 0.95 * dim), 5.0, true)

	# 裂痕（每掉一滴血多一条）
	for i in (max_hp - hp):
		var a := TAU * float(i) / float(max_hp) + 0.5
		draw_line(Vector2.from_angle(a) * r * 0.35, Vector2.from_angle(a) * r * 0.95,
			Color(0.05, 0.02, 0.03, 0.55), 2.0, true)

	# 眼
	var look := Vector2.DOWN
	if target != null and is_instance_valid(target):
		look = (target.global_position - global_position).normalized()
	draw_circle(look * r * 0.34, r * 0.19, Color(1.0, 0.88, 0.90, 0.92 * dim))
	draw_circle(look * r * 0.34 + look * r * 0.05, r * 0.09, Color(0.10, 0.02, 0.04, 0.95 * dim))

	# 无敌指示
	if invuln > 0.0 and not dying:
		draw_arc(Vector2.ZERO, r * 1.45, -PI * 0.5, -PI * 0.5 + TAU * (invuln / CFG.BOSS_IFRAME),
			48, Color(1, 1, 1, 0.22), 2.0, true)

	# 受击白闪
	if flash > 0.0:
		draw_circle(Vector2.ZERO, r * 1.05, Color(1, 1, 1, 0.30 * flash))


func _dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.5:
		return
	var dir := d / length
	var s := 0.0
	while s < length:
		var e := minf(s + 10.0, length)
		draw_line(from + dir * s, from + dir * e, color, width, true)
		s += 17.0
