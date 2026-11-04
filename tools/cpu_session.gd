extends Node
## Boots the game with the autopilot. Used for the recorded CPU session.

func _ready() -> void:
	var world: Node3D = load("res://main.tscn").instantiate()
	add_child(world)
	var bot := preload("res://scripts/autopilot.gd").new()
	world.add_child(bot)
