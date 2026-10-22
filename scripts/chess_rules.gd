extends RefCounted

## Rules-only chess position manager. This is deliberately not an engine: it never
## searches for a best move or evaluates positions. The rendering layer consumes
## legal moves and FEN so a future UCI engine can remain a separate component.

const FILES := "abcdefgh"
const PIECE_ORDER := ["R", "N", "B", "Q", "K", "B", "N", "R"]
const KNIGHT_STEPS := [
	Vector2i(1, 2),
	Vector2i(2, 1),
	Vector2i(2, -1),
	Vector2i(1, -2),
	Vector2i(-1, -2),
	Vector2i(-2, -1),
	Vector2i(-2, 1),
	Vector2i(-1, 2)
]
const KING_STEPS := [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1)
]
const ROOK_DIRECTIONS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const BISHOP_DIRECTIONS := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var board: Array = []
var turn: String = "w"
var en_passant_target: Vector2i = Vector2i(-1, -1)
var halfmove_clock: int = 0
var fullmove_number: int = 1
var move_history: Array[Dictionary] = []
var timeline: Array[Dictionary] = []
var repetition_counts: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	board = []
	for rank in range(8):
		var row: Array = []
		for file in range(8):
			row.append(null)
		board.append(row)

	for file in range(8):
		board[0][file] = _piece(PIECE_ORDER[file], "w", false)
		board[1][file] = _piece("P", "w", false)
		board[6][file] = _piece("P", "b", false)
		board[7][file] = _piece(PIECE_ORDER[file], "b", false)

	turn = "w"
	en_passant_target = Vector2i(-1, -1)
	halfmove_clock = 0
	fullmove_number = 1
	move_history.clear()
	repetition_counts.clear()
	var initial_key := _position_key()
	repetition_counts[initial_key] = 1
	timeline.clear()
	timeline.append(_snapshot_position())


func load_fen(fen: String) -> bool:
	var fields := fen.strip_edges().split(" ", false)
	if fields.size() < 4:
		return false
	var rows := fields[0].split("/", false)
	if rows.size() != 8:
		return false

	var parsed: Array = []
	for rank in range(8):
		var row: Array = []
		for file in range(8):
			row.append(null)
		parsed.append(row)

	for row_index in range(8):
		var file_index := 0
		for symbol in rows[row_index]:
			if symbol.is_valid_int():
				file_index += int(symbol)
				continue
			if file_index < 0 or file_index >= 8:
				return false
			var kind := symbol.to_upper()
			if not ["P", "N", "B", "R", "Q", "K"].has(kind):
				return false
			var color := "w" if symbol == kind else "b"
			parsed[7 - row_index][file_index] = _piece(kind, color, true)
			file_index += 1
		if file_index != 8:
			return false

	board = parsed
	turn = "b" if fields[1] == "b" else "w"
	en_passant_target = _parse_square(fields[3]) if fields[3] != "-" else Vector2i(-1, -1)
	halfmove_clock = int(fields[4]) if fields.size() > 4 and fields[4].is_valid_int() else 0
	fullmove_number = int(fields[5]) if fields.size() > 5 and fields[5].is_valid_int() else 1

	var rights := fields[2]
	for color in ["w", "b"]:
		var home_rank := 0 if color == "w" else 7
		var king_piece = board[home_rank][4]
		if king_piece != null and king_piece["type"] == "K" and king_piece["color"] == color:
			king_piece["moved"] = (
				not (rights.contains("K") or rights.contains("Q"))
				if color == "w"
				else not (rights.contains("k") or rights.contains("q"))
			)
		for file in [0, 7]:
			var rook_piece = board[home_rank][file]
			if rook_piece != null and rook_piece["type"] == "R" and rook_piece["color"] == color:
				var right_char := (
					("Q" if file == 0 else "K") if color == "w" else ("q" if file == 0 else "k")
				)
				rook_piece["moved"] = not rights.contains(right_char)

	move_history.clear()
	repetition_counts.clear()
	repetition_counts[_position_key()] = 1
	timeline.clear()
	timeline.append(_snapshot_position())
	return true


