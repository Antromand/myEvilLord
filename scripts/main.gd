extends Node2D

const DEFENDER_COST := 4
const DEFENDER_REFUND := 2
const DEFENDER_MAX_HP := 3
const DIG_COST := 1
const DARKNESS_CAP := 999
const DEBUG_START_DARKNESS := 999
const DARKNESS_GENERATION_AMOUNT := 1
const HERO_MAX_HP := 8
const HERO_ATTACK := 1
const DEFENDER_ATTACK := 2
const TOTAL_WAVES := 3
const PREPARATION_SECONDS := 75
const INVALID_CELL := Vector2i(-1, -1)

enum Phase {
	PREPARATION,
	APPROACH,
	ASSAULT,
	WON,
	LOST,
}

@onready var board: GrayboxBoard = $Board
@onready var move_timer: Timer = $MoveTimer
@onready var combat_timer: Timer = $CombatTimer
@onready var build_timer: Timer = $BuildTimer
@onready var darkness_timer: Timer = $DarknessTimer

@onready var status_label: Label = $HUD/TopBar/StatusLabel
@onready var resource_label: Label = $HUD/TopBar/ResourceLabel
@onready var timer_label: Label = $HUD/TopBar/TimerLabel
@onready var hero_label: Label = $HUD/TopBar/HeroLabel
@onready var hint_label: Label = $HUD/TopBar/HintLabel
@onready var dig_button: Button = $HUD/RightPanel/DigButton
@onready var defender_button: Button = $HUD/RightPanel/DefenderButton
@onready var move_lord_button: Button = $HUD/RightPanel/MoveLordButton
@onready var pause_button: Button = $HUD/RightPanel/PauseButton
@onready var start_button: Button = $HUD/RightPanel/StartButton
@onready var restart_button: Button = $HUD/RightPanel/RestartButton
@onready var outcome_label: Label = $HUD/RightPanel/OutcomeLabel

var phase := Phase.PREPARATION
var resource_points := DEBUG_START_DARKNESS
var preparation_seconds := PREPARATION_SECONDS
var hero_hp := HERO_MAX_HP
var current_route: Array[Vector2i] = []
var route_index := 0
var combat_cell := INVALID_CELL
var selected_mode := GrayboxBoard.InteractionMode.DIG
var invasion_seed := 0
var event_message := "Подготовка началась."
var game_paused := false
var current_wave := 1
var attackers_left_in_wave := 1
var attacker_number_in_wave := 0
var defeated_attackers := 0


func _ready() -> void:
	board.cell_clicked.connect(_on_board_cell_clicked)
	board.cell_right_clicked.connect(_on_board_cell_right_clicked)
	board.knight_entered_cave.connect(_on_knight_entered_cave)
	move_timer.timeout.connect(_on_move_timer_timeout)
	combat_timer.timeout.connect(_on_combat_timer_timeout)
	build_timer.timeout.connect(_on_build_timer_timeout)
	darkness_timer.timeout.connect(_on_darkness_timer_timeout)
	dig_button.pressed.connect(_on_dig_button_pressed)
	defender_button.pressed.connect(_on_defender_button_pressed)
	move_lord_button.pressed.connect(_on_move_lord_button_pressed)
	pause_button.pressed.connect(_on_pause_button_pressed)
	start_button.pressed.connect(_on_start_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)

	board.reset_board()
	phase = Phase.PREPARATION
	resource_points = DEBUG_START_DARKNESS
	preparation_seconds = PREPARATION_SECONDS
	hero_hp = HERO_MAX_HP
	route_index = 0
	combat_cell = INVALID_CELL
	selected_mode = GrayboxBoard.InteractionMode.DIG
	game_paused = false
	current_wave = 1
	attackers_left_in_wave = 1
	attacker_number_in_wave = 0
	defeated_attackers = 0
	invasion_seed = _create_invasion_seed()
	board.set_interaction(selected_mode, true)
	board.set_invasion_active(false)
	board.clear_hero()
	_update_route_preview()
	build_timer.start()
	darkness_timer.start()
	_refresh_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_code: int = int(event.physical_keycode)
	if key_code == 0:
		key_code = int(event.keycode)
	match key_code:
		KEY_1:
			_set_mode(GrayboxBoard.InteractionMode.DIG)
		KEY_2:
			_set_mode(GrayboxBoard.InteractionMode.DEFENDER)
		KEY_3:
			_set_mode(GrayboxBoard.InteractionMode.MOVE_LORD)
		KEY_ENTER, KEY_KP_ENTER:
			_start_assault()
		KEY_SPACE:
			_toggle_pause()
		KEY_R:
			_restart_game()


