extends Node
## Story take. He walks, then sprints. He slips past cubes, jumps on two of
## them, lets one hit him, grabs coins, and finishes standing on a block.
## The camera pulls wide while he walks and pushes in once he is up high.

const ZOOM_START := 0.92
const ZOOM_WIDE := 1.42
const ZOOM_END := 1.02
const WALK_END := 3.6
const HUNT_START := 7.2
const TANK_START := 11.6
const CLIMB_START := 14.6

var _player: CharacterBody3D
var _cam: Camera3D
var _coin: Node3D
var _prey: Node3D
var _ledge := AABB(Vector3(5, 0, -5), Vector3(4, 1, 4))
var _time := 0.0
var _side := 1
var _dodge_for := 0.0
var _jump_lock := 0.0
var _kills := 0
var _dodges := 0
var _holding := false
var _phase := "walk"

func _ready() -> void:
	_player = get_parent().get_node("KajiBaje")
	_player.cpu_controlled = true
	for child in get_parent().get_children():
		if child is Camera3D:
			_cam = child
	if _cam:
		_cam.zoom = ZOOM_START
		_cam._zoom_target = ZOOM_START
	_ledge = _pick_ledge()
	var centre := _ledge.get_center()
	print("cpu ledge x=%.1f z=%.1f top=%.1f size=%.0fx%.0f" % [centre.x, centre.z, _ledge.position.y + _ledge.size.y, _ledge.size.x, _ledge.size.z])
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "CPU"
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.offset_left = -40
	label.offset_right = 40
	var view := get_viewport().get_visible_rect().size
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	label.offset_top = 250 if base_h > base_w or view.y > view.x else 44
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 0.85))
	label.add_theme_font_size_override("font_size", 18)
	layer.add_child(label)

func _physics_process(delta: float) -> void:
	_time += delta
	_dodge_for = maxf(_dodge_for - delta, 0.0)
	_jump_lock = maxf(_jump_lock - delta, 0.0)
	_drive_zoom()
	if int(_time) != int(_time - delta) and int(_time) % 2 == 0:
		print("cpu t=%ds phase=%s coins=%d health=%d kills=%d dodges=%d y=%.2f" % [int(_time), _phase, get_parent().coins_collected, _player.health, _kills, _dodges, _player.global_position.y])
	if _climbing() and _on_ledge():
		_phase = "ledge"
		_hold_on_ledge()
		return
	if _player._knock_time > 0.0:
		_player.cpu_move = Vector2.ZERO
		_player.cpu_sprint = false
		_player.cpu_jump = false
		return
	if _climbing():
		_phase = "climb"
		_climb()
		return
	if _time >= HUNT_START and _kills < 2:
		_phase = "hunt"
		_stomp()
		return
	if _time >= TANK_START and _player.health == _player.MAX_HEALTH and _kills > 0:
		_phase = "tank"
		_tank()
		return
	_phase = "walk" if _time < WALK_END else "sprint"
	_roam()

func _climbing() -> bool:
	if _time >= CLIMB_START:
		return true
	# A third hit would respawn him, so leave for the block once he is on his last heart.
	return _player.health <= 1 and _kills > 0 and _time > 10.0

func _roam() -> void:
	if _player.global_position.y > 0.55:
		_step_down()
		return
	var monster := _nearest_monster()
	if monster != null and _time >= WALK_END and _player.health > 1:
		var gap := _gap(monster)
		if _dodge_for <= 0.0 and gap < 3.3 and _dodges < 4:
			_dodge_for = 0.72
			_dodges += 1
			var away := _away(monster)
			_side = 1 if away.x * 0.2 + away.y >= 0.0 else -1
		if _dodge_for > 0.0 and gap > 0.05:
			var slip := _away(monster)
			_player.cpu_move = (Vector2(-slip.y, slip.x) * float(_side) + slip * 0.45).normalized()
			_player.cpu_sprint = true
			_player.cpu_jump = false
			return
		# Close in so the sidestep happens in frame, once a few coins are already in hand.
		if _dodges < 2 and gap > 3.3 and gap < 10.0 and get_parent().coins_collected >= 4:
			var toward := -_away(monster)
			_player.cpu_move = toward.normalized() if toward.length() > 0.05 else Vector2.ZERO
			_player.cpu_sprint = true
			_player.cpu_jump = false
			return
	if monster != null and _player.health <= 1 and _gap(monster) < 3.2:
		var flee := _away(monster)
		_player.cpu_move = flee.normalized() if flee.length() > 0.05 else Vector2.ZERO
		_player.cpu_sprint = true
		_player.cpu_jump = false
		return
	if not is_instance_valid(_coin) or not _ground_coin(_coin):
		_coin = _nearest_coin()
	var goal := Vector3(cos(_time * 0.7) * 3.5, 0.0, sin(_time * 0.7) * 3.5)
	if is_instance_valid(_coin) and _ground_coin(_coin):
		goal = _coin.global_position
	var wish := _toward(goal, 0.35)
	_player.cpu_move = wish
	_player.cpu_sprint = _time >= WALK_END and wish.length() > 0.1
	_player.cpu_jump = false

func _stomp() -> void:
	if _note_kill():
		_jump_lock = 0.4
	if _prey == null or not is_instance_valid(_prey) or not _prey.alive:
		_prey = _nearest_monster()
	if _prey == null:
		_roam()
		return
	var gap := _gap(_prey)
	# Run in, stop, and hop so the cube keeps chasing and he drops on it.
	var wish := Vector2.ZERO
	if gap > 2.15:
		wish = -_away(_prey)
		if wish.length() > 0.05:
			wish = wish.normalized()
	_player.cpu_move = wish
	_player.cpu_sprint = gap > 2.15
	var hop := false
	if _player.is_on_floor() and _jump_lock <= 0.0 and gap < 2.55 and gap > 1.55:
		hop = true
		_jump_lock = 0.95
	_player.cpu_jump = hop

