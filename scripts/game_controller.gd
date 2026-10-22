extends Node3D

const ChessRulesScript = preload("res://scripts/chess_rules.gd")
const BoardFactoryScript = preload("res://scripts/board_factory.gd")
const PieceFactoryScript = preload("res://scripts/piece_factory.gd")
const GameUIScript = preload("res://scripts/game_ui.gd")
const SOUND_STREAMS := {
	"select": preload("res://assets/audio/select.wav"),
	"move": preload("res://assets/audio/move.wav"),
	"capture": preload("res://assets/audio/capture.wav"),
	"check": preload("res://assets/audio/check.wav"),
	"menu": preload("res://assets/audio/menu.wav")
}

const BOARD_PLANE_Y := 0.116
const BOARD_EXTENT := 4.0
const DRAG_THRESHOLD := 10.0

var rules
var board_root: Node3D
var pieces_root: Node3D
var highlight_root: Node3D
var camera_pivot: Node3D
var camera: Camera3D
var game_ui
var piece_nodes: Dictionary = {}
var selected_square := Vector2i(-1, -1)
var last_move: Dictionary = {}
var viewed_ply: int = 0
var match_started: bool = false
var match_finished: bool = false
var current_status: Dictionary = {}

var camera_distance: float = 12.8
var camera_pitch: float = 0.69
var camera_yaw: float = 0.0
var camera_dragging: bool = false
var last_mouse_position := Vector2.ZERO
var drag_candidate: bool = false
var dragging_piece: bool = false
var drag_node: Node3D
var drag_from := Vector2i(-1, -1)
var drag_origin := Vector3.ZERO
var pending_promotion_from := Vector2i(-1, -1)
var pending_promotion_to := Vector2i(-1, -1)
var sound_players: Dictionary = {}
var sound_volume: float = 0.75
var sound_muted: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rules = ChessRulesScript.new()
	_build_world()
	board_root = BoardFactoryScript.create_board(self)
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)
	highlight_root = Node3D.new()
	highlight_root.name = "BoardHighlights"
	add_child(highlight_root)
	_build_camera()
	_build_audio()
	_build_ui()
	_load_settings()
	rules.reset()
	current_status = rules.game_status()
	viewed_ply = 0
	_render_position(rules.get_position_at(0))
	_refresh_ui()
	game_ui.show_main_menu(false)


func _build_world() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "ChessRoomEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101720")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8794a2")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.28
	world_environment.environment = environment
	add_child(world_environment)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(180, 180)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("111720")
	floor_material.roughness = 0.78
	var floor := MeshInstance3D.new()
	floor.name = "MidnightRoomFloor"
	floor.mesh = floor_mesh
	floor.material_override = floor_material
	floor.position.y = -1.08
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor)

	var key_light := DirectionalLight3D.new()
	key_light.name = "WarmKeyLight"
	key_light.rotation_degrees = Vector3(-51, -36, 0)
	key_light.light_color = Color("ffe0b2")
	key_light.light_energy = 1.7
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 34.0
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.name = "SoftBlueFill"
	fill_light.position = Vector3(-4.3, 5.6, -3.1)
	fill_light.light_color = Color("8eafda")
	fill_light.light_energy = 0.42
	fill_light.omni_range = 18.0
	fill_light.shadow_enabled = false
	add_child(fill_light)

	var rim_light := SpotLight3D.new()
	rim_light.name = "BrassRimLight"
	rim_light.position = Vector3(0.7, 6.0, -5.0)
	rim_light.rotation_degrees = Vector3(-32, 4, 0)
	rim_light.light_color = Color("e8c98b")
	rim_light.light_energy = 1.0
	rim_light.spot_range = 18.0
	rim_light.spot_angle = 62.0
	rim_light.shadow_enabled = false
	add_child(rim_light)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "OrbitPivot"
	camera_pivot.position = Vector3(1.18, 0.0, 0.0)
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.name = "BoardCamera"
	camera.fov = 39.0
	camera.near = 0.1
	camera.far = 100.0
	camera.current = true
	camera_pivot.add_child(camera)
	_update_camera_transform()