func _on_board_cell_clicked(cell: Vector2i) -> void:
	if phase == Phase.PREPARATION and not game_paused and cell == board.lord_cell:
		if selected_mode == GrayboxBoard.InteractionMode.MOVE_LORD:
			_set_mode(GrayboxBoard.InteractionMode.DIG)
			event_message = "Перенос Владыки выключен."
		else:
			_set_mode(GrayboxBoard.InteractionMode.MOVE_LORD)
			event_message = "Владыка выбран. Повторный клик отменит перенос."
		_refresh_ui()
		return

	if not _can_edit_board():
		return

	if selected_mode == GrayboxBoard.InteractionMode.DIG:
		if resource_points < DIG_COST:
			event_message = "Недостаточно мрака. Сердце создаст 1 мрак максимум через 2 секунды."
			_refresh_ui()
			return
		if not board.can_dig(cell):
			event_message = "Копать можно только рядом с существующим тоннелем."
			_refresh_ui()
			return
		resource_points -= DIG_COST
		var reward := board.dig_cell(cell)
		var gained := _add_darkness(reward)
		if reward > 0:
			event_message = "Руда: копание −%d, получено +%d мрака." % [DIG_COST, gained]
		else:
			event_message = "Новый тоннель проложен за %d мрак." % DIG_COST
		if phase == Phase.PREPARATION:
			_update_route_preview()
		_refresh_ui()
		return

	if selected_mode == GrayboxBoard.InteractionMode.MOVE_LORD:
		if phase != Phase.PREPARATION:
			return
		if board.move_lord(cell):
			event_message = "Владыка перенесён в свободный тоннель."
			_update_route_preview()
		else:
			event_message = "Владыку можно перенести только в свободную прокопанную клетку."
		_refresh_ui()
		return

	if resource_points < DEFENDER_COST:
		event_message = "Недостаточно мрака: нужен ещё %d." % (DEFENDER_COST - resource_points)
		_refresh_ui()
		return
	if board.place_defender(cell, DEFENDER_MAX_HP):
		resource_points -= DEFENDER_COST
		event_message = "Защитник выращен. Проверьте, проходит ли здесь жёлтый маршрут."
	else:
		event_message = "Защитника можно поставить только в свободном тоннеле."
	_refresh_ui()


func _on_board_cell_right_clicked(cell: Vector2i) -> void:
	if not _can_edit_board():
		return
	if board.remove_defender(cell):
		var refunded := _add_darkness(DEFENDER_REFUND)
		event_message = "Защитник убран: возвращено %d мрака." % refunded
	else:
		event_message = "В этой клетке нет защитника."
	_refresh_ui()


func _on_dig_button_pressed() -> void:
	_set_mode(GrayboxBoard.InteractionMode.DIG)


func _on_defender_button_pressed() -> void:
	_set_mode(GrayboxBoard.InteractionMode.DEFENDER)


func _on_move_lord_button_pressed() -> void:
	_set_mode(GrayboxBoard.InteractionMode.MOVE_LORD)


func _on_pause_button_pressed() -> void:
	_toggle_pause()


func _on_start_button_pressed() -> void:
	_start_assault()


func _on_restart_button_pressed() -> void:
	_restart_game()


