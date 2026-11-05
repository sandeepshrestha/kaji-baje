extends Node3D
## Patan Durbar Square, seen from the south. Kaji Baje runs along X on the
## courtyard paving, and the camera watches from the front of the lane.

const PLAYER := preload("res://scripts/player.gd")
const MONSTER := preload("res://scripts/monster.gd")
const COIN := preload("res://scripts/coin.gd")
const DURBAR := preload("res://assets/patan/durbar.glb")
const PLINTH := preload("res://assets/patan/plinth.glb")
const CHAITYA := preload("res://assets/patan/chaitya.glb")
const COURT_BRICK := preload("res://assets/patan/court_brick.glb")
const BRICK_TEX := preload("res://assets/patan/court_brick.png")
const STONE_TEX := preload("res://assets/patan/court_stone.png")
const MAX_MONSTERS := 3
const SPAWN_EVERY := 3.0
const COIN_Y := 0.6                       # coin centre height when resting on the ground
const COMBO_WINDOW_MS := 700
const STREET_X0 := -54.0
const STREET_X1 := 54.0
const LANE_Z := 0.0
# The exported square has its south edge at local z = 0 and its paving top at y = 0.
# One square is about 33 m wide. Two more sit beside it so the run is three times as long.
const DURBAR_POS := Vector3(0.0, 0.0, -1.5)
const SECTION_X := [-36.0, 0.0, 36.0]
# x, height, width, inside one square. 1 m is one jump, 2 m is the double jump.
const PLATFORMS := [
	Vector3(-12, 1, 2.6), Vector3(-4, 1, 3.0), Vector3(6, 2, 3.2), Vector3(13, 1, 2.8),
]
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
var _hearts: Array[TextureRect] = []
static var start_immediately := false
# Restart skips the home screen but still teaches a fresh run. Recordings only
# set start_immediately, and that path never opens the guide.
static var restart_into_play := false
var _play_hud: CanvasLayer
var _home: Control
var _pause_menu: Control
var _start_button: Button
var _resume_button: Button
var _guide_layer: CanvasLayer
var _guide_root: Control
var _guide_card: PanelContainer
var _guide_stack: VBoxContainer
var _guide_index: Label
var _guide_name: Label
var _guide_copy: Label
var _guide_keys: HBoxContainer
var _guide_dots: Array[Panel] = []
var _guide_tween: Tween
var _guide_step := 0
var _guide_active := false
var _guide_busy := false
var _guide_moved := false
var _guide_ran := false
var _guide_jumped := false
var _guide_doubled := false
var _guide_swung := false
var _guide_cracked := false
var _guide_jump_base := 0
var _guide_double_base := 0
var _guide_swing_base := 0
var _guide_crack_base := 0
var _guide_rest_top := 0.0
var _guide_rest_bottom := 0.0
var _guide_hold := 0.0

const HUD_FONT := preload("res://assets/ui/numaposa.ttf")
const HUD_COIN_ICON := preload("res://assets/ui/icon_coin.png")
const HUD_HEART_ICON := preload("res://assets/ui/icon_heart.png")
var _spawn_wait := 1.2
const DAY_LENGTH := 180.0
var _day := 0.21
var _env: Environment
var _sky_mat: ShaderMaterial
var _key: DirectionalLight3D
var _lamp_lights: Array[OmniLight3D] = []
var _time_label: Label

func _ready() -> void:
	_fit_window()
	rng.seed = 7
	_environment()
	_daylight()
	_durbar()
	_floor()
	_blocks()
	_lamps()
	_apply_day()
	_coins()
	_player = CharacterBody3D.new()
	_player.set_script(PLAYER)
	_player.name = "KajiBaje"
	add_child(_player)
	# Just inside the left rail, clear of the first coin. Death returns him here.
	_player.spawn_point = Vector3(STREET_X0 + 1.2, 0.05, 0)
	_player.global_position = _player.spawn_point
	var cam := preload("res://scripts/follow_camera.gd").new()
	cam.target = _player
	add_child(cam)
	_hud()
	_player.health_changed.connect(_on_health_changed)
	_on_health_changed(_player.health)
	_ambience()
	_menus()
	var recording := start_immediately
	var restarted := restart_into_play
	start_immediately = false
	restart_into_play = false
	if recording or restarted:
		_play_hud.visible = true
		_home.visible = false
		if restarted:
			_start_guide()
	else:
		_play_hud.visible = false
		_home.visible = true
		get_tree().paused = true
		_start_button.grab_focus()

