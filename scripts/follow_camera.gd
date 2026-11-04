extends Camera3D
## Medium-distance 2.5D follow camera: fixed angle looking down at ~33°,
## smoothed follow, zoom with mouse wheel or Q/E (R resets to medium).
## The frame eases ahead of Kaji Baje in the direction he is steered, the way
## the older God of War games look further into the way you're moving.

var target: Node3D
const BASE_OFFSET := Vector3(0, 5.2, 8.0)
const PHONE_OFFSET := Vector3(0, 4.6, 6.8)
const PHONE_AHEAD := Vector3.ZERO
const LOOK_HEIGHT := 1.0
const LEAD_WALK := 1.6
const LEAD_RUN := 2.5
const LEAD_RESPONSE := 2.1   # lower = heavier, slower to catch a turn
var zoom := 1.0          # 1.0 = medium
var _zoom_target := 1.0
var _lead := Vector3.ZERO

func _ready() -> void:
	fov = 40.0
	# Vertical framing stays put. A wider window, including 21:9 and 32:9,
	# opens the view out to the sides instead of stretching the picture.
	keep_aspect = Camera3D.KEEP_HEIGHT
	current = true
	if target:
		global_position = target.global_position + BASE_OFFSET
		look_at(target.global_position + Vector3(0, LOOK_HEIGHT, 0))

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target -= 0.1
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target += 0.1
	elif e is InputEventKey and e.pressed:
		match e.physical_keycode:
			KEY_Q: _zoom_target -= 0.15
			KEY_E: _zoom_target += 0.15
			KEY_R: _zoom_target = 1.0
	_zoom_target = clampf(_zoom_target, 0.55, 1.8)

func _process(delta: float) -> void:
	if target == null:
		return
	zoom = lerpf(zoom, _zoom_target, minf(1.0, delta * 8.0))
	var phone := _phone()
	# On a tall phone frame the horizontal view is what would otherwise collapse.
	# Keep that width and let the extra height show more ground ahead and behind.
	if phone:
		keep_aspect = Camera3D.KEEP_WIDTH
		fov = 50.0
	else:
		keep_aspect = Camera3D.KEEP_HEIGHT
		fov = 40.0
	var lead_scale := 0.0 if phone else 1.0
	_lead = _lead.lerp(_lead_goal() * lead_scale, 1.0 - exp(-LEAD_RESPONSE * delta))
	var ahead := PHONE_AHEAD if phone else Vector3.ZERO
	var offset := PHONE_OFFSET if phone else BASE_OFFSET
	var focus := target.global_position + Vector3(0, LOOK_HEIGHT, 0) + _lead + ahead
	var want := target.global_position + offset * zoom + _lead + ahead
	global_position = global_position.lerp(want, minf(1.0, delta * 6.0))
	look_at(focus)

func _phone() -> bool:
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	if base_h > base_w:
		return true
	var s := get_viewport().get_visible_rect().size
	return s.y > s.x

func _lead_goal() -> Vector3:
	# Prefer the keys being held, so the frame starts shifting as soon as you
	# steer. Fall back to velocity when he is still sliding with no input.
	var dir: Vector3 = target.get("aim_dir") if target.get("aim_dir") != null else Vector3.ZERO
	var speed := 0.0
	if target is CharacterBody3D:
		var hv := Vector3(target.velocity.x, 0.0, target.velocity.z)
		speed = hv.length()
		if dir.length() < 0.1 and speed > 0.8:
			dir = hv / speed
	if dir.length() < 0.1:
		return Vector3.ZERO
	var reach := lerpf(LEAD_WALK, LEAD_RUN, clampf(speed / 6.0, 0.0, 1.0))
	return dir.normalized() * reach * dir.length()
