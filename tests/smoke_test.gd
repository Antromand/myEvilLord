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
	_test_dead_end_room_exit()
	_test_loss_without_defenders(packed_scene)
	_test_three_wave_win(packed_scene)
	_finish()


func _test_route_and_economy(packed_scene: PackedScene) -> void:
	var game := _create_game(packed_scene)
	var board: GrayboxBoard = game.get_node("Board")

	_check(int(game.call("debug_get_darkness")) == 999, "Каждый отладочный запуск начинается с 999 мрака.")
	_check(GrayboxBoard.WIDTH == 64 and GrayboxBoard.HEIGHT == 128, "Размер уровня уменьшен до 64×128 клеток.")
	_check(GrayboxBoard.VIEW_WIDTH == 32 and GrayboxBoard.VIEW_HEIGHT == 16, "Камера показывает 32×16 клеток.")
	_check(board.entrance_cell.y == 0, "Вторжение начинается на верхней границе.")
	_check(board.lord_cell == Vector2i(GrayboxBoard.ENTRANCE_X, 3), "Владыка начинает на третьей клетке ниже входа.")
	_check(board.is_walkable(Vector2i(GrayboxBoard.ENTRANCE_X, 1)), "Первая клетка вниз прокопана.")
	_check(board.is_walkable(Vector2i(GrayboxBoard.ENTRANCE_X, 2)), "Вторая клетка вниз прокопана.")
	_check(board.is_walkable(Vector2i(GrayboxBoard.ENTRANCE_X, 3)), "Третья клетка вниз прокопана.")
	_check(not board.is_walkable(Vector2i(GrayboxBoard.ENTRANCE_X, 4)), "Ниже трёх клеток земля не прокопана.")
	_check(board.get_biome_index(Vector2i(0, 31)) == 0, "Первый биом занимает строки 0–31.")
	_check(board.get_biome_index(Vector2i(0, 32)) == 1, "На строке 32 начинается второй биом.")
	_check(board.get_biome_index(Vector2i(0, 64)) == 2, "На строке 64 начинается третий биом.")
	_check(board.get_biome_index(Vector2i(0, 96)) == 3, "На строке 96 начинается четвёртый биом.")

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

	var defender_passage_cell := Vector2i(GrayboxBoard.ENTRANCE_X, 2)
	var lord_passage_target := Vector2i(GrayboxBoard.ENTRANCE_X, 1)
	_check(board.place_defender(defender_passage_cell, 3), "Защитник установлен между Владыкой и целью.")
	game.call("_on_board_cell_clicked", lord_passage_target)
	_finish_lord_action(board)
	_check(board.lord_cell == lord_passage_target, "Защитник не блокирует проход Владыки.")
	board.remove_defender(defender_passage_cell)
	game.call("_on_board_cell_clicked", Vector2i(GrayboxBoard.ENTRANCE_X, 3))
	_finish_lord_action(board)

	var plain_dirt := Vector2i(GrayboxBoard.ENTRANCE_X - 1, 1)
	game.call("debug_set_darkness", 0)
	game.call("_on_board_cell_clicked", plain_dirt)
	_check(board.get_cell_type(plain_dirt) == GrayboxBoard.CellType.DIRT, "При нулевом мраке копание заблокировано.")
	_check(int(game.call("debug_get_darkness")) == 0, "Заблокированное копание не уводит ресурс в минус.")

	game.call("debug_set_darkness", 2)
	game.call("_on_board_cell_clicked", plain_dirt)
	_check(board.is_lord_action_active(), "После клика Владыка начинает анимированный путь к блоку.")
	_finish_lord_action(board)
	_check(board.lord_cell == plain_dirt and board.is_walkable(plain_dirt), "Владыка доходит до блока и прокапывает его.")
	_check(int(game.call("debug_get_darkness")) == 1, "Обычное копание списывает 1 мрак.")

	var ore_cell := GrayboxBoard.FIRST_ORE_CELL
	_check(board.can_dig(ore_cell), "Первая клетка руды доступна для раскопки.")
	game.call("debug_set_darkness", 4)
	game.call("_on_board_cell_clicked", ore_cell)
	_finish_lord_action(board)
	_check(int(game.call("debug_get_darkness")) == 7, "Руда даёт чистый прирост 3 после стоимости копания.")

	game.call("debug_set_darkness", 998)
	game.call("debug_generate_darkness_tick")
	game.call("debug_generate_darkness_tick")
	_check(int(game.call("debug_get_darkness")) == 999, "Пассивная генерация останавливается на отладочном лимите 999.")

	var prepared_side_cell := Vector2i(GrayboxBoard.ENTRANCE_X - 1, 2)
	game.call("_on_board_cell_clicked", prepared_side_cell)
	_finish_lord_action(board)
	game.call("_on_board_cell_clicked", Vector2i(GrayboxBoard.ENTRANCE_X, 2))
	_finish_lord_action(board)
	_check(board.lord_cell == Vector2i(GrayboxBoard.ENTRANCE_X, 2), "Клик по пустому тоннелю заставляет Владыку дойти до него.")

	var patrol_start := board.get_surface_knight_position()
	board.call("_process", 0.5)
	_check(board.get_surface_knight_position() != patrol_start, "До вторжения рыцарь патрулирует около замка.")
	var approach_start := board.get_surface_knight_position()
	game.call("_start_assault")
	_check(game.call("_phase_title") == "РЫЦАРЬ ИДЁТ К ПЕЩЕРЕ", "Вторжение начинается с подхода к пещере.")
	_check(board.get_surface_knight_position() == approach_start, "При старте вторжения рыцарь не телепортируется.")
	_check(board.hero_cell == GrayboxBoard.INVALID_CELL, "Подземный герой не появляется до входа в пещеру.")

	board.call("_process", 0.25)
	_check(board.get_surface_knight_position() > approach_start, "Рыцарь идёт к пещере с текущей позиции.")
	game.call("_toggle_pause")
	var paused_position := board.get_surface_knight_position()
	board.call("_process", 1.0)
	_check(board.get_surface_knight_position() == paused_position, "Активная пауза замораживает подход к пещере.")
	_check(bool(game.get("game_paused")), "Состояние активной паузы включено.")
	game.call("debug_set_darkness", 999)
	var pause_dig_cell := Vector2i(GrayboxBoard.ENTRANCE_X + 1, 1)
	game.call("_on_board_cell_clicked", pause_dig_cell)
	_check(board.get_cell_type(pause_dig_cell) != GrayboxBoard.CellType.FLOOR, "Во время паузы строить нельзя.")

	game.call("_toggle_pause")
	for step in range(20):
		board.call("_process", 0.25)
	_check(game.call("_phase_title") == "ВТОРЖЕНИЕ", "После визуального входа начинается подземное вторжение.")
	_check(board.hero_cell == board.entrance_cell, "Герой появляется у входа только после входа в пещеру.")

	game.call("_on_board_cell_clicked", prepared_side_cell)
	_finish_lord_action(board)
	_check(board.lord_cell == prepared_side_cell, "Во время вторжения Владыка перемещается по клику в пустой тоннель.")

	game.call("_advance_hero")
	var lord_before_blocked_move := board.lord_cell
	game.call("_on_board_cell_clicked", board.entrance_cell)
	_check(board.lord_cell == lord_before_blocked_move and not board.is_lord_action_active(), "Владыка не может переместиться за вторженца.")

	var invasion_dig_cell := Vector2i(GrayboxBoard.ENTRANCE_X - 2, 2)
	game.call("debug_set_darkness", 4)
	game.call("_on_board_cell_clicked", invasion_dig_cell)
	_finish_lord_action(board)
	_check(board.lord_cell == invasion_dig_cell and board.is_walkable(invasion_dig_cell), "Во время вторжения Владыка продолжает копать.")

	game.call("_toggle_pause")
	game.call("_set_mode", GrayboxBoard.InteractionMode.DIG)
	game.call("debug_set_darkness", 4)
	var paused_lord_cell := board.lord_cell
	game.call("_on_board_cell_clicked", Vector2i(GrayboxBoard.ENTRANCE_X - 3, 2))
	_check(board.lord_cell == paused_lord_cell and not board.is_lord_action_active(), "На паузе вторжения доступен только осмотр.")
	game.call("_toggle_pause")

	for button_name in ["DigButton", "DefenderButton", "MoveLordButton", "PauseButton", "StartButton", "RestartButton"]:
		var button: Button = game.get_node("HUD/RightPanel/" + button_name)
		_check(button.focus_mode == Control.FOCUS_NONE, "Стрелки не меняют выбранный инструмент через фокус: %s." % button_name)

	_destroy_game(game)


