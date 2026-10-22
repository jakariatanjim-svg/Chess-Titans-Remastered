extends RefCounted

## Procedurally-built board and table details. The geometry is authored for this
## project rather than relying on placeholder chess icons or external artwork.

const TILE_TOP := 0.106
const SQUARE_SPACING := 1.0


static func create_board(parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = "Chessboard"
	parent.add_child(root)

	var ebony := _material(Color("171b21"), 0.42, 0.22)
	var walnut := _material(Color("2a1912"), 0.20, 0.31)
	var walnut_light := _material(Color("493022"), 0.12, 0.30)
	var brass := _material(Color("b48a4e"), 0.74, 0.26)
	var ivory := _material(Color("d8c6a2"), 0.13, 0.29)
	var dark_tile := _material(Color("33231d"), 0.12, 0.26)
	var ivory_inlay := _material(Color("eadcc0"), 0.10, 0.34)
	var dark_inlay := _material(Color("4a3429"), 0.08, 0.34)

	_add_box(root, "Tabletop", Vector3(10.2, 0.22, 10.2), Vector3(0, -0.38, 0), ebony)
	_add_box(root, "CarvedApron", Vector3(9.45, 0.42, 9.45), Vector3(0, -0.68, 0), walnut)
	_add_box(root, "ApronInlay", Vector3(9.52, 0.055, 9.52), Vector3(0, -0.48, 0), brass)
	_add_box(root, "PedestalFoot", Vector3(8.6, 0.18, 8.6), Vector3(0, -0.94, 0), walnut_light)
	_add_box(root, "BoardFoundation", Vector3(8.28, 0.20, 8.28), Vector3(0, -0.16, 0), walnut)
	_add_box(root, "InnerGoldBinding", Vector3(8.18, 0.035, 8.18), Vector3(0, -0.043, 0), brass)
	_add_box(root, "BoardBed", Vector3(8.10, 0.105, 8.10), Vector3(0, -0.012, 0), walnut_light)

	for rank in range(8):
		for file in range(8):
			var x := float(file) - 3.5
			var z := 3.5 - float(rank)
			var is_light := (file + rank) % 2 == 1
			var tile_material: StandardMaterial3D = ivory if is_light else dark_tile
			var cap_material: StandardMaterial3D = ivory_inlay if is_light else dark_inlay
			_add_box(
				root,
				"Tile_%s%d" % ["abcdefgh".substr(file, 1), rank + 1],
				Vector3(0.988, 0.112, 0.988),
				Vector3(x, 0.042, z),
				tile_material
			)
			# A thin inset top catches the light like a finished, beveled wood tile.
			_add_box(
				root,
				"TileInlay_%s%d" % ["abcdefgh".substr(file, 1), rank + 1],
				Vector3(0.942, 0.009, 0.942),
				Vector3(x, 0.1015, z),
				cap_material
			)

	# Four narrow brass rails frame the playing surface without obscuring the squares.
	_add_box(root, "RailNorth", Vector3(8.28, 0.085, 0.105), Vector3(0, 0.074, -4.115), brass)
	_add_box(root, "RailSouth", Vector3(8.28, 0.085, 0.105), Vector3(0, 0.074, 4.115), brass)
	_add_box(root, "RailWest", Vector3(0.105, 0.085, 8.10), Vector3(-4.115, 0.074, 0), brass)
	_add_box(root, "RailEast", Vector3(0.105, 0.085, 8.10), Vector3(4.115, 0.074, 0), brass)
	_add_box(root, "OuterWoodNorth", Vector3(8.50, 0.15, 0.18), Vector3(0, -0.025, -4.20), walnut)
	_add_box(root, "OuterWoodSouth", Vector3(8.50, 0.15, 0.18), Vector3(0, -0.025, 4.20), walnut)
	_add_box(root, "OuterWoodWest", Vector3(0.18, 0.15, 8.28), Vector3(-4.20, -0.025, 0), walnut)
	_add_box(root, "OuterWoodEast", Vector3(0.18, 0.15, 8.28), Vector3(4.20, -0.025, 0), walnut)

	_add_coordinate_labels(root, ivory)
	return root


static func create_square_overlay(
	parent: Node, square: Vector2i, color: Color, is_destination: bool = false
) -> Node3D:
	var root := Node3D.new()
	root.name = "LegalDestination" if is_destination else "SquareHighlight"
	root.position = Vector3(float(square.x) - 3.5, TILE_TOP + 0.009, 3.5 - float(square.y))
	parent.add_child(root)

	if is_destination:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.075
		torus.outer_radius = 0.13
		torus.rings = 8
		torus.ring_segments = 28
		var marker := MeshInstance3D.new()
		marker.mesh = torus
		marker.material_override = _glow_material(color)
		root.add_child(marker)
	else:
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.94, 0.94)
		var marker := MeshInstance3D.new()
		marker.mesh = plane
		marker.material_override = _glow_material(color, true)
		root.add_child(marker)
	return root


static func _add_coordinate_labels(root: Node3D, material: StandardMaterial3D) -> void:
	for file in range(8):
		var letter := "abcdefgh".substr(file, 1)
		_add_label(root, letter, Vector3(float(file) - 3.5, 0.015, 4.25), 0.0, material)
		_add_label(root, letter, Vector3(float(file) - 3.5, 0.015, -4.25), PI, material)
	for rank in range(8):
		var number := str(rank + 1)
		_add_label(root, number, Vector3(-4.25, 0.015, 3.5 - float(rank)), PI / 2.0, material)
		_add_label(root, number, Vector3(4.25, 0.015, 3.5 - float(rank)), -PI / 2.0, material)


static func _add_label(
	root: Node3D,
	text_value: String,
	position_value: Vector3,
	yaw: float,
	material: StandardMaterial3D
) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = 54
	label.pixel_size = 0.0013
	label.position = position_value
	label.rotation.y = yaw
	label.modulate = material.albedo_color
	label.no_depth_test = false
	label.outline_size = 0
	root.add_child(label)


static func _add_box(
	parent: Node, object_name: String, size: Vector3, position_value: Vector3, material: Material
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = object_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


static func _glow_material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.65
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var alpha_color := color
		alpha_color.a = 0.30
		material.albedo_color = alpha_color
		material.emission_energy_multiplier = 0.22
	return material
