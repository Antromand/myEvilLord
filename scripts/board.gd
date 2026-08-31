class_name GrayboxBoard
extends Node2D

signal cell_clicked(cell: Vector2i)
signal cell_right_clicked(cell: Vector2i)

const WIDTH := 24
const HEIGHT := 13
const CELL_SIZE := 40
const ORE_REWARD := 4
const WANDER_STEP_BUDGET := 72
const INVALID_CELL := Vector2i(-1, -1)
const CARDINALS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]

enum CellType {
	DIRT,
	FLOOR,
	ORE,
	ENTRANCE,
	LORD,
}

enum InteractionMode {
	DIG,
	DEFENDER,
}

var cells: Array = []
var defenders: Dictionary = {}
var entrance_cell := Vector2i(5, 0)
var lord_cell := Vector2i(20, 12)
var hero_cell := INVALID_CELL
var hero_hp := 0
var hero_max_hp := 8
var interaction_enabled := true
var interaction_mode := InteractionMode.DIG
var hover_cell := INVALID_CELL
var hover_valid := false
var preview_path: Array[Vector2i] = []
var _pulse_time := 0.0


func _ready() -> void:
	reset_board()


func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()


func reset_board() -> void:
	cells.clear()
	defenders.clear()
	hero_cell = INVALID_CELL
	hero_hp = 0
	preview_path.clear()

	for y in range(HEIGHT):
		var row: Array = []
		row.resize(WIDTH)
		row.fill(CellType.DIRT)
		cells.append(row)

	for y in range(0, 5):
		_set_cell(Vector2i(5, y), CellType.FLOOR)
	for x in range(3, 14):
		_set_cell(Vector2i(x, 4), CellType.FLOOR)
	for y in range(4, 9):
		_set_cell(Vector2i(3, y), CellType.FLOOR)
	for x in range(3, 11):
		_set_cell(Vector2i(x, 8), CellType.FLOOR)
	for y in range(4, 11):
		_set_cell(Vector2i(10, y), CellType.FLOOR)
	for x in range(10, 19):
		_set_cell(Vector2i(x, 6), CellType.FLOOR)
	for y in range(6, 11):
		_set_cell(Vector2i(18, y), CellType.FLOOR)
	for x in range(10, 22):
		_set_cell(Vector2i(x, 10), CellType.FLOOR)
	for y in range(4, 7):
		_set_cell(Vector2i(13, y), CellType.FLOOR)
	for y in range(10, 13):
		_set_cell(Vector2i(20, y), CellType.FLOOR)

	_set_cell(entrance_cell, CellType.ENTRANCE)
	_set_cell(lord_cell, CellType.LORD)

	var ore_cells: Array[Vector2i] = [
		Vector2i(4, 1),
		Vector2i(6, 2),
		Vector2i(2, 5),
		Vector2i(4, 7),
		Vector2i(7, 7),
		Vector2i(9, 5),
		Vector2i(14, 5),
		Vector2i(16, 7),
		Vector2i(17, 9),
		Vector2i(21, 11),
	]
	for cell in ore_cells:
		_set_cell(cell, CellType.ORE)

	_refresh_hover_validity()
	queue_redraw()


func set_interaction(mode: int, enabled: bool) -> void:
	interaction_mode = mode
	interaction_enabled = enabled
	_refresh_hover_validity()
	queue_redraw()


func set_preview_path(path: Array[Vector2i]) -> void:
	preview_path = path
	queue_redraw()


func set_hero(cell: Vector2i, hp: int, max_hp: int) -> void:
	hero_cell = cell
	hero_hp = hp
	hero_max_hp = max_hp
	queue_redraw()


func clear_hero() -> void:
	hero_cell = INVALID_CELL
	hero_hp = 0
	queue_redraw()


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT


func get_cell_type(cell: Vector2i) -> int:
	if not is_inside(cell):
		return CellType.DIRT
	return int(cells[cell.y][cell.x])


func is_walkable(cell: Vector2i) -> bool:
	if not is_inside(cell):
		return false
	var cell_type := get_cell_type(cell)
	return cell_type == CellType.FLOOR or cell_type == CellType.ENTRANCE or cell_type == CellType.LORD


func can_dig(cell: Vector2i) -> bool:
	if not is_inside(cell):
		return false
	var cell_type := get_cell_type(cell)
	if cell_type != CellType.DIRT and cell_type != CellType.ORE:
		return false
	for neighbor in _neighbors(cell):
		if is_walkable(neighbor):
			return true
	return false


func dig_cell(cell: Vector2i) -> int:
	if not can_dig(cell):
		return 0
	var reward := ORE_REWARD if get_cell_type(cell) == CellType.ORE else 0
	_set_cell(cell, CellType.FLOOR)
	_refresh_hover_validity()
	queue_redraw()
	return reward


func can_place_defender(cell: Vector2i) -> bool:
	return is_inside(cell) and get_cell_type(cell) == CellType.FLOOR and not defenders.has(cell)


func place_defender(cell: Vector2i, hp: int) -> bool:
	if not can_place_defender(cell):
		return false
	defenders[cell] = hp
	_refresh_hover_validity()
	queue_redraw()
	return true


