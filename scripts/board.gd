class_name GrayboxBoard
extends Node2D

signal cell_clicked(cell: Vector2i)
signal cell_right_clicked(cell: Vector2i)
signal knight_entered_cave

const WIDTH := 64
const HEIGHT := 128
const VIEW_WIDTH := 32
const VIEW_HEIGHT := 16
const BIOME_HEIGHT := 32
const CELL_SIZE := 32
const SURFACE_HEIGHT := 96
const ORE_REWARD := 4
const WANDER_STEP_BUDGET := 4096
const INVALID_CELL := Vector2i(-1, -1)
const ENTRANCE_X := 32
const FIRST_ORE_CELL := Vector2i(33, 2)
const CAMERA_STEP_SECONDS := 0.045
const EDGE_SCROLL_MARGIN := 14.0
const SURFACE_KNIGHT_SPEED := 72.0
const SURFACE_PATROL_MIN_OFFSET := -260.0
const SURFACE_PATROL_MAX_OFFSET := -190.0
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
	MOVE_LORD,
}

var cells: Array = []
var defenders: Dictionary = {}
var entrance_cell := Vector2i(ENTRANCE_X, 0)
var lord_cell := Vector2i(ENTRANCE_X, 3)
var hero_cell := INVALID_CELL
var hero_hp := 0
var hero_max_hp := 8
var interaction_enabled := true
var interaction_mode := InteractionMode.DIG
var hover_cell := INVALID_CELL
var hover_valid := false
var preview_path: Array[Vector2i] = []
var camera_cell := Vector2i(ENTRANCE_X - VIEW_WIDTH / 2, 0)
var invasion_active := false
var _pulse_time := 0.0
var _scroll_accumulator := 0.0
var _surface_knight_world_x := 0.0
var _surface_knight_y := -21.0
var _surface_knight_direction := 1.0
var _surface_motion_paused := false
var _surface_knight_entered := false


func _ready() -> void:
	reset_board()


func _process(delta: float) -> void:
	_pulse_time += delta
	_update_surface_knight(delta)
	_update_camera_scroll(delta)
	queue_redraw()


func reset_board() -> void:
	cells.clear()
	defenders.clear()
	hero_cell = INVALID_CELL
	hero_hp = 0
	preview_path.clear()
	entrance_cell = Vector2i(ENTRANCE_X, 0)
	lord_cell = Vector2i(ENTRANCE_X, 3)
	camera_cell = Vector2i(ENTRANCE_X - VIEW_WIDTH / 2, 0)
	invasion_active = false
	_surface_knight_world_x = _surface_cave_world_x() - 220.0
	_surface_knight_y = -21.0
	_surface_knight_direction = 1.0
	_surface_motion_paused = false
	_surface_knight_entered = false

	for y in range(HEIGHT):
		var row: Array = []
		row.resize(WIDTH)
		row.fill(CellType.DIRT)
		cells.append(row)

	_generate_ore()
	_set_cell(entrance_cell, CellType.ENTRANCE)
	_set_cell(Vector2i(ENTRANCE_X, 1), CellType.FLOOR)
	_set_cell(Vector2i(ENTRANCE_X, 2), CellType.FLOOR)
	_set_cell(lord_cell, CellType.LORD)
	_set_cell(FIRST_ORE_CELL, CellType.ORE)

	_refresh_hover_validity()
	queue_redraw()


func _generate_ore() -> void:
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var value := (x * 37 + y * 61 + x * y * 7 + y * y * 3) % 113
			if value < 3:
				_set_cell(Vector2i(x, y), CellType.ORE)


func set_interaction(mode: int, enabled: bool) -> void:
	interaction_mode = mode
	interaction_enabled = enabled
	_refresh_hover_validity()
	queue_redraw()


func set_invasion_active(active: bool) -> void:
	if active and not invasion_active:
		_surface_knight_entered = false
	invasion_active = active
	queue_redraw()


func set_surface_motion_paused(paused: bool) -> void:
	_surface_motion_paused = paused


func has_knight_entered_cave() -> bool:
	return _surface_knight_entered


func get_surface_knight_position() -> float:
	return _surface_knight_world_x


func _surface_cave_world_x() -> float:
	return entrance_cell.x * CELL_SIZE + CELL_SIZE * 0.5


