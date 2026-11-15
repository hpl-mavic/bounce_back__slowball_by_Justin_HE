extends Area2D
## 主角：一颗被「弹」出去的球。
##
## 操作（弹弓式：一次拖动 = 一次发射）
##   按下左键     → 抓住球，球停住，世界进入 0.2 倍速
##   拖动         → 方向 = 拖动方向；力度 = 拖动距离
##   松开         → 球按这个矢量飞出去，世界回到 1.0 倍速
##   滞空时再按下 → 消耗 1 次变向机会，重新抓住球瞄准
##
## 变向次数：每次发射自带 1 次；撞墙 / 障碍物 / 撞 Boss 各 +1，最多存 3 次。
## 攻击 = 撞击，一次 1 点伤害。
##
## 角色：
##   ROAMER  标准球，无技能
##   AEGIS   0.9× 速度、反弹损耗更大；右键开护盾（有扇形蓄能机制）

signal damaged(hp_left: float)
signal died
signal launched(power: float)
signal bounced(pos: Vector2, normal: Vector2)
signal shield_absorbed(kind: int, pos: Vector2)
signal landed(pos: Vector2)
signal upgraded(tier: int)
signal tore_at(pos: Vector2, normal: Vector2)
signal shield_broken(pos: Vector2)

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）
const Skins := preload("res://scripts/skins.gd")   # 手绘素材管线

# =====================================================================
# 视觉参数（想调外观改这里，全部集中在文件顶部）
# =====================================================================
const TRAIL_MAX := 16             # 尾迹采样点数；越大尾巴越长（性能开销也越大）
const TRAIL_INNER := 2.0          # 尾迹最细处线宽（px）
const TRAIL_OUTER := 13.0         # 尾迹最粗处线宽（px）
const TRAIL_ALPHA := 0.26         # 尾迹透明度（0~1）

const SPEEDLINE_SPEED := 420.0    # 超过这个速度才画速度线（px/s）
const SPEEDLINE_COUNT := 3        # 速度线条数
const SPEEDLINE_SPREAD := 7.0     # 速度线之间的间距（px）

const DROP_GROW := 0.0026         # 空投时每像素抬高放大多少（伪立体）

const GLOW_LAYERS := 7            # 外光晕层数
const GLOW_BASE := 2.30           # 最外层半径倍率（× 球半径）
const GLOW_STEP := 0.18           # 每层缩小的步长
const GLOW_ALPHA := 0.042         # 每层透明度（极淡，叠加出光）

const SQUISH_SPEED := 2400.0      # 速度到多少时压扁到达上限（px/s）
const SQUISH_MAX := 0.12          # 最大压扁量（0.12 = 最多放大 12%）

const EYE_OFFSET := 0.34          # 普通眼：瞳孔离球心多远（× 半径）
const EYE_R := 0.26               # 普通眼：瞳孔半径（× 半径）
const EYE_HL_OFFSET := 0.07       # 高光偏移（× 半径）
const EYE_HL_R := 0.10            # 高光半径（× 半径）

const SETTLE_RING_R := 2.0        # 停稳时呼吸环的基准半径（× 半径）
const SETTLE_RING_PULSE := 4.0    # 呼吸环的呼吸幅度（px）
const SETTLE_RING_ALPHA := 0.16   # 呼吸环透明度

const CRACK_LINES_MIN := 2        # 碎裂开始时画几条裂纹
const CRACK_LINES_MAX := 8        # 碎满时画几条裂纹
const CRACK_FRAGMENTS := 5        # 碎裂过程中飞出的碎块数
const CORPSE_FRAGMENTS := 11      # 碎完之后的残骸块数

enum Mode { IDLE, AIMING, FLYING }

# ---- 生命与状态 ----
var hp := 3.0                     # 当前生命（浮点：虫球满级护盾会打出 0.5）
var max_hp := 3                   # 生命上限（由难度决定）
var alive := true                 # 是否还活着
var control_enabled := false      # 是否接受输入（空投/结算/自测时会关掉）

# ---- 角色 ----
var char_id := 0                  # 角色下标（0 游球 / 1 盾球 / 2 虫球）
var char_def: Dictionary = CFG.CHARS[0]  # 当前角色配置（见 config.CHARS）
var radius := CFG.PLAYER_RADIUS   # 实际半径（已被角色倍率乘过）
var max_charges := CFG.AIR_CHANGE_MAX    # 变向上限（虫球是 5）
var is_bug := false               # 是不是虫球（决定很多专属逻辑）
var speed_stacks := 0             # 游球的被动层数（每反弹 +0.5% 极限速度）
var stack_hold := 0.0             # 游球被动：还剩多久开始衰退（现实秒）
var stack_decay_t := 0.0          # 游球被动：普通衰退计时（每 0.2 秒掉一层）

# ---- 虫球：进化 ----
var tier := 0                     # 当前进化档（0~5）
var tier_hits := 0                # 本档已累计的碰撞次数（0~5）
var slow_field_held := false      # 右键是否按住（慢放场）
var slow_charge := CFG.BUG_SLOW_FIELD_MAX  # 慢放场剩余充能（秒）
var slow_exhausted := false       # 是否已耗空（必须松手才能再开）
var bug_shield_ready := true      # 满级抗伤护盾是否可用
var bug_shield_cd := 0.0          # 抗伤护盾的冷却剩余（秒）

# ---- 盾球：护盾 ----
var shield_enabled := false       # 这个角色有没有护盾
var shield_active := false        # 护盾当前是否展开
var shield_time := 0.0            # 本次护盾已开启多久（决定阶段颜色/形状）
var shield_charge := 0.0          # 剩余持续时间（秒），松手后按 SHIELD_REFILL 恢复
var shield_hold := false          # 右键是否按住
var shield_flash := 0.0           # 挡弹时的白闪（0~1，视觉）
var shield_shots := 0             # 本次开盾还能扛几发
var fan_dir := Vector2.RIGHT      # 扇形当前朝向（单位向量）
var fan_lock := Vector2.INF       # 开发/截图用：锁定扇形朝向
var _rmb_prev := false            # 上一帧右键状态（用来取"按下沿"）

# ---- 入场空投 ----
var dropping := false             # 是否还在下落
var drop_t := 0.0                 # 下落进度 0~1
var drop_h := 0.0                 # 当前"高度"（px，用于绘制偏移与放大）

# ---- 运动 ----
var mode := Mode.IDLE             # IDLE 静止 / AIMING 瞄准 / FLYING 飞行
var velocity := Vector2.ZERO      # 当前速度（px/s）
var charges := CFG.AIR_CHANGE_BASE # 剩余变向次数

# ---- 瞄准 ----
var drag_vec := Vector2.ZERO      # 球心 → 鼠标 的向量
var aim := Vector2.RIGHT          # 发射方向（单位向量）
var aim_point := Vector2.ZERO     # 鼠标世界坐标
var power := 0.0                  # 力度 0~1（由拖动距离决定）

# ---- 计时器 ----
var invuln := 0.0                 # 剩余无敌时间（战场秒）
var contact_lock := 0.0           # 撞击后的接触锁，防止同一帧多次结算
var slow_cap_timer := 0.0         # 极速上限剩余时间（现实秒）
var speed_cap := 1.0              # 极速上限倍率（1.0 = 不限）

