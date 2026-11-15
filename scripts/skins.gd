extends RefCounted
## 皮肤 / 手绘素材管线
##
## 规则很简单：`assets/sprites/<名字>.png` 存在就用图片，不存在就用代码画的占位图形。
## 所以你只要把画好的 PNG 放进那个目录、文件名对上，游戏里立刻换皮，不用改代码。
##
## 画布尺寸请用 `tools/make_art_templates.gd` 生成的模板（都是显示尺寸的 2 倍），
## 代码会按 2 倍缩小绘制。所有"会转向"的图请**朝右（+X）画**，引擎负责旋转。

const DIR := "res://assets/sprites/"

static var _cache: Dictionary = {}


## 按名字取贴图；没有这个文件就返回 null（调用方回退到代码绘制）
static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_cache[name] = t
	return t


static func has(name: String) -> bool:
	return tex(name) != null


## 在局部坐标里画一张图（rect 用显示尺寸，贴图会缩放填满它）
## rot != 0 时会临时改绘制变换并在结束后复位；rot == 0 时不动变换（保留外层效果）
static func blit(ci: CanvasItem, name: String, rect: Rect2, rot: float = 0.0) -> bool:
	var t := tex(name)
	if t == null:
		return false
	if absf(rot) < 0.0001:
		ci.draw_texture_rect(t, rect, false)
		return true
	ci.draw_set_transform(rect.get_center(), rot, Vector2.ONE)
	ci.draw_texture_rect(t, Rect2(-rect.size * 0.5, rect.size), false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 清缓存（素材刚导入、想热重载时用）
static func clear_cache() -> void:
	_cache.clear()
