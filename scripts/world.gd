extends Node3D
## Prototype 2.5D night world: plain tiled floor, grey blocks, lamp posts,
## starry sky and moonlight. Kaji Baje is a billboarded sprite in 3D space.

const PLAYER := preload("res://scripts/player.gd")
const MONSTER := preload("res://scripts/monster.gd")
const COIN := preload("res://scripts/coin.gd")
const MAX_MONSTERS := 3
const SPAWN_EVERY := 3.0
const COIN_Y := 0.6                       # coin centre height when resting on the ground
const COMBO_WINDOW_MS := 700
const COMBO_SEMITONES := [0, 2, 4, 5, 7, 9, 11, 12]

var rng := RandomNumberGenerator.new()
var _solids: Array[AABB] = []
var _block_tops: Array[Vector3] = []      # top-centre of each block
var coins_total := 0
var coins_collected := 0
var _coin_label: Label
var _banner: Label
var _coin_players: Array[AudioStreamPlayer] = []
var _coin_player_i := 0
var _combo := 0
var _last_coin_ms := -100000
var _player: CharacterBody3D
var _hearts_label: Label
var _spawn_wait := 1.2

func _ready() -> void:
	_fit_window()
	rng.seed = 7
	_environment()
	_moon()
	_floor()
	_blocks()
	_lamps()
	_coins()
	_player = CharacterBody3D.new()
	_player.set_script(PLAYER)
	_player.name = "KajiBaje"
	add_child(_player)
	_player.global_position = Vector3(0, 0.05, 0)
	var cam := preload("res://scripts/follow_camera.gd").new()
	cam.target = _player
	add_child(cam)
	_hud()
	_player.health_changed.connect(_on_health_changed)
	_on_health_changed(_player.health)
	_ambience()

func _process(delta: float) -> void:
	_spawn_wait -= delta
	if _spawn_wait > 0.0:
		return
	_spawn_wait = SPAWN_EVERY
	if get_tree().get_nodes_in_group("monster").size() >= MAX_MONSTERS:
		return
	if not _spawn_monster():
		_spawn_wait = 0.4