func _set_mode(mode: int) -> void:
	if not _can_edit_board():
		return
	if mode == GrayboxBoard.InteractionMode.MOVE_LORD and phase != Phase.PREPARATION:
		event_message = "После начала вторжения Владыку переносить нельзя."
		_refresh_ui()
		return
	if mode == GrayboxBoard.InteractionMode.DEFENDER and resource_points < DEFENDER_COST:
		event_message = "Сначала добудьте руду: защитник стоит %d мрака." % DEFENDER_COST
		_refresh_ui()
		return
	selected_mode = mode
	board.set_interaction(selected_mode, true)
	match mode:
		GrayboxBoard.InteractionMode.DIG:
			event_message = "Режим: копать."
		GrayboxBoard.InteractionMode.DEFENDER:
			event_message = "Режим: выращивать защитников."
		GrayboxBoard.InteractionMode.MOVE_LORD:
			event_message = "Режим: перенести Владыку в свободный тоннель."
	_refresh_ui()


func _can_edit_board() -> bool:
	return phase == Phase.PREPARATION and not game_paused


func _update_route_preview() -> void:
	current_route = board.build_wandering_route(
		board.entrance_cell,
		board.lord_cell,
		invasion_seed
	)
	board.set_preview_path(current_route)


func _start_assault() -> void:
	if phase != Phase.PREPARATION:
		return
	_update_route_preview()
	if current_route.is_empty():
		event_message = "Герой не видит путь к Владыке. Соедините вход и логово."
		_refresh_ui()
		return

	phase = Phase.APPROACH
	game_paused = false
	build_timer.stop()
	darkness_timer.stop()
	route_index = 0
	combat_cell = INVALID_CELL
	hero_hp = HERO_MAX_HP
	current_wave = 1
	attackers_left_in_wave = 1
	attacker_number_in_wave = 0
	defeated_attackers = 0
	if selected_mode == GrayboxBoard.InteractionMode.MOVE_LORD:
		selected_mode = GrayboxBoard.InteractionMode.DIG
	board.set_interaction(selected_mode, false)
	board.set_surface_motion_paused(false)
	board.set_invasion_active(true)
	board.clear_hero()
	event_message = "Вторжение началось: рыцарь идёт от текущей позиции к пещере."
	_refresh_ui()


func _on_knight_entered_cave() -> void:
	if phase != Phase.APPROACH:
		return
	phase = Phase.ASSAULT
	_spawn_next_attacker()
	_refresh_ui()


func _spawn_next_attacker() -> void:
	hero_hp = HERO_MAX_HP
	route_index = 0
	combat_cell = INVALID_CELL
	attacker_number_in_wave += 1
	board.set_hero(current_route[0], hero_hp, HERO_MAX_HP)
	event_message = "Волна %d/3: вторженец %d/%d начал спуск с %d HP." % [
		current_wave,
		attacker_number_in_wave,
		current_wave,
		HERO_MAX_HP,
	]
	if not game_paused:
		move_timer.start()


func _toggle_pause() -> void:
	if phase != Phase.PREPARATION and phase != Phase.APPROACH and phase != Phase.ASSAULT:
		return
	game_paused = not game_paused
	board.set_surface_motion_paused(game_paused)
	if game_paused:
		move_timer.stop()
		combat_timer.stop()
		build_timer.stop()
		darkness_timer.stop()
		board.set_interaction(selected_mode, false)
		event_message = "ПАУЗА: доступен только осмотр карты."
	else:
		board.set_interaction(selected_mode, phase == Phase.PREPARATION)
		if phase == Phase.PREPARATION:
			build_timer.start()
			darkness_timer.start()
		elif phase == Phase.ASSAULT:
			if combat_cell == INVALID_CELL:
				move_timer.start()
			else:
				combat_timer.start()
		event_message = "Пауза снята."
	_refresh_ui()


func _on_move_timer_timeout() -> void:
	_advance_hero()


func _advance_hero() -> void:
	if game_paused or phase != Phase.ASSAULT or combat_cell != INVALID_CELL:
		return
	if route_index >= current_route.size() - 1:
		_lose_game()
		return

	route_index += 1
	var next_cell := current_route[route_index]
	board.set_hero(next_cell, hero_hp, HERO_MAX_HP)

	if board.has_defender(next_cell):
		move_timer.stop()
		combat_cell = next_cell
		event_message = "Герой столкнулся с защитником."
		combat_timer.start()
		_refresh_ui()
		return

	if next_cell == board.lord_cell:
		_lose_game()
	else:
		_refresh_ui()