func remove_defender(cell: Vector2i) -> bool:
	if not defenders.has(cell):
		return false
	defenders.erase(cell)
	_refresh_hover_validity()
	queue_redraw()
	return true


func has_defender(cell: Vector2i) -> bool:
	return defenders.has(cell)


func get_defender_hp(cell: Vector2i) -> int:
	return int(defenders.get(cell, 0))


func damage_defender(cell: Vector2i, amount: int) -> int:
	if not defenders.has(cell):
		return 0
	var remaining_hp: int = maxi(0, get_defender_hp(cell) - amount)
	if remaining_hp == 0:
		defenders.erase(cell)
	else:
		defenders[cell] = remaining_hp
	queue_redraw()
	return remaining_hp


func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var no_path: Array[Vector2i] = []
	if not is_walkable(start) or not is_walkable(goal):
		return no_path

	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	came_from[start] = INVALID_CELL
	var head := 0

	while head < frontier.size() and not came_from.has(goal):
		var current := frontier[head]
		head += 1
		for neighbor in _neighbors(current):
			if is_walkable(neighbor) and not came_from.has(neighbor):
				came_from[neighbor] = current
				frontier.append(neighbor)
				if neighbor == goal:
					break

	if not came_from.has(goal):
		return no_path

	var path: Array[Vector2i] = []
	var cursor := goal
	while cursor != start:
		path.push_front(cursor)
		var previous: Vector2i = came_from[cursor]
		cursor = previous
	path.push_front(start)
	return path


func build_wandering_route(start: Vector2i, goal: Vector2i, seed_value: int) -> Array[Vector2i]:
	var no_route: Array[Vector2i] = []
	if not is_walkable(start) or not is_walkable(goal):
		return no_route
	if find_path(start, goal).is_empty():
		return no_route

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var route: Array[Vector2i] = [start]
	var visit_count: Dictionary = {}
	visit_count[start] = 1
	var current := start
	var previous := INVALID_CELL

	for step in range(WANDER_STEP_BUDGET):
		if current == goal:
			return route

		var candidates: Array[Vector2i] = []
		for neighbor in _neighbors(current):
			if is_walkable(neighbor):
				candidates.append(neighbor)

		if candidates.is_empty():
			break
		if previous != INVALID_CELL and candidates.size() > 1:
			candidates.erase(previous)

		var next_cell := _choose_wandering_candidate(
			current,
			goal,
			candidates,
			visit_count,
			rng
		)
		previous = current
		current = next_cell
		route.append(current)
		visit_count[current] = int(visit_count.get(current, 0)) + 1

		if current == goal:
			return route

	var fallback := find_path(current, goal)
	if fallback.is_empty():
		return no_route
	for index in range(1, fallback.size()):
		route.append(fallback[index])
	return route


func _choose_wandering_candidate(
	current: Vector2i,
	goal: Vector2i,
	candidates: Array[Vector2i],
	visit_count: Dictionary,
	rng: RandomNumberGenerator
) -> Vector2i:
	var weights: Array[float] = []
	var total_weight := 0.0
	var current_distance := absi(goal.x - current.x) + absi(goal.y - current.y)

	for candidate in candidates:
		var visits := int(visit_count.get(candidate, 0))
		var weight := 1.0
		if visits == 0:
			weight += 5.0
		else:
			weight /= float(visits * 2 + 1)

		if candidate.y > current.y:
			weight += 3.2
		elif candidate.y < current.y:
			weight *= 0.55

		var candidate_distance := absi(goal.x - candidate.x) + absi(goal.y - candidate.y)
		if candidate_distance < current_distance:
			weight += 1.2

		weight *= rng.randf_range(0.75, 1.35)
		weights.append(weight)
		total_weight += weight

	var roll := rng.randf() * total_weight
	for index in range(candidates.size()):
		roll -= weights[index]
		if roll <= 0.0:
			return candidates[index]
	return candidates[candidates.size() - 1]


func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in CARDINALS:
		var candidate := cell + direction
		if is_inside(candidate):
			result.append(candidate)
	return result


func _set_cell(cell: Vector2i, cell_type: int) -> void:
	if is_inside(cell):
		cells[cell.y][cell.x] = cell_type


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_cell = _cell_from_local(to_local(event.position))
		_refresh_hover_validity()
		queue_redraw()
		return

	if not interaction_enabled:
		return

	if event is InputEventMouseButton and event.pressed:
		var clicked_cell := _cell_from_local(to_local(event.position))
		if not is_inside(clicked_cell):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			cell_clicked.emit(clicked_cell)
			_refresh_hover_validity()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cell_right_clicked.emit(clicked_cell)
			_refresh_hover_validity()
			get_viewport().set_input_as_handled()


func _cell_from_local(local_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(local_position.x / float(CELL_SIZE)),
		floori(local_position.y / float(CELL_SIZE))
	)