# ---- 停死 → 碎裂 ----
var crack_t := 0.0                # 碎裂进度 0~1，满则判负
var cracked := false              # 是否是被"停死"判负的（决定结算画面）

# ---- 视觉 ----
var flash := 0.0                  # 受击白闪（0~1）
var deny_flash := 0.0             # 变向次数不足时的红闪（0~1）
var t := 0.0                      # 累计时间（给呼吸/脉冲动画用）
var trail: Array[Vector2] = []    # 尾迹采样点（世界坐标）

## 由 Main 注入：当前关卡里的"实心物"列表（现在只有一个 arena 节点）
var obstacles: Array = []

var _prev_velocity := Vector2.ZERO  # 进瞄准前的速度（取消时用）
var _catch := false               # 本次瞄准是不是"空中改向"（要扣 1 次变向）
var _denied := false              # 是否刚被拒绝过（防止重复闪红）


func _ready() -> void:
	add_to_group("player")
	z_index = 6
	area_entered.connect(_on_area_entered)
	queue_redraw()


func setup(hit_points: int, char_index: int = 0) -> void:
	max_hp = hit_points
	hp = float(hit_points)
	char_id = clampi(char_index, 0, CFG.CHARS.size() - 1)
	char_def = CFG.CHARS[char_id]
	is_bug = char_def.get("key", "") == "bug"
	radius = CFG.PLAYER_RADIUS * float(char_def.get("radius", 1.0))
	max_charges = int(char_def.get("max_changes", CFG.AIR_CHANGE_MAX))
	var shape := $CollisionShape2D.shape as CircleShape2D
	if shape != null:
		shape.radius = radius
	tier = 0
	tier_hits = 0
	speed_stacks = 0
	stack_hold = 0.0
	stack_decay_t = 0.0
	slow_field_held = false
	slow_charge = CFG.BUG_SLOW_FIELD_MAX
	slow_exhausted = false
	bug_shield_ready = true
	bug_shield_cd = 0.0
	shield_shots = 0
	shield_enabled = bool(char_def["shield"])
	shield_active = false
	shield_time = 0.0
	shield_charge = CFG.SHIELD_DURATION
	shield_hold = false
	shield_flash = 0.0
	_rmb_prev = false
	invuln = 0.0
	slow_cap_timer = 0.0
	speed_cap = 1.0
	crack_t = 0.0
	cracked = false
	mode = Mode.IDLE
	velocity = Vector2.ZERO
	charges = CFG.AIR_CHANGE_BASE
	trail.clear()
	# 入场空投
	dropping = true
	drop_t = 0.0
	drop_h = CFG.DROP_HEIGHT
	invuln = 999.0
	control_enabled = false


func speed_scale() -> float:
	return float(char_def.get("speed", 1.0))


func _wall_damp() -> float:
	return CFG.WALL_DAMP * float(char_def.get("wall", 1.0))


func _ram_damp() -> float:
	return CFG.RAM_BOUNCE * float(char_def.get("ram", 1.0))


## 虫球满级后撞到敌人会加速 20%
func _bug_rush() -> void:
	if not is_bug or tier < CFG.BUG_MAX_TIER:
		return
	if velocity == Vector2.ZERO:
		return
	velocity = (velocity * CFG.BUG_RUSH_BOOST).limit_length(CFG.BUG_RUSH_CAP)


## 游球的被动：极限速度倍率（每层 +0.5%）
func max_speed_bonus() -> float:
	return 1.0 + CFG.ROAM_STACK_BONUS * float(speed_stacks)


## 一次「碰」：撞墙 / 撞障碍 / 撞 Boss 都算
func _register_bump() -> void:
	# 游球：每反弹一次叠一层极限速度
	if char_id == 0 and speed_stacks < CFG.ROAM_STACK_MAX:
		speed_stacks += 1
		stack_hold = CFG.ROAM_STACK_HOLD
		stack_decay_t = 0.0
	if not is_bug or tier >= CFG.BUG_MAX_TIER:
		return
	tier_hits += 1
	if tier_hits >= CFG.BUG_HITS_PER_TIER:
		tier_hits = 0
		tier += 1
		upgraded.emit(tier)


func is_flying() -> bool:
	return mode == Mode.FLYING


func is_aiming() -> bool:
	return mode == Mode.AIMING


func is_idle() -> bool:
	return mode == Mode.IDLE


## 慢放场的最大持续时间：每进化一档 ×1.3（相对上一档，复利）
func slow_field_max() -> float:
	return CFG.BUG_SLOW_FIELD_MAX * pow(CFG.BUG_SLOW_FIELD_PER_TIER, float(tier))


## 虫球按住右键时的慢放场：还要有充能，且耗尽后必须松手才能再开
func is_slow_field() -> bool:
	return is_bug and slow_field_held and not slow_exhausted \
		and slow_charge > 0.0 and alive and not dropping


func reset_to_idle() -> void:
	mode = Mode.IDLE
	velocity = Vector2.ZERO
	charges = CFG.AIR_CHANGE_BASE
	crack_t = 0.0
	_catch = false
	power = 0.0
	drag_vec = Vector2.ZERO


# ---------------------------------------------------------------------
# 护盾（AEGIS）
#   按住右键：护盾展开，持续时间（充能）随时间消耗
#   松开右键：立刻关盾，充能开始恢复（0 → 1.5 秒；1.5/0.75 = 2 秒 = 冷却）
#   只有「扇形弧面」这一条弧形才算护盾面，两侧直线与内部面积都不算
# ---------------------------------------------------------------------
func open_shield() -> bool:
	if not shield_enabled or not alive or shield_active:
		return false
	if shield_charge <= 0.02:
		return false
	shield_active = true
	shield_time = 0.0
	shield_shots = CFG.SHIELD_SHOTS
	shield_flash = 1.0
	queue_redraw()
	return true


func close_shield() -> void:
	if not shield_active:
		return
	shield_active = false
	shield_flash = 1.0


## -1 = 未开启；0 = 只有球壳；1 = 绿；2 = 黄绿；3 = 红
func shield_stage() -> int:
	if not shield_active:
		return -1
	if shield_time < CFG.SHIELD_S1:
		return 0
	if shield_time < CFG.SHIELD_S2:
		return 1
	if shield_time < CFG.SHIELD_S3:
		return 2
	return 3


func shield_stage_color() -> Color:
	match _draw_stage():
		1:
			return Color(0.38, 0.96, 0.62)
		2:
			return Color(0.74, 0.96, 0.42)
		3:
			return Color(1.0, 0.32, 0.36)
		_:
			return Color(0.55, 0.92, 0.78)


