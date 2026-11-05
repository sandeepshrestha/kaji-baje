extends CharacterBody3D
## A small critter (one of the UI8 3D Cute Animals). Chases Kaji Baje and bumps
## him. Landing on it squashes it. It is a billboard that swaps between its
## front, back, left and right renders as it turns relative to the camera.

const SIZE := 0.65
const HEIGHT_M := 0.8
const SPEED := 2.7
const ATTACK_RANGE := 0.95
const ATTACK_COOLDOWN := 1.0
const HOP_HZ := 3.2
const CRITTERS := ["bat", "hedgehog", "monkey", "red_panda"]
const CELL := 256.0
const GROUND := 252.0
const CONTENT_PX := 236.0

var player: CharacterBody3D
var alive := true
var critter := ""

var _sprite: Sprite3D
var _views := {}
var _hop := 0.0
var _attack_wait := 0.45
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _ready() -> void:
	add_to_group("monster")
	if critter == "":
		critter = CRITTERS[randi() % CRITTERS.size()]
	for v in ["front", "back", "left", "right"]:
		_views[v] = load("res://assets/critters/%s/%s.png" % [critter, v])
	_sprite = Sprite3D.new()
	_sprite.texture = _views.front
	_sprite.pixel_size = HEIGHT_M / CONTENT_PX
	_sprite.offset = Vector2(0, CELL * 0.5 - (CELL - GROUND))
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.shaded = true
	_sprite.double_sided = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_sprite)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * SIZE
	col.shape = shape
	col.position.y = SIZE * 0.5
	add_child(col)
	_hop = randf() * TAU

func _physics_process(delta: float) -> void:
	if not alive or player == null or not is_instance_valid(player):
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / dist if dist > 0.001 else Vector3.ZERO
	velocity.x = dir.x * SPEED
	velocity.z = 0.0
	if is_on_floor():
		velocity.y = _jump_velocity(dir.x)
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	global_position.z = 0.0
	_face(dir)
	_hop += delta * TAU * HOP_HZ
	var h := absf(sin(_hop)) if is_on_floor() else 0.0
	_sprite.position.y = h * 0.08
	_sprite.scale = Vector3(1.0 + (1.0 - h) * 0.06, 1.0 - (1.0 - h) * 0.06, 1.0)
	_attack_wait = maxf(_attack_wait - delta, 0.0)
	# His feet are at the origin. Above the critter's top means he is landing, not being bumped.
	var above := player.global_position.y > global_position.y + SIZE * 0.55
	if dist < ATTACK_RANGE and not above and _attack_wait == 0.0:
		_attack_wait = ATTACK_COOLDOWN
		player.hurt(global_position)

## How hard to jump to land on the block ahead. 0 when the way is clear.
## End walls are taller than a jump, so those are left alone.
func _jump_velocity(dir_x: float) -> float:
	if absf(dir_x) < 0.1:
		return 0.0
	var space := get_world_3d().direct_space_state
	var ahead := global_position + Vector3(signf(dir_x) * 0.85, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(ahead + Vector3(0, 3.2, 0), ahead + Vector3(0, 0.05, 0))
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not (hit.collider is StaticBody3D):
		return 0.0
	var rise := float(hit.position.y) - global_position.y
	if rise < 0.45 or rise > 2.5:
		return 0.0
	return sqrt(2.0 * _gravity * (rise + 0.25))

func _face(dir: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or dir == Vector3.ZERO:
		return
	var right := cam.global_basis.x
	right.y = 0.0
	var away := -cam.global_basis.z
	away.y = 0.0
	var side := dir.dot(right.normalized())
	var depth := dir.dot(away.normalized())
	if absf(side) > absf(depth) * 0.8:
		_sprite.texture = _views.right if side > 0.0 else _views.left
	else:
		_sprite.texture = _views.back if depth > 0.0 else _views.front

## The cane caught him. He leaves along the swing instead of chasing.
func strike(dir_x: float) -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sprite, "position:x", dir_x * 0.85, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sprite, "position:y", 0.28, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.16).set_delay(0.06)
	tw.chain().tween_callback(queue_free)

func stomp() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_sprite.texture = _views.front
	var pop := AudioStreamPlayer3D.new()
	pop.stream = preload("res://assets/sfx/stomp.wav")
	pop.volume_db = -4.0
	pop.position.y = 0.3
	add_child(pop)
	pop.play()
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", Vector3(1.4, 0.15, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_sprite, "position:y", 0.0, 0.12)
	tw.tween_interval(0.14)
	tw.tween_callback(queue_free)