func _build_audio() -> void:
	for sound_name in SOUND_STREAMS:
		var player := AudioStreamPlayer.new()
		player.name = "SFX_" + sound_name.capitalize()
		player.stream = SOUND_STREAMS[sound_name]
		player.bus = "Master"
		add_child(player)
		sound_players[sound_name] = player


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "InterfaceLayer"
	canvas.layer = 2
	add_child(canvas)
	game_ui = GameUIScript.new()
	game_ui.name = "GameUI"
	canvas.add_child(game_ui)
	game_ui.start_game_requested.connect(_start_match)
	game_ui.undo_requested.connect(_undo_move)
	game_ui.restart_requested.connect(_restart_match)
	game_ui.menu_requested.connect(_open_menu)
	game_ui.resume_requested.connect(_resume_match)
	game_ui.review_requested.connect(_review_after_game)
	game_ui.quit_requested.connect(func(): get_tree().quit())
	game_ui.settings_requested.connect(_set_settings)
	game_ui.promotion_requested.connect(_finish_promotion)
	game_ui.history_requested.connect(_view_history)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		sound_volume = clampf(float(config.get_value("sound", "volume", 0.75)), 0.0, 1.0)
		sound_muted = bool(config.get_value("sound", "muted", false))
	game_ui.apply_settings(sound_volume, sound_muted)
	_apply_audio_settings()


func _set_settings(volume: float, muted: bool) -> void:
	sound_volume = clampf(volume, 0.0, 1.0)
	sound_muted = muted
	_apply_audio_settings()
	var config := ConfigFile.new()
	config.set_value("sound", "volume", sound_volume)
	config.set_value("sound", "muted", sound_muted)
	config.save("user://settings.cfg")


func _apply_audio_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(sound_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, sound_muted)


func _play_sound(sound_name: String) -> void:
	if sound_muted or not sound_players.has(sound_name):
		return
	var player: AudioStreamPlayer = sound_players[sound_name]
	player.stop()
	player.play()


func _start_match() -> void:
	rules.reset()
	match_started = true
	match_finished = false
	selected_square = Vector2i(-1, -1)
	last_move.clear()
	viewed_ply = 0
	pending_promotion_from = Vector2i(-1, -1)
	pending_promotion_to = Vector2i(-1, -1)
	game_ui.show_hud()
	current_status = rules.game_status()
	_render_position(rules.get_position_at(0))
	_refresh_ui()
	_play_sound("menu")


func _restart_match() -> void:
	_start_match()


func _open_menu() -> void:
	game_ui.show_main_menu(match_started)
	selected_square = Vector2i(-1, -1)
	_clear_highlights()
	_play_sound("menu")


func _resume_match() -> void:
	game_ui.show_hud()
	viewed_ply = rules.move_history.size()
	_render_position(rules.get_position_at(viewed_ply))
	_refresh_ui()
	_play_sound("menu")


func _review_after_game() -> void:
	game_ui.show_hud()
	var current_ply: int = rules.move_history.size()
	_view_history(maxi(0, current_ply - 1))


func _undo_move() -> void:
	if not match_started or rules.move_history.is_empty():
		return
	if rules.undo():
		match_finished = false
		selected_square = Vector2i(-1, -1)
		viewed_ply = rules.move_history.size()
		current_status = rules.game_status()
		_render_position(rules.get_position_at(viewed_ply))
		_refresh_ui()
		_play_sound("menu")


func _view_history(ply: int) -> void:
	if not match_started:
		return
	var current_ply: int = rules.move_history.size()
	viewed_ply = current_ply if ply < 0 else clampi(ply, 0, current_ply)
	selected_square = Vector2i(-1, -1)
	_render_position(rules.get_position_at(viewed_ply))
	_refresh_ui()


func _finish_promotion(kind: String) -> void:
	if pending_promotion_from.x < 0:
		return
	var from_square := pending_promotion_from
	var to_square := pending_promotion_to
	pending_promotion_from = Vector2i(-1, -1)
	pending_promotion_to = Vector2i(-1, -1)
	_commit_move(from_square, to_square, kind)


func _request_move(from_square: Vector2i, to_square: Vector2i) -> void:
	if match_finished or viewed_ply != rules.move_history.size():
		return
	for move in rules.get_legal_moves_from(from_square):
		if move["to"] == to_square and move.get("promotion", false):
			pending_promotion_from = from_square
			pending_promotion_to = to_square
			game_ui.show_promotion()
			return
	_commit_move(from_square, to_square, "Q")