func _update_surface_knight(delta: float) -> void:
	if _surface_motion_paused or _surface_knight_entered:
		return
	var cave_x := _surface_cave_world_x()
	if invasion_active:
		if not is_equal_approx(_surface_knight_world_x, cave_x):
			_surface_knight_world_x = move_toward(
				_surface_knight_world_x,
				cave_x,
				SURFACE_KNIGHT_SPEED * delta
			)
		else:
			_surface_knight_y = move_toward(
				_surface_knight_y,
				-5.0,
				SURFACE_KNIGHT_SPEED * 0.5 * delta
			)
		if is_equal_approx(_surface_knight_world_x, cave_x) and is_equal_approx(_surface_knight_y, -5.0):
			_surface_knight_entered = true
			knight_entered_cave.emit()
		return

	var patrol_min := cave_x + SURFACE_PATROL_MIN_OFFSET
	var patrol_max := cave_x + SURFACE_PATROL_MAX_OFFSET
	_surface_knight_y = -21.0
	_surface_knight_world_x += _surface_knight_direction * SURFACE_KNIGHT_SPEED * 0.45 * delta
	if _surface_knight_world_x >= patrol_max:
		_surface_knight_world_x = patrol_max
		_surface_knight_direction = -1.0
	elif _surface_knight_world_x <= patrol_min:
		_surface_knight_world_x = patrol_min
		_surface_knight_direction = 1.0


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


func is_visible_cell(cell: Vector2i) -> bool:
	return cell.x >= camera_cell.x and cell.x < camera_cell.x + VIEW_WIDTH \
		and cell.y >= camera_cell.y and cell.y < camera_cell.y + VIEW_HEIGHT


func get_biome_index(cell: Vector2i) -> int:
	return clampi(cell.y / BIOME_HEIGHT, 0, 3)


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


func can_move_lord(cell: Vector2i) -> bool:
	return is_inside(cell) and get_cell_type(cell) == CellType.FLOOR \
		and not defenders.has(cell) and cell != hero_cell


func move_lord(cell: Vector2i) -> bool:
	if not can_move_lord(cell):
		return false
	_set_cell(lord_cell, CellType.FLOOR)
	lord_cell = cell
	_set_cell(lord_cell, CellType.LORD)
	_refresh_hover_validity()
	queue_redraw()
	return true


func can_place_defender(cell: Vector2i) -> bool:
	return is_inside(cell) and get_cell_type(cell) == CellType.FLOOR \
		and not defenders.has(cell) and cell != hero_cell


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

		var forced_step := _straight_corridor_step(current, previous)
		if forced_step != INVALID_CELL:
			previous = current
			current = forced_step
			route.append(current)
			visit_count[current] = int(visit_count.get(current, 0)) + 1
			continue

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


func _straight_corridor_step(current: Vector2i, previous: Vector2i) -> Vector2i:
	if previous == INVALID_CELL:
		return INVALID_CELL
	var direction := current - previous
	var forward := current + direction
	if not is_walkable(forward):
		return INVALID_CELL
	var side_a := Vector2i(-direction.y, direction.x)
	var side_b := -side_a
	if is_walkable(current + side_a) or is_walkable(current + side_b):
		return INVALID_CELL
	return forward


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


func scroll_by(delta_cells: Vector2i) -> void:
	var max_camera := Vector2i(WIDTH - VIEW_WIDTH, HEIGHT - VIEW_HEIGHT)
	var next_camera := Vector2i(
		clampi(camera_cell.x + delta_cells.x, 0, max_camera.x),
		clampi(camera_cell.y + delta_cells.y, 0, max_camera.y)
	)
	if next_camera == camera_cell:
		return
	camera_cell = next_camera
	_refresh_hover_validity()
	queue_redraw()


func center_camera_on(cell: Vector2i) -> void:
	var target := cell - Vector2i(VIEW_WIDTH / 2, VIEW_HEIGHT / 2)
	var max_camera := Vector2i(WIDTH - VIEW_WIDTH, HEIGHT - VIEW_HEIGHT)
	camera_cell = Vector2i(
		clampi(target.x, 0, max_camera.x),
		clampi(target.y, 0, max_camera.y)
	)
	_refresh_hover_validity()
	queue_redraw()


func _update_camera_scroll(delta: float) -> void:
	var direction := Vector2i.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1
	if Input.is_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		direction.y += 1

	var viewport_size := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	if mouse.x <= EDGE_SCROLL_MARGIN:
		direction.x -= 1
	elif mouse.x >= viewport_size.x - EDGE_SCROLL_MARGIN:
		direction.x += 1
	if mouse.y <= EDGE_SCROLL_MARGIN:
		direction.y -= 1
	elif mouse.y >= viewport_size.y - EDGE_SCROLL_MARGIN:
		direction.y += 1

	if direction == Vector2i.ZERO:
		_scroll_accumulator = 0.0
		return
	_scroll_accumulator += delta
	if _scroll_accumulator >= CAMERA_STEP_SECONDS:
		var steps := maxi(1, floori(_scroll_accumulator / CAMERA_STEP_SECONDS))
		scroll_by(direction * steps)
		_scroll_accumulator = fmod(_scroll_accumulator, CAMERA_STEP_SECONDS)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local_mouse := to_local(event.position)
		hover_cell = _cell_from_local(local_mouse) if _is_inside_view(local_mouse) else INVALID_CELL
		_refresh_hover_validity()
		queue_redraw()
		return

	if not interaction_enabled:
		return

	if event is InputEventMouseButton and event.pressed:
		var local_mouse := to_local(event.position)
		if not _is_inside_view(local_mouse):
			return
		var clicked_cell := _cell_from_local(local_mouse)
		if event.button_index == MOUSE_BUTTON_LEFT:
			cell_clicked.emit(clicked_cell)
			_refresh_hover_validity()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cell_right_clicked.emit(clicked_cell)
			_refresh_hover_validity()
			get_viewport().set_input_as_handled()


