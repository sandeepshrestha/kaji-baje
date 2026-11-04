extends Node
## Captures idle / walk / run / walk-left / jump / double-jump frames to docs/.
func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/%s.png" % name)

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	add_child(load("res://main.tscn").instantiate())
	await _wait(60)
	await _snap("shot_idle")
	_key(KEY_D, true)
	await _wait(50)
	await _snap("shot_walk")
	_key(KEY_SHIFT, true)
	await _wait(40)
	await _snap("shot_run")
	_key(KEY_SHIFT, false)
	_key(KEY_D, false)
	_key(KEY_A, true)
	await _wait(40)
	await _snap("shot_walk_left")
	_key(KEY_A, false)
	await _wait(30)
	_key(KEY_SPACE, true)
	await _wait(20)
	await _snap("shot_jump")
	await _wait(10)
	_key(KEY_SPACE, false)
	_key(KEY_SPACE, true)
	await _wait(8)
	await _snap("shot_double_jump")
	_key(KEY_SPACE, false)
	get_tree().quit()
