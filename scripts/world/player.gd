extends RefCounted
## A continuous player footprint against the authoritative terrain grid.
## Axis-separated small steps prevent tunnelling and permit sliding along walls.

const FarmState = preload("res://scripts/simulation/farm_state.gd")

const RADIUS: float = 0.22
const SPEED: float = 3.8
const MAX_SUBSTEP: float = 0.08

var position := Vector2.ZERO
var facing := Vector2.DOWN
var walk_distance: float = 0.0
var moving: bool = false
var blocked: bool = false


func _init(spawn: Vector2 = Vector2(6.5, 13.5)) -> void:
	position = spawn


func cell() -> Vector2i:
	return Vector2i(floori(position.x), floori(position.y))


func can_stand_at(candidate: Vector2, farm: FarmState) -> bool:
	for offset in [Vector2(-RADIUS, -RADIUS), Vector2(RADIUS, -RADIUS),
		Vector2(-RADIUS, RADIUS), Vector2(RADIUS, RADIUS)]:
		var sample: Vector2 = candidate + offset
		if not farm.is_walkable(Vector2i(floori(sample.x), floori(sample.y))):
			return false
	return true


func advance(direction: Vector2, delta: float, farm: FarmState) -> bool:
	moving = false
	blocked = false
	if direction.is_zero_approx() or delta <= 0.0:
		return false
	var normalized := direction.limit_length(1.0)
	if absf(normalized.x) > absf(normalized.y):
		facing = Vector2(signf(normalized.x), 0)
	else:
		facing = Vector2(0, signf(normalized.y))
	# A stall or a window drag should not teleport the player across the map.
	var motion := normalized * SPEED * minf(delta, 0.25)
	var steps := maxi(1, ceili(motion.length() / MAX_SUBSTEP))
	var step := motion / float(steps)
	var start := position
	for _index in range(steps):
		var horizontal := position + Vector2(step.x, 0)
		if can_stand_at(horizontal, farm):
			position = horizontal
		elif not is_zero_approx(step.x):
			blocked = true
		var vertical := position + Vector2(0, step.y)
		if can_stand_at(vertical, farm):
			position = vertical
		elif not is_zero_approx(step.y):
			blocked = true
	moving = not position.is_equal_approx(start)
	walk_distance += position.distance_to(start)
	return moving
