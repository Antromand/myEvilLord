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
var pending_lord_dig_cost := 0


func _ready() -> void:
	board.cell_clicked.connect(_on_board_cell_clicked)
	board.cell_right_clicked.connect(_on_board_cell_right_clicked)
	board.knight_entered_cave.connect(_on_knight_entered_cave)
	board.lord_cell_changed.connect(_on_lord_cell_changed)
	board.lord_action_finished.connect(_on_lord_action_finished)
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
	pending_lord_dig_cost = 0
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
	if not _can_control_lord() and not _can_build():
		return

	if selected_mode == GrayboxBoard.InteractionMode.DEFENDER:
		if not _can_build():
			event_message = "Защитников можно выращивать только в фазе строительства."
			_refresh_ui()
			return
		if resource_points < DEFENDER_COST:
			event_message = "Недостаточно мрака: нужен ещё %d." % (DEFENDER_COST - resource_points)
			_refresh_ui()
			return
		if board.place_defender(cell, DEFENDER_MAX_HP):
			resource_points -= DEFENDER_COST
			event_message = "Защитник выращен. Проверьте, проходит ли здесь жёлтый маршрут."
			_update_route_preview()
		else:
			event_message = "Защитника можно поставить только в свободном тоннеле."
		_refresh_ui()
		return

	_command_lord(cell)


func _command_lord(cell: Vector2i) -> void:
	if not _can_control_lord():
		return
	if board.is_lord_action_active():
		event_message = "Владыка уже выполняет приказ."
		_refresh_ui()
		return
	if phase == Phase.ASSAULT and board.is_behind_hero(cell):
		event_message = "Владыка не может переместиться за вторженца."
		_refresh_ui()
		return
	var needs_dig := board.lord_action_requires_dig(cell)
	if needs_dig and resource_points < DIG_COST:
		event_message = "Недостаточно мрака для копания."
		_refresh_ui()
		return
	var blocked_cell := board.hero_cell if phase == Phase.ASSAULT else INVALID_CELL
	if not board.begin_lord_action(cell, blocked_cell):
		event_message = "Владыка не может добраться сюда: путь занят или клетка недоступна."
		_refresh_ui()
		return
	pending_lord_dig_cost = DIG_COST if needs_dig else 0
	resource_points -= pending_lord_dig_cost
	event_message = "Владыка идёт копать отмеченный блок." if needs_dig else "Владыка идёт в указанное место."
	_refresh_ui()


func _on_lord_cell_changed() -> void:
	if phase == Phase.ASSAULT:
		_rebuild_active_route()
	else:
		_update_route_preview()


func _on_lord_action_finished(success: bool, did_dig: bool, reward: int) -> void:
	if not success:
		if did_dig:
			_add_darkness(reward)
			event_message = "Владыка успел выкопать блок, но остановился перед вторженцем."
		else:
			_add_darkness(pending_lord_dig_cost)
			event_message = "Путь перекрыт вторженцем — Владыка остановился."
	elif did_dig:
		var gained := _add_darkness(reward)
		event_message = "Владыка закончил копать. Получено %d мрака." % gained if reward > 0 else "Владыка закончил копать."
	else:
		event_message = "Владыка прибыл на место."
	pending_lord_dig_cost = 0
	if phase == Phase.ASSAULT:
		_rebuild_active_route()
	else:
		_update_route_preview()
	_refresh_ui()


func _on_board_cell_right_clicked(cell: Vector2i) -> void:
	if not _can_build():
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
	if game_paused or phase == Phase.WON or phase == Phase.LOST:
		return
	if mode == GrayboxBoard.InteractionMode.DEFENDER and not _can_build():
		event_message = "Защитники доступны только в фазе строительства."
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
			event_message = "Режим Владыки: клик задаёт путь или блок для копания."
		GrayboxBoard.InteractionMode.DEFENDER:
			event_message = "Режим: выращивать защитников."
		GrayboxBoard.InteractionMode.MOVE_LORD:
			event_message = "Режим Владыки: клик задаёт путь или блок для копания."
	_refresh_ui()


func _can_build() -> bool:
	return phase == Phase.PREPARATION and not game_paused


func _can_control_lord() -> bool:
	return (phase == Phase.PREPARATION or phase == Phase.APPROACH or phase == Phase.ASSAULT) \
		and not game_paused


func _update_route_preview() -> void:
	current_route = board.build_wandering_route(
		board.entrance_cell,
		board.lord_cell,
		invasion_seed
	)
	board.set_preview_path(current_route)


func _rebuild_active_route() -> void:
	if phase != Phase.ASSAULT or board.hero_cell == INVALID_CELL:
		return
	current_route = board.build_wandering_route(
		board.hero_cell,
		board.lord_cell,
		invasion_seed + defeated_attackers
	)
	route_index = 0
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
	attackers_left_in_wave = current_wave
	attacker_number_in_wave = 0
	if selected_mode == GrayboxBoard.InteractionMode.DEFENDER:
		selected_mode = GrayboxBoard.InteractionMode.DIG
	board.set_interaction(selected_mode, true)
	board.set_surface_motion_paused(false)
	board.set_invasion_active(true)
	board.clear_hero()
	event_message = "Волна %d/3 началась: к пещере идут %d героев." % [current_wave, current_wave]
	_refresh_ui()


