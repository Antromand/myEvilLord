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

	_check(board.entrance_cell.y == 0, "Вторжение начинается на верхней границе.")
	_check(board.lord_cell.y == GrayboxBoard.HEIGHT - 1, "Владыка находится в нижней части карты.")

	var route_a := board.build_wandering_route(board.entrance_cell, board.lord_cell, TEST_SEED)
	var route_b := board.build_wandering_route(board.entrance_cell, board.lord_cell, TEST_SEED)
	var route_other := board.build_wandering_route(board.entrance_cell, board.lord_cell, TEST_SEED + 1)
	var shortest_route := board.find_path(board.entrance_cell, board.lord_cell)
	_check(route_a == route_b, "Одинаковый seed воспроизводит тот же маршрут.")
	_check(route_a != route_other, "Другой seed меняет блуждающий маршрут.")
	_check(not route_a.is_empty() and route_a[route_a.size() - 1] == board.lord_cell, "Блуждание завершается у Владыки.")
	_check(route_a.size() > shortest_route.size(), "Блуждающий маршрут не сводится к кратчайшему BFS.")
	_check(
		route_a.size() <= GrayboxBoard.WANDER_STEP_BUDGET + GrayboxBoard.WIDTH * GrayboxBoard.HEIGHT,
		"Защита от циклов ограничивает длину маршрута."
	)

	var plain_dirt := Vector2i(4, 0)
	game.call("debug_set_darkness", 0)
	game.call("_on_board_cell_clicked", plain_dirt)
	_check(board.get_cell_type(plain_dirt) == GrayboxBoard.CellType.DIRT, "При нулевом мраке копание заблокировано.")
	_check(int(game.call("debug_get_darkness")) == 0, "Заблокированное копание не уводит ресурс в минус.")

	game.call("debug_set_darkness", 2)
	game.call("_on_board_cell_clicked", plain_dirt)
	_check(board.get_cell_type(plain_dirt) == GrayboxBoard.CellType.FLOOR, "Оплаченное копание создаёт тоннель.")
	_check(int(game.call("debug_get_darkness")) == 1, "Обычное копание списывает 1 мрак.")

	var ore_cell := Vector2i(4, 1)
	_check(board.can_dig(ore_cell), "Первая клетка руды доступна для раскопки.")
	game.call("debug_set_darkness", 4)
	game.call("_on_board_cell_clicked", ore_cell)
	_check(int(game.call("debug_get_darkness")) == 7, "Руда даёт чистый прирост 3 после стоимости копания.")

	game.call("debug_set_darkness", 15)
	game.call("debug_generate_darkness_tick")
	game.call("debug_generate_darkness_tick")
	_check(int(game.call("debug_get_darkness")) == 16, "Пассивная генерация останавливается на лимите 16.")

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
