extends CharacterBody3D
## Kaji Baje: a billboarded AnimatedSprite3D on a capsule body. He runs along
## one street (the X axis) and jumps. Idle when still, walk when moving,
## run while Shift is held; sprites are mirrored when heading left.
## Space jumps; pressing it again in the air does one double jump.
## J sweeps the cane. The hit is live on the two frames where it is in front.
## K brings it down overhead with both hands: slow lift, fast strike, hit on impact.

const LANE_Z := 0.0

const WALK_SPEED := 2.4
const SPRINT_SPEED := 6.0
const ACCEL := 22.0
const AIR_ACCEL := 14.0
const HEIGHT_M := 1.7

# Peak heights with default gravity: ~1.5 m for a jump, ~2.8 m with the double
# jump, so 1 m blocks need a jump and 2 m blocks need the double jump.
const JUMP_VELOCITY := 5.4
const DOUBLE_JUMP_VELOCITY := 5.0
const MAX_AIR_JUMPS := 1
const FALL_GRAVITY_MULT := 1.5
const JUMP_CUT := 0.5          # velocity kept when Space is released while rising
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12

const WALK_STEP_FRAMES := [1, 5, 8]   # foot contacts in the 10-frame walk
const WALK_CANE_FRAME := 3
const RUN_STEP_INTERVAL := 0.25
const AIR_RISE_FRAME := 2             # run frames with the widest stride, held mid-air
const AIR_FALL_FRAME := 15
const SWEEP_WHIP_FRAME := 2           # cane comes over the top
const SWEEP_HIT_FRAMES := [3, 4]      # cane is low and in front on these sweep frames
const CRACK_WHIP_FRAME := 4           # the gold arc on the way down
const CRACK_HIT_FRAMES := [5]         # cane tip on the ground in front
const CRACK_COMMIT_FRAMES := 7        # no jumping before he starts to rise
const CRACK_SPEED := 0.15

var sprite: AnimatedSprite3D
var _blob: MeshInstance3D
var _squash := Vector2.ONE
var _air_jumps := MAX_AIR_JUMPS
var _coyote := 0.0
var _jump_buffer := 0.0
var _air_time := 0.0
var _was_on_floor := true
var jump_counts := {"jump": 0, "double_jump": 0}
var sfx := {}
var feet: Array[AudioStreamPlayer] = []
var _foot_i := 0
var _run_timer := 0.0
var _was_sprinting := false
var _thud_cooldown := 0.0
var _last_speed := 0.0
var _rng := RandomNumberGenerator.new()
var sound_counts := {}   # name prefix -> times played (handy for checks)
var facing_left := false
var _attack := ""   # "", "sweep" or "crack": the animation that is playing out
var _swing_buffer := 0.0
var _crack_buffer := 0.0
var _attack_hits := {}
var swings := 0
var cracks := 0
var _breathing := false
var _breathe_pending := false
var _hurting := false
var aim_dir := Vector3.ZERO   # stick direction, used by the camera lead
var cpu_controlled := false
var cpu_move := Vector2.ZERO
var cpu_sprint := false
var cpu_jump := false
var spawn_point := Vector3(0, 0.6, 0)
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

const MAX_HEALTH := 3
signal health_changed(current: int)
var health := MAX_HEALTH
var _invuln := 0.0
var _knock_time := 0.0

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.8
	add_child(col)
	sprite = AnimatedSprite3D.new()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/kaji_baje/anims.json"))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for name in meta:
		var m: Dictionary = meta[name]
		var tex: Texture2D = load("res://assets/kaji_baje/%s.png" % name)
		frames.add_animation(name)
		frames.set_animation_speed(name, float(m.fps))
		frames.set_animation_loop(name, bool(m.get("loop", true)))
		var durations: Array = m.get("durations", [])
		# Frames are drawn centred, so a taller cell must keep its ground the
		# same distance below centre as idle's.
		var cell_w := float(m.size)
		var cell_h := float(m.get("height", m.size))
		for i in int(m.frames):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * cell_w, 0, cell_w, cell_h)
			frames.add_frame(name, at, float(durations[i]) if i < durations.size() else 1.0)
	sprite.sprite_frames = frames
	var cell: float = meta.idle.size
	var ground: float = meta.idle.ground
	# ~236 px character → 1.7 m tall.
	sprite.pixel_size = HEIGHT_M / 236.0
	sprite.offset = Vector2(0, cell * 0.5 - (cell - ground))
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = true
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(sprite)
	sprite.play("idle")
	# Soft contact shadow.
	_blob = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 0.55)
	quad.orientation = PlaneMesh.FACE_Y
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://scripts/blob_shadow.gdshader")
	quad.material = sm
	_blob.mesh = quad
	_blob.position.y = 0.02
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blob)
	# A faint warm fill so he stays readable between lamps.
	var fill := OmniLight3D.new()
	fill.light_color = Color("ffd2a0")
	fill.light_energy = 0.6
	fill.omni_range = 3.0
	fill.position = Vector3(0.0, 1.4, 1.2)
	add_child(fill)
	_setup_audio()
	sprite.frame_changed.connect(_on_frame)
	sprite.animation_finished.connect(_on_anim_finished)