func _refresh_hover_validity() -> void:
	if not interaction_enabled or not is_inside(hover_cell):
		hover_valid = false
		return
	if interaction_mode == InteractionMode.DIG:
		hover_valid = can_dig(hover_cell)
	else:
		hover_valid = can_place_defender(hover_cell)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE),
		Vector2(CELL_SIZE, CELL_SIZE)
	)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * CELL_SIZE + CELL_SIZE * 0.5,
		cell.y * CELL_SIZE + CELL_SIZE * 0.5
	)


func _draw() -> void:
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell)
			var inner := rect.grow(-1.0)
			var cell_type := get_cell_type(cell)

			match cell_type:
				CellType.DIRT:
					draw_rect(inner, Color(0.19, 0.105, 0.12, 1))
					var grain_y := 11.0 if (x + y) % 2 == 0 else 27.0
					draw_line(
						rect.position + Vector2(7, grain_y),
						rect.position + Vector2(31, grain_y - 3),
						Color(0.26, 0.14, 0.15, 0.8),
						2.0
					)
				CellType.ORE:
					draw_rect(inner, Color(0.22, 0.105, 0.24, 1))
					draw_circle(_cell_center(cell), 10.0, Color(0.7, 0.28, 0.82, 1))
					draw_circle(_cell_center(cell) + Vector2(-3, -3), 3.0, Color(0.95, 0.67, 1, 1))
				CellType.FLOOR:
					draw_rect(inner, Color(0.085, 0.065, 0.085, 1))
					draw_circle(_cell_center(cell), 2.0, Color(0.18, 0.14, 0.18, 1))
				CellType.ENTRANCE:
					draw_rect(inner, Color(0.08, 0.1, 0.14, 1))
					var center := _cell_center(cell)
					draw_colored_polygon(
						PackedVector2Array([
							center + Vector2(-12, -10),
							center + Vector2(12, -10),
							center + Vector2(0, 14),
						]),
						Color(0.32, 0.72, 0.95, 1)
					)
				CellType.LORD:
					draw_rect(inner, Color(0.16, 0.055, 0.075, 1))
					var center := _cell_center(cell)
					draw_circle(center, 13.0, Color(0.86, 0.16, 0.25, 1))
					draw_line(center + Vector2(-10, -8), center + Vector2(-15, -15), Color(1, 0.55, 0.35, 1), 4.0)
					draw_line(center + Vector2(10, -8), center + Vector2(15, -15), Color(1, 0.55, 0.35, 1), 4.0)

			draw_rect(rect, Color(0.3, 0.21, 0.3, 0.22), false, 1.0)

	for cell in preview_path:
		if cell != entrance_cell and cell != lord_cell:
			draw_circle(_cell_center(cell), 3.2, Color(0.95, 0.72, 0.23, 0.52))

	for key in defenders:
		_draw_defender(key, int(defenders[key]))

	if hero_cell != INVALID_CELL:
		_draw_hero(hero_cell)

	if interaction_enabled and is_inside(hover_cell):
		var outline_color := Color(0.34, 0.92, 0.68, 1) if hover_valid else Color(0.95, 0.28, 0.32, 0.85)
		draw_rect(_cell_rect(hover_cell).grow(-2.5), outline_color, false, 3.0)


func _draw_defender(cell: Vector2i, hp: int) -> void:
	var center := _cell_center(cell)
	var pulse := 0.5 + 0.5 * sin(_pulse_time * 3.0 + float(cell.x))
	var body_color := Color(0.2, 0.74 + pulse * 0.08, 0.55, 1)
	draw_circle(center, 14.0, Color(0.025, 0.12, 0.09, 1))
	draw_circle(center, 11.0, body_color)
	draw_circle(center + Vector2(-4, -3), 2.3, Color(0.02, 0.04, 0.03, 1))
	draw_circle(center + Vector2(4, -3), 2.3, Color(0.02, 0.04, 0.03, 1))
	var bar_rect := Rect2(center + Vector2(-14, 15), Vector2(28, 4))
	draw_rect(bar_rect, Color(0.08, 0.04, 0.08, 1))
	draw_rect(
		Rect2(bar_rect.position, Vector2(bar_rect.size.x * clampf(float(hp) / 3.0, 0.0, 1.0), bar_rect.size.y)),
		Color(0.32, 0.9, 0.55, 1)
	)


func _draw_hero(cell: Vector2i) -> void:
	var center := _cell_center(cell)
	var bob := sin(_pulse_time * 8.0) * 2.0
	center.y += bob
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0, -15),
			center + Vector2(13, 0),
			center + Vector2(0, 15),
			center + Vector2(-13, 0),
		]),
		Color(0.96, 0.63, 0.22, 1)
	)
	draw_circle(center + Vector2(-4, -2), 2.1, Color(0.1, 0.03, 0.04, 1))
	draw_circle(center + Vector2(4, -2), 2.1, Color(0.1, 0.03, 0.04, 1))
	var bar_rect := Rect2(center + Vector2(-16, -22), Vector2(32, 5))
	draw_rect(bar_rect, Color(0.08, 0.04, 0.08, 1))
	draw_rect(
		Rect2(bar_rect.position, Vector2(bar_rect.size.x * clampf(float(hero_hp) / float(hero_max_hp), 0.0, 1.0), bar_rect.size.y)),
		Color(0.92, 0.25, 0.22, 1)
	)