func _update_shield(delta: float) -> void:
	# 护盾全程按现实时间走：慢放时 0.3 秒的"起手"依然是 0.3 秒，不会被拉成 1.5 秒
	var real_dt := delta / maxf(Engine.time_scale, 0.02)
	if shield_active:
		if not shield_hold:
			# 松手：立刻关盾
			close_shield()
		else:
			shield_time += real_dt
			shield_charge = maxf(0.0, shield_charge - real_dt)
			if fan_lock != Vector2.INF:
				fan_dir = fan_lock
			else:
				var m := get_global_mouse_position()
				if (m - global_position).length() > 1.0:
					fan_dir = (m - global_position).normalized()
			if shield_charge <= 0.0:
				close_shield()

	# 关盾时恢复充能（这就是冷却）
	if not shield_active and shield_charge < CFG.SHIELD_DURATION:
		shield_charge = minf(CFG.SHIELD_DURATION, shield_charge + CFG.SHIELD_REFILL * real_dt)


func _draw_stage() -> int:
	return shield_stage()


func fan_half_angle() -> float:
	var s := CFG.SHIELD_FAN_SHRINK if _draw_stage() >= 2 else 1.0
	return CFG.SHIELD_FAN_HALF * s


func fan_radius() -> float:
	var s := CFG.SHIELD_FAN_SHRINK if _draw_stage() >= 2 else 1.0
	return CFG.SHIELD_FAN_RADIUS * s


## 弧面判定：距离落在弧环厚度内 + 角度在扇形内。两侧直线与内部面积都不算。
func shield_arc_catch(from_pos: Vector2) -> bool:
	if not shield_active:
		return false
	var d := from_pos - global_position
	var dist := d.length()
	if dist < 1.0:
		return false
	if absf(dist - fan_radius()) > CFG.SHIELD_ARC_THICK:
		return false
	if absf(fan_dir.angle_to(d / dist)) > fan_half_angle():
		return false

	# 命中弧面：按阶段给奖励
	var st := shield_stage()
	var kind := 0
	if st == 1:
		shield_charge = minf(CFG.SHIELD_DURATION + CFG.SHIELD_ABSORB_TIME,
			shield_charge + CFG.SHIELD_ABSORB_TIME)
		kind = 1
	elif st == 2:
		shield_charge = minf(CFG.SHIELD_DURATION, shield_charge + CFG.SHIELD_ABSORB_CD)
		kind = 2
	shield_flash = 1.0
	_consume_shield_shot(global_position)
	shield_absorbed.emit(kind, global_position)
	return true


## 子弹撞在球体上（不是弧面）：挡下但不给奖励
func _absorb_body(from_pos: Vector2) -> void:
	shield_flash = 1.0
	_consume_shield_shot(from_pos)
	shield_absorbed.emit(0, from_pos)


## 每次挡下一发就消耗一格；挡完第 4 发护盾直接碎掉，并给 0.1 秒无敌
func _consume_shield_shot(at: Vector2) -> void:
	shield_shots = maxi(0, shield_shots - 1)
	if shield_shots <= 0:
		close_shield()
		invuln = maxf(invuln, CFG.SHIELD_BREAK_IFRAME)
		shield_broken.emit(at)


# ---------------------------------------------------------------------
# 主循环
# ---------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	t += delta
	queue_redraw()
	invuln = maxf(0.0, invuln - delta)
	contact_lock = maxf(0.0, contact_lock - delta)
	slow_cap_timer = maxf(0.0, slow_cap_timer - delta)
	if slow_cap_timer <= 0.0:
		speed_cap = 1.0
	flash = maxf(0.0, flash - delta * 3.2)
	deny_flash = maxf(0.0, deny_flash - delta * 3.0)
	shield_flash = maxf(0.0, shield_flash - delta * 3.0)

	# 虫球满级：抗伤护盾每 6 秒回复一次
	if is_bug:
		if not bug_shield_ready:
			bug_shield_cd = maxf(0.0, bug_shield_cd - delta)
			if bug_shield_cd <= 0.0:
				bug_shield_ready = true

	# 慢放场：按住消耗充能（现实时间），松手按 0.5/s 回复
	var field_dt := delta / maxf(Engine.time_scale, 0.02)
	if is_bug:
		if is_slow_field():
			slow_charge = maxf(0.0, slow_charge - field_dt)
			if slow_charge <= 0.0:
				slow_exhausted = true
		else:
			slow_charge = minf(slow_field_max(),
				slow_charge + CFG.BUG_SLOW_FIELD_REFILL * field_dt)
	
	# 游球被动：保持 4 秒，之后每 0.2 秒掉一层（都按现实时间）
	if char_id == 0 and speed_stacks > 0:
		if stack_hold > 0.0:
			stack_hold = maxf(0.0, stack_hold - field_dt)
		else:
			stack_decay_t += field_dt
			while stack_decay_t >= CFG.ROAM_STACK_DECAY and speed_stacks > 0:
				stack_decay_t -= CFG.ROAM_STACK_DECAY
				speed_stacks -= 1
			if speed_stacks <= 0:
				stack_decay_t = 0.0

	# 入场空投：按现实时间下落，期间不接受操作、不受伤害
	if dropping:
		var real_dt := field_dt
		drop_t = minf(1.0, drop_t + real_dt / CFG.DROP_TIME)
		drop_h = CFG.DROP_HEIGHT * (1.0 - drop_t * drop_t)
		if drop_t >= 1.0:
			dropping = false
			drop_h = 0.0
			invuln = 0.0
			control_enabled = true
			landed.emit(global_position)
		return

	if not alive:
		velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
		global_position += velocity * delta
		return

	_update_shield(delta)

	if control_enabled:
		_poll_input()

	# 瞄准时每帧重算隐形球的 3 秒轨迹（立刻跟着鼠标走，不拖帧）
	if mode == Mode.AIMING:
		_rebuild_guide()
	else:
		guide_path.clear()

	if mode == Mode.FLYING or mode == Mode.AIMING:
		global_position += velocity * delta
		_bounce_walls()
		_resolve_obstacles()
		if mode == Mode.FLYING:
			velocity = velocity.move_toward(Vector2.ZERO, CFG.FLY_FRICTION * delta)
			if velocity.length() < CFG.SETTLE_SPEED:
				velocity = Vector2.ZERO
				mode = Mode.IDLE
				_denied = false
		_sample_trail()
	else:
		if not trail.is_empty():
			trail.pop_back()

	# 停死：速度归零 + 变向次数归零 → 球体开始从内部裂开
	if alive and not dropping and not cracked:
		var stalled := mode != Mode.FLYING and velocity.length() < 1.0 and charges <= 0
		if stalled:
			crack_t = minf(1.0, crack_t + field_dt / CFG.CRACK_TIME)
			if crack_t >= 1.0:
				_break_apart()
		elif crack_t > 0.0:
			crack_t = maxf(0.0, crack_t - field_dt * 2.5)

	_check_boss_contact()


# ---------------------------------------------------------------------
# 输入：按下抓球 / 拖动瞄准 / 松开发射
# ---------------------------------------------------------------------
func _poll_input() -> void:
	var mouse := get_global_mouse_position()
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	# 右键：盾球按住维持护盾；虫球按住把世界压到 0.05 倍
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if is_bug:
		slow_field_held = rmb
		if not rmb:
			slow_exhausted = false
	else:
		shield_hold = rmb
		if rmb and not _rmb_prev:
			open_shield()
	_rmb_prev = rmb

	if mode == Mode.AIMING:
		update_aim(mouse)
		if not down:
			release_aim()
		_denied = false
	elif mode == Mode.FLYING:
		if down:
			if not _denied and not try_catch(mouse):
				_denied = true
		else:
			_denied = false
	else:
		# 停稳时也实时显示矢量箭头，方便先瞄再按
		update_aim(mouse)
		if down and not _denied:
			if not try_catch(mouse):
				_denied = true
		if not down:
			_denied = false