func _is_inside_view(local_position: Vector2) -> bool:
	return local_position.x >= 0.0 and local_position.x < VIEW_WIDTH * CELL_SIZE \
		and local_position.y >= 0.0 and local_position.y < VIEW_HEIGHT * CELL_SIZE


func _cell_from_local(local_position: Vector2) -> Vector2i:
	return camera_cell + Vector2i(
		floori(local_position.x / float(CELL_SIZE)),
		floori(local_position.y / float(CELL_SIZE))
	)


func _refresh_hover_validity() -> void:
	if not interaction_enabled or not is_visible_cell(hover_cell):
		hover_valid = false
		return
	match interaction_mode:
		InteractionMode.DIG:
			hover_valid = can_dig(hover_cell)
		InteractionMode.DEFENDER:
			hover_valid = can_place_defender(hover_cell)
		InteractionMode.MOVE_LORD:
			hover_valid = can_move_lord(hover_cell)


func _cell_rect(cell: Vector2i) -> Rect2:
	var screen_cell := cell - camera_cell
	return Rect2(
		Vector2(screen_cell.x * CELL_SIZE, screen_cell.y * CELL_SIZE),
		Vector2(CELL_SIZE, CELL_SIZE)
	)


func _cell_center(cell: Vector2i) -> Vector2:
	return _cell_rect(cell).get_center()


func _biome_colors(index: int) -> Array[Color]:
	match index:
		0:
			return [Color(0.19, 0.105, 0.12), Color(0.085, 0.065, 0.085), Color(0.3, 0.13, 0.27)]
		1:
			return [Color(0.12, 0.16, 0.19), Color(0.055, 0.085, 0.1), Color(0.2, 0.42, 0.48)]
		2:
			return [Color(0.16, 0.115, 0.075), Color(0.09, 0.065, 0.045), Color(0.56, 0.31, 0.12)]
		_:
			return [Color(0.115, 0.08, 0.18), Color(0.055, 0.04, 0.095), Color(0.42, 0.2, 0.62)]


func _draw() -> void:
	_draw_surface_strip()
	for y in range(camera_cell.y, camera_cell.y + VIEW_HEIGHT):
		for x in range(camera_cell.x, camera_cell.x + VIEW_WIDTH):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell)
			var inner := rect.grow(-0.5)
			var cell_type := get_cell_type(cell)
			var palette := _biome_colors(get_biome_index(cell))

			match cell_type:
				CellType.DIRT:
					draw_rect(inner, palette[0])
					var grain_y := 10.0 if (x + y) % 2 == 0 else 22.0
					draw_line(
						rect.position + Vector2(6, grain_y),
						rect.position + Vector2(26, grain_y - 2),
						palette[2].darkened(0.35),
						2.0
					)
				CellType.ORE:
					draw_rect(inner, palette[0].lightened(0.04))
					draw_circle(_cell_center(cell), 9.0, palette[2].lightened(0.25))
					draw_circle(_cell_center(cell) + Vector2(-3, -3), 3.0, Color(0.96, 0.72, 1.0))
				CellType.FLOOR:
					draw_rect(inner, palette[1])
					draw_circle(_cell_center(cell), 2.0, palette[0].lightened(0.12))
				CellType.ENTRANCE:
					draw_rect(inner, Color(0.06, 0.08, 0.11))
					var center := _cell_center(cell)
					draw_colored_polygon(
						PackedVector2Array([
							center + Vector2(-10, -8),
							center + Vector2(10, -8),
							center + Vector2(0, 12),
						]),
						Color(0.32, 0.72, 0.95)
					)
				CellType.LORD:
					draw_rect(inner, Color(0.13, 0.045, 0.065))
					var center := _cell_center(cell)
					draw_circle(center, 11.0, Color(0.86, 0.16, 0.25))
					draw_line(center + Vector2(-8, -6), center + Vector2(-12, -14), Color(1, 0.55, 0.35), 4.0)
					draw_line(center + Vector2(8, -6), center + Vector2(12, -14), Color(1, 0.55, 0.35), 4.0)

			draw_rect(rect, Color(0.5, 0.4, 0.5, 0.16), false, 0.5)

	for cell in preview_path:
		if is_visible_cell(cell) and cell != entrance_cell and cell != lord_cell:
			draw_circle(_cell_center(cell), 3.4, Color(0.95, 0.72, 0.23, 0.62))

	for key in defenders:
		if is_visible_cell(key):
			_draw_defender(key, int(defenders[key]))

	if hero_cell != INVALID_CELL and is_visible_cell(hero_cell):
		_draw_hero(hero_cell)

	if interaction_enabled and is_visible_cell(hover_cell):
		var outline_color := Color(0.34, 0.92, 0.68, 1) if hover_valid else Color(0.95, 0.28, 0.32, 0.85)
		draw_rect(_cell_rect(hover_cell).grow(-2.0), outline_color, false, 3.0)

	_draw_camera_status()