func _process(delta: float) -> void:
	_day = fposmod(_day + delta / DAY_LENGTH, 1.0)
	_apply_day()
	_guide_tick(delta)
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
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://scripts/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	var env := Environment.new()
	_env = env
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

func _daylight() -> void:
	# One shadowed light. It follows the sun while the sun is up, then the moon.
	# No angular size: that would turn on the penumbra search the fog repeats.
	_key = DirectionalLight3D.new()
	_key.shadow_enabled = true
	_key.shadow_blur = 2.4
	add_child(_key)
	# A dim fill from the camera, with no shadow, so the hero stays readable
	# when the sun or moon sits over the temples.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("fff4e4")
	fill.light_energy = 0.12
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-28, 12, 0)
	add_child(fill)

func _apply_day() -> void:
	if _sky_mat == null or _key == null:
		return
	# Sun crosses the sky the camera can see: right horizon, overhead, left horizon.
	var sun_t := clampf((_day - 0.22) / 0.56, 0.0, 1.0)
	var elev := sin(sun_t * PI) if _day >= 0.22 and _day <= 0.78 else -0.35
	var across := lerpf(1.15, -1.15, sun_t)
	var sun_dir := Vector3(sin(across) * 0.75, elev, -0.55).normalized()
	var moon_dir := (-sun_dir).normalized()
	var dayness := smoothstep(-0.02, 0.42, sun_dir.y)
	var golden := (1.0 - smoothstep(0.02, 0.38, sun_dir.y)) * dayness
	var rising := sun_dir.x > 0.0
	var night_h := Color("0d1229")
	var day_h := Color("7eafd4")
	var warm_h := Color("f0a06a") if rising else Color("e06a3c")
	var horizon := night_h.lerp(day_h, dayness).lerp(warm_h, golden * 0.55)
	var night_top := Color("03060f")
	var day_top := Color("2f6eb8")
	var warm_top := Color("5a78b0") if rising else Color("3a3058")
	var top := night_top.lerp(day_top, dayness).lerp(warm_top, golden * 0.4)
	var sun_col := Color("ffd39a").lerp(Color("ff8a45"), golden)
	_sky_mat.set_shader_parameter("top_color", top)
	_sky_mat.set_shader_parameter("horizon_color", horizon)
	_sky_mat.set_shader_parameter("sun_color", sun_col)
	_sky_mat.set_shader_parameter("moon_color", Color("d5e2ff"))
	_sky_mat.set_shader_parameter("sun_dir", sun_dir)
	_sky_mat.set_shader_parameter("moon_dir", moon_dir)
	_sky_mat.set_shader_parameter("stars", 1.0 - dayness)
	_sky_mat.set_shader_parameter("sun_disc", smoothstep(-0.02, 0.06, sun_dir.y))
	_sky_mat.set_shader_parameter("moon_disc", smoothstep(-0.02, 0.08, moon_dir.y))
	_sky_mat.set_shader_parameter("sun_glow", lerpf(0.15, 0.85, golden))
	var key_dir := sun_dir if sun_dir.y > moon_dir.y else moon_dir
	_key.global_position = key_dir * 30.0
	_key.look_at(Vector3.ZERO, Vector3.UP)
	if sun_dir.y > 0.0:
		_key.light_color = sun_col
		_key.light_energy = lerpf(0.35, 0.68, smoothstep(0.0, 0.45, sun_dir.y))
	else:
		_key.light_color = Color("9fb4ff")
		_key.light_energy = lerpf(0.12, 0.42, smoothstep(0.0, 0.35, moon_dir.y))
	var nightness := 1.0 - dayness
	_env.ambient_light_color = Color("1a2440").lerp(Color("6f97bf"), dayness).lerp(warm_h, golden * 0.25)
	_env.ambient_light_energy = lerpf(0.32, 0.4, dayness)
	_env.tonemap_exposure = lerpf(1.08, 0.9, dayness)
	_env.fog_light_color = horizon.darkened(0.45)
	_env.fog_density = lerpf(0.008, 0.004, dayness)
	_env.volumetric_fog_density = lerpf(0.02, 0.006, dayness)
	_env.volumetric_fog_albedo = Color(0.62, 0.7, 0.88).lerp(Color(0.62, 0.74, 0.88), dayness)
	_env.volumetric_fog_emission = Color(0.04, 0.05, 0.09).lerp(warm_h * 0.08, golden)
	for lamp in _lamp_lights:
		lamp.light_energy = lerpf(0.08, 2.2, nightness)
		var want_shadow := absf(lamp.position.x) < 20.0 and nightness > 0.55
		if lamp.shadow_enabled != want_shadow:
			lamp.shadow_enabled = want_shadow
	if _time_label != null:
		_time_label.text = _time_name(_day)