func _commit_move(from_square: Vector2i, to_square: Vector2i, promotion: String) -> void:
	var entry: Dictionary = rules.play_move(from_square, to_square, promotion)
	if entry.is_empty():
		return
	match_finished = rules.is_game_over()
	selected_square = Vector2i(-1, -1)
	viewed_ply = rules.move_history.size()
	last_move = entry
	current_status = rules.game_status()
	_animate_move(entry)
	_refresh_highlights()
	_refresh_ui()
	if entry["capture"]:
		_play_sound("capture")
	elif current_status["result"] in ["check", "checkmate"]:
		_play_sound("check")
	else:
		_play_sound("move")
	if match_finished:
		game_ui.show_game_over(current_status["result"], current_status.get("winner", ""))


func _animate_move(entry: Dictionary) -> void:
	var from_square: Vector2i = entry["from"]
	var to_square: Vector2i = entry["to"]
	var capture_square: Vector2i = entry["capture_square"]
	var moving_node: Node3D = piece_nodes.get(_square_key(from_square))
	var captured_node: Node3D = (
		piece_nodes.get(_square_key(capture_square)) if entry["capture"] else null
	)
	if captured_node != null and captured_node != moving_node:
		piece_nodes.erase(_square_key(capture_square))
		var capture_tween := create_tween()
		capture_tween.set_parallel(true)
		var capture_scale := capture_tween.tween_property(
			captured_node, "scale", Vector3(0.08, 0.08, 0.08), 0.22
		)
		capture_scale.set_trans(Tween.TRANS_BACK)
		capture_scale.set_ease(Tween.EASE_IN)
		var capture_drop := capture_tween.tween_property(
			captured_node, "position:y", captured_node.position.y + 0.20, 0.22
		)
		capture_drop.set_trans(Tween.TRANS_CUBIC)
		capture_drop.set_ease(Tween.EASE_IN)
		capture_tween.tween_property(
			captured_node, "rotation:y", captured_node.rotation.y + TAU, 0.22
		)
		capture_tween.finished.connect(captured_node.queue_free)

	if moving_node == null:
		_render_position(rules.get_position_at(viewed_ply))
		return
	piece_nodes.erase(_square_key(from_square))
	var destination := _world_position(to_square)
	if entry.get("promotion", "") != "":
		var owner_color: String = entry["color"]
		var promoted_node: Node3D = PieceFactoryScript.make_piece(entry["promotion"], owner_color)
		promoted_node.position = _world_position(to_square)
		promoted_node.scale = Vector3(0.42, 0.42, 0.42)
		pieces_root.add_child(promoted_node)
		piece_nodes[_square_key(to_square)] = promoted_node
		var pawn_tween := create_tween()
		var pawn_collapse := pawn_tween.tween_property(
			moving_node, "scale", Vector3(0.05, 0.05, 0.05), 0.20
		)
		pawn_collapse.set_trans(Tween.TRANS_BACK)
		pawn_collapse.set_ease(Tween.EASE_IN)
		pawn_tween.finished.connect(moving_node.queue_free)
		var crown_tween := create_tween()
		var crown_rise := crown_tween.tween_property(promoted_node, "scale", Vector3.ONE, 0.27)
		crown_rise.set_trans(Tween.TRANS_BACK)
		crown_rise.set_ease(Tween.EASE_OUT)
	else:
		piece_nodes[_square_key(to_square)] = moving_node
		var motion := create_tween()
		motion.set_trans(Tween.TRANS_CUBIC)
		motion.set_ease(Tween.EASE_OUT)
		motion.tween_property(moving_node, "position", destination + Vector3(0, 0.19, 0), 0.14)
		motion.tween_property(moving_node, "position", destination, 0.20)
		motion.parallel().tween_property(
			moving_node, "rotation:y", moving_node.rotation.y + 0.15, 0.34
		)

	if entry.get("castle", "") != "":
		var rank := 0 if entry["color"] == "w" else 7
		var rook_from := Vector2i(7, rank) if entry["castle"] == "K" else Vector2i(0, rank)
		var rook_to := Vector2i(5, rank) if entry["castle"] == "K" else Vector2i(3, rank)
		var rook_node: Node3D = piece_nodes.get(_square_key(rook_from))
		if rook_node != null:
			piece_nodes.erase(_square_key(rook_from))
			piece_nodes[_square_key(rook_to)] = rook_node
			var rook_tween := create_tween()
			rook_tween.set_trans(Tween.TRANS_CUBIC)
			rook_tween.set_ease(Tween.EASE_OUT)
			rook_tween.tween_property(
				rook_node, "position", _world_position(rook_to) + Vector3(0, 0.12, 0), 0.16
			)
			rook_tween.tween_property(rook_node, "position", _world_position(rook_to), 0.17)