func get_piece(square: Vector2i) -> Dictionary:
	if not _inside(square):
		return {}
	var value = board[square.y][square.x]
	return value.duplicate(true) if value != null else {}


func get_legal_moves_from(square: Vector2i) -> Array[Dictionary]:
	if not _inside(square):
		return []
	var piece = board[square.y][square.x]
	if piece == null or piece["color"] != turn:
		return []
	return _legal_moves_for_piece(square, piece)


func get_all_legal_moves(color: String = "") -> Array[Dictionary]:
	var side := color if color == "w" or color == "b" else turn
	var result: Array[Dictionary] = []
	for rank in range(8):
		for file in range(8):
			var piece = board[rank][file]
			if piece != null and piece["color"] == side:
				result.append_array(_legal_moves_for_piece(Vector2i(file, rank), piece))
	return result


func is_legal_move(from_square: Vector2i, to_square: Vector2i) -> bool:
	for move in get_legal_moves_from(from_square):
		if move["to"] == to_square:
			return true
	return false


func play_move(from_square: Vector2i, to_square: Vector2i, promotion: String = "Q") -> Dictionary:
	var chosen: Dictionary = {}
	for candidate in get_legal_moves_from(from_square):
		if candidate["to"] == to_square:
			chosen = candidate
			break
	if chosen.is_empty():
		return {}

	var moving_piece = board[from_square.y][from_square.x].duplicate(true)
	var capture_square: Vector2i = to_square
	if chosen.get("en_passant", false):
		var direction := 1 if moving_piece["color"] == "w" else -1
		capture_square = Vector2i(to_square.x, to_square.y - direction)
	var captured_piece = board[capture_square.y][capture_square.x]
	var safe_promotion := promotion.to_upper()
	if not ["Q", "R", "B", "N"].has(safe_promotion):
		safe_promotion = "Q"
	var notation := _san_for_move(chosen, moving_piece, captured_piece != null, safe_promotion)

	_apply_position(chosen, safe_promotion)
	var key := _position_key()
	repetition_counts[key] = int(repetition_counts.get(key, 0)) + 1
	var status := game_status()
	if status["result"] == "checkmate":
		notation += "#"
	elif is_in_check(turn):
		notation += "+"

	var entry := {
		"from": from_square,
		"to": to_square,
		"piece": moving_piece["type"],
		"color": moving_piece["color"],
		"capture": captured_piece != null,
		"capture_piece": captured_piece.duplicate(true) if captured_piece != null else {},
		"capture_square": capture_square,
		"promotion": safe_promotion if chosen.get("promotion", false) else "",
		"castle": chosen.get("castle", ""),
		"notation": notation,
		"fen": to_fen()
	}
	move_history.append(entry)
	timeline.append(_snapshot_position())
	return entry


func undo() -> bool:
	if move_history.is_empty() or timeline.size() < 2:
		return false
	move_history.pop_back()
	timeline.pop_back()
	_restore_position(timeline.back())
	return true


func is_in_check(color: String) -> bool:
	var king_square := Vector2i(-1, -1)
	for rank in range(8):
		for file in range(8):
			var piece = board[rank][file]
			if piece != null and piece["color"] == color and piece["type"] == "K":
				king_square = Vector2i(file, rank)
				break
		if king_square.x >= 0:
			break
	if king_square.x < 0:
		return true
	return _is_square_attacked(king_square, _opponent(color))


func is_checkmate() -> bool:
	return is_in_check(turn) and get_all_legal_moves(turn).is_empty()


func is_stalemate() -> bool:
	return not is_in_check(turn) and get_all_legal_moves(turn).is_empty()


