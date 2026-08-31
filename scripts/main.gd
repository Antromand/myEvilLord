extends Node2D

const DEFENDER_COST := 4
const DEFENDER_REFUND := 2
const DEFENDER_MAX_HP := 3
const HERO_MAX_HP := 8
const HERO_ATTACK := 1
const DEFENDER_ATTACK := 2
const PREPARATION_SECONDS := 75
const INVALID_CELL := Vector2i(-1, -1)

enum Phase {
	PREPARATION,
	ASSAULT,
	WON,
	LOST,
}

@onready var board: GrayboxBoard = $Board
@onready var move_timer: Timer = $MoveTimer
@onready var combat_timer: Timer = $CombatTimer
@onready var build_timer: Timer = $BuildTimer

@onready var status_label: Label = $HUD/TopBar/StatusLabel
@onready var resource_label: Label = $HUD/TopBar/ResourceLabel
@onready var timer_label: Label = $HUD/TopBar/TimerLabel
@onready var hero_label: Label = $HUD/TopBar/HeroLabel
@onready var hint_label: Label = $HUD/TopBar/HintLabel
@onready var dig_button: Button = $HUD/RightPanel/DigButton
@onready var defender_button: Button = $HUD/RightPanel/DefenderButton
@onready var start_button: Button = $HUD/RightPanel/StartButton
@onready var restart_button: Button = $HUD/RightPanel/RestartButton
@onready var outcome_label: Label = $HUD/RightPanel/OutcomeLabel

var phase := Phase.PREPARATION
var resource_points := 4
var preparation_seconds := PREPARATION_SECONDS
var hero_hp := HERO_MAX_HP
var current_route: Array[Vector2i] = []
var route_index := 0
var combat_cell := INVALID_CELL
var selected_mode := GrayboxBoard.InteractionMode.DIG
var event_message := "Подготовка началась."


func _ready() -> void:
	board.cell_clicked.connect(_on_board_cell_clicked)
	board.cell_right_clicked.connect(_on_board_cell_right_clicked)
	move_timer.timeout.connect(_on_move_timer_timeout)
	combat_timer.timeout.connect(_on_combat_timer_timeout)
	build_timer.timeout.connect(_on_build_timer_timeout)
	dig_button.pressed.connect(_on_dig_button_pressed)
	defender_button.pressed.connect(_on_defender_button_pressed)
	start_button.pressed.connect(_on_start_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)

	board.reset_board()
	phase = Phase.PREPARATION
	resource_points = 4
	preparation_seconds = PREPARATION_SECONDS
	hero_hp = HERO_MAX_HP
	route_index = 0
	combat_cell = INVALID_CELL
	selected_mode = GrayboxBoard.InteractionMode.DIG
	board.set_interaction(selected_mode, true)
	board.clear_hero()
	_update_route_preview()
	build_timer.start()
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
		KEY_ENTER, KEY_KP_ENTER:
			_start_assault()
		KEY_R:
			_restart_game()


func _on_board_cell_clicked(cell: Vector2i) -> void:
	if phase != Phase.PREPARATION:
		return

	if selected_mode == GrayboxBoard.InteractionMode.DIG:
		if not board.can_dig(cell):
			event_message = "Копать можно только рядом с существующим тоннелем."
			_refresh_ui()
			return
		var reward := board.dig_cell(cell)
		resource_points += reward
		if reward > 0:
			event_message = "Найдена руда: +%d мрака." % reward
		else:
			event_message = "Новый тоннель проложен."
		_update_route_preview()
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
	if phase != Phase.PREPARATION:
		return
	if board.remove_defender(cell):
		resource_points += DEFENDER_REFUND
		event_message = "Защитник убран: возвращено %d мрака." % DEFENDER_REFUND
	else:
		event_message = "В этой клетке нет защитника."
	_refresh_ui()


func _on_dig_button_pressed() -> void:
	_set_mode(GrayboxBoard.InteractionMode.DIG)


func _on_defender_button_pressed() -> void:
	_set_mode(GrayboxBoard.InteractionMode.DEFENDER)


func _on_start_button_pressed() -> void:
	_start_assault()


func _on_restart_button_pressed() -> void:
	_restart_game()


func _set_mode(mode: int) -> void:
	if phase != Phase.PREPARATION:
		return
	if mode == GrayboxBoard.InteractionMode.DEFENDER and resource_points < DEFENDER_COST:
		event_message = "Сначала добудьте руду: защитник стоит %d мрака." % DEFENDER_COST
		_refresh_ui()
		return
	selected_mode = mode
	board.set_interaction(selected_mode, true)
	event_message = "Режим: копать." if mode == GrayboxBoard.InteractionMode.DIG else "Режим: выращивать защитников."
	_refresh_ui()


func _update_route_preview() -> void:
	current_route = board.find_path(board.entrance_cell, board.lord_cell)
	board.set_preview_path(current_route)


