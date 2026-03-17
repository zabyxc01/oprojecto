extends Node
class_name LipSync

# Amplitude-based lip sync — reads audio bus volume and maps to blend shapes
# Works with any model that has morph targets (VRM expressions or GLTF blend shapes)

var _mesh: MeshInstance3D = null
var _blend_indices := {}  # name → blend shape index
var _amplitude := 0.0

# Blend weight rotation for natural mouth variation
var _blend_timer := 0.0
var _blend_target := {"aa": 1.0, "ih": 0.0, "ou": 0.0}
const BLEND_PRESETS = [
	{"aa": 1.0, "ih": 0.0, "ou": 0.0},
	{"aa": 0.6, "ih": 0.3, "ou": 0.1},
	{"aa": 0.4, "ih": 0.1, "ou": 0.5},
	{"aa": 0.7, "ih": 0.2, "ou": 0.1},
	{"aa": 0.3, "ih": 0.5, "ou": 0.2},
]

# VRM expression name variants to search for
const MOUTH_SHAPES = {
	"aa": ["Fcl_MTH_A", "MTH_A", "A", "aa", "vrc.v_aa", "Vowel_A"],
	"ih": ["Fcl_MTH_I", "MTH_I", "I", "ih", "vrc.v_ih", "Vowel_I"],
	"ou": ["Fcl_MTH_O", "MTH_O", "O", "ou", "vrc.v_ou", "Vowel_O"],
}

func setup(model: Node3D) -> void:
	_mesh = _find_face_mesh(model)
	if not _mesh:
		print("[lipsync] No mesh with blend shapes found")
		return

	# Map blend shape names
	_blend_indices.clear()
	var count = _mesh.mesh.get_blend_shape_count()
	print("[lipsync] Found ", count, " blend shapes")

	for i in range(count):
		var name = _mesh.mesh.get_blend_shape_name(i)
		# Check against our mouth shape variants
		for key in MOUTH_SHAPES:
			for variant in MOUTH_SHAPES[key]:
				if name == variant or name.ends_with(variant):
					_blend_indices[key] = i
					print("[lipsync] Mapped: ", key, " → ", name, " (index ", i, ")")
					break

	if _blend_indices.is_empty():
		# Print all blend shapes so we can see what's available
		for i in range(count):
			print("[lipsync] Available: ", _mesh.mesh.get_blend_shape_name(i))

func update(delta: float, is_speaking: bool) -> void:
	if not _mesh or _blend_indices.is_empty():
		return

	if is_speaking:
		# Get audio amplitude from the master bus
		var peak_db = AudioServer.get_bus_peak_volume_left_db(0, 0)
		# Convert dB to linear (0-1 range)
		var linear = db_to_linear(peak_db)
		# Smooth and amplify
		_amplitude = lerp(_amplitude, clampf(linear * 3.0, 0.0, 1.0), delta * 15.0)

		# Rotate blend weights for variety
		_blend_timer += delta
		if _blend_timer > 0.12 + randf() * 0.08:
			_blend_timer = 0.0
			_blend_target = BLEND_PRESETS[randi() % BLEND_PRESETS.size()]

		# Apply to blend shapes
		for key in _blend_indices:
			var weight = _amplitude * _blend_target.get(key, 0.0)
			_mesh.set_blend_shape_value(_blend_indices[key], weight)
	else:
		# Reset mouth
		_amplitude = lerp(_amplitude, 0.0, delta * 10.0)
		for key in _blend_indices:
			_mesh.set_blend_shape_value(_blend_indices[key], 0.0)

func _find_face_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.mesh and mi.mesh.get_blend_shape_count() > 0:
			return mi
	for child in node.get_children():
		var found = _find_face_mesh(child)
		if found:
			return found
	return null