func _on_combat_timer_timeout() -> void:
	_resolve_combat_round()


func _resolve_combat_round() -> void:
	if game_paused or phase != Phase.ASSAULT or combat_cell == INVALID_CELL:
		return

	hero_hp = max(0, hero_hp - DEFENDER_ATTACK)
	var defender_hp := board.damage_defender(combat_cell, HERO_ATTACK)
	board.set_hero(combat_cell, hero_hp, HERO_MAX_HP)

	if hero_hp <= 0:
		_complete_current_attacker()
		return

	if defender_hp <= 0:
		combat_timer.stop()
		event_message = "Защитник погиб, герой продолжает путь с %d HP." % hero_hp
		combat_cell = INVALID_CELL
		move_timer.start()
	else:
		event_message = "Автобой: герой %d HP, защитник %d HP." % [hero_hp, defender_hp]
	_refresh_ui()


func _complete_current_attacker() -> void:
	move_timer.stop()
	combat_timer.stop()
	board.clear_hero()
	combat_cell = INVALID_CELL
	defeated_attackers += 1
	attackers_left_in_wave -= 1
	if attackers_left_in_wave > 0:
		_spawn_next_attacker()
		_refresh_ui()
		return
	if current_wave < TOTAL_WAVES:
		current_wave += 1
		attackers_left_in_wave = current_wave
		attacker_number_in_wave = 0
		_spawn_next_attacker()
		_refresh_ui()
		return
	_win_game()


func _win_game() -> void:
	phase = Phase.WON
	game_paused = false
	move_timer.stop()
	combat_timer.stop()
	build_timer.stop()
	darkness_timer.stop()
	board.clear_hero()
	board.set_surface_motion_paused(false)
	board.set_interaction(selected_mode, false)
	event_message = "Все три волны и шесть вторженцев уничтожены. Подземелье выстояло."
	_refresh_ui()


func _lose_game() -> void:
	phase = Phase.LOST
	game_paused = false
	move_timer.stop()
	combat_timer.stop()
	build_timer.stop()
	darkness_timer.stop()
	combat_cell = INVALID_CELL
	board.set_hero(board.lord_cell, hero_hp, HERO_MAX_HP)
	board.set_surface_motion_paused(false)
	board.set_interaction(selected_mode, false)
	event_message = "Герой добрался до Владыки."
	_refresh_ui()


func _on_build_timer_timeout() -> void:
	if game_paused or phase != Phase.PREPARATION:
		return
	preparation_seconds = maxi(0, preparation_seconds - 1)
	if preparation_seconds == 0:
		event_message = "Время подготовки закончилось."
		_start_assault()
	else:
		_refresh_ui()


func _on_darkness_timer_timeout() -> void:
	if game_paused or phase != Phase.PREPARATION:
		return
	_add_darkness(DARKNESS_GENERATION_AMOUNT)
	_refresh_ui()


func _add_darkness(amount: int) -> int:
	var before := resource_points
	resource_points = mini(DARKNESS_CAP, resource_points + amount)
	return resource_points - before


func _create_invasion_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1000, 999999)


func _restart_game() -> void:
	get_tree().reload_current_scene()