func _setup_audio() -> void:
	for n in ["step_1", "step_2", "step_3", "step_4", "step_run_1", "step_run_2", "step_run_3", "step_run_4",
			"cane_1", "cane_2", "cane_3", "whoosh", "thud", "jump", "double_jump", "land", "hit"]:
		sfx[n] = load("res://assets/sfx/%s.wav" % n)
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		feet.append(p)
	# The listener rides with Kaji Baje so lamp hums swell as he walks past.
	var ear := AudioListener3D.new()
	ear.position.y = 1.2
	add_child(ear)
	ear.make_current()

func _sound(name: String, vol_db: float, pitch_var: float = 0.08) -> void:
	var key := name.rstrip("0123456789").trim_suffix("_")
	sound_counts[key] = sound_counts.get(key, 0) + 1
	var p := feet[_foot_i]
	_foot_i = (_foot_i + 1) % feet.size()
	p.stream = sfx[name]
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()

func _on_frame() -> void:
	if sprite.animation == "walk":
		if sprite.frame in WALK_STEP_FRAMES:
			_sound("step_%d" % _rng.randi_range(1, 4), -8.0)
		elif sprite.frame == WALK_CANE_FRAME:
			_sound("cane_%d" % _rng.randi_range(1, 3), -11.0, 0.05)
	elif sprite.animation == "sweep":
		if sprite.frame == SWEEP_WHIP_FRAME:
			_sound("whoosh", -8.0, 0.07)
		elif sprite.frame == SWEEP_HIT_FRAMES[0]:
			_sound("cane_2", -8.0, 0.04)
	elif sprite.animation == "crack":
		if sprite.frame == CRACK_WHIP_FRAME:
			_sound("whoosh", -6.0, 0.05)
		elif sprite.frame == CRACK_HIT_FRAMES[0]:
			_sound("thud", -4.0, 0.05)
			_sound("land", -8.0, 0.06)
			_squash = Vector2(1.12, 0.88)

func _on_anim_finished() -> void:
	if sprite.animation == "hurt":
		_hurting = false
	elif sprite.animation == "breathe":
		_breathing = false
	elif sprite.animation == "crack":
		_attack = ""
		_breathe_pending = true
	elif sprite.animation == _attack:
		_attack = ""

func _input_dir() -> Vector2:
	if cpu_controlled:
		var steered := cpu_move
		return steered.normalized() if steered.length() > 1.0 else steered
	var x := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): x += 1.0
	return Vector2(x, 0.0)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.physical_keycode == KEY_SPACE and not e.echo:
		if e.pressed:
			_jump_buffer = JUMP_BUFFER
		elif velocity.y > 0.0:
			velocity.y *= JUMP_CUT
	elif e is InputEventKey and e.physical_keycode == KEY_J and e.pressed and not e.echo:
		_swing_buffer = 0.16
	elif e is InputEventKey and e.physical_keycode == KEY_K and e.pressed and not e.echo:
		_crack_buffer = 0.16