func _fit_window() -> void:
	# On a screen wider than 16:9, open a window in that same shape so the
	# extra width is actually on screen. Narrower displays keep the default size.
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_args().has("--write-movie"):
		return
	var screen := DisplayServer.screen_get_size()
	if screen.y < 100 or float(screen.x) / float(screen.y) < 2.0:
		return
	var win := Vector2i(int(round(screen.x * 0.92)), int(round(screen.y * 0.92)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(win)
	var origin := DisplayServer.screen_get_position()
	DisplayServer.window_set_position(origin + (screen - win) / 2)

func _environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://scripts/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2a3558")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color("141c36")
	# Distance haze stays thin so it does not stack with the volumetric layer.
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	# A light veil the lamps can catch. Density stays low so the floor and
	# the character do not disappear into it.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.62, 0.7, 0.88)
	env.volumetric_fog_emission = Color(0.04, 0.05, 0.09)
	env.volumetric_fog_emission_energy = 0.2
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 42.0
	env.volumetric_fog_detail_spread = 1.4
	env.volumetric_fog_ambient_inject = 0.3
	env.volumetric_fog_sky_affect = 0.04
	env.ssao_enabled = true
	env.ssao_intensity = 1.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _moon() -> void:
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("9fb6ff")
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	# Blur feathers the edge. A wide angular size would switch on the expensive
	# penumbra search, which the fog then repeats for every cell.
	moon.shadow_blur = 2.4
	moon.rotation_degrees = Vector3(-38, -32, 0)
	add_child(moon)

func _box(size: Vector3, pos: Vector3, color: Color, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi

func _floor() -> void:
	var size := 80.0
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/tiles.gdshader")
	plane.material = mat
	mi.mesh = plane
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, 1, size)
	cs.shape = shape
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	# Invisible walls at the edge of the tiled area.
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall := StaticBody3D.new()
		var wcs := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = Vector3(1 if side.x != 0 else size, 6, 1 if side.z != 0 else size)
		wcs.shape = ws
		wall.add_child(wcs)
		wall.position = side * (size * 0.5 - 4.0) + Vector3(0, 3, 0)
		add_child(wall)

func _blocks() -> void:
	# Plain grey prototype blocks on the tile grid (2 m tiles), keeping the spawn clear.
	var spots := [Vector2(3, -2), Vector2(-4, -3), Vector2(5, 3), Vector2(-3, 4), Vector2(0, -6),
		Vector2(8, -5), Vector2(-8, 0), Vector2(7, 7), Vector2(-7, -7), Vector2(2, 9), Vector2(-10, 6), Vector2(11, 1)]
	for s in spots:
		var w := float(rng.randi_range(1, 2)) * 2.0
		var d := float(rng.randi_range(1, 2)) * 2.0
		var h: float = [1.0, 1.0, 2.0, 3.0][rng.randi_range(0, 3)]
		var tone := rng.randf_range(0.42, 0.55)
		var pos := Vector3(s.x * 2.0 + w * 0.5 - 1.0, h * 0.5, s.y * 2.0 + d * 0.5 - 1.0)
		_box(Vector3(w, h, d), pos, Color(tone, tone, tone + 0.02))
		_solids.append(AABB(pos - Vector3(w, h, d) * 0.5, Vector3(w, h, d)))
		_block_tops.append(pos + Vector3(0, h * 0.5, 0))

func _lamps() -> void:
	var spots := [Vector3(-2, 0, -2), Vector3(6, 0, -8), Vector3(-9, 0, 4), Vector3(9, 0, 5), Vector3(-6, 0, -10),
		Vector3(1, 0, 6), Vector3(14, 0, -2), Vector3(-14, 0, -4)]
	for p in spots:
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.09
		cyl.height = 3.2
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color("2b2d33")
		cyl.material = pm
		pole.mesh = cyl
		pole.position = p + Vector3(0, 1.6, 0)
		add_child(pole)
		var bulb := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.32
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color("ffd59a")
		bm.emission_enabled = true
		bm.emission = Color("ffb860")
		bm.emission_energy_multiplier = 2.5
		sph.material = bm
		bulb.mesh = sph
		bulb.position = p + Vector3(0, 3.25, 0)
		add_child(bulb)
		var glow := AudioStreamPlayer3D.new()
		glow.stream = preload("res://assets/sfx/lamp_glow.wav")
		glow.volume_db = -16.0
		glow.unit_size = 2.2
		glow.max_distance = 7.0
		glow.position = p + Vector3(0, 3.0, 0)
		add_child(glow)
		glow.play(rng.randf() * glow.stream.get_length())
		var light := OmniLight3D.new()
		light.light_color = Color("ffbe78")
		light.light_energy = 2.2
		light.omni_range = 8.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = true
		# Blur keeps the pool soft. light_size would turn on penumbra sampling
		# for every fog cell this lamp reaches.
		light.shadow_blur = 2.4
		light.position = p + Vector3(0, 3.0, 0)
		add_child(light)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.12
		shape.height = 3.2
		cs.shape = shape
		body.add_child(cs)
		body.position = p + Vector3(0, 1.6, 0)
		add_child(body)
		_solids.append(AABB(p - Vector3(0.15, 0, 0.15), Vector3(0.3, 3.4, 0.3)))

func _spawn_monster() -> bool:
	if _player == null:
		return false
	for _attempt in 8:
		var ang := rng.randf() * TAU
		var pos := _player.global_position + Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(8.0, 13.0)
		pos.y = 0.05
		pos.x = clampf(pos.x, -28.0, 28.0)
		pos.z = clampf(pos.z, -28.0, 28.0)
		if Vector2(pos.x - _player.global_position.x, pos.z - _player.global_position.z).length() < 6.0:
			continue
		var blocked := false
		for s in _solids:
			if s.grow(0.4).has_point(pos + Vector3(0, 0.4, 0)):
				blocked = true
				break
		if blocked:
			continue
		var m := CharacterBody3D.new()
		m.set_script(MONSTER)
		m.player = _player
		add_child(m)
		m.global_position = pos
		return true
	return false

func _on_health_changed(current: int) -> void:
	_hearts_label.text = "Hearts  %d" % current
	if current > 0:
		return
	_banner.text = "The cube got you"
	_banner.modulate.a = 1.0
	var tw := _banner.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)

const COIN_GAP := 3.6

var _coin_spots: Array[Vector3] = []

func _coins() -> void:
	# Ground coins are walked into. They sit across the yard, not in a pile at the spawn.
	for p in [
		Vector3(5.2, 0, 3.4), Vector3(-6.2, 0, -2.2), Vector3(1.2, 0, -8.4),
		Vector3(-2.4, 0, 7.6), Vector3(10.5, 0, -2.0), Vector3(-12.5, 0, 6.5),
		Vector3(14.0, 0, 9.5), Vector3(-9.5, 0, -12.0), Vector3(18.0, 0, -6.5),
		Vector3(3.5, 0, 15.5), Vector3(-17.5, 0, -4.5), Vector3(21.0, 0, 5.5),
		Vector3(-5.0, 0, 16.0), Vector3(7.5, 0, -16.0),
	]:
		_coin(p + Vector3(0, COIN_Y, 0))
	# Longer arcs, three coins each, so a jump still traces them without a cluster.
	_arc(Vector3(-16, 0, 2), Vector3(-7, 0, 9), 3, 1.55)
	_arc(Vector3(9, 0, -15), Vector3(18, 0, -8), 3, 1.6)
	_arc(Vector3(-8, 0, 18), Vector3(2, 0, 11), 3, 1.45)
	# Two lone coins at jump height, far from the ground set.
	_coin(Vector3(-19.0, 1.75, -13.0))
	_coin(Vector3(23.0, 1.7, -5.0))
	# A few coins on blocks he can climb, chosen so they stay apart.
	var tops: Array[Vector3] = []
	for top in _block_tops:
		if top.y <= 2.0:
			tops.append(top)
	tops.sort_custom(func(a: Vector3, b: Vector3) -> bool: return Vector2(a.x, a.z).length() > Vector2(b.x, b.z).length())
	var on_blocks := 0
	for top in tops:
		var before := coins_total
		_coin(top + Vector3(0, 0.7, 0))
		if coins_total > before:
			on_blocks += 1
		if on_blocks >= 4:
			break
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.stream = preload("res://assets/sfx/coin.wav")
		p.volume_db = -6.0
		add_child(p)
		_coin_players.append(p)

func _arc(from: Vector3, to: Vector3, count: int, peak: float) -> void:
	for i in count:
		var t := float(i) / float(count - 1)
		_coin(from.lerp(to, t) + Vector3(0, COIN_Y + peak * sin(PI * t), 0))

func _coin(pos: Vector3) -> void:
	for s in _solids:
		if s.grow(0.45).has_point(pos):
			return
	for prev in _coin_spots:
		if Vector2(prev.x - pos.x, prev.z - pos.z).length() < COIN_GAP:
			return
	_coin_spots.append(pos)
	var c := Area3D.new()
	c.set_script(COIN)
	c.position = pos
	c.collected.connect(_on_coin_collected)
	add_child(c)
	coins_total += 1

func _on_coin_collected(_coin_node: Node3D) -> void:
	coins_collected += 1
	var now := Time.get_ticks_msec()
	_combo = mini(_combo + 1, COMBO_SEMITONES.size() - 1) if now - _last_coin_ms < COMBO_WINDOW_MS else 0
	_last_coin_ms = now
	var p := _coin_players[_coin_player_i]
	_coin_player_i = (_coin_player_i + 1) % _coin_players.size()
	p.pitch_scale = pow(2.0, COMBO_SEMITONES[_combo] / 12.0)
	p.play()
	_update_coin_label()
	if coins_collected == coins_total:
		_banner.text = "All %d coins collected!" % coins_total
		_banner.modulate.a = 1.0
		var tw := _banner.create_tween()
		tw.tween_interval(3.0)
		tw.tween_property(_banner, "modulate:a", 0.0, 1.0)

func _update_coin_label() -> void:
	_coin_label.text = "Coins  %d / %d" % [coins_collected, coins_total]

var _whistle: AudioStreamPlayer3D
var _whistle_timer: Timer

func _ambience() -> void:
	var tune := AudioStreamPlayer.new()
	tune.stream = preload("res://assets/sfx/tune.wav")
	tune.volume_db = -11.0
	tune.autoplay = true
	add_child(tune)
	_whistle = AudioStreamPlayer3D.new()
	_whistle.stream = preload("res://assets/sfx/whistle.wav")
	_whistle.volume_db = -4.0
	_whistle.unit_size = 12.0
	_whistle.max_distance = 36.0
	add_child(_whistle)
	_whistle_timer = Timer.new()
	_whistle_timer.one_shot = true
	_whistle_timer.timeout.connect(_whistle_call)
	add_child(_whistle_timer)
	_whistle_timer.start(rng.randf_range(4.0, 7.0))

func _whistle_call() -> void:
	# A short bright call from somewhere nearby, not a far-off hoot.
	var a := rng.randf_range(0.0, TAU)
	_whistle.position = Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(8.0, 16.0) + Vector3(0, 2.5, 0)
	_whistle.pitch_scale = rng.randf_range(0.97, 1.1)
	_whistle.play()
	_whistle_timer.start(rng.randf_range(8.0, 14.0))

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var l := Label.new()
	l.text = "WASD / arrows: walk    Hold Shift: run    Space: jump, again to double jump    Land on an orange cube to squash it    Esc: quit"
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.offset_left = 16
	l.offset_top = 12
	l.offset_right = -340
	l.offset_bottom = 36
	l.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0, 0.75))
	l.add_theme_font_size_override("font_size", 16)
	layer.add_child(l)
	var view := get_viewport().get_visible_rect().size
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var phone := base_h > base_w or view.y > view.x
	if phone:
		l.visible = false
	_coin_label = Label.new()
	_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coin_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_coin_label.offset_left = -300
	_coin_label.offset_right = -36 if phone else -20
	_coin_label.offset_top = 300 if phone else 40
	_coin_label.add_theme_color_override("font_color", Color("ffd36b"))
	_coin_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.02, 0.8))
	_coin_label.add_theme_constant_override("outline_size", 6)
	_coin_label.add_theme_font_size_override("font_size", 26)
	layer.add_child(_coin_label)
	_update_coin_label()
	_hearts_label = Label.new()
	_hearts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hearts_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hearts_label.offset_left = -300
	_hearts_label.offset_right = -36 if phone else -20
	_hearts_label.offset_top = 348 if phone else 74
	_hearts_label.add_theme_color_override("font_color", Color("ff8d6b"))
	_hearts_label.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 0.8))
	_hearts_label.add_theme_constant_override("outline_size", 6)
	_hearts_label.add_theme_font_size_override("font_size", 26)
	layer.add_child(_hearts_label)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -280 if phone else -400
	_banner.offset_right = 280 if phone else 400
	_banner.offset_top = 360 if phone else 120
	_banner.add_theme_color_override("font_color", Color("ffe39a"))
	_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.02, 0.85))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.modulate.a = 0.0
	layer.add_child(_banner)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		get_tree().quit()
