extends RefCounted
## Terrain is simulation data. The renderer and collision code read this same grid.

signal plot_changed(cell: Vector2i)
signal supplies_changed

const WIDTH: int = 24
const HEIGHT: int = 24
const INVALID_CELL := Vector2i(-1, -1)
const SPAWN := Vector2(6.5, 13.5)
const MAX_MOISTURE: float = 60.0
const CAN_CAPACITY: int = 8
const SEED_ORDER := ["lettuce", "carrot", "tomato"]
const SEED_NAMES := {"lettuce": "生菜", "carrot": "胡萝卜", "tomato": "番茄"}

enum Terrain { GRASS, PATH, SOIL, WATER, BUILDING, TREE, ROCK, FENCE, OUTSIDE }

const NAMES := ["草地", "道路", "裸土", "水域", "农舍", "树木", "岩石", "围栏", "地图外"]
const DESCRIPTIONS := [
	"平整的草地，可以用锄头开垦。",
	"连接农舍、试验田和水源的通道。",
	"预留的种植区域，翻土后可以播种或浇水。",
	"农场的池塘。角色不能进入水中。",
	"农舍占地，当前不能进入建筑。",
	"树木形成的自然障碍，当前不能砍伐。",
	"岩石占地，当前不能移除。",
	"农场边界，角色不能穿过。",
	"请选择地图范围内的地块。",
]

var tiles := PackedInt32Array()
var plots: Array[Dictionary] = []
var seed_stock: Dictionary = {"lettuce": 12, "carrot": 8, "tomato": 6}
var produce_stock: Dictionary = {"lettuce": 0, "carrot": 0, "tomato": 0}
var watering_charges: int = CAN_CAPACITY


func _init() -> void:
	tiles.resize(WIDTH * HEIGHT)
	tiles.fill(Terrain.GRASS)
	for _index in range(WIDTH * HEIGHT):
		plots.append({"tilled": false, "moisture": 18.0, "crop": {}})
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := Vector2i(x, y)
			if x == 0 or x == WIDTH - 1 or y == HEIGHT - 1:
				_set_tile(cell, Terrain.FENCE)
			elif y == 0:
				_set_tile(cell, Terrain.TREE)
	for y in range(2, 23):
		_set_tile(Vector2i(6, y), Terrain.PATH)
	for x in range(1, 23):
		_set_tile(Vector2i(x, 13), Terrain.PATH)
	for y in range(7, 11):
		for x in range(8, 14):
			_set_tile(Vector2i(x, y), Terrain.SOIL)
	for y in range(16, 20):
		for x in range(8, 14):
			_set_tile(Vector2i(x, y), Terrain.SOIL)
	for y in range(3, 6):
		for x in range(2, 6):
			_set_tile(Vector2i(x, y), Terrain.BUILDING)
	for y in range(3, 8):
		for x in range(16, 22):
			var distance := Vector2((float(x) - 18.5) / 3.0, (float(y) - 5.0) / 2.3)
			if distance.length_squared() < 1.0:
				_set_tile(Vector2i(x, y), Terrain.WATER)
	for cell in [Vector2i(2, 1), Vector2i(3, 1), Vector2i(10, 2), Vector2i(11, 1),
		Vector2i(15, 2), Vector2i(22, 2), Vector2i(2, 10), Vector2i(2, 11),
		Vector2i(21, 10), Vector2i(22, 11), Vector2i(3, 18), Vector2i(4, 19),
		Vector2i(17, 20), Vector2i(18, 21), Vector2i(21, 19), Vector2i(22, 20)]:
		_set_tile(cell, Terrain.TREE)
	for cell in [Vector2i(3, 8), Vector2i(15, 16), Vector2i(20, 17), Vector2i(2, 21)]:
		_set_tile(cell, Terrain.ROCK)


func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WIDTH and cell.y < HEIGHT


func terrain_at(cell: Vector2i) -> int:
	if not contains(cell):
		return Terrain.OUTSIDE
	return tiles[cell.y * WIDTH + cell.x]


func is_walkable(cell: Vector2i) -> bool:
	return terrain_at(cell) in [Terrain.GRASS, Terrain.PATH, Terrain.SOIL]


func is_arable(cell: Vector2i) -> bool:
	return terrain_at(cell) in [Terrain.GRASS, Terrain.SOIL]


func describe(cell: Vector2i) -> Dictionary:
	var terrain := terrain_at(cell)
	return {
		"name": NAMES[terrain],
		"description": DESCRIPTIONS[terrain],
		"walkable": is_walkable(cell),
		"arable": is_arable(cell),
		"terrain": terrain,
	}


func plot_at(cell: Vector2i) -> Dictionary:
	if not contains(cell):
		return {}
	return plots[cell.y * WIDTH + cell.x]


func _set_tile(cell: Vector2i, terrain: int) -> void:
	tiles[cell.y * WIDTH + cell.x] = terrain