func _start_assault() -> void:
	if phase != Phase.PREPARATION:
		return
	_update_route_preview()
	if current_route.is_empty():
		event_message = "Герой не видит путь к Владыке. Соедините вход и логово."
		_refresh_ui()
		return

	phase = Phase.ASSAULT
	build_timer.stop()
	route_index = 0
	combat_cell = INVALID_CELL
	hero_hp = HERO_MAX_HP
	board.set_interaction(selected_mode, false)
	board.set_hero(current_route[0], hero_hp, HERO_MAX_HP)
	event_message = "Герой вошёл в подземелье и выбрал кратчайший маршрут."
	move_timer.start()
	_refresh_ui()


func _on_move_timer_timeout() -> void:
	_advance_hero()


func _advance_hero() -> void:
	if phase != Phase.ASSAULT or combat_cell != INVALID_CELL:
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
	if phase != Phase.ASSAULT or combat_cell == INVALID_CELL:
		return

	hero_hp = max(0, hero_hp - DEFENDER_ATTACK)
	var defender_hp := board.damage_defender(combat_cell, HERO_ATTACK)
	board.set_hero(combat_cell, hero_hp, HERO_MAX_HP)

	if hero_hp <= 0:
		_win_game()
		return

	if defender_hp <= 0:
		combat_timer.stop()
		event_message = "Защитник погиб, герой продолжает путь с %d HP." % hero_hp
		combat_cell = INVALID_CELL
		move_timer.start()
	else:
		event_message = "Автобой: герой %d HP, защитник %d HP." % [hero_hp, defender_hp]
	_refresh_ui()


func _win_game() -> void:
	phase = Phase.WON
	move_timer.stop()
	combat_timer.stop()
	build_timer.stop()
	board.clear_hero()
	board.set_interaction(selected_mode, false)
	event_message = "Герой уничтожен. Подземелье выстояло."
	_refresh_ui()


func _lose_game() -> void:
	phase = Phase.LOST
	move_timer.stop()
	combat_timer.stop()
	build_timer.stop()
	combat_cell = INVALID_CELL
	board.set_hero(board.lord_cell, hero_hp, HERO_MAX_HP)
	board.set_interaction(selected_mode, false)
	event_message = "Герой добрался до Владыки."
	_refresh_ui()


func _on_build_timer_timeout() -> void:
	if phase != Phase.PREPARATION:
		return
	preparation_seconds = max(0, preparation_seconds - 1)
	if preparation_seconds == 0:
		event_message = "Время подготовки закончилось."
		_start_assault()
	else:
		_refresh_ui()


func _restart_game() -> void:
	get_tree().reload_current_scene()


func _refresh_ui() -> void:
	status_label.text = "ФАЗА: %s" % _phase_title()
	resource_label.text = "МРАК: %d  •  ЗАЩИТНИК: %d" % [resource_points, DEFENDER_COST]
	timer_label.text = "ДО ВОЛНЫ: %02dс" % preparation_seconds if phase == Phase.PREPARATION else "ВТОРЖЕНИЕ"
	hero_label.text = "ГЕРОЙ: —" if phase == Phase.PREPARATION else "ГЕРОЙ: %d/%d" % [hero_hp, HERO_MAX_HP]
	hint_label.text = event_message

	dig_button.disabled = phase != Phase.PREPARATION
	defender_button.disabled = phase != Phase.PREPARATION
	start_button.disabled = phase != Phase.PREPARATION or current_route.is_empty()
	dig_button.text = "●  1  КОПАТЬ" if selected_mode == GrayboxBoard.InteractionMode.DIG else "1  КОПАТЬ"
	defender_button.text = "●  2  ЗАЩИТНИК" if selected_mode == GrayboxBoard.InteractionMode.DEFENDER else "2  ЗАЩИТНИК"

	match phase:
		Phase.PREPARATION:
			outcome_label.text = "Два защитника на жёлтом пути остановят героя. Новые тоннели могут создать опасный короткий маршрут."
			outcome_label.add_theme_color_override("font_color", Color(0.8, 0.76, 0.83, 1))
		Phase.ASSAULT:
			outcome_label.text = "ВТОРЖЕНИЕ\n\nСтроительство заблокировано. Наблюдайте за маршрутом и автобоем."
			outcome_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.31, 1))
		Phase.WON:
			outcome_label.text = "ПОБЕДА\n\nГерой уничтожен. Нажмите R, чтобы проверить другой маршрут."
			outcome_label.add_theme_color_override("font_color", Color(0.34, 0.92, 0.62, 1))
		Phase.LOST:
			outcome_label.text = "ПОРАЖЕНИЕ\n\nВладыка повержен. Нажмите R и перестройте оборону."
			outcome_label.add_theme_color_override("font_color", Color(0.96, 0.35, 0.35, 1))


func _phase_title() -> String:
	match phase:
		Phase.PREPARATION:
			return "ПОДГОТОВКА"
		Phase.ASSAULT:
			return "ВТОРЖЕНИЕ"
		Phase.WON:
			return "ПОБЕДА"
		Phase.LOST:
			return "ПОРАЖЕНИЕ"
	return "НЕИЗВЕСТНО"


func debug_run_to_completion(max_steps: int = 256) -> int:
	move_timer.stop()
	combat_timer.stop()
	build_timer.stop()
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