## 尝试抓住球。滞空时没有变向次数就抓不住（会闪红提示）。
func try_catch(pos: Vector2) -> bool:
	if not alive:
		return false
	if mode == Mode.AIMING:
		return true
	if mode == Mode.FLYING and charges <= 0:
		deny_flash = 1.0
		return false
	begin_aim(pos)
	return true


func begin_aim(pos: Vector2) -> void:
	# 变向不再把球停住：保留当前速度，瞄准期间球照常飞（只是世界慢下来）
	_catch = mode == Mode.FLYING
	_prev_velocity = velocity
	mode = Mode.AIMING
	update_aim(pos)


## 运动矢量永远以「球心」为起点：方向 = 球 → 鼠标，力度 = 两者距离。
## 所以鼠标一动，箭头就实时跟着变。
func update_aim(pos: Vector2) -> void:
	aim_point = pos
	drag_vec = pos - global_position
	var l := drag_vec.length()
	power = clampf(l / CFG.DRAG_MAX, 0.0, 1.0)
	if l > 1.0:
		aim = drag_vec / l


## 松手：拖动距离决定速度，拖动方向决定方向。
## 拖得太短视为取消（滞空抓下来的会恢复原来的速度）。
func release_aim() -> void:
	guide_path.clear()   # 发射时删掉上一条轨迹
	var l := drag_vec.length()
	if l < CFG.DRAG_DEADZONE:
		power = 0.0
		_catch = false
		# 取消时不改速度，按当前速度继续飞
		if velocity.length() < CFG.SETTLE_SPEED:
			velocity = Vector2.ZERO
			mode = Mode.IDLE
		else:
			mode = Mode.FLYING
		return

	if _catch:
		charges = maxi(charges - 1, 0)
	else:
		charges = CFG.AIR_CHANGE_BASE

	power = clampf(l / CFG.DRAG_MAX, 0.0, 1.0)
	aim = drag_vec.normalized()
	var spd := lerpf(CFG.LAUNCH_MIN_SPEED, CFG.LAUNCH_MAX_SPEED, power) * speed_scale() * max_speed_bonus()
	# 限速生效时压一下出膛速度
	if slow_cap_timer > 0.0:
		spd = minf(spd, CFG.LAUNCH_MAX_SPEED * speed_scale() * max_speed_bonus() * speed_cap)
	velocity = aim * spd
	mode = Mode.FLYING
	_catch = false
	launched.emit(power)


# ---------------------------------------------------------------------
# 空中物理
# ---------------------------------------------------------------------
func _bounce_walls() -> void:
	var r := radius
	var a := CFG.ARENA
	var normal := Vector2.ZERO

	if global_position.x < a.position.x + r:
		global_position.x = a.position.x + r
		velocity.x = absf(velocity.x) * _wall_damp()
		normal = Vector2.RIGHT
	elif global_position.x > a.end.x - r:
		global_position.x = a.end.x - r
		velocity.x = -absf(velocity.x) * _wall_damp()
		normal = Vector2.LEFT

	if global_position.y < a.position.y + r:
		global_position.y = a.position.y + r
		velocity.y = absf(velocity.y) * _wall_damp()
		normal = Vector2.DOWN
	elif global_position.y > a.end.y - r:
		global_position.y = a.end.y - r
		velocity.y = -absf(velocity.y) * _wall_damp()
		normal = Vector2.UP

	if normal != Vector2.ZERO:
		# 撞墙储存一次变向机会
		charges = mini(charges + 1, max_charges)
		_register_bump()
		bounced.emit(global_position, normal)


## 撞击障碍物：推出去 + 按法线反弹 + 储存 1 次变向
func _resolve_obstacles() -> void:
	for o in obstacles:
		if not is_instance_valid(o):
			continue
		var info: Dictionary = o.collide_circle(global_position - o.global_position, radius)
		if not info["hit"]:
			continue
		var n: Vector2 = info["normal"]
		global_position += n * (float(info["depth"]) + 0.5)
		var vn := velocity.dot(n)
		if vn < 0.0:
			velocity -= (1.0 + _wall_damp()) * vn * n
		charges = mini(charges + 1, max_charges)
		_register_bump()
		bounced.emit(global_position, n)
		return


## Boss2 的撞击惩罚：弹开 + 减速 25% + 3 秒内极速压到 50%
func apply_boss_slow() -> void:
	velocity *= CFG.BOSS2_SLOW_FACTOR
	slow_cap_timer = CFG.BOSS2_CAP_TIME
	speed_cap = CFG.BOSS2_SPEED_CAP


## 通用限速：把极速压到 factor 倍，持续 time 秒（取更严的那个）
func apply_speed_cap(factor: float, time: float) -> void:
	slow_cap_timer = maxf(slow_cap_timer, time)
	speed_cap = minf(speed_cap, factor)


## 撞击判定用「持续重叠检测」而不是只靠 area_entered：
## 否则玩家贴着 Boss 站着时不会再次触发进入事件，会出现撞不出伤害的情况。
func _check_boss_contact() -> void:
	if not alive or contact_lock > 0.0:
		return
	for area in get_overlapping_areas():
		if not area.is_in_group("boss"):
			continue
		if area.has_method("try_ram"):
			area.try_ram()
		var n := global_position - area.global_position
		if n.length() < 0.01:
			n = -velocity if velocity != Vector2.ZERO else Vector2.DOWN
		n = n.normalized()
		# 每块敌人可能有自己的接触半径（Boss2 的护盾板比本体小）
		var br: Variant = area.get("body_radius")
		var boss_r: float = float(br) if br != null else CFG.BOSS_RADIUS
		global_position = area.global_position + n * (boss_r + radius + 2.0)
		var spd := maxf(velocity.length(), CFG.LAUNCH_MIN_SPEED)
		velocity = n * spd * _ram_damp()
		mode = Mode.FLYING
		_catch = false
		power = 0.0
		charges = mini(charges + 1, max_charges)
		contact_lock = 0.12
		_register_bump()
		if area.is_in_group("boss2"):
			apply_boss_slow()
		if is_bug and tier >= CFG.BUG_MAX_TIER:
			_bug_rush()
			tore_at.emit(global_position - n * radius, n)
		bounced.emit(global_position, n)
		return


func _sample_trail() -> void:
	if velocity.length() > 160.0:
		trail.push_front(global_position)
		if trail.size() > TRAIL_MAX:
			trail.resize(16)
	elif not trail.is_empty():
		trail.pop_back()