func _time_name(t: float) -> String:
	if t < 0.20 or t >= 0.80:
		return "Night"
	if t < 0.35:
		return "Morning"
	if t < 0.65:
		return "Day"
	return "Evening"

func _durbar() -> void:
	for origin in SECTION_X:
		var square := DURBAR.instantiate()
		square.position = DURBAR_POS + Vector3(origin, 0.0, 0.0)
		add_child(square)
		_dress_square(square)

func _court_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.86
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	# One tile is a few bricks across, so the court reads at the hero's scale.
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

func _paint(root: Node, tex: Texture2D) -> void:
	var mat := _court_mat(tex)
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)

func _dress_square(root: Node) -> void:
	var brick := _court_mat(BRICK_TEX)
	var stone := _court_mat(STONE_TEX)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var src := mi.mesh.surface_get_material(0)
		var name := src.resource_name if src != null else ""
		var mat: Material = null
		if "Courtyard_Brick" in name:
			mat = brick
		elif "Courtyard_Stone" in name or "Base_Stone" in name or "Sandstone_Blocks" in name:
			mat = stone
		if mat == null:
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)

func _floor() -> void:
	var length := STREET_X1 - STREET_X0
	# The near edge reaches past the camera, so the court fills the foreground
	# instead of ending in empty sky under his feet.
	var depth := 32.0
	var center := Vector3((STREET_X0 + STREET_X1) * 0.5, 0.0, 8.0)
	var z0 := -3.0
	var z1 := 24.0
	var pave := _drop_prop(COURT_BRICK, Vector3(center.x, 0.0, (z0 + z1) * 0.5), Vector3(length, -1.0, z1 - z0))
	# Sit the top of the slab just under the square's paving so the two don't flicker.
	var pave_box := _mesh_bounds(pave)
	pave.position.y -= pave_box.size.y * pave.scale.y + 0.02
	_paint(pave, BRICK_TEX)
	var pave_meshes: Array[Node] = []
	if pave is MeshInstance3D:
		pave_meshes.append(pave)
	pave_meshes.append_array(pave.find_children("*", "MeshInstance3D", true, false))
	for mi in pave_meshes:
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 1.0, depth)
	cs.shape = shape
	cs.position = center + Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	# Invisible rails. They keep him on the court without adding grey walls.
	_wall(Vector3(STREET_X0, 3.0, center.z), Vector3(1.0, 6.0, depth))
	_wall(Vector3(STREET_X1, 3.0, center.z), Vector3(1.0, 6.0, depth))
	_wall(Vector3(center.x, 3.0, center.z - depth * 0.5), Vector3(length, 6.0, 1.0))
	_wall(Vector3(center.x, 3.0, center.z + depth * 0.5), Vector3(length, 6.0, 1.0))