func _refresh_ui() -> void:
	status_label.text = "ФАЗА: %s" % _phase_title()
	resource_label.text = "МРАК %d/%d • КОПАТЬ %d • ЗАЩ. %d" % [
		resource_points,
		DARKNESS_CAP,
		DIG_COST,
		DEFENDER_COST,
	]
	if game_paused:
		timer_label.text = "ПАУЗА"
	elif phase == Phase.PREPARATION:
		timer_label.text = "ДО ВОЛНЫ: %02dс" % preparation_seconds
	elif phase == Phase.APPROACH:
		timer_label.text = "ПОДХОД"
	else:
		timer_label.text = "ВТОРЖЕНИЕ"
	if phase == Phase.PREPARATION or phase == Phase.APPROACH:
		hero_label.text = "ВОЛНА 1/3 • HP %d" % HERO_MAX_HP
	else:
		hero_label.text = "ВОЛНА %d/3 • ВРАГ %d/%d • HP %d/%d" % [
			current_wave,
			attacker_number_in_wave,
			current_wave,
			hero_hp,
			HERO_MAX_HP,
		]
	hint_label.text = event_message

	var can_edit := _can_edit_board()
	dig_button.disabled = not can_edit
	defender_button.disabled = not can_edit
	move_lord_button.disabled = phase != Phase.PREPARATION
	start_button.disabled = phase != Phase.PREPARATION or current_route.is_empty()
	pause_button.disabled = phase == Phase.WON or phase == Phase.LOST
	pause_button.text = "▶  ПРОДОЛЖИТЬ" if game_paused else "Ⅱ  ПАУЗА"
	dig_button.text = "●  1  КОПАТЬ" if selected_mode == GrayboxBoard.InteractionMode.DIG else "1  КОПАТЬ"
	defender_button.text = "●  2  ЗАЩИТНИК" if selected_mode == GrayboxBoard.InteractionMode.DEFENDER else "2  ЗАЩИТНИК"
	move_lord_button.text = "●  3  ПЕРЕНЕСТИ" if selected_mode == GrayboxBoard.InteractionMode.MOVE_LORD else "3  ПЕРЕНЕСТИ"

	match phase:
		Phase.PREPARATION:
			outcome_label.text = "Карта 64×128, окно 32×16. Клик по Владыке включает и выключает перенос. На паузе доступен только осмотр."
			outcome_label.add_theme_color_override("font_color", Color(0.8, 0.76, 0.83, 1))
		Phase.APPROACH:
			outcome_label.text = "Начинается серия из трёх волн: 1, 2 и 3 вторженца с 8 HP каждый."
			outcome_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.31, 1))
		Phase.ASSAULT:
			outcome_label.text = "ВТОРЖЕНИЕ\n\nПробел замораживает бой. На паузе можно только осматривать карту."
			outcome_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.31, 1))
		Phase.WON:
			outcome_label.text = "ПОБЕДА\n\nВсе шесть вторженцев уничтожены. Нажмите R, чтобы начать заново."
			outcome_label.add_theme_color_override("font_color", Color(0.34, 0.92, 0.62, 1))
		Phase.LOST:
			outcome_label.text = "ПОРАЖЕНИЕ\n\nВладыка повержен. Нажмите R и перестройте оборону."
			outcome_label.add_theme_color_override("font_color", Color(0.96, 0.35, 0.35, 1))


func _phase_title() -> String:
	match phase:
		Phase.PREPARATION:
			return "ПОДГОТОВКА"
		Phase.APPROACH:
			return "РЫЦАРЬ ИДЁТ К ПЕЩЕРЕ"
		Phase.ASSAULT:
			return "ВТОРЖЕНИЕ"
		Phase.WON:
			return "ПОБЕДА"
		Phase.LOST:
			return "ПОРАЖЕНИЕ"
	return "НЕИЗВЕСТНО"


func debug_set_invasion_seed(seed_value: int) -> void:
	invasion_seed = seed_value
	_update_route_preview()
	_refresh_ui()


func debug_set_darkness(amount: int) -> void:
	resource_points = clampi(amount, 0, DARKNESS_CAP)
	_refresh_ui()


func debug_get_darkness() -> int:
	return resource_points


func debug_generate_darkness_tick() -> void:
	_on_darkness_timer_timeout()


func debug_run_to_completion(max_steps: int = 512) -> int:
	move_timer.stop()
	combat_timer.stop()
	build_timer.stop()
	if phase == Phase.APPROACH:
		_on_knight_entered_cave()
	var steps := 0
	while phase == Phase.ASSAULT and steps < max_steps:
		if combat_cell == INVALID_CELL:
			_advance_hero()
		else:
			_resolve_combat_round()
		move_timer.stop()
		combat_timer.stop()
		steps += 1
	return phase
