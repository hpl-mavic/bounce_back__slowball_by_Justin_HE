extends Node2D
## 场地：地图就是在 scenes/arena.tscn 里画的 TileMapLayer（Floor + Walls）。
##
##   · 想改地图：在编辑器 2D 视图里选中 Floor / Walls 层，
##     右侧检查器下方会出现 TileMap 面板，选图块直接涂即可。
##   · 想换图块：改 assets/tiles.png + scenes/tileset.tres。
##
## 本脚本只做一件事：把墙格合并成矩形，给玩家 / 子弹 / 预测线做碰撞。
## 对外接口与旧版一致（collide_circle / blocks_point / raycast）。

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）

const TILE := 32                        # 单个图块边长（px）；要改得同时改 tileset.tres 与 config.ARENA

@onready var floor_layer: TileMapLayer = $Floor   # 地板层（纯装饰，不参与碰撞）
@onready var wall_layer: TileMapLayer = $Walls    # 墙体层（碰撞由它的格子推导）

var rects: Array[Rect2] = []   # 合并后的墙矩形（局部坐标），碰撞只查这个
var radius := 0.0              # 兼容旧接口：整张图当作一个"障碍物"，半径恒为 0
var flash := 0.0               # 子弹打墙时的白闪（0~1，视觉）


## 给调试层用：把碰撞矩形换成世界坐标（真正的碰撞箱就是这个）
func world_rects() -> Array:
	var out: Array = []
	for r in rects:
		out.append(Rect2(r.position + global_position, r.size))
	return out


func _ready() -> void:
	_build_rects()


## 把所有墙格贪心合并成尽量少的矩形（几十个，够快）
func _build_rects() -> void:
	rects.clear()
	var cells := {}
	for c in wall_layer.get_used_cells():
		cells[c] = true
	var covered := {}
	for c in cells.keys():
		if covered.has(c):
			continue
		# 向右扩
		var x1: int = c.x
		while cells.has(Vector2i(x1 + 1, c.y)) and not covered.has(Vector2i(x1 + 1, c.y)):
			x1 += 1
		# 向下扩：整行都得是墙且没被占用
		var y1: int = c.y
		while true:
			var next_y: int = y1 + 1
			var ok := true
			for x in range(c.x, x1 + 1):
				if not cells.has(Vector2i(x, next_y)) or covered.has(Vector2i(x, next_y)):
					ok = false
					break
			if not ok:
				break
			y1 = next_y
		for y in range(c.y, y1 + 1):
			for x in range(c.x, x1 + 1):
				covered[Vector2i(x, y)] = true
		rects.append(Rect2(
			float(c.x * TILE), float(c.y * TILE),
			float((x1 - c.x + 1) * TILE), float((y1 - c.y + 1) * TILE)))


# ---------------------------------------------------------------------
# 与 obstacle.gd 一致的碰撞接口
# ---------------------------------------------------------------------
func collide_circle(local_p: Vector2, r: float) -> Dictionary:
	var out := {"hit": false, "normal": Vector2.ZERO, "depth": 0.0, "cp": Vector2.ZERO}
	var best := INF
	for rect in rects:
		var cp := Vector2(
			clampf(local_p.x, rect.position.x, rect.end.x),
			clampf(local_p.y, rect.position.y, rect.end.y))
		var d := local_p - cp
		var dist := d.length()
		if dist > r:
			continue
		var depth := r - dist
		if depth < best:
			best = depth
			var n := d / dist if dist > 0.001 else Vector2.UP
			out["hit"] = true
			out["normal"] = n
			out["depth"] = depth
			out["cp"] = cp
	return out


func blocks_point(local_p: Vector2, r: float) -> bool:
	for rect in rects:
		var cp := Vector2(
			clampf(local_p.x, rect.position.x, rect.end.x),
			clampf(local_p.y, rect.position.y, rect.end.y))
		if local_p.distance_squared_to(cp) <= r * r:
			return true
	return false


## 线段与墙的最近交点（全局坐标），返回 {hit, dist, point, normal}
func raycast(from_g: Vector2, dir: Vector2, max_dist: float) -> Dictionary:
	var out := {"hit": false, "dist": max_dist, "point": from_g, "normal": Vector2.ZERO}
	var p := from_g - global_position
	var best := max_dist
	var best_n := Vector2.ZERO
	for rect in rects:
		var tmin := -INF
		var tmax := INF
		var nrm := Vector2.ZERO
		var ok := true
		for axis in 2:
			var d: float = dir[axis]
			var o: float = p[axis]
			var lo: float = rect.position[axis]
			var hi: float = rect.end[axis]
			if absf(d) < 0.000001:
				if o < lo or o > hi:
					ok = false
					break
				continue
			var t1 := (lo - o) / d
			var t2 := (hi - o) / d
			var n_axis := Vector2.ZERO
			if d > 0.0:
				n_axis = Vector2.LEFT if axis == 0 else Vector2.UP
			else:
				n_axis = Vector2.RIGHT if axis == 0 else Vector2.DOWN
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			if t1 > tmin:
				tmin = t1
				nrm = n_axis
			tmax = minf(tmax, t2)
			if tmin > tmax:
				ok = false
				break
		if not ok or tmin < 0.0:
			continue
		if tmin < best:
			best = tmin
			best_n = nrm
	if best < max_dist:
		out["hit"] = true
		out["dist"] = best
		out["point"] = from_g + dir * best
		out["normal"] = best_n
	return out


func flash_hit() -> void:
	flash = 1.0