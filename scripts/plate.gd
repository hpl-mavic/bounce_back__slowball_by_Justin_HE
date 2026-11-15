extends Area2D
## Boss2 的环绕护盾：弧形圣盾，2 点耐久，撞碎后消失。
## 撞上去只会掉护盾的耐久，不会掉 Boss 的血。

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）
const Skins := preload("res://scripts/skins.gd")   # 手绘素材管线

var hp := CFG.BOSS2_PLATE_HP        # 当前耐久（撞到 0 就碎）
var max_hp := CFG.BOSS2_PLATE_HP    # 耐久上限（用来画两颗宝石）
var body_radius := CFG.BOSS2_PLATE_R # 圣盾半径（px），同时是碰撞半径
var active := true                  # 还在不在（碎了就 false）
var flash := 0.0                    # 被撞时的白闪（0~1）
var boss = null                     # 所属 Boss（碎掉时通知它）
var facing := Vector2.DOWN          # 弧面朝外的方向，由 Boss 每帧设置
var t := 0.0                        # 累计时间（光点流动用）


func _ready() -> void:
	add_to_group("boss")
	add_to_group("boss2")
	collision_layer = 4
	collision_mask = 0
	z_index = 3
	var shape := CircleShape2D.new()
	shape.radius = body_radius
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	queue_redraw()


func try_ram() -> bool:
	if hp <= 0:
		return false
	hp -= 1
	flash = 1.0
	if hp <= 0:
		active = false
		set_deferred("monitorable", false)
		set_deferred("monitoring", false)
		if boss != null and is_instance_valid(boss):
			boss.on_plate_broken()
		queue_free()
	return true


func _physics_process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var r := body_radius
	var ang := facing.angle()
	var a0 := ang - 0.95
	var a1 := ang + 0.95

	# 圣光：外侧三层金晕
	for i in 3:
		draw_arc(Vector2.ZERO, r * (1.02 + 0.12 * float(i)), a0, a1, 26,
			Color(1.0, 0.86, 0.48, 0.045), 8.0, true)

	# 盾体：有手绘素材就用图片（朝右画，这里按 facing 旋转），否则用同心弧叠出来
	if not Skins.blit(self, "boss2_plate", Rect2(-r, -r, r * 2.0, r * 2.0), ang):
		for k in 5:
			var rr := r * (0.64 + 0.075 * float(k))
			draw_arc(Vector2.ZERO, rr, a0, a1, 30, Color(0.13, 0.11, 0.08, 0.30), 6.5, true)
		draw_arc(Vector2.ZERO, r * 0.62, a0, a1, 30, Color(0.20, 0.17, 0.12, 0.45), 5.0, true)

	# 金边
	draw_arc(Vector2.ZERO, r * 1.02, a0, a1, 34, Color(0.98, 0.82, 0.46), 2.6, true)
	draw_arc(Vector2.ZERO, r * 1.02, a0, a1, 34, Color(1.0, 0.95, 0.72, 0.35), 1.0, true)
	draw_arc(Vector2.ZERO, r * 0.60, a0 + 0.03, a1 - 0.03, 34, Color(0.62, 0.48, 0.24), 1.6, true)

	# 十字徽记（中世纪盾牌）
	var dirv := Vector2.from_angle(ang)
	var side := Vector2.from_angle(ang + PI * 0.5)
	var mid := dirv * r * 0.84
	draw_line(mid - side * 4.6, mid + side * 4.6, Color(1.0, 0.94, 0.72, 0.95), 2.0, true)
	draw_line(mid - dirv * 2.6, mid + dirv * 6.4, Color(1.0, 0.94, 0.72, 0.95), 2.0, true)
	draw_circle(mid, 1.8, Color(1.0, 1.0, 0.88, 0.95))

	# 耐久：弧上两颗宝石，掉一点暗一颗
	for i in 2:
		var ga := ang + (0.66 if i == 0 else -0.66)
		var gp := Vector2.from_angle(ga) * r * 0.86
		if i < hp:
			draw_circle(gp, 3.4, Color(1.0, 0.84, 0.42, 0.16))
			draw_circle(gp, 2.6, Color(0.99, 0.86, 0.50, 0.95))
			draw_circle(gp, 1.1, Color(1, 1, 1, 0.95))
		else:
			draw_arc(gp, 2.4, 0.0, TAU, 10, Color(0.30, 0.26, 0.18, 0.8), 1.2, true)

	# 裂纹（掉了一点耐久之后）
	if hp < max_hp:
		var c1 := Vector2.from_angle(ang - 0.30) * r * 0.62
		var c2 := Vector2.from_angle(ang - 0.05) * r * 1.00
		var c3 := Vector2.from_angle(ang + 0.22) * r * 0.72
		draw_polyline(PackedVector2Array([c1, c2, c3]), Color(0.03, 0.03, 0.04, 0.75), 1.4, true)

	# 缓慢流动的光点
	for i in 3:
		var sa := a0 + (a1 - a0) * fmod(t * 0.35 + float(i) * 0.31, 1.0)
		draw_circle(Vector2.from_angle(sa) * r * 1.02, 1.4, Color(1.0, 0.93, 0.65, 0.55))

	if flash > 0.0:
		draw_arc(Vector2.ZERO, r * 1.04, a0, a1, 30, Color(1, 1, 1, 0.55 * flash), 4.0, true)
