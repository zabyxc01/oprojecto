extends Node
class_name AvatarExpressions

# Drives VRM expression blend shapes from emotion tags.
# Uses the same mesh as lip sync but targets expression blend shapes
# (happy, angry, sad, surprised, relaxed, neutral).

var _mesh: MeshInstance3D = null
var _expression_indices := {}  # emotion name → blend shape index
var _current_emotion := "neutral"
var _current_weight := 0.0
var _target_weight := 0.0
var _transition_speed := 4.0

# How long an expression holds before returning to neutral
var _hold_timer := 0.0
var _hold_duration := 4.0

# VRM expression name variants to search for
const EXPRESSION_SHAPES = {
	"happy": ["Fcl_ALL_Joy", "Fcl_ALL_Happy", "Joy", "Happy", "happy"],
	"angry": ["Fcl_ALL_Angry", "Angry", "angry"],
	"sad": ["Fcl_ALL_Sad", "Fcl_ALL_Sorrow", "Sad", "Sorrow", "sad"],
	"surprised": ["Fcl_ALL_Surprised", "Surprised", "surprised"],
	"relaxed": ["Fcl_ALL_Fun", "Fcl_ALL_Relaxed", "Fun", "Relaxed", "relaxed"],
	"neutral": ["Fcl_ALL_Neutral", "Neutral", "neutral"],
}

# Blink system (periodic, independent of emotions)
var _blink_index := -1
var _blink_timer := 0.0
var _blink_interval := 3.0
var _blink_weight := 0.0
var _is_blinking := false
const BLINK_SHAPES = ["Fcl_ALL_Close", "Fcl_EYE_Close", "Blink", "blink"]

func setup(model: Node3D) -> void:
	_mesh = _find_face_mesh(model)
	if not _mesh:
		print("[expressions] No mesh with blend shapes found")
		return

	_expression_indices.clear()
	var count = _mesh.mesh.get_blend_shape_count()

	for i in range(count):
		var name = _mesh.mesh.get_blend_shape_name(i)
		# Check expression shapes
		for emotion in EXPRESSION_SHAPES:
			for variant in EXPRESSION_SHAPES[emotion]:
				if name == variant or name.ends_with(variant):
					_expression_indices[emotion] = i
					print("[expressions] Mapped: ", emotion, " → ", name, " (index ", i, ")")
					break

		# Check blink
		for variant in BLINK_SHAPES:
			if name == variant or name.ends_with(variant):
				_blink_index = i
				print("[expressions] Blink → ", name, " (index ", i, ")")
				break

	print("[expressions] Ready: ", _expression_indices.keys())

func set_emotion(emotion: String) -> void:
	if emotion == _current_emotion:
		return
	# Only set if we have the blend shape
	if emotion in _expression_indices or emotion == "neutral":
		# Fade out current expression
		_current_emotion = emotion
		_target_weight = 1.0 if emotion != "neutral" else 0.0
		_hold_timer = 0.0
		print("[expressions] → ", emotion)

func update(delta: float) -> void:
	if not _mesh:
		return

	# Expression transition
	_current_weight = lerp(_current_weight, _target_weight, delta * _transition_speed)

	# Hold timer — return to neutral after hold_duration
	if _current_emotion != "neutral" and _target_weight > 0.5:
		_hold_timer += delta
		if _hold_timer >= _hold_duration:
			_target_weight = 0.0
			_current_emotion = "neutral"

	# Apply expression blend shape
	for emotion in _expression_indices:
		var idx = _expression_indices[emotion]
		if emotion == _current_emotion:
			_mesh.set_blend_shape_value(idx, _current_weight)
		else:
			# Fade out other expressions
			var current = _mesh.get_blend_shape_value(idx)
			if current > 0.01:
				_mesh.set_blend_shape_value(idx, lerp(current, 0.0, delta * _transition_speed))

	# Periodic blink
	if _blink_index >= 0:
		_blink_timer += delta
		if not _is_blinking and _blink_timer >= _blink_interval:
			_is_blinking = true
			_blink_timer = 0.0
			_blink_interval = 2.5 + randf() * 4.0  # randomize next blink
		if _is_blinking:
			_blink_weight += delta * 20.0  # fast blink
			if _blink_weight >= 1.0:
				_blink_weight = 1.0
				_is_blinking = false
		else:
			_blink_weight = move_toward(_blink_weight, 0.0, delta * 15.0)
		_mesh.set_blend_shape_value(_blink_index, _blink_weight)

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
