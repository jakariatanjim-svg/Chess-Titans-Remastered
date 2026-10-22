extends RefCounted

## Original, procedural turned-piece models with distinct silhouettes and hand-built
## knight relief. Meshes are cached and shared so every match remains lightweight.

static var _lathe_cache: Dictionary = {}
static var _knight_cache: ArrayMesh


static func make_piece(kind: String, color: String) -> Node3D:
	var root := Node3D.new()
	root.name = "%s_%s" % ["White" if color == "w" else "Black", _long_name(kind)]
	root.set_meta("piece_type", kind)
	root.set_meta("piece_color", color)
	var main_material := _piece_material(color)
	var trim_material := _trim_material(color)

	_add_lathe(root, "turned_base", _base_profile(), main_material)
	_add_lathe(
		root,
		"base_trim",
		[
			Vector2(0.275, 0.095),
			Vector2(0.295, 0.105),
			Vector2(0.295, 0.123),
			Vector2(0.272, 0.134)
		],
		trim_material
	)

	match kind:
		"P":
			_build_pawn(root, main_material, trim_material)
		"R":
			_build_rook(root, main_material, trim_material)
		"N":
			_build_knight(root, main_material, trim_material, color)
		"B":
			_build_bishop(root, main_material, trim_material)
		"Q":
			_build_queen(root, main_material, trim_material)
		"K":
			_build_king(root, main_material, trim_material)
	return root


static func _build_pawn(root: Node3D, body: Material, trim: Material) -> void:
	_add_lathe(
		root,
		"pawn_shaft",
		[
			Vector2(0.205, 0.245),
			Vector2(0.205, 0.285),
			Vector2(0.177, 0.325),
			Vector2(0.139, 0.390),
			Vector2(0.106, 0.485),
			Vector2(0.112, 0.575),
			Vector2(0.148, 0.625),
			Vector2(0.172, 0.642)
		],
		body
	)
	_add_lathe(
		root,
		"pawn_collar",
		[
			Vector2(0.142, 0.590),
			Vector2(0.182, 0.605),
			Vector2(0.186, 0.632),
			Vector2(0.160, 0.651),
			Vector2(0.145, 0.656)
		],
		trim
	)
	_add_lathe(
		root,
		"pawn_head",
		[
			Vector2(0.018, 0.647),
			Vector2(0.090, 0.662),
			Vector2(0.151, 0.694),
			Vector2(0.190, 0.748),
			Vector2(0.199, 0.806),
			Vector2(0.183, 0.864),
			Vector2(0.146, 0.909),
			Vector2(0.091, 0.936),
			Vector2(0.018, 0.945)
		],
		body
	)
	_add_lathe(
		root,
		"pawn_neck_ring",
		[Vector2(0.110, 0.643), Vector2(0.154, 0.650), Vector2(0.163, 0.666)],
		trim
	)


static func _build_rook(root: Node3D, body: Material, trim: Material) -> void:
	_add_lathe(
		root,
		"rook_tower",
		[
			Vector2(0.205, 0.245),
			Vector2(0.212, 0.295),
			Vector2(0.176, 0.344),
			Vector2(0.168, 0.405),
			Vector2(0.205, 0.445),
			Vector2(0.250, 0.470),
			Vector2(0.267, 0.520),
			Vector2(0.268, 0.815),
			Vector2(0.302, 0.873),
			Vector2(0.330, 0.900),
			Vector2(0.329, 0.955),
			Vector2(0.292, 0.985),
			Vector2(0.016, 0.991)
		],
		body
	)
	_add_lathe(
		root,
		"rook_turret_band",
		[
			Vector2(0.267, 0.825),
			Vector2(0.316, 0.835),
			Vector2(0.329, 0.858),
			Vector2(0.298, 0.879)
		],
		trim
	)
	_add_lathe(
		root,
		"rook_cap_band",
		[
			Vector2(0.290, 0.933),
			Vector2(0.343, 0.940),
			Vector2(0.348, 0.967),
			Vector2(0.303, 0.980)
		],
		trim
	)
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + PI / 8.0
		_add_box(
			root,
			"RookMerlon%d" % index,
			Vector3(0.115, 0.165, 0.115),
			Vector3(cos(angle) * 0.245, 1.045, sin(angle) * 0.245),
			body
		)


