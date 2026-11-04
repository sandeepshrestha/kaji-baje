extends Area3D
## A spinning, bobbing gold coin. Emits `collected` once when Kaji Baje
## touches it, then pops upward and disappears.

signal collected(coin: Node3D)

const RADIUS := 0.22
const SPIN_SPEED := 2.6
const BOB_HEIGHT := 0.08

static var _mat: StandardMaterial3D

var _base_y := 0.0
var _t := 0.0
var _taken := false

func _ready() -> void:
	add_to_group("coin")
	_base_y = position.y
	_t = randf() * TAU
	rotation.y = randf() * TAU
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color("ffc53d")
		_mat.metallic = 0.85
		_mat.roughness = 0.3
		_mat.emission_enabled = true
		_mat.emission = Color("ffaa1f")
		_mat.emission_energy_multiplier = 0.7
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.05
	disc.radial_segments = 24
	disc.rings = 1
	disc.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.rotation_degrees.x = 90.0
	add_child(mi)
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	cs.shape = sphere
	add_child(cs)
	monitorable = false
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	rotation.y += SPIN_SPEED * delta
	position.y = _base_y + sin(_t * 2.2) * BOB_HEIGHT

func _on_body_entered(body: Node3D) -> void:
	if _taken or not body is CharacterBody3D:
		return
	_taken = true
	set_deferred("monitoring", false)
	collected.emit(self)
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "position:y", position.y + 0.9, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "rotation:y", rotation.y + TAU * 2.0, 0.35)
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(queue_free)
