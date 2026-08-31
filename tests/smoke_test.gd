extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	_check(packed_scene != null, "Главная сцена загружается.")
	if packed_scene == null:
		_finish()
		return

	_test_board_and_loss(packed_scene)
	_test_two_defender_win(packed_scene)
	_finish()


func _test_board_and_loss(packed_scene: PackedScene) -> void:
	var game := packed_scene.instantiate()
	root.add_child(game)
	var board: GrayboxBoard = game.get_node("Board")
	game.get_node("BuildTimer").stop()

	var route := board.find_path(board.entrance_cell, board.lord_cell)
	_check(route.size() > 10, "На стартовой карте существует маршрут к Владыке.")

	var ore_cell := Vector2i(2, 1)
	_check(board.can_dig(ore_cell), "Первая клетка руды доступна для раскопки.")
	var reward := board.dig_cell(ore_cell)
	_check(reward == GrayboxBoard.ORE_REWARD, "Руда начисляет ожидаемый ресурс.")

	game.call("_start_assault")
	game.call("debug_run_to_completion")
	_check(game.call("_phase_title") == "ПОРАЖЕНИЕ", "Без защитников герой достигает Владыки.")

	root.remove_child(game)
	game.free()


func _test_two_defender_win(packed_scene: PackedScene) -> void:
	var game := packed_scene.instantiate()
	root.add_child(game)
	var board: GrayboxBoard = game.get_node("Board")
	game.get_node("BuildTimer").stop()

	var route := board.find_path(board.entrance_cell, board.lord_cell)
	_check(route.size() > 7, "Для боевого теста хватает клеток маршрута.")
	if route.size() > 7:
		_check(board.place_defender(route[3], 3), "Первый защитник поставлен на маршрут.")
		_check(board.place_defender(route[7], 3), "Второй защитник поставлен на маршрут.")

	game.call("_start_assault")
	game.call("debug_run_to_completion")
	_check(game.call("_phase_title") == "ПОБЕДА", "Два защитника останавливают героя.")

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
