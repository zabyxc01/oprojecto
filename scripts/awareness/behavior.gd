extends Node
class_name BehaviorTree

## State machine that drives Kira's autonomous behavior based on
## screen context, idle time, mood, and interaction history.
##
## States:
##   ATTENTIVE  — actively chatting. Full engagement.
##   OBSERVING  — user is doing something, she watches. Occasional reactions.
##   IDLE       — user is here but quiet. She entertains herself.
##   SLEEPING   — 10+ min idle. Dozes. Wakes on input.
##   REACTING   — context just changed (new app, game launched). Brief reaction.
##   INITIATING — she says/does something unprompted. Rare, mood-driven.

signal state_changed(new_state: String, old_state: String)
signal wants_to_speak(prompt: String)  # request ambient LLM query
signal wants_animation(anim_name: String)

enum State { ATTENTIVE, OBSERVING, IDLE, SLEEPING, REACTING, INITIATING }

var current_state: State = State.OBSERVING
var _state_timer := 0.0  # time in current state
var _last_interaction := 0.0  # time since last user interaction (seconds)
var _interaction_timer := 0.0
var _initiate_cooldown := 0.0  # cooldown before next initiation
var _react_timer := 0.0
var _context: Dictionary = {}  # latest screen context
var _mood := "content"

# Thresholds
const IDLE_THRESHOLD := 120.0      # 2 min → IDLE
const SLEEP_THRESHOLD := 600.0     # 10 min → SLEEPING
const REACT_DURATION := 5.0        # reaction state lasts 5s
const INITIATE_MIN_COOLDOWN := 120.0  # min 2 min between initiations
var INITIATE_CHANCE := 0.15        # 15% chance per check when conditions met (adjustable via /focus /chill)

# Idle animations to cycle through
const IDLE_ANIMS := ["LookAround", "Relax", "Thinking"]
var _idle_anim_timer := 0.0
var _idle_anim_interval := 10.0


func update(delta: float) -> void:
	_state_timer += delta
	_interaction_timer += delta
	_last_interaction += delta
	if _initiate_cooldown > 0:
		_initiate_cooldown -= delta

	match current_state:
		State.ATTENTIVE:
			_update_attentive(delta)
		State.OBSERVING:
			_update_observing(delta)
		State.IDLE:
			_update_idle(delta)
		State.SLEEPING:
			_update_sleeping(delta)
		State.REACTING:
			_update_reacting(delta)
		State.INITIATING:
			_update_initiating(delta)


func on_user_interaction() -> void:
	"""Call when user sends a message or presses PTT."""
	_last_interaction = 0.0
	_interaction_timer = 0.0
	if current_state == State.SLEEPING:
		_transition(State.ATTENTIVE)
		wants_animation.emit("Surprised")
	elif current_state != State.ATTENTIVE:
		_transition(State.ATTENTIVE)


func on_context_changed(context: Dictionary) -> void:
	"""Call when screen context changes."""
	var old_activity = _context.get("activity", "")
	_context = context

	var new_activity = context.get("activity", "")

	# If activity type changed meaningfully, react
	if old_activity != "" and old_activity != new_activity and new_activity != "unknown":
		if current_state in [State.OBSERVING, State.IDLE]:
			_transition(State.REACTING)
			_react_timer = 0.0

	# Update idle state from context
	var idle_min: float = context.get("idle_minutes", 0.0)
	if idle_min > SLEEP_THRESHOLD / 60.0 and current_state != State.SLEEPING:
		_transition(State.SLEEPING)


func on_mood_changed(mood: String) -> void:
	_mood = mood


func get_state_name() -> String:
	match current_state:
		State.ATTENTIVE: return "attentive"
		State.OBSERVING: return "observing"
		State.IDLE: return "idle"
		State.SLEEPING: return "sleeping"
		State.REACTING: return "reacting"
		State.INITIATING: return "initiating"
	return "unknown"


# ── State updates ────────────────────────────────────────────────────────────

func _update_attentive(_delta: float) -> void:
	# Stay attentive while user is actively chatting
	# Transition to observing after quiet period
	if _last_interaction > 30.0:
		_transition(State.OBSERVING)


func _update_observing(delta: float) -> void:
	# User is doing something, she watches
	if _last_interaction > IDLE_THRESHOLD:
		_transition(State.IDLE)

	# Occasionally initiate
	if _initiate_cooldown <= 0 and _state_timer > 30.0:
		_maybe_initiate()


func _update_idle(delta: float) -> void:
	if _last_interaction > SLEEP_THRESHOLD:
		_transition(State.SLEEPING)

	# Cycle idle animations
	_idle_anim_timer += delta
	if _idle_anim_timer >= _idle_anim_interval:
		_idle_anim_timer = 0.0
		_idle_anim_interval = 8.0 + randf() * 8.0
		var anim = IDLE_ANIMS[randi() % IDLE_ANIMS.size()]
		wants_animation.emit(anim)

	# Occasionally initiate
	if _initiate_cooldown <= 0 and _state_timer > 60.0:
		_maybe_initiate()


func _update_sleeping(_delta: float) -> void:
	# Just sleep. Wake on user interaction (handled in on_user_interaction).
	if _state_timer < 1.0:
		wants_animation.emit("Sleepy")


func _update_reacting(_delta: float) -> void:
	_react_timer += _delta
	if _react_timer >= REACT_DURATION:
		_transition(State.OBSERVING)

	# On enter: trigger a reaction
	if _react_timer < 0.1:
		var activity = _context.get("activity", "unknown")
		var title = _context.get("window_title", "")
		if activity == "gaming":
			wants_to_speak.emit(
				"User just launched a game: " + title + ". " +
				"Kira is " + _mood + ". React briefly and naturally."
			)
		elif activity == "coding":
			wants_to_speak.emit(
				"User switched to coding: " + title + ". " +
				"Kira is " + _mood + ". Brief, natural reaction."
			)
		elif activity == "browsing":
			# Don't comment on every tab switch
			pass
		else:
			wants_to_speak.emit(
				"User switched to: " + title + ". " +
				"Kira is " + _mood + ". Brief observation if interesting."
			)


func _update_initiating(_delta: float) -> void:
	# Initiation is a brief state — the LLM query was sent, now wait
	if _state_timer > 3.0:
		_transition(State.OBSERVING)


func _maybe_initiate() -> void:
	"""Chance-based initiation — mood-driven."""
	var chance = INITIATE_CHANCE
	# More likely when energetic, less when melancholy
	if _mood == "energetic":
		chance *= 1.5
	elif _mood == "melancholy":
		chance *= 0.3
	elif _mood == "bored":
		chance *= 2.0  # bored Kira is chatty

	if randf() < chance:
		_initiate_cooldown = INITIATE_MIN_COOLDOWN + randf() * 60.0
		_transition(State.INITIATING)

		var time_of_day = _context.get("time_of_day", "afternoon")
		var activity = _context.get("activity", "unknown")
		var idle_min = _context.get("idle_minutes", 0.0)

		wants_to_speak.emit(
			"Kira is " + _mood + ". It's " + time_of_day + ". " +
			"User is " + activity + " (idle " + str(int(idle_min)) + " min). " +
			"Say something casual and unprompted — a thought, observation, or question. " +
			"Keep it very short (1 sentence)."
		)


func _transition(new_state: State) -> void:
	if new_state == current_state:
		return
	var old_name = get_state_name()
	current_state = new_state
	_state_timer = 0.0
	var new_name = get_state_name()
	print("[behavior] ", old_name, " -> ", new_name)
	state_changed.emit(new_name, old_name)