func _wall(pos: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var ws := BoxShape3D.new()
	ws.size = size
	wcs.shape = ws
	wall.add_child(wcs)
	wall.position = pos
	add_child(wall)

func _blocks() -> void:
	for origin in SECTION_X:
		for spec in PLATFORMS:
			_place_block(spec.x + origin, spec.y, spec.z)

func _place_block(x: float, h: float, w: float) -> void:
	var depth := 2.4
	_paint(_drop_prop(PLINTH, Vector3(x, 0.0, LANE_Z), Vector3(w, h, depth)), STONE_TEX)
	var pos := Vector3(x, h * 0.5, LANE_Z)
	# The plinth mesh has no collision of its own, so a box of the jump size stands in for it.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, depth)
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	add_child(body)
	_solids.append(AABB(pos - Vector3(w, h, depth) * 0.5, Vector3(w, h, depth)))
	_block_tops.append(pos + Vector3(0, h * 0.5, 0))

func _mesh_bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for mi in meshes:
		var aabb: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = (root as Node3D).global_transform.affine_inverse() * (mi as Node3D).global_transform
		aabb = xf * aabb
		box = aabb if first else box.merge(aabb)
		first = false
	return box

## Puts a Patan prop so its base sits on bottom_center. Pass fit.x/y/z above 0
## to stretch that axis to a size in metres; -1 leaves the exported size.
func _drop_prop(scene: PackedScene, bottom_center: Vector3, fit: Vector3 = Vector3(-1, -1, -1)) -> Node3D:
	var n: Node3D = scene.instantiate()
	add_child(n)
	var box := _mesh_bounds(n)
	var sx := 1.0 if fit.x <= 0.0 else fit.x / maxf(box.size.x, 0.001)
	var sy := 1.0 if fit.y <= 0.0 else fit.y / maxf(box.size.y, 0.001)
	var sz := 1.0 if fit.z <= 0.0 else fit.z / maxf(box.size.z, 0.001)
	n.scale = Vector3(sx, sy, sz)
	n.position = Vector3(
		bottom_center.x - sx * (box.position.x + box.size.x * 0.5),
		bottom_center.y - sy * box.position.y,
		bottom_center.z - sz * (box.position.z + box.size.z * 0.5)
	)
	return n

func _lamps() -> void:
	# Chaityas stand on the near rim of the square. The light sits just above
	# them; there is no separate bulb mesh, and no penumbra search.
	for origin in SECTION_X:
		for x in [-15.0, -1.0, 10.0]:
			_place_lamp(x + origin)

func _place_lamp(x: float) -> void:
	var p := Vector3(x, 0.0, -0.85)
	_drop_prop(CHAITYA, p)
	var glow := AudioStreamPlayer3D.new()
	glow.stream = preload("res://assets/sfx/lamp_glow.wav")
	glow.volume_db = -16.0
	glow.unit_size = 2.2
	glow.max_distance = 7.0
	glow.position = p + Vector3(0, 1.4, 0)
	add_child(glow)
	glow.play(rng.randf() * glow.stream.get_length())
	var light := OmniLight3D.new()
	light.light_color = Color("ffbe78")
	light.light_energy = 2.2
	light.omni_range = 8.0
	light.omni_attenuation = 1.4
	# Only the middle square casts these shadows. The wings stay lit without
	# adding more shadowed lamps for the fog to sample.
	light.shadow_enabled = absf(x) < 20.0
	light.shadow_blur = 2.4
	light.position = p + Vector3(0, 1.8, 0)
	add_child(light)
	_lamp_lights.append(light)

func _spawn_monster() -> bool:
	if _player == null:
		return false
	for _attempt in 8:
		var dir := 1.0 if rng.randf() > 0.3 else -1.0
		var pos := Vector3(_player.global_position.x + dir * rng.randf_range(7.0, 13.0), 0.05, LANE_Z)
		pos.x = clampf(pos.x, STREET_X0 + 2.0, STREET_X1 - 2.0)
		if absf(pos.x - _player.global_position.x) < 6.0:
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
	for i in _hearts.size():
		_hearts[i].modulate = Color.WHITE if i < current else Color(0.25, 0.25, 0.3, 0.5)
	if current > 0:
		return
	_banner.text = "The critters got you"
	_banner.modulate.a = 1.0
	var tw := _banner.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)

const COIN_GAP := 2.6

var _coin_spots: Array[Vector3] = []

func _coins() -> void:
	# Along the pavement, far enough apart that they read one at a time.
	for origin in SECTION_X:
		for x in [-16.0, -8.0, 16.0]:
			_coin(Vector3(x + origin, COIN_Y, LANE_Z))
		# A jump's arc between platforms, and one coin only a double jump can take.
		_arc(Vector3(-2.0 + origin, 0, LANE_Z), Vector3(3.6 + origin, 0, LANE_Z), 3, 1.5)
		_coin(Vector3(9.4 + origin, 2.55, LANE_Z))
	for top in _block_tops:
		_coin(top + Vector3(0, 0.55, 0))
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
	_coin_label.text = "%d / %d" % [coins_collected, coins_total]

