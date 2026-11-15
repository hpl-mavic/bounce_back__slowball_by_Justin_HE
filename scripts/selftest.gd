extends RefCounted
## 机制自检：从 main.gd 拆出来的独立模块（headless 也能跑）
## 用法：SELF_TEST.new(main).run()

const CFG := preload("res://scripts/config.gd")  # 全局数值表（所有可调参数都在那）
const I18N := preload("res://scripts/i18n.gd")
const Skins := preload("res://scripts/skins.gd")

var g: Node            # 指向 Main，测试通过它读写游戏状态


func _init(game: Node) -> void:
	g = game

func _wait(frames: int) -> void:
	# 用物理帧：headless 下进程帧可能跑得比物理帧快得多，等物理帧才和 delta 对得上
	for i in frames:
		await g.get_tree().physics_frame


func _check(fails: int, label: String, ok: bool) -> int:
	if ok:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
	return fails + (0 if ok else 1)

func run() -> void:
	var fails := 0
	g.boss_stage = 1
	g.character = 0
	g.skip_drop = true
	print("===== SLOWBALL SELFTEST =====")

	# 1. 难度只改主角血量，Boss 不变
	for i in 3:
		g.start_game(i)
		var want_hp: int = CFG.DIFFICULTIES[i]["hp"]
		fails = _check(fails, "难度[%s] 主角血量 = %d" % [CFG.DIFFICULTIES[i]["name"], g.player.max_hp],
			g.player.max_hp == want_hp and g.player.hp == want_hp)
		fails = _check(fails, "难度[%s] Boss 仍是 3 血" % CFG.DIFFICULTIES[i]["name"],
			g.boss.hp == 3 and g.boss.max_hp == 3)
		await _wait(2)

	# 2. 发射：方向 = 拖动方向，速度 = 拖动距离
	g.start_game(1)
	g.player.control_enabled = false
	var origin := Vector2(640.0, 500.0)
	g.player.global_position = origin
	g.player.begin_aim(origin)
	g.player.update_aim(origin + Vector2(0.0, CFG.DRAG_MAX))
	g.player.release_aim()
	fails = _check(fails, "满力下拖 → 球向下飞", g.player.velocity.normalized().y > 0.99)
	fails = _check(fails, "满力 → 最高速 %.0f（实测 %.0f）" % [CFG.LAUNCH_MAX_SPEED, g.player.velocity.length()],
		absf(g.player.velocity.length() - CFG.LAUNCH_MAX_SPEED) < 1.0)

	g.player.reset_to_idle()
	g.player.begin_aim(origin)
	g.player.update_aim(origin + Vector2(CFG.DRAG_MAX * 0.5, 0.0))
	g.player.release_aim()
	var half_speed: float = g.player.velocity.length()
	var want_half: float = lerpf(CFG.LAUNCH_MIN_SPEED, CFG.LAUNCH_MAX_SPEED, 0.5)
	fails = _check(fails, "半程拖动 → 半力 %.0f（实测 %.0f）" % [want_half, half_speed],
		absf(half_speed - want_half) < 2.0)

	g.player.reset_to_idle()
	g.player.begin_aim(origin)
	g.player.update_aim(origin + Vector2(CFG.DRAG_DEADZONE * 0.5, 0.0))
	g.player.release_aim()
	fails = _check(fails, "拖动小于死区 → 取消，球不动",
		g.player.is_idle() and g.player.velocity == Vector2.ZERO)

	# 矢量原点必须是球心，而不是按下鼠标的位置
	g.player.reset_to_idle()
	g.player.global_position = Vector2(300.0, 300.0)
	g.player.begin_aim(Vector2(900.0, 620.0))              # 在很远的地方按下
	g.player.update_aim(Vector2(300.0 + 115.0, 300.0))     # 鼠标移到球右侧 115px
	g.player.release_aim()
	fails = _check(fails, "矢量以球心为原点（按下点不影响方向）",
		g.player.velocity.normalized().x > 0.99)
	fails = _check(fails, "力度只看球到鼠标的距离（115px → 半力）",
		absf(g.player.velocity.length() - lerpf(CFG.LAUNCH_MIN_SPEED, CFG.LAUNCH_MAX_SPEED, 0.5)) < 2.0)

	# 3. 空中变向次数
	g.player.reset_to_idle()
	g.player.global_position = origin
	g.player.begin_aim(origin)
	g.player.update_aim(origin + Vector2(200.0, 0.0))
	g.player.release_aim()
	fails = _check(fails, "发射自带 1 次变向", g.player.charges == 1)
	fails = _check(fails, "滞空时可以抓一次", g.player.try_catch(g.player.global_position + Vector2(0.0, 80.0)))
	fails = _check(fails, "抓住后进入瞄准且速度保留（%.0f）" % g.player.velocity.length(),
		g.player.is_aiming() and g.player.velocity.length() > 1.0)
	g.player.update_aim(g.player.global_position + Vector2(0.0, -120.0))
	g.player.release_aim()
	fails = _check(fails, "用掉变向后归零", g.player.charges == 0)
	fails = _check(fails, "次数为 0 时抓不住", not g.player.try_catch(g.player.global_position))

	# 4. 撞墙储藏一次变向
	g.player.reset_to_idle()
	g.player.global_position = Vector2(CFG.ARENA.end.x - 60.0, 400.0)
	g.player.debug_launch(Vector2(1.0, 0.0), 600.0)
	await _wait(24)
	fails = _check(fails, "撞墙后变向次数 +1（当前 %d）" % g.player.charges, g.player.charges >= 2)

	# 5. 球在飞 = 1.0 倍速 / 抓住瞄准 = 0.2 倍速
	g.start_game(1)
	g.player.control_enabled = false
	g.player.reset_to_idle()
	await _wait(40)
	fails = _check(fails, "静止时 0.2 倍速（实测 %.2f）" % Engine.time_scale,
		absf(Engine.time_scale - CFG.SLOW_SCALE) < 0.05)
	g.player.debug_launch(Vector2(0.3, -1.0), 700.0)
	await _wait(34)
	fails = _check(fails, "球在飞时 1.0 倍速（实测 %.2f）" % Engine.time_scale,
		absf(Engine.time_scale - CFG.FAST_SCALE) < 0.05)
	g.player.try_catch(g.player.global_position)
	await _wait(34)
	fails = _check(fails, "抓住瞄准时回到 0.2 倍速（实测 %.2f）" % Engine.time_scale,
		absf(Engine.time_scale - CFG.SLOW_SCALE) < 0.05)

	# 6. 撞击 Boss：一次 1 血，三下击破
	g.start_game(1)
	g.player.control_enabled = false
	g.player.invuln = 9999.0   # 测试撞击，不让弹幕干扰
	var spin_up := 0
	while not g.boss.active and spin_up < 1500:
		await g.get_tree().process_frame
		spin_up += 1
	fails = _check(fails, "Boss 登场后进入战斗", g.boss.active)

	var hits := 0
	for i in 3:
		g.player.global_position = g.boss.global_position + Vector2(0.0, 150.0)
		g.player.reset_to_idle()
		g.player.debug_launch(Vector2(0.0, -1.0), 820.0)
		var before: int = g.boss.hp
		var guard := 0
		while g.boss.hp == before and guard < 120:
			await g.get_tree().process_frame
			guard += 1
		if g.boss.hp == before - 1:
			hits += 1
		var cool := 0
		while g.boss.invuln > 0.0 and cool < 400:
			await g.get_tree().process_frame
			cool += 1
	fails = _check(fails, "撞击 3 次击破 Boss（实际生效 %d 次）" % hits, hits == 3)
	fails = _check(fails, "Boss 归零 -> 胜利结算", g.state == CFG.ST_WIN)


	# 7. 中弹扣血
	g.start_game(1)
	g.player.control_enabled = false
	await _wait(4)
	var hp0: int = g.player.hp
	g._on_boss_fire(g.player.global_position + Vector2(0.0, 26.0), Vector2(0.0, -1.0), 240.0, 0)
	await _wait(30)
	fails = _check(fails, "子弹命中 -1 血（%d -> %d）" % [hp0, g.player.hp], g.player.hp == hp0 - 1)

	# 8. 困难一碰即死
	g.start_game(2)
	g.player.control_enabled = false
	await _wait(4)
	g._on_boss_fire(g.player.global_position + Vector2(0.0, 26.0), Vector2(0.0, -1.0), 240.0, 0)
	await _wait(40)
	fails = _check(fails, "困难 1 血被命中 -> 失败状态", g.state == CFG.ST_LOSE and g.player.hp <= 0)

	# 9. 场地（TileMap）
	g.start_game(1)
	g.player.control_enabled = false
	await _wait(2)
	fails = _check(fails, "场地由 TileMap 生成（合并出 %d 块墙）" % g.arena.rects.size(),
		g.arena != null and g.arena.rects.size() > 10)
	fails = _check(fails, "地板 / 墙两层都已铺满（%d / %d 格）" %
		[g.arena.get_node("Floor").get_used_cells().size(), g.arena.get_node("Walls").get_used_cells().size()],
		g.arena.get_node("Floor").get_used_cells().size() > 800
		and g.arena.get_node("Walls").get_used_cells().size() > 50)

	# 挑一块下方有空间的墙做撞击测试
	var probe := Rect2()
	for r in g.arena.rects:
		var gp: Vector2 = r.get_center() + g.arena.global_position
		if CFG.BOSS_ZONE.grow(50.0).has_point(gp):
			continue
		if gp.distance_to(CFG.PLAYER_SPAWN) < 140.0:
			continue
		if gp.y < 160.0 or gp.y > 560.0:
			continue
		if gp.x < 120.0 or gp.x > 1160.0:
			continue
		probe = r
		break
	fails = _check(fails, "找到可用于撞击测试的墙块", probe.size != Vector2.ZERO)

	if probe.size != Vector2.ZERO:
		var center_g: Vector2 = probe.get_center() + g.arena.global_position
		var start_pos: Vector2 = center_g + Vector2(0.0, probe.size.y * 0.5 + 70.0)
		g.player.global_position = start_pos
		g.player.reset_to_idle()
		g.player.debug_launch(Vector2.UP, 620.0)
		var bounced_back := false
		var min_dist := 9999.0
		for f in 40:
			await g.get_tree().physics_frame
			min_dist = minf(min_dist, g.player.global_position.distance_to(center_g))
			if g.player.velocity.y > 60.0:
				bounced_back = true
				break
		fails = _check(fails, "球撞地图墙会反弹（最近 %.0f px）" % min_dist, bounced_back)

		# 子弹打墙被吸收
		g._on_boss_fire(center_g + Vector2(0.0, -probe.size.y * 0.5 - 60.0), Vector2.DOWN, 320.0, 0)
		await _wait(40)
		fails = _check(fails, "子弹被地图墙吸收（场上 %d 发）" % g.bullets.get_child_count(),
			g.bullets.get_child_count() == 0)

		# 预测轨迹也要考虑墙，否则预览线和实际弹道对不上
		g.player.global_position = start_pos
		g.player.begin_aim(g.player.global_position + Vector2(0.0, -200.0))
		var path: PackedVector2Array = g.player.predict_path()
		g.player.reset_to_idle()
		var bounce_pt := path[1] if path.size() >= 2 else Vector2.ZERO
		fails = _check(fails, "预测轨迹会在墙上反弹（%d 段）" % path.size(),
			path.size() >= 3
			and absf(bounce_pt.y - (center_g.y + probe.size.y * 0.5 + g.player.radius)) < 8.0)

	# 引导带：两条边各自成线
	g.player.global_position = Vector2(640.0, 560.0)
	g.player.reset_to_idle()
	g.player.begin_aim(g.player.global_position + Vector2(0.0, -200.0))
	var guide: PackedVector2Array = g.player.predict_path()
	fails = _check(fails, "引导带路径可算出（%d 个拐点）" % guide.size(),
		guide.size() >= 2)
	g.player.reset_to_idle()

	# 9.5 游球被动：反弹叠极限速度
	g.character = 0
	g.start_game(1)
	g.player.control_enabled = false
	await _wait(2)
	fails = _check(fails, "游球初始 0 层", g.player.speed_stacks == 0)
	for i in 5:
		g.player._register_bump()
	fails = _check(fails, "反弹叠层（%d 层）" % g.player.speed_stacks, g.player.speed_stacks == 5)
	for i in 30:
		g.player._register_bump()
	fails = _check(fails, "加速封顶 20 层（%d）" % g.player.speed_stacks, g.player.speed_stacks == CFG.ROAM_STACK_MAX)
	g.player.reset_to_idle()
	g.player.begin_aim(g.player.global_position)
	g.player.update_aim(g.player.global_position + Vector2(0.0, CFG.DRAG_MAX * 2.0))
	g.player.release_aim()
	fails = _check(fails, "满层极限速度 +40%%（%.0f）" % g.player.velocity.length(),
		absf(g.player.velocity.length() - CFG.LAUNCH_MAX_SPEED * 1.40) < 2.0)
	# 保持 4 秒 → 之后每 0.2 秒掉一层（先把球停住，别让它再撞墙叠层）
	g.player.reset_to_idle()
	g.player.global_position = Vector2(640.0, 300.0)
	g.player.speed_stacks = 20
	g.player.stack_hold = 0.0
	g.player.stack_decay_t = 0.0
	await _wait(13)
	fails = _check(fails, "衰退第一层（剩 %d 层）" % g.player.speed_stacks, g.player.speed_stacks == 19)
	await _wait(13)
	fails = _check(fails, "接着继续掉（剩 %d 层）" % g.player.speed_stacks, g.player.speed_stacks == 18)

	# 10. 圆形弹幕的 1.5 秒预警
	g.start_game(1)
	g.player.control_enabled = false
	var wspin := 0
	while not g.boss.active and wspin < 1500:
		await g.get_tree().process_frame
		wspin += 1
	g.boss.ring_t = 0.0
	await _wait(3)
	fails = _check(fails, "圆形弹幕先进入预警（剩余 %.2fs / %d 条弹道）" %
		[g.boss.windup, g.boss.windup_shots.size()],
		g.boss.windup > 1.0 and g.boss.windup_shots.size() >= 9)

	var before_b: int = g.bullets.get_child_count()
	await _wait(30)
	fails = _check(fails, "预警期间不发弹（场上 %d 发）" % g.bullets.get_child_count(),
		g.bullets.get_child_count() == before_b)

	var wguard := 0
	while g.boss.windup > 0.0 and wguard < 400:
		await g.get_tree().process_frame
		wguard += 1
	await _wait(3)
	fails = _check(fails, "预警走完才发射（场上 %d 发）" % g.bullets.get_child_count(),
		g.bullets.get_child_count() >= 9)

	# 11. 四向反击：只朝 4 个箭头各打一发
	g.start_game(1)
	g.player.control_enabled = false
	g.player.invuln = 9999.0
	var cspin := 0
	while not g.boss.active and cspin < 1500:
		await g.get_tree().process_frame
		cspin += 1
	for b in g.bullets.get_children():
		b.queue_free()
	await _wait(2)
	g.boss.invuln = 0.0
	g.boss.try_ram()
	await _wait(2)
	var bs: Array = g.bullets.get_children()
	var want_n: int = g.boss.arrow_count
	fails = _check(fails, "受击只反击 %d 发（实际 %d 发）" % [want_n, bs.size()], bs.size() == want_n)
	var dir_ok: bool = bs.size() == want_n
	if dir_ok:
		for i in want_n:
			var v: Vector2 = bs[i].velocity.normalized()
			if v.dot(Vector2.from_angle(g.boss.arrow_angle(i))) < 0.97:
				dir_ok = false
	fails = _check(fails, "每发都朝着对应箭头方向", dir_ok)

	# 12. 难度决定箭头数量
	for i in 3:
		g.start_game(i)
		fails = _check(fails, "难度%d 反击箭头 = %d（实际 %d）" %
			[i, CFG.ARROWS_BY_DIFFICULTY[i], g.boss.arrow_count],
			g.boss.arrow_count == CFG.ARROWS_BY_DIFFICULTY[i])
		await _wait(1)

	# 13. 扇形弹幕的 1 秒预警
	g.character = 0
	g.start_game(1)
	g.player.control_enabled = false
	g.player.invuln = 9999.0
	var fspin := 0
	while not g.boss.active and fspin < 1500:
		await g.get_tree().process_frame
		fspin += 1
	for b in g.bullets.get_children():
		b.queue_free()
	await _wait(2)
	g.boss.fan_t = 0.0
	await _wait(3)
	fails = _check(fails, "扇形先进入 1s 预警（剩余 %.2fs）" % g.boss.fan_windup, g.boss.fan_windup > 0.7)
	var bf: int = g.bullets.get_child_count()
	await _wait(20)
	fails = _check(fails, "扇形预警期间不发弹", g.bullets.get_child_count() == bf)
	var fguard := 0
	while g.boss.fan_windup > 0.0 and fguard < 400:
		await g.get_tree().process_frame
		fguard += 1
	await _wait(3)
	fails = _check(fails, "扇形预警结束才发射（场上 %d 发）" % g.bullets.get_child_count(),
		g.bullets.get_child_count() >= 3)

	# 14. 入场空投（这一项要真的播动画）
	g.character = 1
	g.skip_drop = false
	g.start_game(1)
	g.player.control_enabled = false
	fails = _check(fails, "入场空投：开始时在空中（高度 %.0f）" % g.player.drop_h,
		g.player.dropping and g.player.drop_h > 100.0)
	var dguard := 0
	while g.player.dropping and dguard < 300:
		await g.get_tree().process_frame
		dguard += 1
	fails = _check(fails, "空投落地后恢复操作",
		(not g.player.dropping) and g.player.control_enabled and g.player.drop_h == 0.0)
	g.skip_drop = true

	# 15. 盾球与护盾
	g.player.control_enabled = false   # 关掉输入轮询，手动控制按住/松开
	await _wait(2)
	fails = _check(fails, "盾球带护盾技能", g.player.shield_enabled)
	fails = _check(fails, "开局充能满（%.2f）" % g.player.shield_charge,
		absf(g.player.shield_charge - CFG.SHIELD_DURATION) < 0.02)

	g.player.shield_hold = true
	fails = _check(fails, "按住右键开盾", g.player.open_shield() and g.player.shield_active)
	fails = _check(fails, "开盾当帧即完全显现（无渐显）",
		g.player.shield_active and g.player.shield_time == 0.0)
	fails = _check(fails, "护盾有 4 发耐受（%d）" % g.player.shield_shots,
		g.player.shield_shots == CFG.SHIELD_SHOTS)
	await _wait(20)
	fails = _check(fails, "按住时持续时间下降（%.2f）" % g.player.shield_charge,
		g.player.shield_charge < CFG.SHIELD_DURATION - 0.05)

	# 弧面命中（一阶段绿色）
	g.player.shield_time = 0.4
	g.player.fan_dir = Vector2.UP
	g.player.shield_charge = 1.4
	var arc_pos: Vector2 = g.player.global_position + Vector2(0.0, -g.player.fan_radius())
	fails = _check(fails, "弧面命中判定成立", g.player.shield_arc_catch(arc_pos))
	fails = _check(fails, "绿色弧面 +0.5s 且可超过上限（%.2f）" % g.player.shield_charge,
		g.player.shield_charge > 1.7)

	# 内部 / 侧面 / 背后都不算
	g.player.shield_charge = 1.4
	fails = _check(fails, "内部面积不算护盾",
		not g.player.shield_arc_catch(g.player.global_position + Vector2(0.0, -g.player.fan_radius() * 0.5)))
	fails = _check(fails, "球体本身不算弧面",
		not g.player.shield_arc_catch(g.player.global_position + Vector2(0.0, -26.0)))
	fails = _check(fails, "扇形外不算护盾",
		not g.player.shield_arc_catch(g.player.global_position + Vector2(0.0, g.player.fan_radius())))

	# 二阶段：黄绿，只补到上限
	g.player.shield_time = 0.7
	g.player.shield_charge = 1.4
	arc_pos = g.player.global_position + Vector2(0.0, -g.player.fan_radius())
	g.player.shield_arc_catch(arc_pos)
	fails = _check(fails, "黄绿弧面补到上限为止（%.2f）" % g.player.shield_charge,
		g.player.shield_charge <= CFG.SHIELD_DURATION + 0.01)

	# 三阶段：红的，什么都不给
	g.player.shield_time = 1.2
	var c3: float = g.player.shield_charge
	arc_pos = g.player.global_position + Vector2(0.0, -g.player.fan_radius())
	g.player.shield_arc_catch(arc_pos)
	fails = _check(fails, "红色阶段不给回复（%.2f）" % g.player.shield_charge,
		absf(g.player.shield_charge - c3) < 0.01)

	# 第 4 发：挡下但护盾破碎，并给 0.1 秒无敌
	var hp_before: float = g.player.hp
	g.player.invuln = 0.0
	fails = _check(fails, "破碎前只剩 1 发（%d）" % g.player.shield_shots,
		g.player.shield_shots == 1)
	g.player.take_hit(g.player.global_position + Vector2(0.0, -30.0))
	fails = _check(fails, "护盾期间不掉血", is_equal_approx(g.player.hp, hp_before))
	fails = _check(fails, "第 4 发后护盾破碎", not g.player.shield_active)
	fails = _check(fails, "破碎给 0.1 秒无敌（%.2f）" % g.player.invuln,
		g.player.invuln > 0.0 and g.player.invuln <= 0.15)

	# 松手关盾 + 恢复
	g.player.shield_hold = false
	await _wait(3)
	fails = _check(fails, "松开右键保持关闭", not g.player.shield_active)
	g.player.shield_charge = 0.40
	var rec0: float = g.player.shield_charge
	await _wait(60)
	fails = _check(fails, "松手后充能恢复（%.2f → %.2f）" % [rec0, g.player.shield_charge],
		g.player.shield_charge > rec0 + 0.06)

	# 耗尽自动关盾
	g.player.shield_hold = true
	g.player.shield_charge = 0.05
	g.player.open_shield()
	await _wait(60)
	fails = _check(fails, "充能耗尽自动关盾", not g.player.shield_active)

	g.character = 0
	g.start_game(1)
	await _wait(2)
	fails = _check(fails, "游球没有护盾", (not g.player.shield_enabled) and (not g.player.open_shield()))

	# 16. 虫球
	g.character = 2
	g.start_game(1)
	g.player.control_enabled = false
	await _wait(2)
	fails = _check(fails, "虫球半径 = 70%%（%.1f）" % g.player.radius,
		absf(g.player.radius - CFG.PLAYER_RADIUS * 0.7) < 0.01)
	fails = _check(fails, "虫球变向上限 = 5", g.player.max_charges == 5)
	fails = _check(fails, "初始 0 档进化", g.player.tier == 0)

	for i in CFG.BUG_HITS_PER_TIER:
		g.player._register_bump()
	fails = _check(fails, "碰 5 次进化 1 档（tier=%d）" % g.player.tier,
		g.player.tier == 1 and g.player.tier_hits == 0)
	for i in 20:
		g.player._register_bump()
	fails = _check(fails, "5 档封顶", g.player.tier == CFG.BUG_MAX_TIER)

	var hp_b0: float = g.player.hp
	g.player.invuln = 0.0
	g.player.take_hit(g.player.global_position + Vector2(0.0, -40.0))
	fails = _check(fails, "满级护盾只吃 0.5 伤（%.1f）" % (hp_b0 - g.player.hp),
		absf((hp_b0 - g.player.hp) - 0.5) < 0.01)
	fails = _check(fails, "护盾进入 6 秒冷却（%.1fs）" % g.player.bug_shield_cd,
		(not g.player.bug_shield_ready) and g.player.bug_shield_cd > 5.0)

	var hp_b1: float = g.player.hp
	g.player.invuln = 0.0
	g.player.take_hit(g.player.global_position + Vector2(0.0, -40.0))
	fails = _check(fails, "冷却中吃满 1 点（%.1f）" % (hp_b1 - g.player.hp),
		absf((hp_b1 - g.player.hp) - 1.0) < 0.01)

	g.player.slow_field_held = true
	await _wait(20)
	fails = _check(fails, "按住右键压到 0.05× （实测 %.2f）" % Engine.time_scale,
		Engine.time_scale < 0.10)
	fails = _check(fails, "慢放场消耗充能（%.2f）" % g.player.slow_charge,
		g.player.slow_charge < CFG.BUG_SLOW_FIELD_MAX - 0.05)
	g.player.slow_field_held = false
	await _wait(30)
	fails = _check(fails, "松手后慢放场回充（%.2f）" % g.player.slow_charge,
		g.player.slow_charge > 0.05)

	# 变向不再把球停住
	g.character = 0
	g.start_game(1)
	g.player.control_enabled = false
	g.player.global_position = Vector2(400.0, 400.0)
	g.player.reset_to_idle()
	g.player.debug_launch(Vector2(1.0, 0.0), 500.0)
	await _wait(2)
	g.player.try_catch(g.player.global_position)
	var v_before: float = g.player.velocity.length()
	var x_before: float = g.player.global_position.x
	await _wait(12)
	fails = _check(fails, "瞄准时球不停下（速度 %.0f）" % g.player.velocity.length(),
		g.player.velocity.length() > v_before * 0.85)
	fails = _check(fails, "瞄准时球继续位移（+%.0f px）" % (g.player.global_position.x - x_before),
		g.player.global_position.x > x_before + 3.0)
	g.player.reset_to_idle()

	# 10.4 停死 → 球体碎裂判负
	g.boss_stage = 1
	g.start_game(1)
	g.player.control_enabled = false
	g.player.reset_to_idle()
	g.player.charges = 0
	await _wait(30)
	fails = _check(fails, "停死开始出现裂纹（%.2f）" % g.player.crack_t,
		g.player.crack_t > 0.2 and g.player.alive)
	await _wait(110)
	fails = _check(fails, "停死 1.2 秒后碎裂判负",
		(not g.player.alive) and g.state == CFG.ST_LOSE and g.death_cause == "cracked")

	# 10.5 第二只 Boss「壁」：单独选关进入
	g.boss_stage = 2
	g.start_game(1)
	g.player.control_enabled = false
	await _wait(2)
	fails = _check(fails, "选第二关直接打壁（stage=%d / HP=%d）" % [g.stage, g.boss.max_hp],
		g.stage == 2 and g.boss != null and g.boss.max_hp == CFG.BOSS2_HP)
	fails = _check(fails, "壁有 3 块护盾（%d）" % g.boss.alive_plates(), g.boss.alive_plates() == 3)

	var b2wait := 0
	while not g.boss.active and b2wait < 1500:
		await g.get_tree().physics_frame
		b2wait += 1
	fails = _check(fails, "壁登场后进入战斗", g.boss.active)

	var plate = g.boss.plates[0]
	var b2_hp0: int = g.boss.hp
	plate.try_ram()
	fails = _check(fails, "撞护盾板只掉板耐久（板 %d / 本体 %d）" % [plate.hp, g.boss.hp],
		plate.hp == 1 and g.boss.hp == b2_hp0)
	plate.try_ram()
	fails = _check(fails, "护盾板 2 点耐久后碎掉（剩 %d 块）" % g.boss.alive_plates(),
		g.boss.alive_plates() == 2)

	g.player.velocity = Vector2(600.0, 0.0)
	g.player.apply_boss_slow()
	fails = _check(fails, "撞击减速 25%%（600 -> %.0f）" % g.player.velocity.length(),
		absf(g.player.velocity.length() - 450.0) < 6.0)
	fails = _check(fails, "极速上限持续 3 秒（%.1f）" % g.player.slow_cap_timer,
		g.player.slow_cap_timer > 2.9)
	fails = _check(fails, "撞击限速 50%%（%.2f）" % g.player.speed_cap,
		absf(g.player.speed_cap - CFG.BOSS2_SPEED_CAP) < 0.01)
	g.player.speed_cap = 1.0
	g.player.slow_cap_timer = 0.0
	g.player.apply_speed_cap(CFG.BOSS2_RAIL_CAP, CFG.BOSS2_CAP_TIME)
	fails = _check(fails, "被长方形弹命中限速 65%%（%.2f）" % g.player.speed_cap,
		absf(g.player.speed_cap - 0.65) < 0.01)

	g.player.reset_to_idle()
	g.player.global_position = Vector2(400.0, 400.0)
	g.player.begin_aim(Vector2(400.0, 400.0))
	g.player.update_aim(Vector2(400.0, 400.0) + Vector2(0.0, CFG.DRAG_MAX * 2.0))
	g.player.release_aim()
	fails = _check(fails, "限速期间极速被压到 %.0f%%（%.0f）" % [g.player.speed_cap * 100.0, g.player.velocity.length()],
		g.player.velocity.length() <= CFG.LAUNCH_MAX_SPEED * g.player.speed_cap + 1.0)

	g.boss.fan_t = 0.0
	await _wait(90)
	fails = _check(fails, "壁会打出扇形弹幕（场上 %d 发）" % g.bullets.get_child_count(),
		g.bullets.get_child_count() >= CFG.BOSS2_FAN_BASE)

	for i in CFG.BOSS2_HP:
		g.boss.invuln = 0.0
		g.boss.try_ram()
		await _wait(2)
	await _wait(4)
	fails = _check(fails, "壁归零 -> 胜利结算", g.state == CFG.ST_WIN)

	# 17. 多语言 / 素材管线
	I18N.set_lang("en")
	fails = _check(fails, "英文模式生效", I18N.is_en() and I18N.t("end.win") == "CLEARED")
	I18N.set_lang("zh")
	fails = _check(fails, "中文模式生效", (not I18N.is_en()) and I18N.t("end.win") == "目标清除")
	fails = _check(fails, "素材缺失时回退到代码绘制",
		not Skins.has("__not_a_real_asset__") and Skins.tex("__not_a_real_asset__") == null)
	I18N.set_lang("en")
	var back_zh: bool = I18N.next_lang() == "zh"
	I18N.set_lang("zh")
	var to_en: bool = I18N.next_lang() == "en"
	fails = _check(fails, "语言切换可循环", back_zh and to_en)

	print("===== %s（失败 %d 项）=====" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	g.get_tree().quit(0 if fails == 0 else 1)
