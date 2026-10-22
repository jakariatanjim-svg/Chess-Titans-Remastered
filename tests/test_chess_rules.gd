extends SceneTree

const RulesScript = preload("res://scripts/chess_rules.gd")
var failures: int = 0


func _initialize() -> void:
	_test_initial_position()
	_test_legal_moves_and_undo()
	_test_castling()
	_test_pins_and_attacked_castle_squares()
	_test_en_passant()
	_test_promotion()
	_test_checkmate()
	_test_stalemate()
	_test_draw_rules()
	if failures == 0:
		print("PASS: all chess-rules regression checks")
		quit(0)
	else:
		push_error("FAIL: %d chess-rules regression check(s)" % failures)
		quit(1)


func _test_initial_position() -> void:
	var rules = RulesScript.new()
	_expect(
		rules.to_fen() == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "initial FEN"
	)
	_expect(rules.get_all_legal_moves("w").size() == 20, "20 legal white opening moves")
	_expect(rules.get_all_legal_moves("b").size() == 20, "20 legal black opening moves")
	_expect(
		rules.is_legal_move(Vector2i(4, 1), Vector2i(4, 3)), "white e-pawn may advance two squares"
	)
	_expect(
		not rules.is_legal_move(Vector2i(4, 1), Vector2i(4, 4)), "pawn cannot jump three squares"
	)


func _test_legal_moves_and_undo() -> void:
	var rules = RulesScript.new()
	var first = rules.play_move(Vector2i(4, 1), Vector2i(4, 3))
	_expect(first.get("notation", "") == "e4", "pawn algebraic notation")
	_expect(rules.turn == "b", "turn advances after a move")
	_expect(
		rules.to_fen() == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
		"en-passant square in FEN"
	)
	_expect(rules.undo(), "undo is available after a move")
	_expect(
		rules.to_fen() == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"undo restores the complete opening position"
	)


func _test_castling() -> void:
	var rules = RulesScript.new()
	_expect(rules.load_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"), "load castling test position")
	_expect(rules.is_legal_move(Vector2i(4, 0), Vector2i(6, 0)), "king-side castle is legal")
	_expect(rules.is_legal_move(Vector2i(4, 0), Vector2i(2, 0)), "queen-side castle is legal")
	var castle = rules.play_move(Vector2i(4, 0), Vector2i(6, 0))
	_expect(castle.get("notation", "") == "O-O", "king-side castle notation")
	_expect(rules.get_piece(Vector2i(6, 0)).get("type", "") == "K", "king reaches g1")
	_expect(rules.get_piece(Vector2i(5, 0)).get("type", "") == "R", "rook crosses to f1")
	_expect(
		not rules.to_fen().split(" ", false)[2].contains("K"),
		"white king-side castling right is removed"
	)


func _test_pins_and_attacked_castle_squares() -> void:
	var pinned = RulesScript.new()
	_expect(pinned.load_fen("k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1"), "load pinned-piece position")
	_expect(
		not pinned.is_legal_move(Vector2i(4, 1), Vector2i(3, 1)),
		"pinned rook cannot expose its king"
	)

	var castle = RulesScript.new()
	_expect(
		castle.load_fen("r3kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1"), "load attacked castling position"
	)
	_expect(
		not castle.is_legal_move(Vector2i(4, 0), Vector2i(6, 0)),
		"king cannot castle through an attacked f1 square"
	)


func _test_en_passant() -> void:
	var rules = RulesScript.new()
	_expect(rules.load_fen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1"), "load en-passant test position")
	_expect(
		rules.is_legal_move(Vector2i(4, 4), Vector2i(3, 5)),
		"en passant is legal on the immediately following ply"
	)
	var capture = rules.play_move(Vector2i(4, 4), Vector2i(3, 5))
	_expect(capture.get("capture", false), "en passant is recorded as a capture")
	_expect(
		capture.get("capture_square", Vector2i(-1, -1)) == Vector2i(3, 4),
		"en-passant victim square is correct"
	)
	_expect(
		rules.get_piece(Vector2i(3, 4)).is_empty(),
		"captured pawn is removed from its original square"
	)
	_expect(rules.get_piece(Vector2i(3, 5)).get("type", "") == "P", "capturing pawn occupies d6")


func _test_promotion() -> void:
	var rules = RulesScript.new()
	_expect(rules.load_fen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1"), "load promotion test position")
	_expect(rules.is_legal_move(Vector2i(0, 6), Vector2i(0, 7)), "pawn reaches its promotion rank")
	var promotion = rules.play_move(Vector2i(0, 6), Vector2i(0, 7), "N")
	_expect(promotion.get("promotion", "") == "N", "selected underpromotion is retained")
	_expect(
		promotion.get("notation", "") == "a8=N", "promotion notation reflects the selected piece"
	)
	_expect(
		rules.get_piece(Vector2i(0, 7)).get("type", "") == "N", "promoted piece replaces the pawn"
	)


func _test_checkmate() -> void:
	var rules = RulesScript.new()
	rules.play_move(Vector2i(5, 1), Vector2i(5, 2))  # f3
	rules.play_move(Vector2i(4, 6), Vector2i(4, 4))  # ...e5
	rules.play_move(Vector2i(6, 1), Vector2i(6, 3))  # g4
	var mate = rules.play_move(Vector2i(3, 7), Vector2i(7, 3))  # ...Qh4#
	var status: Dictionary = rules.game_status()
	_expect(status.get("result", "") == "checkmate", "Fool's Mate is checkmate")
	_expect(status.get("winner", "") == "b", "checkmate winner is black")
	_expect(mate.get("notation", "") == "Qh4#", "checkmate SAN suffix")


func _test_stalemate() -> void:
	var rules = RulesScript.new()
	_expect(rules.load_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"), "load stalemate test position")
	_expect(rules.is_stalemate(), "black king has no legal move and is not in check")
	_expect(rules.game_status().get("result", "") == "stalemate", "stalemate is surfaced as a draw")


func _test_draw_rules() -> void:
	var rules = RulesScript.new()
	_expect(rules.load_fen("4k3/8/8/8/8/8/8/R3K2R w KQ - 99 50"), "load fifty-move test position")
	rules.play_move(Vector2i(0, 0), Vector2i(0, 1))
	_expect(
		rules.game_status().get("result", "") == "draw_fifty_move",
		"fifty-move rule after 100 half-moves"
	)

	var repetition = RulesScript.new()
	for cycle in range(2):
		repetition.play_move(Vector2i(6, 0), Vector2i(5, 2))
		repetition.play_move(Vector2i(6, 7), Vector2i(5, 5))
		repetition.play_move(Vector2i(5, 2), Vector2i(6, 0))
		repetition.play_move(Vector2i(5, 5), Vector2i(6, 7))
	_expect(repetition.game_status().get("result", "") == "draw_repetition", "threefold repetition")
	repetition.undo()
	_expect(
		repetition.game_status().get("result", "") == "playing",
		"undo also restores repetition counts"
	)

	var material = RulesScript.new()
	_expect(
		material.load_fen("4k3/8/8/8/8/8/8/2B1K3 w - - 0 1"), "load insufficient-material position"
	)
	_expect(
		material.game_status().get("result", "") == "draw_material",
		"king and bishop versus king is drawn"
	)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	failures += 1
	push_error("Assertion failed: " + label)
