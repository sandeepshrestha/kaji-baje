extends Camera3D
## Side-on 2.5D follow. The lens stays beside him, looking straight across
## the street. It does not lead his turns or rise with a jump. Wheel or Q/E zooms, R resets.

var target: Node3D
const BASE_OFFSET := Vector3(0, 2.5, 11.5)
const PHONE_OFFSET := Vector3(0, 2.1, 9.2)
const LOOK_HEIGHT := 1.3
var zoom := 1.0          # 1.0 = medium
var _zoom_target := 1.0
var _base_y := 0.0

func _ready() -> void:
	# Stays awake while the tree is paused so Esc still opens and closes the menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	fov = 40.0
	# Vertical framing stays put. A wider window, including 21:9 and 32:9,
	# opens the view out to the sides instead of stretching the picture.
	keep_aspect = Camera3D.KEEP_HEIGHT
	current = true
	if target:
		_base_y = target.global_position.y
		_place(false)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		var world := get_parent()
		if world.has_method("_on_escape"):
			world._on_escape()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
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
	if get_tree().paused or target == null:
		return
	zoom = lerpf(zoom, _zoom_target, minf(1.0, delta * 8.0))
	var feet := target.global_position.y
	# Hold the last ground height in the air, so a jump does not drag the street.
	if target is CharacterBody3D and not (target as CharacterBody3D).is_on_floor():
		feet = _base_y
	_base_y = lerpf(_base_y, feet, 1.0 - exp(-4.0 * delta))
	_place(_phone())

func _place(phone: bool) -> void:
	# On a tall phone frame the horizontal view is what would otherwise collapse.
	# Keep that width and let the extra height show more ground ahead and behind.
	if phone:
		keep_aspect = Camera3D.KEEP_WIDTH
		fov = 50.0
	else:
		keep_aspect = Camera3D.KEEP_HEIGHT
		fov = 40.0
	var offset := (PHONE_OFFSET if phone else BASE_OFFSET) * zoom
	global_position = Vector3(target.global_position.x, _base_y + offset.y, target.global_position.z + offset.z)
	# Same x as the lens, so the view never yaws when he turns around.
	look_at(Vector3(global_position.x, _base_y + LOOK_HEIGHT, target.global_position.z))

func _phone() -> bool:
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	if base_h > base_w:
		return true
	var s := get_viewport().get_visible_rect().size
	return s.y > s.x