# ---------------------------------------------------------------------
# 受击
# ---------------------------------------------------------------------
## from_pos 是子弹的位置。护盾开着时一律挡下（返回 true 让子弹消失），
## 是否掉血取决于护盾是否开启。
func take_hit(from_pos: Vector2) -> bool:
	if not alive:
		return false
	if shield_active:
		_absorb_body(from_pos)
		return true
	if invuln > 0.0:
		return false
	invuln = CFG.PLAYER_IFRAME
	flash = 1.0

	# 虫球满级：0.5 抗伤护盾，每 6 秒回一次
	var dmg := 1.0
	if is_bug and tier >= CFG.BUG_MAX_TIER and bug_shield_ready:
		bug_shield_ready = false
		bug_shield_cd = CFG.BUG_SHIELD_CD
		dmg = maxf(0.0, 1.0 - CFG.BUG_SHIELD_ABSORB)
		shield_absorbed.emit(3, global_position)
	hp -= dmg

	velocity += (global_position - from_pos).normalized() * 160.0
	emit_signal("damaged", hp)
	if hp <= 0.0:
		alive = false
		control_enabled = false
		mode = Mode.IDLE
		velocity = Vector2.ZERO
		shield_active = false
		emit_signal("died")
	return true


## 停死判负：球体从内部碎裂
func _break_apart() -> void:
	if not alive:
		return
	alive = false
	cracked = true
	control_enabled = false
	mode = Mode.IDLE
	velocity = Vector2.ZERO
	shield_active = false
	shield_hold = false
	slow_field_held = false
	crack_t = 1.0
	emit_signal("died")


func _on_area_entered(area: Area2D) -> void:
	if not alive:
		return
	if area.is_in_group("bullet"):
		if take_hit(area.global_position):
			if area.has_method("pop"):
				area.pop()


# ---------------------------------------------------------------------
# 开发 / 截图用
# ---------------------------------------------------------------------
func debug_launch(dir: Vector2, speed: float) -> void:
	control_enabled = false
	velocity = dir.normalized() * speed
	mode = Mode.FLYING
	_catch = false
	power = 0.0


func debug_aim_at(origin: Vector2, target: Vector2) -> void:
	control_enabled = false
	begin_aim(origin)
	update_aim(target)


# ---------------------------------------------------------------------
# 轨迹预测：到墙就反弹，最多 3 段
# ---------------------------------------------------------------------
func predict_path() -> PackedVector2Array:
	if power <= 0.02:
		return PackedVector2Array()
	return _trace(global_position, aim, radius)