func _test_loss_without_defenders(packed_scene: PackedScene) -> void:
	var game := _create_game(packed_scene)
	game.call("_start_assault")
	game.call("debug_run_to_completion")
	_check(game.call("_phase_title") == "ПОРАЖЕНИЕ", "Без защитников герой достигает Владыки.")
	_destroy_game(game)


func _test_three_wave_win(packed_scene: PackedScene) -> void:
	var game := _create_game(packed_scene)
	var board: GrayboxBoard = game.get_node("Board")
	var route := board.build_wandering_route(board.entrance_cell, board.lord_cell, TEST_SEED)
	var placed := false
	for cell in route:
		if board.can_place_defender(cell) and board.place_defender(cell, 99):
			placed = true
			break
	_check(placed, "Усиленный тестовый защитник поставлен на маршрут трёх волн.")

	game.call("_start_assault")
	game.call("debug_run_current_wave")
	_check(game.call("_phase_title") == "СТРОИТЕЛЬСТВО", "После первой атаки снова начинается фаза строительства.")
	_check(int(game.get("current_wave")) == 2, "Вторая фаза строительства готовит волну из двух героев.")
	_check(int(game.get("defeated_attackers")) == 1, "В первой атаке участвовал один герой.")
	game.call("_start_assault")
	game.call("_on_knight_entered_cave")
	game.call("_advance_hero")
	game.call("_on_spawn_timer_timeout")
	var active_attackers: Array = game.get("active_attackers")
	_check(active_attackers.size() == 2, "Второй герой выходит, пока первый герой ещё жив.")
	_check(
		active_attackers[0]["cell"] != active_attackers[1]["cell"],
		"Герои выходят друг за другом и не занимают одну клетку."
	)
	_check(int(game.get("defeated_attackers")) == 1, "Выход следующего героя не зависит от смерти предыдущего.")
	game.call("debug_run_to_completion")
	_check(game.call("_phase_title") == "ПОБЕДА", "Защита останавливает все три волны.")
	_check(int(game.get("defeated_attackers")) == 6, "В волнах последовательно уничтожены 1 + 2 + 3 вторженца.")
	_check(int(game.get("current_wave")) == 3, "Победа наступает после третьей волны.")
	_destroy_game(game)