var _whistle: AudioStreamPlayer3D
var _whistle_timer: Timer

func _ambience() -> void:
	var tune := AudioStreamPlayer.new()
	tune.stream = preload("res://assets/sfx/tune.wav")
	tune.volume_db = -11.0
	tune.autoplay = true
	tune.process_mode = Node.PROCESS_MODE_ALWAYS
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
	_play_hud = layer
	add_child(layer)
	_time_label = Label.new()
	_time_label.text = _time_name(_day)
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_time_label.offset_left = 16
	_time_label.offset_top = 14
	_time_label.offset_right = 240
	_time_label.offset_bottom = 46
	_time_label.add_theme_font_override("font", HUD_FONT)
	_time_label.add_theme_font_size_override("font_size", 20)
	_time_label.add_theme_color_override("font_color", Color("ffe39a"))
	_time_label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 0.8))
	_time_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_time_label)
	var view := get_viewport().get_visible_rect().size
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var phone := base_h > base_w or view.y > view.x
	var coin_row := _hud_row(layer, 300 if phone else 36, -36 if phone else -20)
	coin_row.add_child(_hud_icon(HUD_COIN_ICON, 38))
	_coin_label = Label.new()
	_coin_label.add_theme_font_override("font", HUD_FONT)
	_coin_label.add_theme_color_override("font_color", Color("ffd36b"))
	_coin_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.02, 0.8))
	_coin_label.add_theme_constant_override("outline_size", 6)
	_coin_label.add_theme_font_size_override("font_size", 30)
	coin_row.add_child(_coin_label)
	_update_coin_label()
	var heart_row := _hud_row(layer, 348 if phone else 82, -36 if phone else -20)
	for i in PLAYER.MAX_HEALTH:
		var heart := _hud_icon(HUD_HEART_ICON, 30)
		heart_row.add_child(heart)
		_hearts.append(heart)
	_banner = Label.new()
	_banner.add_theme_font_override("font", HUD_FONT)
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

func _hud_row(layer: CanvasLayer, top: float, right: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -320
	row.offset_right = right
	row.offset_top = top
	row.offset_bottom = top + 40
	layer.add_child(row)
	return row

func _hud_icon(tex: Texture2D, px: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(px, px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon

func _menus() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_home = _menu_screen()
	layer.add_child(_home)
	var home_box := _menu_column(_home)
	home_box.add_child(_menu_title("Kaajiman", 92))
	home_box.add_child(_menu_note("A night run through Patan Durbar"))
	_start_button = _menu_button("Start")
	_start_button.pressed.connect(_begin)
	home_box.add_child(_start_button)
	_pause_menu = _menu_screen()
	_pause_menu.visible = false
	layer.add_child(_pause_menu)
	var pause_box := _menu_column(_pause_menu)
	pause_box.add_child(_menu_title("Paused", 72))
	_resume_button = _menu_button("Resume")
	_resume_button.pressed.connect(_begin)
	pause_box.add_child(_resume_button)
	var restart := _menu_button("Restart")
	restart.pressed.connect(_restart_run)
	pause_box.add_child(restart)
	_resume_button.focus_neighbor_bottom = _resume_button.get_path_to(restart)
	restart.focus_neighbor_top = restart.get_path_to(_resume_button)

func _menu_screen() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.09, 0.58)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	return root

func _menu_column(screen: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	return box

func _menu_title(text: String, size: int) -> Label:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", HUD_FONT)
	title.add_theme_font_size_override("font_size", size)
	title.add_theme_color_override("font_color", Color("ffe39a"))
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 0.9))
	title.add_theme_constant_override("outline_size", 16)
	return title

func _menu_note(text: String) -> Label:
	var note := Label.new()
	note.text = text
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_override("font", HUD_FONT)
	note.add_theme_font_size_override("font_size", 22)
	note.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96, 0.9))
	return note

