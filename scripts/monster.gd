extends CharacterBody3D
## A plain orange cube. Chases Kaji Baje and bumps him. Landing on it squashes it.

const SIZE := 0.65
const SPEED := 2.7
const ATTACK_RANGE := 0.95
const ATTACK_COOLDOWN := 1.0

var player: CharacterBody3D
var alive := true

var _mesh: MeshInstance3D
var _attack_wait := 0.45
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _ready() -> void:
	add_to_group("monster")
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ff7a18")
	mat.roughness = 0.55
	box.material = mat
	_mesh.mesh = box
	_mesh.position.y = SIZE * 0.5
	add_child(_mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * SIZE
	col.shape = shape
	col.position.y = SIZE * 0.5
	add_child(col)

func _physics_process(delta: float) -> void:
	if not alive or player == null or not is_instance_valid(player):
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / dist if dist > 0.001 else Vector3.ZERO
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	_attack_wait = maxf(_attack_wait - delta, 0.0)
	# His feet are at the origin. Above the cube's top means he is landing, not being bumped.
	var above := player.global_position.y > global_position.y + SIZE * 0.55
	if dist < ATTACK_RANGE and not above and _attack_wait == 0.0:
		_attack_wait = ATTACK_COOLDOWN
		player.hurt(global_position)

func stomp() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	var pop := AudioStreamPlayer3D.new()
	pop.stream = preload("res://assets/sfx/stomp.wav")
	pop.volume_db = -4.0
	pop.position.y = 0.3
	add_child(pop)
	pop.play()
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3(1.35, 0.12, 1.35), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_mesh, "position:y", 0.04, 0.12)
	tw.tween_interval(0.14)
	tw.tween_callback(queue_free)
