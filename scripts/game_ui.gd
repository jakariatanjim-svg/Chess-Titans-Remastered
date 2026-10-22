extends Control

signal start_game_requested
signal undo_requested
signal restart_requested
signal menu_requested
signal resume_requested
signal review_requested
signal quit_requested
signal settings_requested(volume: float, muted: bool)
signal promotion_requested(piece: String)
signal history_requested(ply: int)

const INK := Color("111925")
const PANEL := Color("172231")
const PANEL_LIGHT := Color("1c2a3a")
const GOLD := Color("d8b77a")
const CREAM := Color("f1e7d1")
const MUTED := Color("9daaba")
const RED := Color("e07a66")

var menu_overlay: Control
var game_over_overlay: Control
var settings_overlay: Control
var promotion_overlay: Control
var game_hud: Control
var menu_continue_button: Button
var turn_label: Label
var status_label: Label
var white_card: PanelContainer
var black_card: PanelContainer
var white_name: Label
var black_name: Label
var white_turn_dot: Label
var black_turn_dot: Label
var move_list: VBoxContainer
var history_scroll: ScrollContainer
var history_position_label: Label
var previous_button: Button
var next_button: Button
var live_button: Button
var volume_slider: HSlider
var mute_toggle: CheckButton
var current_volume: float = 0.75
var muted: bool = false
var game_has_started: bool = false
var current_view_ply: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_game_hud()
	_build_menu_overlay()
	_build_settings_overlay()
	_build_promotion_overlay()
	_build_game_over_overlay()
	show_main_menu(false)


func show_main_menu(has_live_game: bool) -> void:
	game_has_started = has_live_game
	menu_overlay.visible = true
	game_hud.visible = false
	game_over_overlay.visible = false
	settings_overlay.visible = false
	promotion_overlay.visible = false
	menu_continue_button.visible = has_live_game


func show_hud() -> void:
	game_has_started = true
	menu_overlay.visible = false
	game_hud.visible = true
	game_over_overlay.visible = false
	settings_overlay.visible = false
	promotion_overlay.visible = false


func show_settings() -> void:
	settings_overlay.visible = true
	settings_overlay.move_to_front()


func close_settings() -> void:
	settings_overlay.visible = false


func show_promotion() -> void:
	promotion_overlay.visible = true
	promotion_overlay.move_to_front()


func show_game_over(result: String, winner: String) -> void:
	var heading: Label = game_over_overlay.get_node("Card/Content/Heading")
	var detail: Label = game_over_overlay.get_node("Card/Content/Detail")
	match result:
		"checkmate":
			heading.text = "CHECKMATE"
			detail.text = "%s wins the match." % ("White" if winner == "w" else "Black")
		"stalemate":
			heading.text = "STALEMATE"
			detail.text = "The position is drawn."
		"draw_repetition":
			heading.text = "DRAW BY REPETITION"
			detail.text = "The same position occurred three times."
		"draw_fifty_move":
			heading.text = "FIFTY-MOVE DRAW"
			detail.text = "No pawn move or capture in fifty moves."
		"draw_material":
			heading.text = "DRAW"
			detail.text = "There is not enough material to mate."
	game_over_overlay.visible = true
	game_over_overlay.move_to_front()


func is_board_input_blocked() -> bool:
	return (
		not game_hud.visible
		or menu_overlay.visible
		or settings_overlay.visible
		or promotion_overlay.visible
		or game_over_overlay.visible
	)


func apply_settings(volume: float, is_muted: bool) -> void:
	current_volume = volume
	muted = is_muted
	if is_instance_valid(volume_slider):
		volume_slider.set_value_no_signal(volume * 100.0)
	if is_instance_valid(mute_toggle):
		mute_toggle.set_pressed_no_signal(is_muted)


