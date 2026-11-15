extends Area2D
## 子弹：只会被「让时间慢下来」这一招躲开。
## 三层绘制的光球，命中主角后立刻消失。

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）
const Skins := preload("res://scripts/skins.gd")   # 手绘素材管线

# 长方形快弹拖尾：弹头金 → 末端棕
const COLOR_RAIL_GOLD := Color(1.0, 0.84, 0.35)
const COLOR_RAIL_BROWN := Color(0.45, 0.28, 0.12)

var velocity := Vector2.ZERO      # 当前速度（px/s，直线飞行，不会被减速）
var radius := CFG.BULLET_RADIUS   # 判定半径（px）
var life := CFG.BULLET_LIFE       # 剩余存活时间（战场秒）
var kind := 0                     # 弹种：0 普通 / 1 快 / 2 大 / 3 长方形快弹
var color := CFG.COL_BULLET       # 颜色（由 kind 决定）
var dead := false                 # 是否已消失（防止重复结算）
var t := 0.0                      # 累计时间（呼吸微动）

## 由 Main 注入：当前关卡的障碍物列表（打上去就消失）与主角引用（护盾弧面判定）
var obstacles: Array = []   # 由 Main 注入：挡子弹的实心物（现在只有 arena）
var player_ref = null       # 由 Main 注入：用来做护盾弧面判定


func _ready() -> void:
	add_to_group("bullet")
	z_index = 4
	area_entered.connect(_on_area_entered)
	queue_redraw()


func setup(pos: Vector2, vel: Vector2, bullet_kind: int = 0) -> void:
	global_position = pos
	velocity = vel
	kind = bullet_kind
	t = randf() * TAU
	match kind:
		1:
			color = CFG.COL_BULLET_FAST
			radius = CFG.BULLET_RADIUS * 0.86
		2:
			color = CFG.COL_BULLET_BIG
			radius = CFG.BULLET_RADIUS * 1.35
			life = 10.0
		3:
			# Boss2 的直线快弹：长方形（面积 ×2）
			color = Color(0.86, 0.94, 1.0)
			radius = CFG.BULLET_RADIUS * 0.85 * 1.414
			life = 8.0
		_:
			color = CFG.COL_BULLET
			radius = CFG.BULLET_RADIUS


func _physics_process(delta: float) -> void:
	t += delta
	global_position += velocity * delta

	# 护盾的弧面：只有那条弧线算，两侧直线和内部面积不算
	if player_ref != null and is_instance_valid(player_ref) and player_ref.shield_active:
		if player_ref.shield_arc_catch(global_position):
			pop()
			return

	# 障碍物：挡住就消失
	for o in obstacles:
		if not is_instance_valid(o):
			continue
		if o.blocks_point(global_position - o.global_position, radius * 0.55):
			o.flash_hit()
			pop()
			return

	life -= delta
	if life <= 0.0 or not CFG.ARENA.grow(70.0).has_point(global_position):
		queue_free()
		return
	queue_redraw()


func pop() -> void:
	dead = true
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if dead:
		return
	if area.is_in_group("player"):
		# 被长方形快弹命中：限速到 65%
		if kind == 3 and area.has_method("apply_speed_cap"):
			area.apply_speed_cap(CFG.BOSS2_RAIL_CAP, CFG.BOSS2_CAP_TIME)
		if area.take_hit(velocity.normalized()):
			pop()


func _draw() -> void:
	var a := 1.0
	if life < 1.0:
		a = clampf(life, 0.0, 1.0)
	if kind == 3:
		# 长方形快弹：沿速度方向拉长（有手绘素材就整张替换）
		var ang := velocity.angle()
		var w := CFG.BOSS2_RAIL_LEN
		var h := CFG.BOSS2_RAIL_THICK
		# 金色粒子拖尾：弹头附近金，越往后越棕
		draw_set_transform(Vector2.ZERO, ang, Vector2.ONE)
		var trail_len := w * 3.2
		var dots := 12
		for k in dots:
			var t0 := float(k) / float(dots)
			var x := -w * 0.5 - trail_len * t0
			var rad := h * 0.46 * (1.0 - 0.72 * t0)
			var col := COLOR_RAIL_GOLD.lerp(COLOR_RAIL_BROWN, t0)
			var wob := sin(t0 * 11.0 + t * 26.0) * h * 0.18 * t0
			draw_circle(Vector2(x, wob), rad, Color(col, 0.60 * (1.0 - 0.45 * t0) * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if Skins.blit(self, "bullet_3", Rect2(-w * 0.5, -h * 0.5, w, h), ang):
			return
		draw_set_transform(Vector2.ZERO, ang, Vector2.ONE)
		draw_rect(Rect2(-w * 1.9, -h * 0.9, w * 1.9, h * 1.8), Color(color, 0.10 * a))
		draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color(color, 0.95 * a), true)
		draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color(1, 1, 1, 0.85 * a), false, 1.0)
		draw_rect(Rect2(-w * 1.6, -h * 0.28, w * 1.1, h * 0.56), Color(color, 0.22 * a), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var r := radius * (1.0 + 0.04 * sin(t * 9.0))
	# 圆形弹（有手绘素材就用图片）
	if Skins.blit(self, "bullet_%d" % kind, Rect2(-r * 2.0, -r * 2.0, r * 4.0, r * 4.0), 0.0):
		return
	draw_circle(Vector2.ZERO, r * 2.6, Color(color, 0.055 * a))
	draw_circle(Vector2.ZERO, r * 1.7, Color(color, 0.12 * a))
	draw_circle(Vector2.ZERO, r, Color(color, 0.90 * a))
	draw_circle(Vector2.ZERO, r * 0.42, Color(1, 1, 1, 0.85 * a))