static func _build_knight(root: Node3D, body: Material, trim: Material, color: String) -> void:
	_add_lathe(
		root,
		"knight_neck",
		[
			Vector2(0.208, 0.245),
			Vector2(0.223, 0.294),
			Vector2(0.184, 0.344),
			Vector2(0.154, 0.412),
			Vector2(0.138, 0.475),
			Vector2(0.176, 0.512)
		],
		body
	)
	var horse := MeshInstance3D.new()
	horse.name = "HandSculptedHorseHead"
	horse.mesh = _knight_mesh()
	var horse_material := _piece_material(color)
	horse_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	horse.material_override = horse_material
	horse.position = Vector3(0.0, 0.39, 0.0)
	root.add_child(horse)

	# The relief eye and swept mane make the silhouette read clearly from the seat.
	_add_sphere(
		root,
		"KnightEye",
		Vector3(0.135, 1.445, 0.151),
		Vector3(0.035, 0.035, 0.025),
		_eye_material(color)
	)
	_add_sphere(
		root,
		"KnightEyeFar",
		Vector3(0.135, 1.445, -0.151),
		Vector3(0.035, 0.035, 0.025),
		_eye_material(color)
	)
	for index in range(3):
		var mane := BoxMesh.new()
		mane.size = Vector3(0.035, 0.245, 0.035)
		var ridge := MeshInstance3D.new()
		ridge.name = "ManeRidge%d" % index
		ridge.mesh = mane
		ridge.material_override = trim
		ridge.position = Vector3(-0.17 - float(index) * 0.035, 1.08 - float(index) * 0.18, 0.142)
		ridge.rotation.z = -0.34
		root.add_child(ridge)


static func _build_bishop(root: Node3D, body: Material, trim: Material) -> void:
	_add_lathe(
		root,
		"bishop_mitre",
		[
			Vector2(0.198, 0.245),
			Vector2(0.204, 0.292),
			Vector2(0.169, 0.341),
			Vector2(0.144, 0.405),
			Vector2(0.127, 0.520),
			Vector2(0.143, 0.605),
			Vector2(0.197, 0.671),
			Vector2(0.228, 0.760),
			Vector2(0.230, 0.865),
			Vector2(0.192, 0.976),
			Vector2(0.127, 1.072),
			Vector2(0.020, 1.145)
		],
		body
	)
	_add_lathe(
		root,
		"bishop_collar",
		[
			Vector2(0.157, 0.574),
			Vector2(0.209, 0.589),
			Vector2(0.214, 0.620),
			Vector2(0.174, 0.641)
		],
		trim
	)
	_add_lathe(
		root,
		"bishop_mitre_band",
		[
			Vector2(0.207, 0.861),
			Vector2(0.230, 0.875),
			Vector2(0.224, 0.903),
			Vector2(0.193, 0.918)
		],
		trim
	)
	_add_box(
		root,
		"BishopMitreSlit",
		Vector3(0.028, 0.345, 0.025),
		Vector3(0.035, 1.009, 0.210),
		trim,
		Vector3(0, 0, -0.48)
	)
	_add_sphere(root, "BishopFinial", Vector3(0, 1.156, 0), Vector3(0.055, 0.065, 0.055), trim)


static func _build_queen(root: Node3D, body: Material, trim: Material) -> void:
	_add_lathe(
		root,
		"queen_column",
		[
			Vector2(0.205, 0.245),
			Vector2(0.211, 0.295),
			Vector2(0.175, 0.345),
			Vector2(0.142, 0.414),
			Vector2(0.118, 0.574),
			Vector2(0.141, 0.636),
			Vector2(0.192, 0.684),
			Vector2(0.207, 0.742),
			Vector2(0.183, 0.789),
			Vector2(0.151, 0.842),
			Vector2(0.171, 0.923),
			Vector2(0.228, 0.985),
			Vector2(0.249, 1.061),
			Vector2(0.217, 1.125),
			Vector2(0.166, 1.161)
		],
		body
	)
	_add_lathe(
		root,
		"queen_collar",
		[
			Vector2(0.154, 0.619),
			Vector2(0.206, 0.636),
			Vector2(0.212, 0.667),
			Vector2(0.173, 0.685)
		],
		trim
	)
	_add_lathe(
		root,
		"queen_crown_rim",
		[
			Vector2(0.207, 1.045),
			Vector2(0.272, 1.062),
			Vector2(0.279, 1.099),
			Vector2(0.232, 1.119)
		],
		trim
	)
	_add_sphere(root, "QueenOrb", Vector3(0, 1.208, 0), Vector3(0.102, 0.115, 0.102), trim)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var point := _cone_mesh(0.045, 0.17)
		var spike := MeshInstance3D.new()
		spike.name = "QueenCrownPoint%d" % index
		spike.mesh = point
		spike.material_override = trim
		spike.position = Vector3(cos(angle) * 0.233, 1.181, sin(angle) * 0.233)
		root.add_child(spike)