func _draw_surface_strip() -> void:
	var strip := Rect2(Vector2(0, -SURFACE_HEIGHT), Vector2(VIEW_WIDTH * CELL_SIZE, SURFACE_HEIGHT))
	draw_rect(strip, Color(0.055, 0.04, 0.075))
	draw_rect(Rect2(Vector2(0, -18), Vector2(VIEW_WIDTH * CELL_SIZE, 18)), Color(0.13, 0.09, 0.1))
	var cave_x := _surface_cave_world_x() - camera_cell.x * CELL_SIZE
	if cave_x >= -24.0 and cave_x <= VIEW_WIDTH * CELL_SIZE + 24.0:
		draw_circle(Vector2(cave_x, -13), 21.0, Color(0.19, 0.16, 0.2))
		draw_circle(Vector2(cave_x, -8), 11.0, Color(0.025, 0.025, 0.04))
	var castle_x := cave_x - 280.0
	if castle_x > -80.0 and castle_x < VIEW_WIDTH * CELL_SIZE + 80.0:
		draw_rect(Rect2(Vector2(castle_x, -66), Vector2(58, 50)), Color(0.2, 0.19, 0.24))
		draw_rect(Rect2(Vector2(castle_x + 8, -82), Vector2(13, 66)), Color(0.23, 0.22, 0.27))
		draw_rect(Rect2(Vector2(castle_x + 37, -76), Vector2(13, 60)), Color(0.23, 0.22, 0.27))
	var knight_x := _surface_knight_world_x - camera_cell.x * CELL_SIZE
	if not _surface_knight_entered and knight_x >= -10.0 and knight_x <= VIEW_WIDTH * CELL_SIZE + 10.0:
		var knight_y := _surface_knight_y + sin(_pulse_time * 8.0) * 1.5
		draw_circle(Vector2(knight_x, knight_y - 8), 4.0, Color(0.82, 0.84, 0.9))
		draw_line(Vector2(knight_x, knight_y - 4), Vector2(knight_x, knight_y + 7), Color(0.72, 0.74, 0.82), 4.0)
		draw_line(Vector2(knight_x + 3, knight_y), Vector2(knight_x + 8, knight_y - 7), Color(0.95, 0.7, 0.25), 1.5)


func _draw_camera_status() -> void:
	var biome := get_biome_index(camera_cell) + 1
	var text := "x %03d–%03d  y %03d–%03d  •  БИОМ %d/4" % [
		camera_cell.x,
		camera_cell.x + VIEW_WIDTH - 1,
		camera_cell.y,
		camera_cell.y + VIEW_HEIGHT - 1,
		biome,
	]
	draw_string(ThemeDB.fallback_font, Vector2(8, -5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.72, 0.67, 0.76))


func _draw_defender(cell: Vector2i, hp: int) -> void:
	var center := _cell_center(cell)
	var pulse := 0.5 + 0.5 * sin(_pulse_time * 3.0 + float(cell.x))
	var body_color := Color(0.2, 0.74 + pulse * 0.08, 0.55, 1)
	draw_circle(center, 11.6, Color(0.025, 0.12, 0.09, 1))
	draw_circle(center, 9.2, body_color)
	var bar_rect := Rect2(center + Vector2(-12, 12), Vector2(24, 3))
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
			center + Vector2(0, -12),
			center + Vector2(10, 0),
			center + Vector2(0, 12),
			center + Vector2(-10, 0),
		]),
		Color(0.96, 0.63, 0.22, 1)
	)
	var bar_rect := Rect2(center + Vector2(-14, -16), Vector2(28, 3))
	draw_rect(bar_rect, Color(0.08, 0.04, 0.08, 1))
	draw_rect(
		Rect2(bar_rect.position, Vector2(bar_rect.size.x * clampf(float(hero_hp) / float(hero_max_hp), 0.0, 1.0), bar_rect.size.y)),
		Color(0.92, 0.25, 0.22, 1)
	)