func _physics_process(delta: float) -> void:
	var inp := _input_dir()
	aim_dir = Vector3(inp.x, 0.0, 0.0)
	var sprint := cpu_sprint if cpu_controlled else Input.is_physical_key_pressed(KEY_SHIFT)
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	if _attack == "sweep":
		speed *= 0.35
	elif _attack == "crack":
		speed *= CRACK_SPEED
	var on_floor := is_on_floor()
	var target := Vector3(inp.x, 0, 0) * speed
	if _knock_time > 0.0:
		_knock_time = maxf(_knock_time - delta, 0.0)
	var steer := 0.2 if _knock_time > 0.0 else 1.0
	velocity.x = move_toward(velocity.x, target.x, (ACCEL if on_floor else AIR_ACCEL) * delta * steer)
	velocity.z = 0.0
	# Keep an upward shove (a jump, or a bump from a cube) even if the floor check is still true.
	if on_floor and velocity.y <= 0.0:
		velocity.y = 0.0
		_coyote = COYOTE_TIME
		_air_jumps = MAX_AIR_JUMPS
		_air_time = 0.0
	else:
		if not on_floor:
			velocity.y -= gravity * (FALL_GRAVITY_MULT if velocity.y < 0.0 else 1.0) * delta
			_coyote = maxf(_coyote - delta, 0.0)
			_air_time += delta
	if cpu_controlled and cpu_jump:
		_jump_buffer = JUMP_BUFFER
		cpu_jump = false
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	var committed := _attack == "crack" and sprite.frame < CRACK_COMMIT_FRAMES
	if _jump_buffer > 0.0 and not committed:
		_try_jump()
	var fall_speed := -velocity.y
	move_and_slide()
	global_position.z = LANE_Z
	_stomp_monsters(fall_speed)
	_swing_buffer = maxf(_swing_buffer - delta, 0.0)
	_crack_buffer = maxf(_crack_buffer - delta, 0.0)
	var can_attack := _attack == "" and not _hurting and health > 0 and _knock_time <= 0.0
	if can_attack and _crack_buffer > 0.0 and is_on_floor():
		_crack_buffer = 0.0
		_begin_attack("crack")
	elif can_attack and _swing_buffer > 0.0:
		_swing_buffer = 0.0
		_begin_attack("sweep")
	elif _attack != "":
		_attack_check()
	if is_on_floor() and not _was_on_floor and fall_speed > 2.0:
		_land(fall_speed)
	_was_on_floor = is_on_floor()
	_animate(inp, sprint)
	_movement_sounds(delta, inp, sprint)
	_update_body_fx(delta)

func _stomp_monsters(fall_speed: float) -> void:
	# Only a downward landing counts. Walking into the side of a cube does not.
	if fall_speed < 1.0:
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider()
		if body == null or not body.is_in_group("monster"):
			continue
		if hit.get_normal().y < 0.5:
			continue
		if hit.get_position().y < body.global_position.y + 0.4:
			continue
		body.stomp()
		velocity.y = maxf(velocity.y, 4.2)
		_squash = Vector2(1.16, 0.82)

func _begin_attack(kind: String) -> void:
	_attack = kind
	_attack_hits.clear()
	_breathing = false
	_breathe_pending = false
	_hurting = false
	if kind == "sweep":
		swings += 1
		_squash = Vector2(1.08, 0.92)
	else:
		cracks += 1
	sprite.speed_scale = 1.0
	sprite.play(kind)

func _attack_check() -> void:
	var sweep := _attack == "sweep"
	if sprite.animation != _attack or not (sprite.frame in (SWEEP_HIT_FRAMES if sweep else CRACK_HIT_FRAMES)):
		return
	# Sweep: low arc right in front. Crack: lands a little further out, and reaches up onto a low block.
	var near := 0.1 if sweep else 0.3
	var far := 1.25 if sweep else 1.4
	var dir := -1.0 if facing_left else 1.0
	for node in get_tree().get_nodes_in_group("monster"):
		if not is_instance_valid(node) or not node.get("alive"):
			continue
		var id := node.get_instance_id()
		if _attack_hits.has(id):
			continue
		var critter := node as Node3D
		var rel := critter.global_position - global_position
		var dx := rel.x * dir
		if dx < near or dx > far or absf(rel.y) > 1.2 or absf(rel.z) > 0.8:
			continue
		_attack_hits[id] = true
		if sweep:
			node.call("strike", dir)
			_sound("thud", -6.0, 0.05)
		else:
			node.call("stomp")

func hurt(from: Vector3) -> void:
	if _invuln > 0.0 or health <= 0:
		return
	health -= 1
	health_changed.emit(health)
	_attack = ""
	_breathing = false
	_breathe_pending = false
	_hurting = false
	_invuln = 1.05
	_knock_time = 0.35
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	away.z = 0.0
	if absf(away.x) < 0.01:
		away.x = 1.0 if global_position.x >= from.x else -1.0
	velocity = away.normalized() * 7.0 + Vector3.UP * 3.2
	_sound("hit", -5.0, 0.05)
	if health <= 0:
		_respawn()
		return
	_hurting = true
	sprite.speed_scale = 1.0
	sprite.play("hurt")