func game_status() -> Dictionary:
	if is_checkmate():
		return {"result": "checkmate", "winner": _opponent(turn), "turn": turn}
	if is_stalemate():
		return {"result": "stalemate", "winner": "", "turn": turn}
	if int(repetition_counts.get(_position_key(), 0)) >= 3:
		return {"result": "draw_repetition", "winner": "", "turn": turn}
	if halfmove_clock >= 100:
		return {"result": "draw_fifty_move", "winner": "", "turn": turn}
	if _is_insufficient_material():
		return {"result": "draw_material", "winner": "", "turn": turn}
	if is_in_check(turn):
		return {"result": "check", "winner": "", "turn": turn}
	return {"result": "playing", "winner": "", "turn": turn}


func is_game_over() -> bool:
	return game_status()["result"] not in ["playing", "check"]


func get_move_history() -> Array[Dictionary]:
	return move_history.duplicate(true)


func get_position_at(ply: int) -> Dictionary:
	if ply < 0 or ply >= timeline.size():
		return {}
	return timeline[ply].duplicate(true)


func status_at(ply: int) -> Dictionary:
	var snapshot := get_position_at(ply)
	if snapshot.is_empty():
		return {}
	var current := _snapshot_position()
	_restore_position(snapshot)
	var result := game_status()
	_restore_position(current)
	return result


func get_king_square(color: String) -> Vector2i:
	for rank in range(8):
		for file in range(8):
			var piece = board[rank][file]
			if piece != null and piece["type"] == "K" and piece["color"] == color:
				return Vector2i(file, rank)
	return Vector2i(-1, -1)


func to_fen() -> String:
	var placement := ""
	for rank in range(7, -1, -1):
		var empty_count := 0
		for file in range(8):
			var piece = board[rank][file]
			if piece == null:
				empty_count += 1
			else:
				if empty_count > 0:
					placement += str(empty_count)
					empty_count = 0
				placement += _fen_symbol(piece)
		if empty_count > 0:
			placement += str(empty_count)
		if rank > 0:
			placement += "/"

	var rights := ""
	for color in ["w", "b"]:
		var home_rank := 0 if color == "w" else 7
		var king_piece = board[home_rank][4]
		if (
			king_piece == null
			or king_piece["type"] != "K"
			or king_piece["color"] != color
			or king_piece["moved"]
		):
			continue
		var king_side_rook = board[home_rank][7]
		if (
			king_side_rook != null
			and king_side_rook["type"] == "R"
			and king_side_rook["color"] == color
			and not king_side_rook["moved"]
		):
			rights += "K" if color == "w" else "k"
		var queen_side_rook = board[home_rank][0]
		if (
			queen_side_rook != null
			and queen_side_rook["type"] == "R"
			and queen_side_rook["color"] == color
			and not queen_side_rook["moved"]
		):
			rights += "Q" if color == "w" else "q"
	if rights.is_empty():
		rights = "-"
	var ep := _square_name(en_passant_target) if _inside(en_passant_target) else "-"
	return "%s %s %s %s %d %d" % [placement, turn, rights, ep, halfmove_clock, fullmove_number]


func _piece(kind: String, color: String, has_moved: bool) -> Dictionary:
	return {"type": kind, "color": color, "moved": has_moved}


func _inside(square: Vector2i) -> bool:
	return square.x >= 0 and square.x < 8 and square.y >= 0 and square.y < 8


func _opponent(color: String) -> String:
	return "b" if color == "w" else "w"


func _legal_moves_for_piece(square: Vector2i, piece: Dictionary) -> Array[Dictionary]:
	var legal: Array[Dictionary] = []
	for candidate in _pseudo_moves_from(square, piece):
		var before := _snapshot_position()
		_apply_position(candidate, "Q")
		var leaves_king_safe := not is_in_check(piece["color"])
		_restore_position(before)
		if leaves_king_safe:
			legal.append(candidate)
	return legal