func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 58)
	button.add_theme_font_override("font", HUD_FONT)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color("1a1208"))
	button.add_theme_color_override("font_hover_color", Color("1a1208"))
	button.add_theme_color_override("font_pressed_color", Color("1a1208"))
	button.add_theme_color_override("font_focus_color", Color("1a1208"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("ffe39a")
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("fff1c9")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("e0c07a")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	return button

func _begin() -> void:
	var from_home := _home.visible
	_home.visible = false
	_pause_menu.visible = false
	_play_hud.visible = true
	get_tree().paused = false
	if from_home:
		_start_guide()
	elif _guide_active:
		_guide_show_after_menu()

func _open_pause() -> void:
	if _home.visible or get_tree().paused:
		return
	_guide_hide_for_menu()
	_pause_menu.visible = true
	get_tree().paused = true
	_resume_button.grab_focus()

func _restart_run() -> void:
	restart_into_play = true
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_escape() -> void:
	if _home.visible:
		get_tree().quit()
	elif get_tree().paused:
		_begin()
	else:
		_open_pause()

# Taught after Start, in the order the old help line listed them. Esc is shown
# on the last card and still opens the pause menu; it is not a required step.
const GUIDE_STEPS := [
	{
		"index": "01",
		"name": "Move",
		"body": "Walk with A and D, or the arrows.",
		"keys": ["A", "D"],
	},
	{
		"index": "02",
		"name": "Run",
		"body": "Hold Shift to sprint.",
		"keys": ["Shift"],
	},
	{
		"index": "03",
		"name": "Jump",
		"body": "Space hops the low blocks.",
		"keys": ["Space"],
	},
	{
		"index": "04",
		"name": "Again",
		"body": "Jump once more for the tall ones.",
		"keys": ["Space"],
	},
	{
		"index": "05",
		"name": "Swing",
		"body": "Press J. The cane sweeps ahead of him.",
		"keys": ["J"],
	},
	{
		"index": "06",
		"name": "Crack",
		"body": "Press K. Bring the cane down hard.",
		"keys": ["K"],
	},
	{
		"index": "07",
		"name": "Ready",
		"body": "Esc pauses. Stomp a critter from above.",
		"keys": ["Esc"],
	},
]

func _unhandled_input(event: InputEvent) -> void:
	if not _guide_active or get_tree().paused or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.physical_keycode == KEY_ESCAPE:
		return
	match key_event.physical_keycode:
		KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT:
			_guide_moved = true
		KEY_SHIFT:
			_guide_ran = true

func _phone_layout() -> bool:
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	if base_h > base_w:
		return true
	var view := get_viewport().get_visible_rect().size
	return view.y > view.x

func _start_guide() -> void:
	if _guide_active:
		return
	_guide_active = true
	_guide_moved = false
	_guide_ran = false
	_guide_jumped = false
	_guide_doubled = false
	_guide_swung = false
	_guide_cracked = false
	_guide_jump_base = _guide_jumps("jump")
	_guide_double_base = _guide_jumps("double_jump")
	_guide_swing_base = int(_player.get("swings"))
	_guide_crack_base = int(_player.get("cracks"))
	_guide_step = 0
	_guide_busy = false
	_guide_hold = 0.0
	_build_guide()
	_guide_place()
	_guide_fill(0)
	get_viewport().gui_release_focus()
	_guide_intro()

func _guide_jumps(which: String) -> int:
	var counts: Variant = _player.get("jump_counts")
	if counts is Dictionary:
		return int((counts as Dictionary).get(which, 0))
	return 0

func _guide_watch() -> void:
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_D) \
			or Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_RIGHT):
		_guide_moved = true
	if Input.is_physical_key_pressed(KEY_SHIFT):
		_guide_ran = true
	if _guide_jumps("jump") > _guide_jump_base:
		_guide_jumped = true
	if _guide_jumps("double_jump") > _guide_double_base:
		_guide_doubled = true
	if int(_player.get("swings")) > _guide_swing_base:
		_guide_swung = true
	if int(_player.get("cracks")) > _guide_crack_base:
		_guide_cracked = true

