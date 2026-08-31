extends SceneTree

const TEST_SEED := 424242

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	_check(packed_scene != null, "Главная сцена загружается.")
	if packed_scene == null:
		_finish()
		return

	_test_route_and_economy(packed_scene)
	_test_loss_without_defenders(packed_scene)
	_test_two_defender_win(packed_scene)
	_finish()


func _test_route_and_economy(packed_scene: PackedScene) -> void:
	var game := _create_game(packed_scene)
	var board: GrayboxBoard = game.get_node("Board")

	_check(GrayboxBoard.WIDTH == 128 and GrayboxBoard.HEIGHT == 256, "Размер уровня равен 128×256 клеток.")
	_check(GrayboxBoard.VIEW_WIDTH == 64 and GrayboxBoard.VIEW_HEIGHT == 32, "Камера показывает 64×32 клетки.")
	_check(board.entrance_cell.y == 0, "Вторжение начинается на верхней границе.")
	_check(board.lord_cell == Vector2i(GrayboxBoard.ENTRANCE_X, 3), "Владыка начинает на третьей клетке ниже входа.")
	_check(board.is_walkable(Vector2i(GrayboxBoard.ENTRANCE_X, 1)), "Первая клетка вниз прокопана.")
	_check(board.is_walkable(Vector2i(GrayboxBoard.ENTRANCE_X, 2)), "Вторая клетка вниз прокопана.")
	_check(board.is_walkable(Vector2i(GrayboxBoard.ENTRANCE_X, 3)), "Третья клетка вниз прокопана.")
	_check(not board.is_walkable(Vector2i(GrayboxBoard.ENTRANCE_X, 4)), "Ниже трёх клеток земля не прокопана.")
	_check(board.get_biome_index(Vector2i(0, 63)) == 0, "Первый биом занимает строки 0–63.")
	_check(board.get_biome_index(Vector2i(0, 64)) == 1, "На строке 64 начинается второй биом.")
	_check(board.get_biome_index(Vector2i(0, 128)) == 2, "На строке 128 начинается третий биом.")
	_check(board.get_biome_index(Vector2i(0, 192)) == 3, "На строке 192 начинается четвёртый биом.")

	board.scroll_by(Vector2i(999, 999))
	_check(
		board.camera_cell == Vector2i(GrayboxBoard.WIDTH - GrayboxBoard.VIEW_WIDTH, GrayboxBoard.HEIGHT - GrayboxBoard.VIEW_HEIGHT),
		"Прокрутка ограничена правой и нижней границами карты."
	)
	board.center_camera_on(board.entrance_cell)

	var route_a := board.build_wandering_route(board.entrance_cell, board.lord_cell, TEST_SEED)
	var route_b := board.build_wandering_route(board.entrance_cell, board.lord_cell, TEST_SEED)
	_check(route_a == route_b, "Одинаковый seed воспроизводит тот же маршрут.")
	_check(not route_a.is_empty() and route_a[route_a.size() - 1] == board.lord_cell, "Блуждание завершается у Владыки.")
	_check(route_a == [
		board.entrance_cell,
		Vector2i(GrayboxBoard.ENTRANCE_X, 1),
		Vector2i(GrayboxBoard.ENTRANCE_X, 2),
		board.lord_cell,
	], "В узком стартовом коридоре герой идёт исключительно прямо.")

	var plain_dirt := Vector2i(GrayboxBoard.ENTRANCE_X - 1, 1)
	game.call("debug_set_darkness", 0)
	game.call("_on_board_cell_clicked", plain_dirt)
	_check(board.get_cell_type(plain_dirt) == GrayboxBoard.CellType.DIRT, "При нулевом мраке копание заблокировано.")
	_check(int(game.call("debug_get_darkness")) == 0, "Заблокированное копание не уводит ресурс в минус.")

	game.call("debug_set_darkness", 2)
	game.call("_on_board_cell_clicked", plain_dirt)
	_check(board.get_cell_type(plain_dirt) == GrayboxBoard.CellType.FLOOR, "Оплаченное копание создаёт тоннель.")
	_check(int(game.call("debug_get_darkness")) == 1, "Обычное копание списывает 1 мрак.")

	var ore_cell := GrayboxBoard.FIRST_ORE_CELL
	_check(board.can_dig(ore_cell), "Первая клетка руды доступна для раскопки.")
	game.call("debug_set_darkness", 4)
	game.call("_on_board_cell_clicked", ore_cell)
	_check(int(game.call("debug_get_darkness")) == 7, "Руда даёт чистый прирост 3 после стоимости копания.")

	game.call("debug_set_darkness", 15)
	game.call("debug_generate_darkness_tick")
	game.call("debug_generate_darkness_tick")
	_check(int(game.call("debug_get_darkness")) == 16, "Пассивная генерация останавливается на лимите 16.")

	game.call("_set_mode", GrayboxBoard.InteractionMode.MOVE_LORD)
	game.call("_on_board_cell_clicked", plain_dirt)
	_check(board.lord_cell == plain_dirt, "До вторжения Владыка переносится в свободную клетку.")
	var previous_lord := board.lord_cell
	game.call("_start_assault")
	game.call("_on_board_cell_clicked", Vector2i(GrayboxBoard.ENTRANCE_X, 2))
	_check(board.lord_cell == previous_lord, "После начала вторжения перенос Владыки заблокирован.")

	_destroy_game(game)


func _test_loss_without_defenders(packed_scene: PackedScene) -> void:
	var game := _create_game(packed_scene)
	game.call("_start_assault")
	game.call("debug_run_to_completion")
	_check(game.call("_phase_title") == "ПОРАЖЕНИЕ", "Без защитников герой достигает Владыки.")
	_destroy_game(game)


func _test_two_defender_win(packed_scene: PackedScene) -> void:
	var game := _create_game(packed_scene)
	var board: GrayboxBoard = game.get_node("Board")
	var route := board.build_wandering_route(board.entrance_cell, board.lord_cell, TEST_SEED)
	var placed := 0
	var occupied: Dictionary = {}
	for cell in route:
		if placed >= 2:
			break
		if board.can_place_defender(cell) and not occupied.has(cell):
			occupied[cell] = true
			if board.place_defender(cell, 3):
				placed += 1
	_check(placed == 2, "Два защитника поставлены на блуждающий маршрут.")

	game.call("_start_assault")
	game.call("debug_run_to_completion")
	_check(game.call("_phase_title") == "ПОБЕДА", "Два защитника останавливают героя.")
	_destroy_game(game)


func _create_game(packed_scene: PackedScene) -> Node:
	var game := packed_scene.instantiate()
	root.add_child(game)
	game.get_node("BuildTimer").stop()
	game.get_node("DarknessTimer").stop()
	game.call("debug_set_invasion_seed", TEST_SEED)
	return game


func _destroy_game(game: Node) -> void:
	root.remove_child(game)
	game.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	if failures == 0:
		print("SMOKE TESTS PASSED")
	else:
		push_error("SMOKE TESTS FAILED: %d" % failures)
	quit(failures)