func _pseudo_moves_from(square: Vector2i, piece: Dictionary) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var kind: String = piece["type"]
	var color: String = piece["color"]
	var forward := 1 if color == "w" else -1

	match kind:
		"P":
			var one := Vector2i(square.x, square.y + forward)
			if _inside(one) and board[one.y][one.x] == null:
				_add_move(moves, square, one, one.y == 7 or one.y == 0)
				var start_rank := 1 if color == "w" else 6
				var two := Vector2i(square.x, square.y + 2 * forward)
				if square.y == start_rank and board[two.y][two.x] == null:
					_add_move(moves, square, two)
			for dx in [-1, 1]:
				var target := Vector2i(square.x + dx, square.y + forward)
				if not _inside(target):
					continue
				var occupant = board[target.y][target.x]
				if occupant != null and occupant["color"] != color and occupant["type"] != "K":
					_add_move(moves, square, target, target.y == 7 or target.y == 0)
				elif target == en_passant_target:
					var adjacent = board[square.y][target.x]
					if adjacent != null and adjacent["type"] == "P" and adjacent["color"] != color:
					moves.append({"from": square, "to": target, "en_passant": true})
		"N":
			for step in KNIGHT_STEPS:
				var target := square + step
				if _inside(target):
					_add_if_available(moves, square, target, color)
		"B":
			_add_sliding_moves(moves, square, color, BISHOP_DIRECTIONS)
		"R":
			_add_sliding_moves(moves, square, color, ROOK_DIRECTIONS)
		"Q":
			_add_sliding_moves(moves, square, color, ROOK_DIRECTIONS)
			_add_sliding_moves(moves, square, color, BISHOP_DIRECTIONS)
		"K":
			for step in KING_STEPS:
				var target := square + step
				if _inside(target):
					_add_if_available(moves, square, target, color)
			_add_castling_moves(moves, square, piece)
	return moves


func _add_move(
	moves: Array[Dictionary], from_square: Vector2i, to_square: Vector2i, promotion: bool = false
) -> void:
	var move := {"from": from_square, "to": to_square}
	if promotion:
		move["promotion"] = true
	moves.append(move)


func _add_if_available(
	moves: Array[Dictionary], from_square: Vector2i, to_square: Vector2i, color: String
) -> void:
	var occupant = board[to_square.y][to_square.x]
	if occupant == null:
		_add_move(moves, from_square, to_square)
	elif occupant["color"] != color and occupant["type"] != "K":
		_add_move(moves, from_square, to_square)


func _add_sliding_moves(
	moves: Array[Dictionary], from_square: Vector2i, color: String, directions: Array
) -> void:
	for direction in directions:
		var target := from_square + direction
		while _inside(target):
			var occupant = board[target.y][target.x]
			if occupant == null:
				_add_move(moves, from_square, target)
			else:
				if occupant["color"] != color and occupant["type"] != "K":
					_add_move(moves, from_square, target)
				break
			target += direction


func _add_castling_moves(moves: Array[Dictionary], square: Vector2i, king: Dictionary) -> void:
	if king["moved"] or square.x != 4 or is_in_check(king["color"]):
		return
	var rank := 0 if king["color"] == "w" else 7
	if square.y != rank:
		return
	var enemy := _opponent(king["color"])
	var king_rook = board[rank][7]
	if (
		king_rook != null
		and king_rook["type"] == "R"
		and king_rook["color"] == king["color"]
		and not king_rook["moved"]
	):
		if (
			board[rank][5] == null
			and board[rank][6] == null
			and not _is_square_attacked(Vector2i(5, rank), enemy)
			and not _is_square_attacked(Vector2i(6, rank), enemy)
		):
			moves.append({"from": square, "to": Vector2i(6, rank), "castle": "K"})
	var queen_rook = board[rank][0]
	if (
		queen_rook != null
		and queen_rook["type"] == "R"
		and queen_rook["color"] == king["color"]
		and not queen_rook["moved"]
	):
		if (
			board[rank][1] == null
			and board[rank][2] == null
			and board[rank][3] == null
			and not _is_square_attacked(Vector2i(3, rank), enemy)
			and not _is_square_attacked(Vector2i(2, rank), enemy)
		):
			moves.append({"from": square, "to": Vector2i(2, rank), "castle": "Q"})