func _guide_step_done(step: int) -> bool:
	match step:
		0:
			return _guide_moved
		1:
			return _guide_ran
		2:
			return _guide_jumped
		3:
			return _guide_doubled
		4:
			return _guide_swung
		5:
			return _guide_cracked
		_:
			return false

func _guide_tick(delta: float) -> void:
	if not _guide_active:
		return
	_guide_watch()
	if _guide_step >= GUIDE_STEPS.size() - 1:
		if not _guide_busy:
			_guide_hold += delta
			if _guide_hold >= 2.4:
				_guide_finish()
		return
	if _guide_busy:
		return
	if _guide_step_done(_guide_step):
		_guide_present(_guide_step + 1)

func _build_guide() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_guide_layer = layer
	add_child(layer)
	var root := Control.new()
	_guide_root = root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.focus_mode = Control.FOCUS_NONE
	root.modulate.a = 0.0
	layer.add_child(root)
	var card := PanelContainer.new()
	_guide_card = card
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("0c101c", 0.88)
	plate.set_corner_radius_all(12)
	plate.content_margin_left = 14
	plate.content_margin_right = 14
	plate.content_margin_top = 12
	plate.content_margin_bottom = 8
	plate.border_width_left = 1
	plate.border_width_top = 1
	plate.border_width_right = 1
	plate.border_width_bottom = 1
	plate.border_color = Color("ffe39a", 0.28)
	plate.shadow_color = Color(0, 0, 0, 0.28)
	plate.shadow_size = 6
	plate.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", plate)
	root.add_child(card)
	var stack := VBoxContainer.new()
	_guide_stack = stack
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stack)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(body)
	_guide_keys = HBoxContainer.new()
	_guide_keys.alignment = BoxContainer.ALIGNMENT_CENTER
	_guide_keys.add_theme_constant_override("separation", 6)
	_guide_keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_guide_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_guide_keys)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(text)
	var kicker := HBoxContainer.new()
	kicker.add_theme_constant_override("separation", 8)
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(kicker)
	_guide_index = _guide_label(13, Color("e0c07a"))
	_guide_index.size_flags_vertical = Control.SIZE_SHRINK_END
	kicker.add_child(_guide_index)
	_guide_name = _guide_label(20, Color("ffe39a"))
	_guide_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_guide_name.size_flags_vertical = Control.SIZE_SHRINK_END
	kicker.add_child(_guide_name)
	_guide_copy = _guide_label(14, Color("ffe39a", 0.78))
	_guide_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_guide_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_copy.custom_minimum_size = Vector2(168, 0)
	text.add_child(_guide_copy)
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(footer)
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 6)
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(dots)
	_guide_dots.clear()
	for _i in GUIDE_STEPS.size():
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dots.add_child(dot)
		_guide_dots.append(dot)
		_guide_set_dot(dot, false)
	var skip := Button.new()
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	skip.mouse_filter = Control.MOUSE_FILTER_STOP
	skip.custom_minimum_size = Vector2(48, 22)
	skip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	skip.add_theme_font_override("font", HUD_FONT)
	skip.add_theme_font_size_override("font_size", 13)
	skip.add_theme_color_override("font_color", Color("ffe39a", 0.55))
	skip.add_theme_color_override("font_hover_color", Color("ffe39a"))
	skip.add_theme_color_override("font_pressed_color", Color("e0c07a"))
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		skip.add_theme_stylebox_override(state, empty)
	skip.pressed.connect(_guide_finish)
	footer.add_child(skip)

func _guide_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", HUD_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _guide_keycap(text: String) -> PanelContainer:
	var wide := text.length() > 1
	var side := PanelContainer.new()
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side_box := StyleBoxFlat.new()
	side_box.bg_color = Color("1a1208")
	side_box.set_corner_radius_all(7)
	side_box.content_margin_left = 0
	side_box.content_margin_right = 0
	side_box.content_margin_top = 0
	side_box.content_margin_bottom = 3
	side_box.shadow_color = Color(0, 0, 0, 0.35)
	side_box.shadow_size = 2
	side_box.shadow_offset = Vector2(0, 2)
	side.add_theme_stylebox_override("panel", side_box)
	var face := PanelContainer.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.custom_minimum_size = Vector2(58 if wide else 32, 28)
	var face_box := StyleBoxFlat.new()
	face_box.bg_color = Color("ffe39a")
	face_box.set_corner_radius_all(6)
	face_box.content_margin_left = 6
	face_box.content_margin_right = 6
	face_box.content_margin_top = 2
	face_box.content_margin_bottom = 1
	face_box.border_width_top = 1
	face_box.border_color = Color("fff1c9")
	face.add_theme_stylebox_override("panel", face_box)
	var caption := _guide_label(13 if wide else 15, Color("1a1208"))
	caption.text = text
	face.add_child(caption)
	side.add_child(face)
	return side

