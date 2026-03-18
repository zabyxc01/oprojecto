extends Node
class_name ExpressionManager

## Three-layer expression orchestrator (inspired by three-vrm override pattern).
##
## Every frame, three layers are evaluated in order:
##   1. Body animation — skeleton poses from VRMA clips (emotion + idle)
##   2. Facial expression — blend shapes with intensity (primary + secondary)
##   3. Procedural overlays — blink, lip sync, eye tracking
##
## Override system: each emotion declares what it suppresses:
##   - override_mouth: attenuate lip sync (e.g. big smile → less mouth movement)
##   - override_blink: suppress auto-blink (e.g. surprise → eyes wide)
##   - override_look_at: suppress eye tracking (e.g. sleepy → half-closed)

signal emotion_applied(emotion: String, intensity: float)

var _expressions: AvatarExpressions
var _animation: AvatarAnimation
var _lipsync: LipSync
var _is_speaking := false

# Emotion → animation clip mapping
const EMOTION_ANIM_MAP := {
	"happy": "Clapping",
	"angry": "Angry",
	"sad": "Sad",
	"surprised": "Surprised",
	"relaxed": "Relax",
	"blush": "Blush",
	"shy": "Blush",
	"sleepy": "Sleepy",
	"thinking": "Thinking",
	"curious": "LookAround",
	"bored": "LookAround",
	"serious": "Thinking",
	"love": "Clapping",
	"neutral": "",
}

# Override declarations per emotion
# override_mouth: 0.0 = no suppression, 1.0 = full suppression of lip sync
# override_blink: true = suppress auto-blink (eyes stay as expression dictates)
# override_look_at: true = suppress eye tracking
const EMOTION_OVERRIDES := {
	"happy":     {"override_mouth": 0.5, "override_blink": false, "override_look_at": false},
	"angry":     {"override_mouth": 0.4, "override_blink": false, "override_look_at": false},
	"sad":       {"override_mouth": 0.3, "override_blink": false, "override_look_at": false},
	"surprised": {"override_mouth": 0.6, "override_blink": true,  "override_look_at": false},
	"relaxed":   {"override_mouth": 0.0, "override_blink": false, "override_look_at": false},
	"neutral":   {"override_mouth": 0.0, "override_blink": false, "override_look_at": false},
	"blush":     {"override_mouth": 0.3, "override_blink": false, "override_look_at": true},
	"sleepy":    {"override_mouth": 0.2, "override_blink": true,  "override_look_at": true},
	"thinking":  {"override_mouth": 0.1, "override_blink": false, "override_look_at": true},
	"shy":       {"override_mouth": 0.3, "override_blink": false, "override_look_at": true},
	"bored":     {"override_mouth": 0.0, "override_blink": false, "override_look_at": false},
	"serious":   {"override_mouth": 0.2, "override_blink": false, "override_look_at": false},
	"curious":   {"override_mouth": 0.0, "override_blink": false, "override_look_at": false},
	"love":      {"override_mouth": 0.4, "override_blink": false, "override_look_at": false},
}

# Current overrides (applied, intensity-scaled)
var _mouth_suppression := 0.0
var _blink_suppressed := false
var _look_at_suppressed := false

# Idle animation
var _idle_anim := "LookAround"
var _idle_timer := 0.0
var _idle_interval := 8.0  # seconds between idle animation changes
var _in_emotion_anim := false
var _emotion_anim_timer := 0.0
var _emotion_anim_duration := 4.0


func setup(expressions: AvatarExpressions, animation: AvatarAnimation, lipsync: LipSync) -> void:
	_expressions = expressions
	_animation = animation
	_lipsync = lipsync

	# Start idle animation
	if _animation and _animation.has_animation(_idle_anim):
		_animation.play(_idle_anim)


func set_emotion(emotion_data: Dictionary) -> void:
	"""Accept full emotion payload from server.

	emotion_data format:
	  {primary: "happy", primary_intensity: 0.8,
	   secondary: "curious", secondary_intensity: 0.3}
	Or legacy string format is handled by the caller.
	"""
	var primary: String = emotion_data.get("primary", "neutral")
	var intensity: float = emotion_data.get("primary_intensity", 0.7)
	var secondary: String = emotion_data.get("secondary", "")
	var secondary_intensity: float = emotion_data.get("secondary_intensity", 0.0)

	if not _expressions:
		return

	# Layer 2: facial expression
	_expressions.set_emotion(primary, intensity)
	if secondary:
		_expressions.set_secondary(secondary, secondary_intensity)

	# Layer 1: body animation
	_play_emotion_animation(primary, intensity)

	# Calculate overrides
	_apply_overrides(primary, intensity)

	emotion_applied.emit(primary, intensity)


func set_speaking(speaking: bool) -> void:
	_is_speaking = speaking


func is_look_at_suppressed() -> bool:
	return _look_at_suppressed


func _play_emotion_animation(emotion: String, intensity: float) -> void:
	if not _animation:
		return

	if emotion == "neutral" or intensity < 0.2:
		# Return to idle
		if _in_emotion_anim:
			_in_emotion_anim = false
			_animation.play(_idle_anim)
		return

	var anim_name: String = EMOTION_ANIM_MAP.get(emotion, "")
	if anim_name and _animation.has_animation(anim_name):
		_animation.play(anim_name)
		_in_emotion_anim = true
		_emotion_anim_timer = 0.0
		# Longer animations for stronger emotions
		_emotion_anim_duration = 3.0 + intensity * 3.0


func _apply_overrides(emotion: String, intensity: float) -> void:
	var overrides: Dictionary = EMOTION_OVERRIDES.get(emotion, {})

	# Scale mouth suppression by intensity
	var base_mouth: float = overrides.get("override_mouth", 0.0)
	_mouth_suppression = base_mouth * intensity

	# Bool overrides only apply above intensity threshold
	_blink_suppressed = overrides.get("override_blink", false) and intensity > 0.4
	_look_at_suppressed = overrides.get("override_look_at", false) and intensity > 0.3

	# Tell expression system about blink override
	if _expressions:
		_expressions.set_blink_enabled(not _blink_suppressed)


func update(delta: float) -> void:
	if not _expressions:
		return

	# Layer 2: facial expressions (blend shapes)
	_expressions.update(delta)

	# Layer 1: body animation
	if _animation:
		_animation.update(delta)

		# Return to idle after emotion animation duration
		if _in_emotion_anim:
			_emotion_anim_timer += delta
			if _emotion_anim_timer >= _emotion_anim_duration:
				_in_emotion_anim = false
				_animation.play(_idle_anim)

		# Cycle idle animations occasionally
		if not _in_emotion_anim:
			_idle_timer += delta
			if _idle_timer >= _idle_interval:
				_idle_timer = 0.0
				_idle_interval = 6.0 + randf() * 6.0

	# Layer 3: procedural overlays (lip sync with mouth suppression)
	if _lipsync:
		_lipsync.update(delta, _is_speaking, _mouth_suppression)