func _note_kill() -> bool:
	if _prey == null:
		return false
	if is_instance_valid(_prey) and _prey.alive:
		return false
	_kills += 1
	print("cpu stomp kills=%d" % _kills)
	_prey = null
	return true

func _tank() -> void:
	var monster := _nearest_monster()
	if monster == null:
		_roam()
		return
	var wish := -_away(monster)
	_player.cpu_move = wish.normalized() if wish.length() > 0.05 and _gap(monster) > 0.15 else Vector2.ZERO
	_player.cpu_sprint = false
	_player.cpu_jump = false

func _climb() -> void:
	var centre := _ledge.get_center()
	var outside := _outside_dist(_ledge)
	var wish := _toward(Vector3(centre.x, 0.0, centre.z), 0.15)
	_player.cpu_move = wish
	_player.cpu_sprint = outside > 2.0
	var top := _ledge.position.y + _ledge.size.y
	var hop := false
	if _player.is_on_floor() and _jump_lock <= 0.0 and _player.global_position.y < top - 0.25 and outside < 1.15 and outside > 0.2:
		hop = true
		_jump_lock = 0.9
	_player.cpu_jump = hop
	if _player.health <= 1:
		for monster in get_tree().get_nodes_in_group("monster"):
			if is_instance_valid(monster):
				monster.player = null

func _step_down() -> void:
	var centre := _ledge.get_center()
	var away := Vector2(_player.global_position.x - centre.x, _player.global_position.z - centre.z)
	if away.length() < 0.2:
		away = Vector2.RIGHT
	_player.cpu_move = away.normalized()
	_player.cpu_sprint = false
	_player.cpu_jump = false

func _on_ledge() -> bool:
	var top := _ledge.position.y + _ledge.size.y
	if not _player.is_on_floor() or _player.global_position.y < top - 0.4:
		return false
	var p := _player.global_position
	return p.x > _ledge.position.x - 0.15 and p.x < _ledge.end.x + 0.15 and p.z > _ledge.position.z - 0.15 and p.z < _ledge.end.z + 0.15

func _outside_dist(box: AABB) -> float:
	var p := _player.global_position
	var dx := maxf(box.position.x - p.x, maxf(0.0, p.x - box.end.x))
	var dz := maxf(box.position.z - p.z, maxf(0.0, p.z - box.end.z))
	return Vector2(dx, dz).length()

func _hold_on_ledge() -> void:
	if not _holding:
		_holding = true
		print("cpu on ledge y=%.2f" % _player.global_position.y)
		for monster in get_tree().get_nodes_in_group("monster"):
			if is_instance_valid(monster):
				monster.player = null
				monster.velocity = Vector3.ZERO
	_player.cpu_move = Vector2.ZERO
	_player.cpu_sprint = false
	_player.cpu_jump = false

func _drive_zoom() -> void:
	if _cam == null:
		return
	var z := ZOOM_WIDE
	if _time < 2.8:
		z = lerpf(ZOOM_START, ZOOM_WIDE, _smooth(_time / 2.8))
	elif _holding:
		z = ZOOM_END
	_cam._zoom_target = z

func _smooth(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _pick_ledge() -> AABB:
	var best := AABB(Vector3(5, 0, -5), Vector3(4, 1, 4))
	var best_area := 0.0
	var best_d := INF
	for box in get_parent()._solids:
		var top: float = box.position.y + box.size.y
		if top < 0.95 or top > 1.15:
			continue
		if box.size.x < 1.8 or box.size.z < 1.8:
			continue
		var centre: Vector3 = box.get_center()
		var d := Vector2(centre.x, centre.z).length()
		if d < 5.0 or d > 18.0:
			continue
		var area: float = box.size.x * box.size.z
		if area > best_area or (is_equal_approx(area, best_area) and d < best_d):
			best_area = area
			best_d = d
			best = box
	return best

func _toward(goal: Vector3, arrive: float) -> Vector2:
	var flat := Vector2(goal.x - _player.global_position.x, goal.z - _player.global_position.z)
	var dist := flat.length()
	return flat / dist if dist > arrive else Vector2.ZERO

func _away(monster: Node3D) -> Vector2:
	var v := Vector2(_player.global_position.x - monster.global_position.x, _player.global_position.z - monster.global_position.z)
	return v / v.length() if v.length() > 0.05 else Vector2.RIGHT

func _gap(monster: Node3D) -> float:
	return Vector2(_player.global_position.x - monster.global_position.x, _player.global_position.z - monster.global_position.z).length()

func _ground_coin(coin: Variant) -> bool:
	if not is_instance_valid(coin) or not (coin is Node):
		return false
	return not coin._taken and coin.global_position.y < 0.9

func _nearest_coin() -> Node3D:
	var best: Node3D
	var best_d := INF
	for coin in get_tree().get_nodes_in_group("coin"):
		if not _ground_coin(coin):
			continue
		var d := Vector2(coin.global_position.x - _player.global_position.x, coin.global_position.z - _player.global_position.z).length()
		if d < best_d:
			best_d = d
			best = coin
	return best

func _nearest_monster() -> Node3D:
	var best: Node3D
	var best_d := INF
	for monster in get_tree().get_nodes_in_group("monster"):
		if not is_instance_valid(monster) or not monster.alive:
			continue
		var d := _gap(monster)
		if d < best_d:
			best_d = d
			best = monster
	return best
