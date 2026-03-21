extends Node
class_name ExpressionManager

## Four-layer expression orchestrator with animation priority queue.
##
## Animation priorities (higher number = higher priority):
##   POSITIONAL (0): IdleBreathing, Walking, Sitting, LayingDown — base layer, loops
##   BEHAVIOR (1): idle cycling (LookAround, Relax, Thinking) — timed, from behavior tree
##   EMOTION (2): happy, sad, angry etc — from LLM, returns to positional when done
##   USER (3): manual F3 selection — highest priority, plays until changed
##
## Layers evaluated every frame:
##   1. Body animation (positional base + emotion/behavior overlay)
##   2. Facial expression (blend shapes with intensity)
##   3. Procedural overlays (blink, lip sync, eye tracking)

signal emotion_applied(emotion: String, intensity: float)
signal positional_changed(anim_name: String)

var _expressions: AvatarExpressions
var _animation: AvatarAnimation
var _lipsync: LipSync
var _is_speaking := false

# ── Animation Priority System ────────────────────────────────────────────────
enum AnimPriority { POSITIONAL = 0, BEHAVIOR = 1, EMOTION = 2, USER = 3 }

var _current_anim := ""
var _current_priority := -1
var _anim_remaining := 0.0  # seconds left for current non-positional anim
var _positional_anim := "LookAround"  # base animation to return to
var _anim_queue: Array = []  # [{name: String, priority: int, duration: float}]

# Physics state → positional animation mapping
const PHYSICS_ANIM_MAP := {
	"standing": "Idle",
	"walking": "FemaleWalk",
	"sitting": "Sitting",
	"sleeping": "LayingSleeping",
	"falling": "Jump",
	"dragged": "Defeated",
}

# Emotion → animation clip mapping (87 VRMA clips available)
const EMOTION_ANIM_MAP := {
	"happy": "Happy",
	"angry": "Angry",
	"sad": "Sad",
	"surprised": "Surprised",
	"relaxed": "Relax",
	"blush": "Blush",
	"shy": "Bashful",
	"sleepy": "Sleepy",
	"thinking": "Thinking",
	"curious": "LookAround",
	"bored": "BreathingIdle",
	"serious": "StandingIdle",
	"love": "BlowAKiss",
	"neutral": "",
}

# Override declarations per emotion
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


func setup(expressions: AvatarExpressions, animation: AvatarAnimation, lipsync: LipSync) -> void:
	_expressions = expressions
	_animation = animation
	_lipsync = lipsync

	# Start with positional animation
	_play_anim(_positional_anim)


# ── Public API ───────────────────────────────────────────────────────────────

func set_emotion(emotion_data: Dictionary) -> void:
	"""Accept full emotion payload from LLM response."""
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

	# Layer 1: body animation (emotion priority)
	if primary != "neutral" and intensity >= 0.2:
		var anim_name: String = EMOTION_ANIM_MAP.get(primary, "")
		if anim_name:
			var duration = 3.0 + intensity * 3.0
			request_animation(anim_name, AnimPriority.EMOTION, duration)

	# Calculate overrides
	_apply_overrides(primary, intensity)
	emotion_applied.emit(primary, intensity)


func request_animation(anim_name: String, priority: int, duration: float = 4.0) -> bool:
	"""Request an animation with priority. Returns true if played immediately."""
	if not _animation or not _animation.has_animation(anim_name):
		return false

	if priority >= _current_priority:
		# Play immediately — higher or equal priority
		_play_anim(anim_name)
		_current_priority = priority
		_anim_remaining = duration if priority > AnimPriority.POSITIONAL else 0.0
		DebugLog.log("expr_mgr", "Playing: %s (pri %d, %.1fs)" % [anim_name, priority, duration])
		return true
	else:
		# Queue it — lower priority, play when current finishes
		_anim_queue.append({"name": anim_name, "priority": priority, "duration": duration})
		return false


func set_positional(physics_state: String) -> void:
	"""Set the base positional animation based on desktop physics state."""
	var anim_name: String = PHYSICS_ANIM_MAP.get(physics_state, "LookAround")
	if anim_name == _positional_anim:
		return

	_positional_anim = anim_name
	positional_changed.emit(anim_name)

	# If nothing higher-priority is playing, switch immediately
	if _current_priority <= AnimPriority.POSITIONAL:
		_play_anim(anim_name)
		_current_priority = AnimPriority.POSITIONAL
		DebugLog.log("expr_mgr", "Positional: %s" % anim_name)


func set_speaking(speaking: bool) -> void:
	_is_speaking = speaking


func is_look_at_suppressed() -> bool:
	return _look_at_suppressed


# ── Update Loop ──────────────────────────────────────────────────────────────

func update(delta: float) -> void:
	if not _expressions:
		return

	# Layer 2: facial expressions (blend shapes)
	_expressions.update(delta)

	# Layer 1: body animation
	if _animation:
		_animation.update(delta)

		# Track animation duration (non-positional only)
		if _anim_remaining > 0.0:
			_anim_remaining -= delta
			if _anim_remaining <= 0.0:
				# Current animation expired — check queue or return to positional
				_anim_remaining = 0.0
				_advance_queue()

	# Layer 3: procedural overlays (lip sync with mouth suppression)
	if _lipsync:
		_lipsync.update(delta, _is_speaking, _mouth_suppression)


# ── Internal ─────────────────────────────────────────────────────────────────

func _advance_queue() -> void:
	"""Pop next animation from queue, or return to positional base."""
	if _anim_queue.size() > 0:
		# Sort by priority (highest first)
		_anim_queue.sort_custom(func(a, b): return a["priority"] > b["priority"])
		var next = _anim_queue.pop_front()
		_play_anim(next["name"])
		_current_priority = next["priority"]
		_anim_remaining = next["duration"]
		DebugLog.log("expr_mgr", "Queue -> %s (pri %d)" % [next["name"], next["priority"]])
	else:
		# Return to positional base
		_play_anim(_positional_anim)
		_current_priority = AnimPriority.POSITIONAL
		DebugLog.log("expr_mgr", "Returning to positional: %s" % _positional_anim)


func _play_anim(anim_name: String) -> void:
	if _animation and _animation.has_animation(anim_name) and _current_anim != anim_name:
		_animation.play(anim_name)
		_current_anim = anim_name


func _apply_overrides(emotion: String, intensity: float) -> void:
	var overrides: Dictionary = EMOTION_OVERRIDES.get(emotion, {})
	var base_mouth: float = overrides.get("override_mouth", 0.0)
	_mouth_suppression = base_mouth * intensity
	_blink_suppressed = overrides.get("override_blink", false) and intensity > 0.4
	_look_at_suppressed = overrides.get("override_look_at", false) and intensity > 0.3
	if _expressions:
		_expressions.set_blink_enabled(not _blink_suppressed)