func update_match(
	state: Dictionary, move_history: Array, current_ply: int, viewed_ply: int
) -> void:
	if not is_instance_valid(turn_label):
		return
	current_view_ply = viewed_ply
	var side: String = state.get("turn", "w")
	var result: String = state.get("result", "playing")
	var is_reviewing := viewed_ply != current_ply
	var side_name := "White" if side == "w" else "Black"
	turn_label.text = "%s TO MOVE" % side_name.to_upper()
	if is_reviewing:
		turn_label.text = "REVIEW · MOVE %d OF %d" % [viewed_ply, current_ply]
	match result:
		"check":
			status_label.text = "%s is in check" % side_name
			status_label.add_theme_color_override("font_color", RED)
		"checkmate":
			status_label.text = "Checkmate"
			status_label.add_theme_color_override("font_color", GOLD)
		"stalemate":
			status_label.text = "Stalemate · draw"
			status_label.add_theme_color_override("font_color", MUTED)
		"draw_repetition":
			status_label.text = "Draw · repetition"
			status_label.add_theme_color_override("font_color", MUTED)
		"draw_fifty_move":
			status_label.text = "Draw · fifty-move rule"
			status_label.add_theme_color_override("font_color", MUTED)
		"draw_material":
			status_label.text = "Draw · insufficient material"
			status_label.add_theme_color_override("font_color", MUTED)
		_:
			status_label.text = "Local two-player match"
			status_label.add_theme_color_override("font_color", MUTED)
	white_turn_dot.modulate = GOLD if side == "w" and not is_reviewing else Color("566171")
	black_turn_dot.modulate = GOLD if side == "b" and not is_reviewing else Color("566171")
	white_card.add_theme_stylebox_override(
		"panel",
		_panel_style(
			Color("243142") if side == "w" and not is_reviewing else PANEL,
			side == "w" and not is_reviewing
		)
	)
	black_card.add_theme_stylebox_override(
		"panel",
		_panel_style(
			Color("243142") if side == "b" and not is_reviewing else PANEL,
			side == "b" and not is_reviewing
		)
	)
	white_name.add_theme_color_override(
		"font_color", CREAM if side == "w" and not is_reviewing else MUTED
	)
	black_name.add_theme_color_override(
		"font_color", CREAM if side == "b" and not is_reviewing else MUTED
	)
	_update_move_list(move_history, viewed_ply)
	history_position_label.text = (
		"LIVE POSITION" if not is_reviewing else "POSITION %d / %d" % [viewed_ply, current_ply]
	)
	previous_button.disabled = viewed_ply <= 0
	next_button.disabled = viewed_ply >= current_ply
	live_button.disabled = not is_reviewing