func _test_dead_end_room_exit() -> void:
	var board := GrayboxBoard.new()
	root.add_child(board)
	board.reset_board()
	board.call("_set_cell", board.lord_cell, GrayboxBoard.CellType.FLOOR)
	for y in range(2, 6):
		for x in range(30, 35):
			board.call("_set_cell", Vector2i(x, y), GrayboxBoard.CellType.FLOOR)
	for x in range(32, 37):
		board.call("_set_cell", Vector2i(x, 1), GrayboxBoard.CellType.FLOOR)
	board.lord_cell = Vector2i(36, 1)
	board.call("_set_cell", board.lord_cell, GrayboxBoard.CellType.LORD)

	var route := board.build_wandering_route(Vector2i(33, 5), board.lord_cell, 760)
	_check(not route.is_empty() and route[-1] == board.lord_cell, "Нападающий находит выход из тупиковой комнаты.")
	_check(route.size() <= 32, "Нападающий покидает тупиковую комнату без долгого зацикливания.")
	root.remove_child(board)
	board.free()


func _create_game(packed_scene: PackedScene) -> Node:
	var game := packed_scene.instantiate()
	root.add_child(game)
	game.get_node("BuildTimer").stop()
	game.get_node("DarknessTimer").stop()
	game.get_node("SpawnTimer").stop()
	game.call("debug_set_invasion_seed", TEST_SEED)
	return game


func _destroy_game(game: Node) -> void:
	root.remove_child(game)
	game.free()


func _finish_lord_action(board: GrayboxBoard, max_steps: int = 128) -> void:
	var steps := 0
	while board.is_lord_action_active() and steps < max_steps:
		board.call("_process", 0.1)
		steps += 1
	_check(not board.is_lord_action_active(), "Анимация действия Владыки завершается за допустимое время.")


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
