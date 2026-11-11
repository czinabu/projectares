class_name StanceIndicator
extends Control
## Three marks around the crosshair for directional melee: which side you are
## set to attack or guard, and which side an enemy swing is coming at.

const OFFSETS := [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]

## The player's `MeleeWeapon.Dir`, or -1 to hide the stance marks.
var stance := -1
var guarding := false
## The side of the screen an enemy swing is coming at, or -1 for none.
var threat := -1

var radius := 34.0
var threat_radius := 48.0
var mark_length := 22.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	for dir in OFFSETS.size():
		var out: Vector2 = OFFSETS[dir]
		var along := Vector2(-out.y, out.x) * mark_length * 0.5
		if stance >= 0:
			var active := dir == stance
			var color := Color(1, 1, 1, 0.22)
			if active:
				color = Color(0.45, 0.75, 1.0) if guarding else Color.WHITE
			var at := center + out * radius
			draw_line(at - along, at + along, color, 4.0 if active else 2.0)
		if dir == threat:
			var at := center + out * threat_radius
			# Yellow on a dark outline, so it shows against red enemies and sky.
			draw_line(at - along * 1.6, at + along * 1.6, Color(0, 0, 0, 0.85), 12.0)
			draw_line(at - along * 1.5, at + along * 1.5, Color(1.0, 0.9, 0.15), 7.0)