func _build_game_hud() -> void:
	game_hud = Control.new()
	game_hud.name = "GameHUD"
	game_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_hud)

	var brand := PanelContainer.new()
	brand.name = "BrandBar"
	brand.anchor_left = 0.025
	brand.anchor_top = 0.025
	brand.anchor_right = 0.355
	brand.anchor_bottom = 0.105
	brand.add_theme_stylebox_override("panel", _panel_style(INK, false))
	game_hud.add_child(brand)
	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 14)
	brand.add_child(brand_row)
	var crest := Label.new()
	crest.text = "♔"
	crest.add_theme_color_override("font_color", GOLD)
	crest.add_theme_font_size_override("font_size", 32)
	crest.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand_row.add_child(crest)
	var brand_text := VBoxContainer.new()
	brand_text.add_theme_constant_override("separation", 0)
	brand_row.add_child(brand_text)
	var brand_title := Label.new()
	brand_title.text = "CHESS TITANS"
	brand_title.add_theme_color_override("font_color", CREAM)
	brand_title.add_theme_font_size_override("font_size", 20)
	brand_text.add_child(brand_title)
	var brand_subtitle := Label.new()
	brand_subtitle.text = "REMASTERED  ·  LOCAL MATCH"
	brand_subtitle.add_theme_color_override("font_color", GOLD)
	brand_subtitle.add_theme_font_size_override("font_size", 10)
	brand_text.add_child(brand_subtitle)

	var turn_panel := PanelContainer.new()
	turn_panel.name = "TurnBar"
	turn_panel.anchor_left = 0.365
	turn_panel.anchor_top = 0.030
	turn_panel.anchor_right = 0.645
	turn_panel.anchor_bottom = 0.098
	turn_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, true))
	game_hud.add_child(turn_panel)
	var turn_content := VBoxContainer.new()
	turn_content.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_content.add_theme_constant_override("separation", 1)
	turn_panel.add_child(turn_content)
	turn_label = Label.new()
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.add_theme_color_override("font_color", GOLD)
	turn_label.add_theme_font_size_override("font_size", 17)
	turn_content.add_child(turn_label)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", MUTED)
	status_label.add_theme_font_size_override("font_size", 11)
	turn_content.add_child(status_label)

	var settings_button := _button("⚙", false, 52)
	settings_button.tooltip_text = "Settings"
	settings_button.anchor_left = 0.665
	settings_button.anchor_top = 0.028
	settings_button.anchor_right = 0.710
	settings_button.anchor_bottom = 0.095
	settings_button.pressed.connect(show_settings)
	game_hud.add_child(settings_button)

	var menu_button := _button("MENU", false, 52)
	menu_button.anchor_left = 0.895
	menu_button.anchor_top = 0.028
	menu_button.anchor_right = 0.975
	menu_button.anchor_bottom = 0.095
	menu_button.pressed.connect(func(): menu_requested.emit())
	game_hud.add_child(menu_button)

	var side := PanelContainer.new()
	side.name = "MatchPanel"
	side.anchor_left = 0.735
	side.anchor_top = 0.135
	side.anchor_right = 0.975
	side.anchor_bottom = 0.965
	side.add_theme_stylebox_override("panel", _panel_style(INK, false))
	game_hud.add_child(side)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	side.add_child(content)

	var section_header := HBoxContainer.new()
	content.add_child(section_header)
	var live_dot := Label.new()
	live_dot.text = "●"
	live_dot.add_theme_color_override("font_color", Color("8fae91"))
	live_dot.add_theme_font_size_override("font_size", 10)
	section_header.add_child(live_dot)
	var section_title := Label.new()
	section_title.text = "LIVE MATCH"
	section_title.add_theme_color_override("font_color", GOLD)
	section_title.add_theme_font_size_override("font_size", 12)
	section_header.add_child(section_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_header.add_child(spacer)
	var version_label := Label.new()
	version_label.text = "v" + _read_version()
	version_label.add_theme_color_override("font_color", MUTED)
	version_label.add_theme_font_size_override("font_size", 10)
	section_header.add_child(version_label)

	white_card = _player_card("WHITE", "Ivory pieces", "♔", true)
	content.add_child(white_card)
	white_name = white_card.get_node("Content/Row/Name")
	white_turn_dot = white_card.get_node("Content/Row/TurnDot")
	black_card = _player_card("BLACK", "Onyx pieces", "♚", false)
	content.add_child(black_card)
	black_name = black_card.get_node("Content/Row/Name")
	black_turn_dot = black_card.get_node("Content/Row/TurnDot")

	var history_header := HBoxContainer.new()
	content.add_child(history_header)
	var history_title := Label.new()
	history_title.text = "MOVE HISTORY"
	history_title.add_theme_color_override("font_color", CREAM)
	history_title.add_theme_font_size_override("font_size", 12)
	history_header.add_child(history_title)
	var history_spacer := Control.new()
	history_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_header.add_child(history_spacer)
	history_position_label = Label.new()
	history_position_label.add_theme_color_override("font_color", MUTED)
	history_position_label.add_theme_font_size_override("font_size", 9)
	history_header.add_child(history_position_label)

	history_scroll = ScrollContainer.new()
	history_scroll.name = "HistoryScroll"
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(history_scroll)
	move_list = VBoxContainer.new()
	move_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_list.add_theme_constant_override("separation", 3)
	history_scroll.add_child(move_list)

	var history_nav := HBoxContainer.new()
	history_nav.add_theme_constant_override("separation", 6)
	content.add_child(history_nav)
	previous_button = _small_button("‹", "Previous move")
	previous_button.pressed.connect(func(): history_requested.emit(maxi(0, current_view_ply - 1)))
	history_nav.add_child(previous_button)
	next_button = _small_button("›", "Next move")
	next_button.pressed.connect(func(): history_requested.emit(current_view_ply + 1))
	history_nav.add_child(next_button)
	live_button = _small_button("LIVE", "Return to the current position")
	live_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_button.pressed.connect(func(): history_requested.emit(-1))
	history_nav.add_child(live_button)

	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color("3b4656"))
	content.add_child(separator)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	content.add_child(action_row)
	var undo_button := _button("UNDO", false, 44)
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_button.pressed.connect(func(): undo_requested.emit())
	action_row.add_child(undo_button)
	var restart_button := _button("RESTART", false, 44)
	restart_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart_button.pressed.connect(_confirm_restart)
	action_row.add_child(restart_button)

	var helper := Label.new()
	helper.text = "Drag a piece or select it, then choose a destination.\nRight-drag to orbit · scroll to zoom."
	helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	helper.add_theme_color_override("font_color", MUTED)
	helper.add_theme_font_size_override("font_size", 10)
	content.add_child(helper)