static func _build_king(root: Node3D, body: Material, trim: Material) -> void:
	_add_lathe(
		root,
		"king_column",
		[
			Vector2(0.209, 0.245),
			Vector2(0.216, 0.294),
			Vector2(0.178, 0.343),
			Vector2(0.143, 0.416),
			Vector2(0.119, 0.607),
			Vector2(0.151, 0.680),
			Vector2(0.198, 0.722),
			Vector2(0.201, 0.784),
			Vector2(0.174, 0.850),
			Vector2(0.153, 0.974),
			Vector2(0.204, 1.030),
			Vector2(0.266, 1.078),
			Vector2(0.270, 1.130),
			Vector2(0.220, 1.165),
			Vector2(0.020, 1.173)
		],
		body
	)
	_add_lathe(
		root,
		"king_collar",
		[
			Vector2(0.157, 0.652),
			Vector2(0.215, 0.668),
			Vector2(0.219, 0.701),
			Vector2(0.172, 0.721)
		],
		trim
	)
	_add_lathe(
		root,
		"king_crown_band",
		[
			Vector2(0.217, 1.046),
			Vector2(0.285, 1.064),
			Vector2(0.286, 1.102),
			Vector2(0.235, 1.125)
		],
		trim
	)
	_add_sphere(root, "KingCrossJoint", Vector3(0, 1.245, 0), Vector3(0.070, 0.075, 0.070), trim)
	_add_box(root, "KingCrossVertical", Vector3(0.075, 0.420, 0.075), Vector3(0, 1.415, 0), trim)
	_add_box(root, "KingCrossHorizontal", Vector3(0.295, 0.075, 0.075), Vector3(0, 1.465, 0), trim)


static func _base_profile() -> Array[Vector2]:
	return [
		Vector2(0.020, 0.000),
		Vector2(0.235, 0.000),
		Vector2(0.284, 0.025),
		Vector2(0.318, 0.064),
		Vector2(0.321, 0.105),
		Vector2(0.291, 0.139),
		Vector2(0.260, 0.158),
		Vector2(0.255, 0.190),
		Vector2(0.278, 0.214),
		Vector2(0.262, 0.245),
		Vector2(0.212, 0.272),
		Vector2(0.018, 0.277)
	]


static func _add_lathe(
	root: Node3D, profile_name: String, profile: Array[Vector2], material: Material
) -> void:
	var key := profile_name
	if not _lathe_cache.has(key):
		_lathe_cache[key] = _make_lathe_mesh(profile, 48)
	var instance := MeshInstance3D.new()
	instance.name = profile_name
	instance.mesh = _lathe_cache[key]
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(instance)