func _is_square_attacked(square: Vector2i, by_color: String) -> bool:
	if not _inside(square):
		return false
	var pawn_origin_rank := square.y - 1 if by_color == "w" else square.y + 1
	for file_offset in [-1, 1]:
		var pawn_file := square.x + file_offset
		if pawn_file >= 0 and pawn_file < 8 and pawn_origin_rank >= 0 and pawn_origin_rank < 8:
			var pawn = board[pawn_origin_rank][pawn_file]
			if pawn != null and pawn["color"] == by_color and pawn["type"] == "P":
				return true

	for step in KNIGHT_STEPS:
		var knight_square := square + step
		if _inside(knight_square):
			var knight = board[knight_square.y][knight_square.x]
			if knight != null and knight["color"] == by_color and knight["type"] == "N":
				return true

	for step in KING_STEPS:
		var king_square := square + step
		if _inside(king_square):
			var king = board[king_square.y][king_square.x]
			if king != null and king["color"] == by_color and king["type"] == "K":
				return true

	for direction in ROOK_DIRECTIONS:
		if _ray_attacked(square, direction, by_color, ["R", "Q"]):
			return true
	for direction in BISHOP_DIRECTIONS:
		if _ray_attacked(square, direction, by_color, ["B", "Q"]):
			return true
	return false


func _ray_attacked(
	from_square: Vector2i, direction: Vector2i, by_color: String, attackers: Array
) -> bool:
	var target := from_square + direction
	while _inside(target):
		var piece = board[target.y][target.x]
		if piece != null:
			return piece["color"] == by_color and attackers.has(piece["type"])
		target += direction
	return false


func _apply_position(move: Dictionary, promotion: String) -> void:
	var from_square: Vector2i = move["from"]
	var to_square: Vector2i = move["to"]
	var moving = board[from_square.y][from_square.x].duplicate(true)
	var is_pawn_move: bool = moving["type"] == "P"
	var old_turn: String = moving["color"]
	var direction := 1 if old_turn == "w" else -1
	var capture_square := to_square
	if move.get("en_passant", false):
		capture_square = Vector2i(to_square.x, to_square.y - direction)
	var is_capture: bool = board[capture_square.y][capture_square.x] != null

	board[from_square.y][from_square.x] = null
	if move.get("en_passant", false):
		board[capture_square.y][capture_square.x] = null
	moving["moved"] = true
	if move.get("promotion", false):
		moving["type"] = promotion
	board[to_square.y][to_square.x] = moving

	if move.get("castle", "") != "":
		var rank := 0 if old_turn == "w" else 7
		var rook_from := 7 if move["castle"] == "K" else 0
		var rook_to := 5 if move["castle"] == "K" else 3
		var rook = board[rank][rook_from].duplicate(true)
		rook["moved"] = true
		board[rank][rook_from] = null
		board[rank][rook_to] = rook

	en_passant_target = Vector2i(-1, -1)
	if moving["type"] == "P" and abs(to_square.y - from_square.y) == 2:
		en_passant_target = Vector2i(from_square.x, (from_square.y + to_square.y) / 2)
	halfmove_clock = 0 if is_pawn_move or is_capture else halfmove_clock + 1
	if old_turn == "b":
		fullmove_number += 1
	turn = _opponent(old_turn)


func _snapshot_position() -> Dictionary:
	return {
		"board": board.duplicate(true),
		"turn": turn,
		"en_passant_target": en_passant_target,
		"halfmove_clock": halfmove_clock,
		"fullmove_number": fullmove_number,
		"repetition_counts": repetition_counts.duplicate(true)
	}


func _restore_position(snapshot: Dictionary) -> void:
	board = snapshot["board"].duplicate(true)
	turn = snapshot["turn"]
	en_passant_target = snapshot["en_passant_target"]
	halfmove_clock = snapshot["halfmove_clock"]
	fullmove_number = snapshot["fullmove_number"]
	repetition_counts = snapshot["repetition_counts"].duplicate(true)