func _player_card(
	title: String, subtitle: String, symbol: String, is_white: bool
) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "WhitePlayer" if is_white else "BlackPlayer"
	card.add_theme_stylebox_override("panel", _panel_style(PANEL, false))
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 3)
	card.add_child(content)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var emblem := Label.new()
	emblem.text = symbol
	emblem.add_theme_color_override("font_color", GOLD if is_white else Color("a9b4c2"))
	emblem.add_theme_font_size_override("font_size", 23)
	row.add_child(emblem)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 0)
	row.add_child(labels)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = title
	name_label.add_theme_color_override("font_color", CREAM)
	name_label.add_theme_font_size_override("font_size", 12)
	labels.add_child(name_label)
	var detail := Label.new()
	detail.text = subtitle
	detail.add_theme_color_override("font_color", MUTED)
	detail.add_theme_font_size_override("font_size", 10)
	labels.add_child(detail)
	var dot := Label.new()
	dot.name = "TurnDot"
	dot.text = "●"
	dot.add_theme_color_override("font_color", MUTED)
	dot.add_theme_font_size_override("font_size", 11)
	row.add_child(dot)
	return card


func _build_menu_overlay() -> void:
	menu_overlay = _overlay("MainMenu")
	add_child(menu_overlay)
	var shade := _shade()
	menu_overlay.add_child(shade)
	var card := PanelContainer.new()
	card.name = "MenuCard"
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -250
	card.offset_right = 250
	card.offset_top = -264
	card.offset_bottom = 264
	card.add_theme_stylebox_override("panel", _panel_style(INK, true, 0.97))
	menu_overlay.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)
	var sigil := Label.new()
	sigil.text = "♔"
	sigil.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sigil.add_theme_color_override("font_color", GOLD)
	sigil.add_theme_font_size_override("font_size", 46)
	content.add_child(sigil)
	var title := Label.new()
	title.text = "CHESS TITANS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", CREAM)
	title.add_theme_font_size_override("font_size", 34)
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "REMASTERED"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", GOLD)
	subtitle.add_theme_font_size_override("font_size", 13)
	content.add_child(subtitle)
	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", Color("7d6443"))
	content.add_child(divider)
	var line := Label.new()
	line.text = "The timeless game, polished for a new generation."
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_color_override("font_color", MUTED)
	line.add_theme_font_size_override("font_size", 13)
	content.add_child(line)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 5
	content.add_child(spacer)
	var start_button := _button("NEW LOCAL GAME", true, 54)
	start_button.pressed.connect(func(): start_game_requested.emit())
	content.add_child(start_button)
	menu_continue_button = _button("RESUME MATCH", false, 48)
	menu_continue_button.pressed.connect(func(): resume_requested.emit())
	content.add_child(menu_continue_button)
	var settings_button := _button("SETTINGS", false, 44)
	settings_button.pressed.connect(show_settings)
	content.add_child(settings_button)
	var quit_button := _button("EXIT GAME", false, 42)
	quit_button.pressed.connect(func(): quit_requested.emit())
	content.add_child(quit_button)
	var footer := Label.new()
	footer.text = "TWO PLAYERS · ONE BOARD · NO ENGINE"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", MUTED)
	footer.add_theme_font_size_override("font_size", 9)
	content.add_child(footer)