func _on_knight_entered_cave() -> void:
	if phase != Phase.APPROACH:
		return
	phase = Phase.ASSAULT
	_spawn_next_attacker()
	_refresh_ui()


func _spawn_next_attacker() -> void:
	_update_route_preview()
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
		board.set_interaction(selected_mode, _can_control_lord())
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
		if board.hero_cell == board.lord_cell:
			_lose_game()
		else:
			_rebuild_active_route()
			if current_route.size() > 1:
				move_timer.start()
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
		_begin_next_preparation()
		return
	_win_game()


func _begin_next_preparation() -> void:
	current_wave += 1
	phase = Phase.PREPARATION
	preparation_seconds = PREPARATION_SECONDS
	attackers_left_in_wave = current_wave
	attacker_number_in_wave = 0
	board.set_invasion_active(false)
	board.clear_hero()
	board.set_interaction(selected_mode, true)
	build_timer.start()
	darkness_timer.start()
	_update_route_preview()
	event_message = "Волна отбита. Фаза строительства перед волной %d/3." % current_wave
	_refresh_ui()


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
		timer_label.text = "ДО ВОЛНЫ %d: %02dс" % [current_wave, preparation_seconds]
	elif phase == Phase.APPROACH:
		timer_label.text = "ПОДХОД"
	else:
		timer_label.text = "ВТОРЖЕНИЕ"
	if phase == Phase.PREPARATION or phase == Phase.APPROACH:
		hero_label.text = "ВОЛНА %d/3 • ГЕРОЕВ %d" % [current_wave, current_wave]
	else:
		hero_label.text = "ВОЛНА %d/3 • ВРАГ %d/%d • HP %d/%d" % [
			current_wave,
			attacker_number_in_wave,
			current_wave,
			hero_hp,
			HERO_MAX_HP,
		]
	hint_label.text = event_message

	var can_control := _can_control_lord()
	dig_button.disabled = not can_control
	defender_button.disabled = not _can_build()
	move_lord_button.disabled = not can_control
	start_button.disabled = phase != Phase.PREPARATION or current_route.is_empty()
	start_button.text = "НАЧАТЬ ВОЛНУ %d" % current_wave
	pause_button.disabled = phase == Phase.WON or phase == Phase.LOST
	pause_button.text = "▶  ПРОДОЛЖИТЬ" if game_paused else "Ⅱ  ПАУЗА"
	dig_button.text = "●  1  КОПАТЬ" if selected_mode == GrayboxBoard.InteractionMode.DIG else "1  КОПАТЬ"
	defender_button.text = "●  2  ЗАЩИТНИК" if selected_mode == GrayboxBoard.InteractionMode.DEFENDER else "2  ЗАЩИТНИК"
	move_lord_button.text = "●  3  ВЛАДЫКА" if selected_mode == GrayboxBoard.InteractionMode.MOVE_LORD else "3  ВЛАДЫКА"

	match phase:
		Phase.PREPARATION:
			outcome_label.text = "СТРОИТЕЛЬСТВО %d/3\n\nКликните в тоннель — Владыка пойдёт туда. Кликните в землю — сам дойдёт и выкопает блок." % current_wave
			outcome_label.add_theme_color_override("font_color", Color(0.8, 0.76, 0.83, 1))
		Phase.APPROACH:
			outcome_label.text = "АТАКА %d/3\n\nВ этой волне %d героев. Владыка может двигаться и копать." % [current_wave, current_wave]
			outcome_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.31, 1))
		Phase.ASSAULT:
			outcome_label.text = "АТАКА %d/3\n\nВладыка может двигаться и копать, но не может пройти за вторженца." % current_wave
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
			return "СТРОИТЕЛЬСТВО"
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
	var steps := 0
	while phase != Phase.WON and phase != Phase.LOST and steps < max_steps:
		if phase == Phase.PREPARATION:
			_start_assault()
		if phase == Phase.APPROACH:
			_on_knight_entered_cave()
		elif phase == Phase.ASSAULT:
			if combat_cell == INVALID_CELL:
				_advance_hero()
			else:
				_resolve_combat_round()
		move_timer.stop()
		combat_timer.stop()
		steps += 1
	return phase


func debug_run_current_wave(max_steps: int = 256) -> int:
	move_timer.stop()
	combat_timer.stop()
	build_timer.stop()
	if phase == Phase.APPROACH:
		_on_knight_entered_cave()
	var starting_wave := current_wave
	var steps := 0
	while phase == Phase.ASSAULT and current_wave == starting_wave and steps < max_steps:
		if combat_cell == INVALID_CELL:
			_advance_hero()
		else:
			_resolve_combat_round()
		move_timer.stop()
		combat_timer.stop()
		steps += 1
	return phase