## 从 start 沿 dir 走，遇墙 / 障碍反弹，最多 3 段
## inset = 这条线离场地边界要留多少（中心线留球半径）
func _trace(start: Vector2, dir: Vector2, inset: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var pos := start
	var rect := CFG.ARENA.grow(-inset)
	pts.append(pos)
	for i in 3:
		var t_hit := INF
		var normal := Vector2.ZERO
		if dir.x > 0.0001:
			t_hit = (rect.end.x - pos.x) / dir.x
			normal = Vector2.LEFT
		elif dir.x < -0.0001:
			t_hit = (rect.position.x - pos.x) / dir.x
			normal = Vector2.RIGHT
		if dir.y > 0.0001:
			var ty := (rect.end.y - pos.y) / dir.y
			if ty < t_hit:
				t_hit = ty
				normal = Vector2.UP
		elif dir.y < -0.0001:
			var ty2 := (rect.position.y - pos.y) / dir.y
			if ty2 < t_hit:
				t_hit = ty2
				normal = Vector2.DOWN

		# 障碍物也参与预测：打出反弹线才对得上实际弹道
		for o in obstacles:
			if not is_instance_valid(o):
				continue
			var rh: Dictionary = o.raycast(pos, dir, t_hit)
			if rh["hit"]:
				normal = rh["normal"]
				# 圆的边缘贴墙时，圆心还差 inset / |cosθ|（θ = 入射角），斜着撞会提前更多
				var cos_hit := maxf(absf(dir.dot(normal)), 0.25)
				t_hit = maxf(0.0, float(rh["dist"]) - inset / cos_hit)

		if t_hit == INF or t_hit < 0.0:
			break
		var hitp := pos + dir * t_hit
		pts.append(hitp)
		pos = hitp
		dir = dir.bounce(normal)
	return pts


# ---------------------------------------------------------------------
# 绘制：全部用圆和线，无贴图依赖
# ---------------------------------------------------------------------
func _draw() -> void:
	var r := radius
	var a := 1.0
	if invuln > 0.0 and invuln < 5.0 and alive:
		a = 0.42 if int(t * 22.0) % 2 == 0 else 1.0

	if not alive:
		if cracked:
			_draw_corpse(r)
		else:
			draw_circle(Vector2.ZERO, r * 0.9, Color(0.35, 0.42, 0.5, 0.25))
			draw_circle(Vector2.ZERO, r * 0.5, Color(0.5, 0.56, 0.64, 0.25))
		return

	if mode != Mode.FLYING:
		_draw_aim(r, 1.0 if mode == Mode.AIMING else 0.40, mode == Mode.AIMING)

	# 空投阴影：贴在复活点，落地时消失
	if dropping:
		var p := drop_t
		var sr := r * (1.10 + 0.90 * p)
		var sa := (0.22 + 0.30 * p) * (1.0 - smoothstep(0.80, 1.0, p))
		draw_circle(Vector2(0.0, r * 0.14), sr, Color(0.0, 0.0, 0.0, sa))

	# 尾迹：一段段递减宽度，画出彗尾的感觉
	var n := trail.size()
	if n >= 2:
		for i in n - 1:
			var k := 1.0 - float(i) / float(n - 1)
			draw_line(to_local(trail[i]), to_local(trail[i + 1]),
				Color(CFG.COL_PLAYER, TRAIL_ALPHA * k * a), TRAIL_INNER + TRAIL_OUTER * k, true)

	# 高速时加几道速度线
	if mode == Mode.FLYING and velocity.length() > SPEEDLINE_SPEED:
		var back := -velocity.normalized()
		var side := velocity.orthogonal().normalized()
		for i in SPEEDLINE_COUNT:
			var off := side * (float(i) - 1.0) * SPEEDLINE_SPREAD
			draw_line(back * (r * 1.5) + off, back * (r * 3.3 + float(i) * 6.0) + off,
				Color(CFG.COL_PLAYER, 0.14 * a), 2.0, true)

	# 空投时球被"抬高"：向上偏移 + 放大，做出伪立体
	var body_scale := 1.0 + drop_h * DROP_GROW
	draw_set_transform(Vector2(0.0, -drop_h), 0.0, Vector2(body_scale, body_scale))

	# 光晕
	for i in GLOW_LAYERS:
		draw_circle(Vector2.ZERO, r * (GLOW_BASE - GLOW_STEP * i), Color(CFG.COL_PLAYER, GLOW_ALPHA * a))

	# 球体（有手绘素材就用图片，没有就用代码画的圆）
	var squish := 1.0 + minf(velocity.length() / SQUISH_SPEED, SQUISH_MAX)
	var rr := r * squish
	if not Skins.blit(self, "player_body", Rect2(-rr, -rr, rr * 2.0, rr * 2.0), 0.0):
		draw_circle(Vector2.ZERO, rr, Color(CFG.COL_PLAYER, 0.95 * a))
		draw_circle(Vector2.ZERO, r * 0.54, Color(CFG.COL_PLAYER_CORE, 0.92 * a))


	# 眼（指向速度方向；停住时指向鼠标）
	var look := aim
	if mode != Mode.AIMING and velocity.length() > 40.0:
		look = velocity.normalized()
	var eye_name := "player_eye" if char_id == 0 else "player_eye_%d" % char_id
	if _draw_eye_sprite(eye_name, r, look, body_scale):
		pass
	elif char_id == 2:
		_draw_compound_eye(r, look, a)
	elif char_id == 1:
		_draw_mech_eye(r, look, a)
	else:
		draw_circle(look * r * EYE_OFFSET, r * EYE_R, Color(0.02, 0.05, 0.08, 0.88 * a))
		draw_circle(look * r * EYE_OFFSET - look * r * EYE_HL_OFFSET, r * EYE_HL_R,
			Color(1, 1, 1, 0.75 * a))

	# 虫球：慢放场
	if is_slow_field():
		var field_pulse := 0.5 + 0.5 * sin(t * 2.0)
		for k in 3:
			draw_arc(Vector2.ZERO, r * (2.3 + float(k) * 0.85 + field_pulse * 0.18), 0.0, TAU, 64,
				Color(0.55, 0.86, 0.96, 0.12 - 0.025 * float(k)), 1.0, true)

	# 停死：球体从内部裂开
	if crack_t > 0.0:
		_draw_cracks(r, a)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 护盾
	if shield_enabled:
		_draw_shield(r, a)

	# 虫球：五格进化条
	if is_bug:
		_draw_bug_bar(r, a)

	# 停稳时：可再次发射的呼吸环
	if mode == Mode.IDLE and not dropping:
		var pulse := 0.5 + 0.5 * sin(t * 3.2)
		draw_arc(Vector2.ZERO, r * SETTLE_RING_R + pulse * SETTLE_RING_PULSE, 0.0, TAU, 48,
			Color(CFG.COL_PLAYER, 0.16 + 0.12 * pulse), 1.5, true)

	# 空中变向次数
	if mode == Mode.FLYING:
		for i in charges:
			var x := (float(i) - float(charges - 1) * 0.5) * 13.0
			draw_circle(Vector2(x, r + 14.0), 3.0, Color(CFG.COL_PLAYER, 0.75 * a))

	# 残血警告环
	if hp <= 1.0:
		var pulse2 := 0.5 + 0.5 * sin(t * 6.0)
		draw_arc(Vector2.ZERO, r * 1.55, 0.0, TAU, 40,
			Color(CFG.COL_DANGER, 0.35 + 0.35 * pulse2), 1.6, true)

	# Boss2 减速惩罚：蓝色虚环
	if slow_cap_timer > 0.0:
		var k := clampf(slow_cap_timer / CFG.BOSS2_CAP_TIME, 0.0, 1.0)
		var seg := 12
		for i in seg:
			var a0 := TAU * float(i) / float(seg) + t * 0.6
			draw_arc(Vector2.ZERO, r * 1.75, a0, a0 + 0.28, 8,
				Color(0.45, 0.68, 1.0, 0.30 + 0.25 * k), 2.0, true)

	if deny_flash > 0.0:
		draw_arc(Vector2.ZERO, r * 1.9, 0.0, TAU, 40, Color(CFG.COL_DANGER, 0.8 * deny_flash), 2.5, true)

	if flash > 0.0:
		draw_circle(Vector2.ZERO, r * 1.1, Color(1, 1, 1, 0.45 * flash))


## 盾球的机械眼：长方形眼窝 + 绿色方形瞳孔
func _draw_mech_eye(r: float, look: Vector2, a: float) -> void:
	var c := look * r * 0.26
	var w := r * 1.15
	var h := r * 0.54
	var socket := Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h)
	draw_rect(socket, Color(0.03, 0.07, 0.06, 0.92 * a), true)
	draw_rect(socket, Color(0.42, 0.95, 0.70, 0.45 * a), false, 1.2)
	# 两侧散热槽
	draw_line(Vector2(socket.position.x - r * 0.20, c.y), Vector2(socket.position.x - r * 0.06, c.y),
		Color(0.42, 0.95, 0.70, 0.30 * a), 1.5)
	draw_line(Vector2(socket.end.x + r * 0.06, c.y), Vector2(socket.end.x + r * 0.20, c.y),
		Color(0.42, 0.95, 0.70, 0.30 * a), 1.5)
	# 绿色方形瞳孔
	var ps := r * 0.30
	var pupil := Rect2(
		c.x - ps * 0.5 + look.x * r * 0.18,
		c.y - ps * 0.5 + look.y * r * 0.18,
		ps, ps)
	draw_rect(pupil, Color(0.36, 1.0, 0.62, 0.95 * a), true)
	draw_rect(pupil, Color(0.80, 1.0, 0.88, 0.85 * a), false, 1.0)


## 护盾：扇形指示 + 球壳 + 球下方的充能条
func _draw_shield(r: float, a: float) -> void:
	var st := shield_stage()
	var vis := a

	# 扇形指示：按下就出现轮廓，0.3 秒后才着色（二阶段缩到 0.8×）
	if st >= 0:
		var colored := st >= 1
		var col := shield_stage_color() if colored else Color(0.56, 0.80, 0.74)
		var mul := 1.0 if colored else 0.55
		var rad := fan_radius()
		var half := fan_half_angle()
		var seg := 14
		var poly := PackedVector2Array()
		var arc := PackedVector2Array()
		poly.append(Vector2.ZERO)
		for i in seg + 1:
			var ang := fan_dir.angle() - half + 2.0 * half * float(i) / float(seg)
			var p := Vector2.from_angle(ang) * rad
			poly.append(p)
			arc.append(p)
		if colored:
			draw_colored_polygon(poly, Color(col, 0.17 + 0.13 * shield_flash))
		# 弧面就是护盾本体，画粗一点
		draw_polyline(arc, Color(col, 0.85 * vis * mul), 5.0, true)
		draw_polyline(arc, Color(col, 0.22 * vis * mul), 11.0, true)
		draw_line(Vector2.ZERO, arc[0], Color(col, 0.32 * vis * mul), 1.2, true)
		draw_line(Vector2.ZERO, arc[arc.size() - 1], Color(col, 0.32 * vis * mul), 1.2, true)

	# 护盾球壳
	if shield_active:
		var col2 := shield_stage_color()
		draw_arc(Vector2.ZERO, r * 2.05, 0.0, TAU, 56,
			Color(col2, 0.45 + 0.4 * shield_flash), 2.0, true)
		draw_arc(Vector2.ZERO, r * 1.92, 0.0, TAU, 56, Color(col2, 0.18), 1.0, true)

	# 球体下方的充能条（简约风格，绿色）
	var bw := 46.0
	var bh := 4.0
	var base := Rect2(-bw * 0.5, r + 26.0, bw, bh)
	draw_rect(base, Color(0.06, 0.10, 0.09, 0.85), true)
	var k := clampf(shield_charge / CFG.SHIELD_DURATION, 0.0, 1.0)
	var bar_col := Color(0.37, 0.95, 0.62) if shield_active else Color(0.30, 0.62, 0.50)
	if k > 0.01:
		draw_rect(Rect2(base.position.x, base.position.y, bw * k, bh), bar_col, true)
	draw_rect(base, Color(0.45, 0.85, 0.70, 0.35), false, 1.0)

	# 还能扛几发
	for i in CFG.SHIELD_SHOTS:
		var px := -18.0 + float(i) * 12.0
		var py := r + 37.0
		if i < shield_shots:
			draw_circle(Vector2(px, py), 3.0, Color(0.78, 0.98, 0.86, 0.9))
		else:
			draw_arc(Vector2(px, py), 2.6, 0.0, TAU, 10, Color(0.45, 0.60, 0.55, 0.35), 1.0)