func _build_settings_overlay() -> void:
	settings_overlay = _overlay("Settings")
	settings_overlay.visible = false
	add_child(settings_overlay)
	var shade := _shade()
	settings_overlay.add_child(shade)
	var card := PanelContainer.new()
	card.name = "SettingsCard"
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -220
	card.offset_right = 220
	card.offset_top = -190
	card.offset_bottom = 190
	card.add_theme_stylebox_override("panel", _panel_style(INK, true, 0.98))
	settings_overlay.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	card.add_child(content)
	var heading := Label.new()
	heading.text = "SETTINGS"
	heading.add_theme_color_override("font_color", GOLD)
	heading.add_theme_font_size_override("font_size", 22)
	content.add_child(heading)
	var camera_note := Label.new()
	camera_note.text = "CAMERA"
	camera_note.add_theme_color_override("font_color", MUTED)
	camera_note.add_theme_font_size_override("font_size", 11)
	content.add_child(camera_note)
	var camera_help := Label.new()
	camera_help.text = "Right mouse drag to orbit · scroll to zoom\nDouble-click the board to restore the view."
	camera_help.add_theme_color_override("font_color", CREAM)
	camera_help.add_theme_font_size_override("font_size", 12)
	camera_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(camera_help)
	var sound_header := Label.new()
	sound_header.text = "SOUND"
	sound_header.add_theme_color_override("font_color", MUTED)
	sound_header.add_theme_font_size_override("font_size", 11)
	content.add_child(sound_header)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.value = current_volume * 100
	volume_slider.value_changed.connect(_on_volume_changed)
	content.add_child(volume_slider)
	mute_toggle = CheckButton.new()
	mute_toggle.text = "Mute sound"
	mute_toggle.button_pressed = muted
	mute_toggle.toggled.connect(_on_mute_toggled)
	content.add_child(mute_toggle)
	var close_button := _button("DONE", true, 46)
	close_button.pressed.connect(close_settings)
	content.add_child(close_button)


func _build_promotion_overlay() -> void:
	promotion_overlay = _overlay("PromotionPicker")
	promotion_overlay.visible = false
	add_child(promotion_overlay)
	var shade := _shade()
	promotion_overlay.add_child(shade)
	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -245
	card.offset_right = 245
	card.offset_top = -125
	card.offset_bottom = 125
	card.add_theme_stylebox_override("panel", _panel_style(INK, true, 0.98))
	promotion_overlay.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	card.add_child(content)
	var heading := Label.new()
	heading.text = "PROMOTE YOUR PAWN"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", GOLD)
	heading.add_theme_font_size_override("font_size", 17)
	content.add_child(heading)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 8)
	content.add_child(choices)
	for choice in ["Q", "R", "B", "N"]:
		var promotion_choice: String = choice
		var label := {"Q": "QUEEN", "R": "ROOK", "B": "BISHOP", "N": "KNIGHT"}[promotion_choice]
		var button := _button(label, promotion_choice == "Q", 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_promotion_button.bind(promotion_choice))
		choices.add_child(button)


func _build_game_over_overlay() -> void:
	game_over_overlay = _overlay("GameOver")
	game_over_overlay.visible = false
	add_child(game_over_overlay)
	var shade := _shade()
	game_over_overlay.add_child(shade)
	var card := PanelContainer.new()
	card.name = "Card"
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -235
	card.offset_right = 235
	card.offset_top = -170
	card.offset_bottom = 170
	card.add_theme_stylebox_override("panel", _panel_style(INK, true, 0.98))
	game_over_overlay.add_child(card)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 15)
	card.add_child(content)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "CHECKMATE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", GOLD)
	heading.add_theme_font_size_override("font_size", 26)
	content.add_child(heading)
	var detail := Label.new()
	detail.name = "Detail"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_color_override("font_color", CREAM)
	detail.add_theme_font_size_override("font_size", 14)
	content.add_child(detail)
	var review_button := _button("REVIEW MOVES", false, 44)
	review_button.pressed.connect(func(): review_requested.emit())
	content.add_child(review_button)
	var new_button := _button("NEW LOCAL GAME", true, 48)
	new_button.pressed.connect(func(): start_game_requested.emit())
	content.add_child(new_button)
	var menu_button := _button("MAIN MENU", false, 44)
	menu_button.pressed.connect(func(): menu_requested.emit())
	content.add_child(menu_button)