func _position_key() -> String:
	var placement_key := ""
	for rank in range(7, -1, -1):
		for file in range(8):
			var piece = board[rank][file]
			placement_key += "." if piece == null else _fen_symbol(piece)
	var fen := to_fen().split(" ", false)
	var ep_key := "-"
	if _has_legal_en_passant_capture():
		ep_key = _square_name(en_passant_target)
	return "%s %s %s %s" % [placement_key, turn, fen[2], ep_key]


func _has_legal_en_passant_capture() -> bool:
	if not _inside(en_passant_target):
		return false
	var direction := 1 if turn == "w" else -1
	var pawn_rank := en_passant_target.y - direction
	for file_offset in [-1, 1]:
		var file := en_passant_target.x + file_offset
		if file < 0 or file > 7 or pawn_rank < 0 or pawn_rank > 7:
			continue
		var piece = board[pawn_rank][file]
		if piece == null or piece["type"] != "P" or piece["color"] != turn:
			continue
		var from_square := Vector2i(file, pawn_rank)
		for move in _legal_moves_for_piece(from_square, piece):
			if move.get("en_passant", false) and move["to"] == en_passant_target:
				return true
	return false


func _is_insufficient_material() -> bool:
	var minors: Array[Dictionary] = []
	for rank in range(8):
		for file in range(8):
			var piece = board[rank][file]
			if piece == null or piece["type"] == "K":
				continue
			if piece["type"] in ["P", "R", "Q"]:
				return false
			minors.append({"type": piece["type"], "square": Vector2i(file, rank)})
	if minors.size() <= 1:
		return true
	var only_bishops := true
	var bishop_color := -1
	for minor in minors:
		if minor["type"] != "B":
			only_bishops = false
			break
		var square: Vector2i = minor["square"]
		var color := (square.x + square.y) % 2
		if bishop_color < 0:
			bishop_color = color
		elif bishop_color != color:
			return false
	return only_bishops


func _san_for_move(
	move: Dictionary, piece: Dictionary, is_capture: bool, promotion: String
) -> String:
	if move.get("castle", "") == "K":
		return "O-O"
	if move.get("castle", "") == "Q":
		return "O-O-O"
	var from_square: Vector2i = move["from"]
	var to_square: Vector2i = move["to"]
	var kind: String = piece["type"]
	var text := "" if kind == "P" else kind
	if kind == "P" and is_capture:
		text += FILES.substr(from_square.x, 1)
	elif kind != "P":
		var same_type: Array[Vector2i] = []
		for rank in range(8):
			for file in range(8):
				if file == from_square.x and rank == from_square.y:
					continue
				var other = board[rank][file]
				if other == null or other["color"] != piece["color"] or other["type"] != kind:
					continue
				for alternative in _legal_moves_for_piece(Vector2i(file, rank), other):
					if alternative["to"] == to_square:
						same_type.append(Vector2i(file, rank))
						break
		if not same_type.is_empty():
			var file_unique := true
			var rank_unique := true
			for other_square in same_type:
				if other_square.x == from_square.x:
					file_unique = false
				if other_square.y == from_square.y:
					rank_unique = false
			if file_unique:
				text += FILES.substr(from_square.x, 1)
			elif rank_unique:
				text += str(from_square.y + 1)
			else:
				text += FILES.substr(from_square.x, 1) + str(from_square.y + 1)
	if is_capture:
		text += "x"
	text += _square_name(to_square)
	if move.get("promotion", false):
		text += "=" + promotion
	return text


func _square_name(square: Vector2i) -> String:
	if not _inside(square):
		return "-"
	return FILES.substr(square.x, 1) + str(square.y + 1)


func _parse_square(name: String) -> Vector2i:
	if name.length() != 2:
		return Vector2i(-1, -1)
	var file := FILES.find(name.substr(0, 1))
	var rank := int(name.substr(1, 1)) - 1
	var square := Vector2i(file, rank)
	return square if _inside(square) else Vector2i(-1, -1)


func _fen_symbol(piece: Dictionary) -> String:
	var kind: String = piece["type"]
	return kind if piece["color"] == "w" else kind.to_lower()
