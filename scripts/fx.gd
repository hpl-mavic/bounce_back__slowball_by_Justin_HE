extends Node2D
## 极简粒子 / 冲击波系统。
## 自己算、自己画，不用 GPUParticles，保证低配机和 headless 下行为一致。
## 注意：这里的时间是「战场时间」，所以慢放时粒子也会变慢，很好看。

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）


class Spark:                      # 一个火花粒子
	var pos: Vector2              # 当前位置（世界坐标）
	var vel: Vector2              # 当前速度（px/s，每帧衰减到 94%）
	var life: float               # 剩余寿命（秒）
	var max_life: float           # 初始寿命（算淡出比例用）
	var size: float               # 初始半径（px）
	var color: Color              # 颜色


class Wave:                       # 一圈扩散的冲击波
	var pos: Vector2              # 圆心（世界坐标）
	var from_r: float             # 起始半径（px）
	var to_r: float               # 终止半径（px）
	var life: float               # 剩余寿命（秒）
	var max_life: float           # 初始寿命
	var width: float              # 线宽（px）
	var color: Color              # 颜色


class Slash:                      # 一道锯齿状"撕裂"划痕
	var pos: Vector2              # 起点（世界坐标）
	var angle: float              # 走向（rad）
	var length: float             # 长度（px）
	var life: float               # 剩余寿命（秒）
	var max_life: float           # 初始寿命
	var seed: int                 # 随机种子（保证锯齿形状每帧稳定）
	var color: Color              # 颜色


var sparks: Array[Spark] = []     # 当前所有火花
var waves: Array[Wave] = []       # 当前所有冲击波
var slashes: Array[Slash] = []    # 当前所有撕裂划痕
var debug_rects: Array = []       # 调试：地图碰撞箱（F3 打开，由 Main 灌进来）


## 调试：把地图合并出的碰撞箱传进来（传空数组即关闭）
func set_debug_rects(list: Array) -> void:
	debug_rects = list
	queue_redraw()


func burst(pos: Vector2, color: Color, count: int = 12, speed: float = 280.0,
		size: float = 3.0, life: float = 0.55) -> void:
	for i in count:
		var s := Spark.new()
		s.pos = pos
		s.vel = Vector2.from_angle(randf() * TAU) * speed * randf_range(0.35, 1.0)
		s.life = life * randf_range(0.6, 1.15)
		s.max_life = s.life
		s.size = size * randf_range(0.6, 1.4)
		s.color = color
		sparks.append(s)
	if sparks.size() > 400:
		sparks = sparks.slice(sparks.size() - 400)


func ring(pos: Vector2, color: Color, from_r: float, to_r: float,
		life: float = 0.45, width: float = 3.0) -> void:
	var w := Wave.new()
	w.pos = pos
	w.from_r = from_r
	w.to_r = to_r
	w.life = life
	w.max_life = life
	w.width = width
	w.color = color
	waves.append(w)


func clear_all() -> void:
	sparks.clear()
	waves.clear()
	slashes.clear()
	queue_redraw()


## 撕裂特效：几道锯齿状的裂口，沿切线方向撕开
func tear(pos: Vector2, normal: Vector2, color: Color = Color(1.0, 0.55, 0.85)) -> void:
	var base := normal.angle() + PI * 0.5
	for i in 3:
		var s := Slash.new()
		s.pos = pos
		s.angle = base + randf_range(-0.55, 0.55)
		s.length = randf_range(32.0, 74.0)
		s.life = randf_range(0.18, 0.30)
		s.max_life = s.life
		s.seed = randi()
		s.color = color
		slashes.append(s)


func _process(delta: float) -> void:
	var i := sparks.size() - 1
	while i >= 0:
		var s: Spark = sparks[i]
		s.life -= delta
		if s.life <= 0.0:
			sparks.remove_at(i)
		else:
			s.pos += s.vel * delta
			s.vel *= 0.94
		i -= 1

	var j := waves.size() - 1
	while j >= 0:
		var w: Wave = waves[j]
		w.life -= delta
		if w.life <= 0.0:
			waves.remove_at(j)
		j -= 1

	var k2 := slashes.size() - 1
	while k2 >= 0:
		var sl: Slash = slashes[k2]
		sl.life -= delta
		if sl.life <= 0.0:
			slashes.remove_at(k2)
		k2 -= 1

	queue_redraw()


func _draw() -> void:
	# 调试层：地图碰撞箱（F3 打开）。画在粒子层，所以能盖在 TileMap 上面
	for r in debug_rects:
		draw_rect(r, Color(1.0, 0.32, 0.28, 0.12), true)
		draw_rect(r, Color(1.0, 0.45, 0.38, 0.65), false, 1.0)

	for w in waves:
		var k: float = 1.0 - w.life / w.max_life
		var r: float = lerpf(w.from_r, w.to_r, ease(k, 0.45))
		var a: float = (1.0 - k) * 0.8
		draw_arc(w.pos, r, 0.0, TAU, 72, Color(w.color, a), w.width * (1.0 - k * 0.6), true)

	for s in slashes:
		var k: float = s.life / s.max_life
		var d := Vector2.from_angle(s.angle)
		var n := d.orthogonal()
		var rng := RandomNumberGenerator.new()
		rng.seed = s.seed
		var pts := PackedVector2Array()
		var seg := 4
		for i in seg + 1:
			var t := float(i) / float(seg)
			var off := rng.randf_range(-7.0, 7.0) * (1.0 - t * 0.5)
			pts.append(s.pos + d * (s.length * (t - 0.5)) + n * off)
		draw_polyline(pts, Color(s.color, 0.95 * k), 2.6 * k + 0.6, true)
		draw_circle(s.pos, 5.0 * k, Color(1, 1, 1, 0.35 * k))

	for s in sparks:
		var k: float = s.life / s.max_life
		draw_circle(s.pos, s.size * (0.35 + 0.65 * k), Color(s.color, 0.9 * k))