func _respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	_knock_time = 0.0
	_hurting = false
	health = MAX_HEALTH
	_invuln = 1.4
	health_changed.emit(health)

func _try_jump() -> void:
	if _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_coyote = 0.0
		_squash = Vector2(0.86, 1.16)
		_sound("jump", -9.0, 0.06)
		jump_counts.jump += 1
	elif _air_jumps > 0:
		_air_jumps -= 1
		velocity.y = DOUBLE_JUMP_VELOCITY
		_squash = Vector2(0.8, 1.24)
		_sound("double_jump", -8.0, 0.05)
		_puff()
		jump_counts.double_jump += 1
	else:
		return
	_jump_buffer = 0.0
	_air_time = 0.1

func _land(fall_speed: float) -> void:
	var k := clampf((fall_speed - 2.0) / 8.0, 0.0, 1.0)
	_squash = Vector2(1.08 + 0.17 * k, 0.9 - 0.15 * k)
	_sound("land", lerpf(-12.0, -5.0, k), 0.06)

func _puff() -> void:
	# A ring of air pushed down by the double jump.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.38
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.93, 0.8, 0.4)
	torus.material = m
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.1, 0)
	ring.scale = Vector3(0.6, 1.0, 0.6)
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(2.4, 1.0, 2.4), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ring, "position:y", ring.position.y - 0.3, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)

func _update_body_fx(delta: float) -> void:
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, delta * 12.0))
	sprite.scale = Vector3(_squash.x, _squash.y, 1.0)
	if _invuln > 0.0:
		_invuln = maxf(_invuln - delta, 0.0)
		sprite.modulate = Color(1.0, 0.5, 0.45) if int(_invuln * 14.0) % 2 == 0 else Color.WHITE
	else:
		sprite.modulate = Color.WHITE
	# Keep the contact shadow on whatever is below, fading as he rises.
	var from := global_position + Vector3.UP * 0.1
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		_blob.visible = true
		_blob.global_position.y = hit.position.y + 0.02
		var s := clampf(1.0 - (global_position.y - hit.position.y) / 4.0, 0.35, 1.0)
		_blob.scale = Vector3(s, 1.0, s)
	else:
		_blob.visible = false

func _movement_sounds(delta: float, inp: Vector2, sprint: bool) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var running := sprite.animation == "run" and sprite.is_playing()
	if running:
		_run_timer -= delta
		if _run_timer <= 0.0:
			_run_timer = RUN_STEP_INTERVAL
			_sound("step_run_%d" % _rng.randi_range(1, 4), -5.0, 0.1)
	else:
		_run_timer = 0.05
	if running and not _was_sprinting:
		_sound("whoosh", -10.0, 0.1)
	_was_sprinting = running
	# Bump into a block or lamp post at speed.
	_thud_cooldown = maxf(_thud_cooldown - delta, 0.0)
	if inp.length() > 0.1 and _last_speed > 2.0 and speed < _last_speed * 0.4 and _thud_cooldown == 0.0 and get_slide_collision_count() > 0:
		_sound("thud", -6.0, 0.05)
		_thud_cooldown = 0.6
	_last_speed = speed

func _animate(inp: Vector2, sprint: bool) -> void:
	var moving := inp.length() > 0.1 and Vector2(velocity.x, velocity.z).length() > 0.3
	if _attack == "" and not _hurting:
		if inp.x < -0.1:
			facing_left = true
		elif inp.x > 0.1:
			facing_left = false
	sprite.flip_h = facing_left
	if _attack != "" or _hurting:
		return
	var airborne := not is_on_floor() and _air_time > 0.08
	if moving or airborne:
		_breathing = false
		_breathe_pending = false
	# The short grace period stops a flicker when stepping off small ledges.
	if airborne:
		if sprite.animation != "run":
			sprite.play("run")
		sprite.pause()
		sprite.frame = AIR_RISE_FRAME if velocity.y > 0.0 else AIR_FALL_FRAME
	elif moving:
		if sprint:
			_play("run", 1.0)
		else:
			_play("walk", 1.0)
	elif _breathe_pending:
		_breathe_pending = false
		_breathing = true
		sprite.speed_scale = 1.0
		sprite.play("breathe")
	elif _breathing:
		pass
	else:
		_play("idle", 1.0)

func _play(anim: String, spd: float) -> void:
	sprite.speed_scale = spd
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