func _update_move_list(move_history: Array, viewed_ply: int) -> void:
	for child in move_list.get_children():
		child.queue_free()
	if move_history.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Your first move will appear here."
		empty_label.add_theme_color_override("font_color", MUTED)
		empty_label.add_theme_font_size_override("font_size", 11)
		move_list.add_child(empty_label)
		return
	for pair_start in range(0, move_history.size(), 2):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		move_list.add_child(row)
		var number := Label.new()
		number.text = "%02d" % (int(pair_start / 2) + 1)
		number.custom_minimum_size.x = 30
		number.add_theme_color_override("font_color", MUTED)
		number.add_theme_font_size_override("font_size", 10)
		row.add_child(number)
		for offset in range(2):
			var index := pair_start + offset
			if index >= move_history.size():
				break
			var move: Dictionary = move_history[index]
			var ply := index + 1
			var button := _history_button(str(move.get("notation", "—")), ply == viewed_ply)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_on_history_button_pressed.bind(ply))
			row.add_child(button)


func _on_history_button_pressed(ply: int) -> void:
	history_requested.emit(ply)


func _on_promotion_button(piece: String) -> void:
	promotion_overlay.visible = false
	promotion_requested.emit(piece)


func _history_button(text_value: String, selected: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 30)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", GOLD if selected else CREAM)
	button.add_theme_stylebox_override(
		"normal", _button_style(Color("233143") if selected else Color("182331"), 6)
	)
	button.add_theme_stylebox_override("hover", _button_style(Color("304155"), 6))
	button.add_theme_stylebox_override("pressed", _button_style(Color("394a5d"), 6))
	return button


func _button(text_value: String, primary: bool, height: float) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, height)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 12 if not primary else 13)
	button.add_theme_color_override("font_color", INK if primary else CREAM)
	button.add_theme_color_override("font_hover_color", INK if primary else GOLD)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_stylebox_override("normal", _button_style(GOLD if primary else PANEL_LIGHT, 9))
	button.add_theme_stylebox_override(
		"hover", _button_style(Color("ebcf9c") if primary else Color("27374b"), 9)
	)
	button.add_theme_stylebox_override(
		"pressed", _button_style(Color("c9a96e") if primary else Color("33445a"), 9)
	)
	return button


func _small_button(text_value: String, help: String) -> Button:
	var button := _button(text_value, false, 34)
	button.tooltip_text = help
	button.add_theme_font_size_override("font_size", 14)
	return button


func _confirm_restart() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Restart match"
	dialog.dialog_text = "Start a new local game? The current match will be cleared."
	dialog.ok_button_text = "RESTART"
	dialog.confirmed.connect(func(): restart_requested.emit())
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(390, 160))


func _on_volume_changed(value: float) -> void:
	current_volume = value / 100.0
	settings_requested.emit(current_volume, muted)


func _on_mute_toggled(value: bool) -> void:
	muted = value
	settings_requested.emit(current_volume, muted)


func _overlay(object_name: String) -> Control:
	var root := Control.new()
	root.name = object_name
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	return root


func _shade() -> ColorRect:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.018, 0.025, 0.039, 0.74)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	return shade


func _panel_style(color: Color, accent: bool, alpha: float = 1.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, alpha)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.border_width_left = 1 if accent else 0
	style.border_width_top = 1 if accent else 0
	style.border_width_right = 1 if accent else 0
	style.border_width_bottom = 1 if accent else 0
	style.border_color = Color(0.73, 0.58, 0.34, 0.62)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style


func _button_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _read_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "1.0-dev"))