static func _make_lathe_mesh(profile: Array[Vector2], segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in range(profile.size()):
		var previous: Vector2 = profile[maxi(0, ring - 1)]
		var following: Vector2 = profile[mini(profile.size() - 1, ring + 1)]
		var dr := following.x - previous.x
		var dy := following.y - previous.y
		for segment in range(segments):
			var angle := TAU * float(segment) / float(segments)
			var cosine := cos(angle)
			var sine := sin(angle)
			vertices.append(
				Vector3(profile[ring].x * cosine, profile[ring].y, profile[ring].x * sine)
			)
			var normal := Vector3(cosine * dy, -dr, sine * dy).normalized()
			normals.append(normal)
			uvs.append(Vector2(float(segment) / float(segments), profile[ring].y))
	for ring in range(profile.size() - 1):
		for segment in range(segments):
			var next := (segment + 1) % segments
			var a := ring * segments + segment
			var b := (ring + 1) * segments + segment
			var c := (ring + 1) * segments + next
			var d := ring * segments + next
			indices.append_array(PackedInt32Array([a, b, c, a, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _knight_mesh() -> ArrayMesh:
	if _knight_cache != null:
		return _knight_cache
	var outline := PackedVector2Array(
		[
			Vector2(-0.285, 0.035),
			Vector2(0.315, 0.035),
			Vector2(0.355, 0.105),
			Vector2(0.330, 0.200),
			Vector2(0.255, 0.318),
			Vector2(0.191, 0.493),
			Vector2(0.182, 0.657),
			Vector2(0.353, 0.823),
			Vector2(0.404, 0.912),
			Vector2(0.368, 0.994),
			Vector2(0.196, 1.035),
			Vector2(0.105, 1.219),
			Vector2(0.031, 1.385),
			Vector2(-0.030, 1.256),
			Vector2(-0.171, 1.314),
			Vector2(-0.278, 1.238),
			Vector2(-0.264, 1.105),
			Vector2(-0.374, 0.967),
			Vector2(-0.366, 0.808),
			Vector2(-0.264, 0.650),
			Vector2(-0.225, 0.465),
			Vector2(-0.318, 0.293),
			Vector2(-0.365, 0.169)
		]
	)
	var triangulation := Geometry2D.triangulate_polygon(outline)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half_depth := 0.145
	for point in outline:
		vertices.append(Vector3(point.x, point.y, half_depth))
		normals.append(Vector3.BACK)
		uvs.append(Vector2(point.x + 0.5, point.y))
	for point in outline:
		vertices.append(Vector3(point.x, point.y, -half_depth))
		normals.append(Vector3.FORWARD)
		uvs.append(Vector2(point.x + 0.5, point.y))
	var count := outline.size()
	for index in range(0, triangulation.size(), 3):
		var a: int = triangulation[index]
		var b: int = triangulation[index + 1]
		var c: int = triangulation[index + 2]
		var p0: Vector2 = outline[a]
		var p1: Vector2 = outline[b]
		var p2: Vector2 = outline[c]
		var area := (p1.x - p0.x) * (p2.y - p0.y) - (p1.y - p0.y) * (p2.x - p0.x)
		if area >= 0.0:
			indices.append_array(PackedInt32Array([a, b, c]))
			indices.append_array(PackedInt32Array([a + count, c + count, b + count]))
		else:
			indices.append_array(PackedInt32Array([a, c, b]))
			indices.append_array(PackedInt32Array([a + count, b + count, c + count]))
	for edge in range(count):
		var next := (edge + 1) % count
		var front_a := edge
		var front_b := next
		var back_a := edge + count
		var back_b := next + count
		var base := vertices.size()
		var p_a: Vector2 = outline[edge]
		var p_b: Vector2 = outline[next]
		vertices.append_array(
			PackedVector3Array(
				[
					Vector3(p_a.x, p_a.y, half_depth),
					Vector3(p_b.x, p_b.y, half_depth),
					Vector3(p_b.x, p_b.y, -half_depth),
					Vector3(p_a.x, p_a.y, -half_depth)
				]
			)
		)
		var edge_normal := Vector3(p_b.y - p_a.y, p_a.x - p_b.x, 0).normalized()
		for unused in range(4):
			normals.append(edge_normal)
		uvs.append_array(
			PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_knight_cache = ArrayMesh.new()
	_knight_cache.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _knight_cache


static func _add_box(
	root: Node3D,
	object_name: String,
	size: Vector3,
	position_value: Vector3,
	material: Material,
	rotation_value: Vector3 = Vector3.ZERO
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = object_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_value
	instance.rotation = rotation_value
	root.add_child(instance)


static func _add_sphere(
	root: Node3D,
	object_name: String,
	position_value: Vector3,
	scale_value: Vector3,
	material: Material
) -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 12
	var instance := MeshInstance3D.new()
	instance.name = object_name
	instance.mesh = sphere
	instance.material_override = material
	instance.position = position_value
	instance.scale = scale_value
	root.add_child(instance)


static func _cone_mesh(radius: float, height_value: float) -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.008
	cone.bottom_radius = radius
	cone.height = height_value
	cone.radial_segments = 16
	return cone


static func _piece_material(color: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if color == "w":
		material.albedo_color = Color("eee1c3")
		material.metallic = 0.16
		material.roughness = 0.24
	else:
		material.albedo_color = Color("17232d")
		material.metallic = 0.42
		material.roughness = 0.23
	return material


static func _trim_material(color: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d4ae70") if color == "w" else Color("a77d45")
	material.metallic = 0.76
	material.roughness = 0.25
	return material


static func _eye_material(color: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("24180e") if color == "w" else Color("e1bd7c")
	material.metallic = 0.3
	material.roughness = 0.18
	return material


static func _long_name(kind: String) -> String:
	match kind:
		"P":
			return "Pawn"
		"R":
			return "Rook"
		"N":
			return "Knight"
		"B":
			return "Bishop"
		"Q":
			return "Queen"
		"K":
			return "King"
	return "Piece"