## 碎裂后的残骸
func _draw_corpse(r: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in CORPSE_FRAGMENTS:
		var ang := TAU * float(i) / float(CORPSE_FRAGMENTS) + rng.randf_range(-0.22, 0.22)
		var d := r * (0.45 + rng.randf_range(0.0, 1.7))
		var sz := r * rng.randf_range(0.10, 0.23)
		draw_rect(Rect2(Vector2.from_angle(ang) * d - Vector2(sz, sz) * 0.5,
			Vector2(sz, sz)), Color(0.74, 0.85, 0.93, 0.42))
	draw_arc(Vector2.ZERO, r * 0.72, 0.0, TAU, 26, Color(1.0, 0.36, 0.30, 0.22), 1.6, true)
	draw_circle(Vector2.ZERO, r * 0.22, Color(0.30, 0.36, 0.42, 0.30))


## 停死裂纹：越接近碎裂，裂缝越多、越亮，还有碎块往外飘
func _draw_cracks(r: float, a: float) -> void:
	var k := clampf(crack_t, 0.0, 1.0)
	# 内部红光
	draw_circle(Vector2.ZERO, r * (0.55 + 0.45 * k), Color(1.0, 0.28, 0.24, 0.18 + 0.30 * k))
	draw_arc(Vector2.ZERO, r * 1.02, 0.0, TAU, 40,
		Color(1.0, 0.32, 0.26, 0.25 + 0.55 * k), 1.6 + 1.6 * k, true)

	# 裂缝：数量随进度增长
	var count := int(round(float(CRACK_LINES_MIN) + k * float(CRACK_LINES_MAX - CRACK_LINES_MIN)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	for i in count:
		var base := TAU * float(i) / float(maxi(count, 1)) + rng.randf_range(-0.3, 0.3)
		var pts := PackedVector2Array()
		var dist := r * 0.06
		var ang := base
		pts.append(Vector2.from_angle(ang) * dist)
		for seg in 3:
			dist += r * (0.30 + 0.05 * float(seg))
			ang += rng.randf_range(-0.34, 0.34)
			pts.append(Vector2.from_angle(ang) * minf(dist, r * 1.02))
		draw_polyline(pts, Color(0.03, 0.02, 0.03, 0.80), 1.2 + 1.4 * k, true)
		draw_polyline(pts, Color(1.0, 0.42, 0.34, 0.35 + 0.45 * k), 0.8 + 0.6 * k, true)

	# 碎块：随进度向外飘
	for i in CRACK_FRAGMENTS:
		var ang2 := TAU * float(i) / 5.0 + 0.6
		var d := r * (0.4 + 1.5 * k)
		var sz := r * 0.13 * (1.0 - 0.4 * k)
		draw_rect(Rect2(Vector2.from_angle(ang2) * d - Vector2(sz, sz) * 0.5,
			Vector2(sz, sz)), Color(0.75, 0.86, 0.92, 0.35 + 0.35 * k))


## 有手绘眼睛素材就画图片（素材朝右画，这里按 look 旋转），返回 true
func _draw_eye_sprite(name: String, r: float, look: Vector2, bs: float) -> bool:
	var tex := Skins.tex(name)
	if tex == null:
		return false
	var drop_pos := Vector2(0.0, -drop_h)
	var off := look * r * EYE_OFFSET
	var er := r * EYE_R
	draw_set_transform(drop_pos + off * bs, look.angle(), Vector2(bs, bs))
	draw_texture_rect(tex, Rect2(-er, -er, er * 2.0, er * 2.0), false)
	draw_set_transform(drop_pos, 0.0, Vector2(bs, bs))
	return true


func _draw_compound_eye(r: float, look: Vector2, a: float) -> void:
	var c := look * r * 0.30
	draw_circle(c, r * 0.58, Color(0.03, 0.07, 0.09, 0.85 * a))
	var lens := r * 0.17
	for i in 6:
		var ang := TAU * float(i) / 6.0 + 0.3
		var p := c + Vector2.from_angle(ang) * r * 0.30
		draw_circle(p, lens, Color(0.10, 0.24, 0.28, 0.92 * a))
		draw_circle(p - Vector2(lens * 0.32, lens * 0.32), lens * 0.45,
			Color(0.60, 0.98, 1.0, 0.55 * a))
	draw_circle(c, lens * 1.08, Color(0.13, 0.28, 0.32, 0.95 * a))
	draw_circle(c - Vector2(lens * 0.34, lens * 0.34), lens * 0.48,
		Color(0.66, 1.0, 1.0, 0.6 * a))


## 绿 → 紫 的五格进化条
func _draw_bug_bar(r: float, a: float) -> void:
	var n := CFG.BUG_MAX_TIER
	var cw := 9.0
	var gap := 2.0
	var total := float(n) * cw + float(n - 1) * gap
	var y := r + 24.0
	var x0 := -total * 0.5
	for i in n:
		var rect := Rect2(x0 + float(i) * (cw + gap), y, cw, 5.0)
		draw_rect(rect, Color(0.06, 0.09, 0.09, 0.85), true)
		var fill := 0.0
		if i < tier:
			fill = 1.0
		elif i == tier:
			fill = float(tier_hits) / float(CFG.BUG_HITS_PER_TIER)
		if fill > 0.01:
			var t := float(i) / float(maxi(1, n - 1))
			var col := Color(0.35, 0.95, 0.55).lerp(Color(0.72, 0.35, 0.95), t)
			draw_rect(Rect2(rect.position, Vector2(cw * fill, rect.size.y)), Color(col, a), true)
		if i < tier:
			draw_rect(rect, Color(1, 1, 1, 0.28 * a), false, 1.0)
	# 满级：整条发亮
	if tier >= CFG.BUG_MAX_TIER:
		var glow := 0.35 + 0.25 * sin(t * 5.0)
		draw_rect(Rect2(x0 - 3.0, y - 3.0, total + 6.0, 11.0),
			Color(0.80, 0.55, 1.0, glow * a), false, 1.2)

	# 慢放场充能条（细的一条，压在最下面）
	var sw := 40.0
	var sy := y + 9.0
	draw_rect(Rect2(-sw * 0.5, sy, sw, 3.0), Color(0.06, 0.09, 0.10, 0.85), true)
	var sk := clampf(slow_charge / slow_field_max(), 0.0, 1.0)
	if sk > 0.01:
		var scol := Color(0.35, 0.50, 0.58) if slow_exhausted else Color(0.45, 0.88, 0.98)
		draw_rect(Rect2(-sw * 0.5, sy, sw * sk, 3.0), Color(scol, a), true)


func _draw_aim(r: float, strength: float, show_path: bool) -> void:
	if power <= 0.02:
		return
	# 引导拖尾：隐形球模拟出来的轨迹
	if show_path:
		_draw_guide_trail(strength)

	# 球心 → 鼠标 的矢量线（这就是发射矢量本身）
	var dist := drag_vec.length()
	draw_line(Vector2.ZERO, aim * dist, Color(CFG.COL_ACCENT, 0.20 * strength), 1.0)

	# 满力刻度：越过这条刻度，力度不再增加
	if show_path:
		var tick := aim * CFG.DRAG_MAX
		var side_tick := aim.orthogonal() * 6.0
		draw_line(tick - side_tick, tick + side_tick, Color(CFG.COL_ACCENT, 0.35 * strength), 1.5)

	# 发射箭头：长度即力度
	var arrow_len := 44.0 + 122.0 * power
	var tip := aim * (r + arrow_len)
	draw_line(aim * (r + 7.0), tip, Color(CFG.COL_PLAYER, 0.85 * strength), 3.0, true)
	var side := aim.orthogonal() * 8.0
	var back := tip - aim * 15.0
	draw_line(tip, back + side, Color(CFG.COL_PLAYER, 0.85 * strength), 3.0, true)
	draw_line(tip, back - side, Color(CFG.COL_PLAYER, 0.85 * strength), 3.0, true)

	# 力度环
	draw_arc(Vector2.ZERO, r * 1.75, -PI * 0.5, -PI * 0.5 + TAU * power, 48,
		Color(CFG.COL_PLAYER, 0.75 * strength), 3.0, true)

	# 抓住状态的外环
	draw_arc(Vector2.ZERO, r * 1.35, 0.0, TAU, 40, Color(CFG.COL_ACCENT, 0.35 * strength), 1.2, true)


## 引导拖尾：在球心放一个"隐形球"，数值和真球完全一样，直接往前模拟 3 秒，
## 把轨迹画成拖尾。每帧重算一次，松手就清掉。
const GUIDE_TIME := 1.5          # 模拟多久（战场秒）
const GUIDE_STEP := 1.0 / 60.0   # 模拟步长（秒）
const GUIDE_REC_EVERY := 2       # 每几步记一个点（控制点数）

var guide_path: PackedVector2Array = []   # 隐形球的轨迹（世界坐标）
var guide_end := Vector2.ZERO             # 3 秒后隐形球在哪


func _rebuild_guide() -> void:
	guide_path.clear()
	guide_end = global_position
	if power <= 0.02:
		return
	# 出膛速度和真球走同一套公式（含角色倍率与被限速的情况）
	var spd := lerpf(CFG.LAUNCH_MIN_SPEED, CFG.LAUNCH_MAX_SPEED, power) * speed_scale() * max_speed_bonus()
	if slow_cap_timer > 0.0:
		spd = minf(spd, CFG.LAUNCH_MAX_SPEED * speed_scale() * max_speed_bonus() * speed_cap)
	var pos := global_position
	var vel := aim * spd
	var damp := _wall_damp()
	var rr := radius
	var area := CFG.ARENA
	guide_path.append(pos)

	var steps := int(GUIDE_TIME / GUIDE_STEP)
	# 壁的盾牌 / 本体也算障碍：隐形球撞上去要像真球一样弹开
	var shields: Array = []
	for nd in get_tree().get_nodes_in_group("boss2"):
		if is_instance_valid(nd) and nd.get("body_radius") != null and nd.get("active") != false:
			shields.append(nd)
	for i in steps:
		pos += vel * GUIDE_STEP
		# 撞墙：和 _bounce_walls 同一套反射
		if pos.x < area.position.x + rr:
			pos.x = area.position.x + rr
			vel.x = absf(vel.x) * damp
		elif pos.x > area.end.x - rr:
			pos.x = area.end.x - rr
			vel.x = -absf(vel.x) * damp
		if pos.y < area.position.y + rr:
			pos.y = area.position.y + rr
			vel.y = absf(vel.y) * damp
		elif pos.y > area.end.y - rr:
			pos.y = area.end.y - rr
			vel.y = -absf(vel.y) * damp
		# 撞 Boss2 的盾牌 / 本体（圆 vs 圆）
		for s in shields:
			if not is_instance_valid(s):
				continue
			var br := float(s.get("body_radius"))
			var dv: Vector2 = pos - s.global_position
			var dd := dv.length()
			if dd < br + rr and dd > 0.001:
				var sn := dv / dd
				pos = s.global_position + sn * (br + rr + 0.5)
				var svn := vel.dot(sn)
				if svn < 0.0:
					vel -= (1.0 + damp) * svn * sn
		# 撞障碍：和 _resolve_obstacles 同一套解算
		for o in obstacles:
			if not is_instance_valid(o):
				continue
			var info: Dictionary = o.collide_circle(pos - o.global_position, rr)
			if not info["hit"]:
				continue
			var n: Vector2 = info["normal"]
			pos += n * (float(info["depth"]) + 0.5)
			var vn := vel.dot(n)
			if vn < 0.0:
				vel -= (1.0 + damp) * vn * n
		# 摩擦
		vel = vel.move_toward(Vector2.ZERO, CFG.FLY_FRICTION * GUIDE_STEP)
		if i % GUIDE_REC_EVERY == 0:
			guide_path.append(pos)
		if vel.length() < CFG.SETTLE_SPEED:
			break
	guide_path.append(pos)
	guide_end = pos


## 画拖尾：从球心的粗实，逐渐变细变淡（拐角处补圆点避免断裂）
func _draw_guide_trail(strength: float) -> void:
	var n := guide_path.size()
	if n < 2:
		return
	for i in n - 1:
		var t := float(i) / float(n - 1)
		var w := lerpf(radius * 2.0, radius * 0.8, t)
		var col := Color(0.55, 0.88, 1.0, lerpf(0.42, 0.05, t) * strength)
		draw_line(to_local(guide_path[i]), to_local(guide_path[i + 1]), col, w, false)
	# 只在真正的拐角补圆，直线上不重复叠画
	for i in range(1, n - 1):
		var d0 := (guide_path[i] - guide_path[i - 1]).normalized()
		var d1 := (guide_path[i + 1] - guide_path[i]).normalized()
		if d0.dot(d1) < 0.985:
			var t := float(i) / float(n - 1)
			draw_circle(to_local(guide_path[i]), lerpf(radius, radius * 0.4, t),
				Color(0.55, 0.88, 1.0, lerpf(0.42, 0.05, t) * strength))

func _dashed(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var a := to_local(from)
	var b := to_local(to)
	var d := b - a
	var length := d.length()
	if length < 0.5:
		return
	var dir := d / length
	var seg := 9.0
	var gap := 7.0
	var s := 0.0
	while s < length:
		var e := minf(s + seg, length)
		draw_line(a + dir * s, a + dir * e, color, width, true)
		s += seg + gap
