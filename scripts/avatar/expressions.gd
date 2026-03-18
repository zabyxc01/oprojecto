extends Node
class_name AvatarExpressions

## Blend shape controller — maps emotions to VRM blend shapes with intensity.
## Does NOT manage layers or overrides; that's expression_manager.gd's job.

signal emotion_changed(emotion: String, intensity: float)
signal emotion_faded()

var _mesh: MeshInstance3D = null
var _expression_indices := {}  # emotion name → blend shape index
var _current_emotion := "neutral"
var _current_intensity := 0.0
var _target_emotion := "neutral"
var _target_intensity := 0.0
var _secondary_emotion := ""
var _secondary_intensity := 0.0
var _transition_speed := 6.0  # blend shapes per second

# Active blend shape weights (smoothed)
var _weights := {}  # emotion name → current weight

# How long an expression holds before fading
var _hold_timer := 0.0
var _hold_duration := 5.0

# 14 emotions — VRM blend shape name variants
const EXPRESSION_SHAPES := {
	"happy": ["Fcl_ALL_Joy", "Fcl_ALL_Happy", "Joy", "Happy", "happy"],
	"angry": ["Fcl_ALL_Angry", "Angry", "angry"],
	"sad": ["Fcl_ALL_Sad", "Fcl_ALL_Sorrow", "Sad", "Sorrow", "sad"],
	"surprised": ["Fcl_ALL_Surprised", "Surprised", "surprised"],
	"relaxed": ["Fcl_ALL_Fun", "Fcl_ALL_Relaxed", "Fun", "Relaxed", "relaxed"],
	"neutral": ["Fcl_ALL_Neutral", "Neutral", "neutral"],
	"blush": ["Fcl_ALL_Blush", "Blush", "blush"],
	"sleepy": ["Fcl_ALL_Sleepy", "Sleepy", "sleepy"],
	"thinking": ["Fcl_ALL_Thinking", "Thinking", "thinking"],
	"shy": ["Fcl_ALL_Shy", "Shy", "shy"],
	"bored": ["Fcl_ALL_Bored", "Bored", "bored"],
	"serious": ["Fcl_ALL_Serious", "Serious", "serious"],
	"curious": ["Fcl_ALL_Curious", "Curious", "curious"],
	"love": ["Fcl_ALL_Love", "Love", "love"],
}

# Fallback: emotions that don't have their own blend shape use another
const FACE_FALLBACK := {
	"blush": "happy",
	"shy": "happy",
	"sleepy": "relaxed",
	"thinking": "neutral",
	"bored": "neutral",
	"serious": "neutral",
	"curious": "surprised",
	"love": "happy",
}

# Blink system
var _blink_index := -1
var _blink_timer := 0.0
var _blink_interval := 3.0
var _blink_weight := 0.0
var _is_blinking := false
var _blink_enabled := true  # can be suppressed by expression_manager
const BLINK_SHAPES := ["Fcl_ALL_Close", "Fcl_EYE_Close", "Blink", "blink"]


func setup(model: Node3D) -> void:
	_mesh = _find_face_mesh(model)
	if not _mesh:
		print("[expressions] No mesh with blend shapes found")
		return

	_expression_indices.clear()
	_weights.clear()
	var count = _mesh.mesh.get_blend_shape_count()

	for i in range(count):
		var bname = _mesh.mesh.get_blend_shape_name(i)
		for emotion in EXPRESSION_SHAPES:
			if emotion in _expression_indices:
				continue  # already found
			for variant in EXPRESSION_SHAPES[emotion]:
				if bname == variant or bname.ends_with(variant):
					_expression_indices[emotion] = i
					_weights[emotion] = 0.0
					print("[expressions] Mapped: ", emotion, " -> ", bname, " (", i, ")")
					break

		for variant in BLINK_SHAPES:
			if bname == variant or bname.ends_with(variant):
				_blink_index = i
				break

	print("[expressions] Ready: ", _expression_indices.keys())


func set_emotion(emotion: String, intensity: float = 0.7) -> void:
	"""Set target emotion with intensity (0.0-1.0)."""
	if emotion == _target_emotion and absf(intensity - _target_intensity) < 0.05:
		return
	_target_emotion = emotion
	_target_intensity = clampf(intensity, 0.0, 1.0)
	_hold_timer = 0.0
	emotion_changed.emit(emotion, intensity)
	print("[expressions] -> ", emotion, ":", snappedf(intensity, 0.01))


func set_secondary(emotion: String, intensity: float = 0.3) -> void:
	"""Set secondary blend emotion."""
	_secondary_emotion = emotion
	_secondary_intensity = clampf(intensity, 0.0, 1.0)


func set_blink_enabled(enabled: bool) -> void:
	_blink_enabled = enabled


func get_current_emotion() -> String:
	return _current_emotion


func get_current_intensity() -> float:
	return _current_intensity


func get_mouth_override() -> float:
	"""Returns how much the current expression should suppress lip sync (0=none, 1=full)."""
	# Emotions that involve the mouth area suppress lip sync
	var mouth_emotions := ["happy", "angry", "sad", "surprised", "love"]
	var face = FACE_FALLBACK.get(_current_emotion, _current_emotion)
	if face in mouth_emotions:
		return _current_intensity * 0.6  # attenuate lip sync to 40% at full intensity
	return 0.0


func update(delta: float) -> void:
	if not _mesh:
		return

	# Hold timer
	if _target_emotion != "neutral":
		_hold_timer += delta
		if _hold_timer >= _hold_duration:
			_target_emotion = "neutral"
			_target_intensity = 0.0
			_secondary_emotion = ""
			_secondary_intensity = 0.0
			emotion_faded.emit()

	# Resolve face blend shape for primary emotion
	var primary_face = FACE_FALLBACK.get(_target_emotion, _target_emotion)
	var secondary_face = FACE_FALLBACK.get(_secondary_emotion, _secondary_emotion) if _secondary_emotion else ""

	# Update weights for all emotions
	for emotion in _weights:
		var target := 0.0
		if emotion == primary_face:
			target = _target_intensity
		if emotion == secondary_face and secondary_face != primary_face:
			target = maxf(target, _secondary_intensity)

		_weights[emotion] = lerpf(_weights[emotion], target, delta * _transition_speed)

		# Apply to blend shape
		if emotion in _expression_indices:
			_mesh.set_blend_shape_value(_expression_indices[emotion], _weights[emotion])

	# Track current dominant emotion for external queries
	_current_emotion = _target_emotion
	_current_intensity = _weights.get(primary_face, 0.0)

	# Periodic blink
	if _blink_index >= 0 and _blink_enabled:
		_blink_timer += delta
		if not _is_blinking and _blink_timer >= _blink_interval:
			_is_blinking = true
			_blink_timer = 0.0
			_blink_interval = 2.5 + randf() * 4.0
		if _is_blinking:
			_blink_weight += delta * 20.0
			if _blink_weight >= 1.0:
				_blink_weight = 1.0
				_is_blinking = false
		else:
			_blink_weight = move_toward(_blink_weight, 0.0, delta * 15.0)
		_mesh.set_blend_shape_value(_blink_index, _blink_weight)
	elif _blink_index >= 0 and not _blink_enabled:
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