func _render_position(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or not is_instance_valid(pieces_root):
		return
	for child in pieces_root.get_children():
		pieces_root.remove_child(child)
		child.queue_free()
	piece_nodes.clear()
	var position_board: Array = snapshot["board"]
	for rank in range(8):
		for file in range(8):
			var piece = position_board[rank][file]
			if piece == null:
				continue
			var model: Node3D = PieceFactoryScript.make_piece(piece["type"], piece["color"])
			model.position = _world_position(Vector2i(file, rank))
			pieces_root.add_child(model)
			piece_nodes[_square_key(Vector2i(file, rank))] = model
	_clear_highlights()
	_refresh_highlights()


func _world_position(square: Vector2i) -> Vector3:
	return Vector3(float(square.x) - 3.5, 0.108, 3.5 - float(square.y))


func _square_key(square: Vector2i) -> String:
	return "%d:%d" % [square.x, square.y]


func _refresh_ui() -> void:
	if not is_instance_valid(game_ui):
		return
	var current_ply: int = rules.move_history.size()
	viewed_ply = clampi(viewed_ply, 0, current_ply)
	var status: Dictionary = rules.status_at(viewed_ply)
	current_status = rules.game_status()
	var game_finished := false
	if match_started and viewed_ply == current_ply:
		match_finished = current_status.get("result", "playing") not in ["playing", "check"]
		game_finished = match_finished
	game_ui.update_match(status, rules.move_history, current_ply, viewed_ply)
	if game_finished and game_ui.game_over_overlay.visible == false:
		game_ui.show_game_over(current_status["result"], current_status.get("winner", ""))


func _refresh_highlights() -> void:
	if not is_instance_valid(highlight_root):
		return
	_clear_highlights()
	if viewed_ply > 0 and viewed_ply <= rules.move_history.size():
		var previous: Dictionary = rules.move_history[viewed_ply - 1]
		BoardFactoryScript.create_square_overlay(
			highlight_root, previous["from"], Color(0.78, 0.60, 0.27, 0.32), false
		)
		BoardFactoryScript.create_square_overlay(
			highlight_root, previous["to"], Color(0.78, 0.60, 0.27, 0.32), false
		)
	if viewed_ply == rules.move_history.size():
		var status: Dictionary = rules.game_status()
		if status.get("result", "") == "check":
			var king_square: Vector2i = rules.get_king_square(rules.turn)
			if king_square.x >= 0:
				BoardFactoryScript.create_square_overlay(
					highlight_root, king_square, Color(0.91, 0.24, 0.18, 0.30), false
				)
	if viewed_ply != rules.move_history.size() or selected_square.x < 0:
		return
	var current_piece := rules.get_piece(selected_square)
	if current_piece.is_empty():
		return
	BoardFactoryScript.create_square_overlay(
		highlight_root, selected_square, Color(0.23, 0.70, 0.90, 0.34), false
	)
	for move in rules.get_legal_moves_from(selected_square):
		BoardFactoryScript.create_square_overlay(
			highlight_root, move["to"], Color(0.87, 0.76, 0.52, 0.95), true
		)


func _clear_highlights() -> void:
	if not is_instance_valid(highlight_root):
		return
	for child in highlight_root.get_children():
		highlight_root.remove_child(child)
		child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(game_ui):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if game_ui.settings_overlay.visible:
				game_ui.close_settings()
			elif game_ui.game_over_overlay.visible:
				game_ui.show_hud()
			elif game_ui.menu_overlay.visible:
				if match_started:
					_resume_match()
				else:
					get_tree().quit()
			else:
				_open_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F11:
			var mode := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(
				(
					DisplayServer.WINDOW_MODE_WINDOWED
					if mode == DisplayServer.WINDOW_MODE_FULLSCREEN
					else DisplayServer.WINDOW_MODE_FULLSCREEN
				)
			)
			get_viewport().set_input_as_handled()
			return
	if game_ui.is_board_input_blocked():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			camera_dragging = event.pressed
			last_mouse_position = event.position
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clampf(camera_distance - 0.7, 9.6, 17.0)
			_update_camera_transform()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clampf(camera_distance + 0.7, 9.6, 17.0)
			_update_camera_transform()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click:
					_reset_camera()
				else:
					_handle_board_press(event.position)
			else:
				_handle_board_release(event.position)
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseMotion:
		if camera_dragging:
			camera_yaw -= event.relative.x * 0.006
			camera_pitch = clampf(camera_pitch + event.relative.y * 0.0035, 0.38, 1.13)
			_update_camera_transform()
			get_viewport().set_input_as_handled()
		elif drag_candidate and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if (
				not dragging_piece
				and event.position.distance_to(last_mouse_position) > DRAG_THRESHOLD
			):
				dragging_piece = true
			if dragging_piece and is_instance_valid(drag_node):
				var point = _screen_to_board_point(event.position)
				if point != null:
					drag_node.position = Vector3(point.x, drag_origin.y + 0.36, point.z)
			get_viewport().set_input_as_handled()


func _handle_board_press(screen_position: Vector2) -> void:
	if viewed_ply != rules.move_history.size() or match_finished:
		return
	var square := _screen_to_square(screen_position)
	if square.x < 0:
		return
	if selected_square.x >= 0 and rules.is_legal_move(selected_square, square):
		_request_move(selected_square, square)
		return
	var piece := rules.get_piece(square)
	if piece.is_empty() or piece["color"] != rules.turn:
		return
	selected_square = square
	drag_from = square
	drag_node = piece_nodes.get(_square_key(square))
	drag_origin = _world_position(square)
	drag_candidate = drag_node != null
	dragging_piece = false
	last_mouse_position = screen_position
	_refresh_highlights()
	_play_sound("select")


func _handle_board_release(screen_position: Vector2) -> void:
	if drag_candidate and dragging_piece and is_instance_valid(drag_node):
		var destination := _screen_to_square(screen_position)
		if destination.x >= 0 and rules.is_legal_move(drag_from, destination):
			_request_move(drag_from, destination)
		else:
			var return_tween := create_tween()
			var return_motion := return_tween.tween_property(
				drag_node, "position", drag_origin, 0.16
			)
			return_motion.set_trans(Tween.TRANS_CUBIC)
			return_motion.set_ease(Tween.EASE_OUT)
	drag_candidate = false
	dragging_piece = false
	drag_node = null
	drag_from = Vector2i(-1, -1)


func _screen_to_square(screen_position: Vector2) -> Vector2i:
	var point = _screen_to_board_point(screen_position)
	if point == null:
		return Vector2i(-1, -1)
	var file := floori(point.x + 4.0)
	var rank := floori(4.0 - point.z)
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return Vector2i(-1, -1)
	return Vector2i(file, rank)


func _screen_to_board_point(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return null
	var distance := (BOARD_PLANE_Y - origin.y) / direction.y
	if distance < 0.0:
		return null
	var point := origin + direction * distance
	if absf(point.x) > BOARD_EXTENT or absf(point.z) > BOARD_EXTENT:
		return null
	return point


func _update_camera_transform() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(camera_pivot):
		return
	camera_pivot.rotation.y = camera_yaw
	camera.position = Vector3(
		0, sin(camera_pitch) * camera_distance, cos(camera_pitch) * camera_distance
	)
	camera.look_at(camera_pivot.global_position, Vector3.UP)


func _reset_camera() -> void:
	camera_distance = 12.8
	camera_pitch = 0.69
	camera_yaw = 0.0
	_update_camera_transform()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_settings()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("sound", "volume", sound_volume)
	config.set_value("sound", "muted", sound_muted)
	config.save("user://settings.cfg")