func _guide_set_dot(dot: Panel, on: bool) -> void:
	dot.custom_minimum_size = Vector2(14.0 if on else 5.0, 5.0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("ffe39a") if on else Color("ffe39a", 0.28)
	box.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", box)

func _guide_place() -> void:
	var phone := _phone_layout()
	var left := 16.0
	var top := 54.0
	var width := 280.0 if phone else 318.0
	var height := 124.0
	_guide_rest_top = top
	_guide_rest_bottom = top + height
	_guide_card.offset_left = left
	_guide_card.offset_top = top
	_guide_card.offset_right = left + width
	_guide_card.offset_bottom = _guide_rest_bottom

func _guide_fill(step: int) -> void:
	var info: Dictionary = GUIDE_STEPS[step]
	_guide_index.text = str(info["index"])
	_guide_name.text = str(info["name"])
	_guide_copy.text = str(info["body"])
	while _guide_keys.get_child_count() > 0:
		var child := _guide_keys.get_child(0)
		_guide_keys.remove_child(child)
		child.free()
	for key_name in info["keys"]:
		_guide_keys.add_child(_guide_keycap(str(key_name)))
	for i in _guide_dots.size():
		_guide_set_dot(_guide_dots[i], i == step)

func _guide_intro() -> void:
	_guide_card.offset_top = _guide_rest_top
	_guide_card.offset_bottom = _guide_rest_bottom
	_guide_root.modulate.a = 0.0
	_guide_busy = true
	if _guide_tween:
		_guide_tween.kill()
	var tw := create_tween()
	_guide_tween = tw
	tw.tween_property(_guide_root, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		_guide_busy = false
		_guide_tween = null
		if _guide_active and _guide_step_done(_guide_step):
			_guide_present(_guide_step + 1)
	)

func _guide_present(step: int) -> void:
	if not _guide_active or _guide_busy:
		return
	while step < GUIDE_STEPS.size() - 1 and _guide_step_done(step):
		step += 1
	if step == _guide_step:
		return
	_guide_step = step
	_guide_busy = true
	_guide_hold = 0.0
	if _guide_tween:
		_guide_tween.kill()
	var tw := create_tween()
	_guide_tween = tw
	tw.tween_property(_guide_stack, "modulate:a", 0.0, 0.1).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		var dest := _guide_step
		while dest < GUIDE_STEPS.size() - 1 and _guide_step_done(dest):
			dest += 1
		_guide_step = dest
		_guide_fill(dest)
		_guide_hold = 0.0
	)
	tw.tween_property(_guide_stack, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		_guide_busy = false
		_guide_tween = null
	)

func _guide_hide_for_menu() -> void:
	if not _guide_active or _guide_root == null:
		return
	if _guide_tween:
		_guide_tween.kill()
		_guide_tween = null
	_guide_busy = false
	_guide_fill(_guide_step)
	_guide_stack.modulate.a = 1.0
	_guide_card.offset_top = _guide_rest_top
	_guide_card.offset_bottom = _guide_rest_bottom
	_guide_root.visible = false

func _guide_show_after_menu() -> void:
	if not _guide_active or _guide_root == null:
		return
	_guide_root.visible = true
	_guide_root.modulate.a = 1.0
	_guide_stack.modulate.a = 1.0
	get_viewport().gui_release_focus()

func _guide_finish() -> void:
	if not _guide_active:
		return
	_guide_active = false
	_guide_busy = false
	if _guide_tween:
		_guide_tween.kill()
		_guide_tween = null
	var layer := _guide_layer
	var root := _guide_root
	_guide_layer = null
	_guide_root = null
	if root == null:
		if layer != null:
			layer.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	)
