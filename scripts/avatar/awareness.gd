extends Node
class_name AvatarAwareness

# Awareness state machine — drives avatar behavior based on user presence
# Works with any rigged model via Godot's skeleton retargeting

enum State {
	SITTING_AWAY,
	NOTICING,
	GETTING_UP,
	STANDING,
	WALKING,
	TALKING,
	CLOSEUP,
	SITTING_DOWN,
}

signal state_changed(new_state: State)

var current_state: State = State.SITTING_AWAY
var state_timer: float = 0.0
var last_mouse_move: float = 0.0
var mouse_position: Vector2 = Vector2(0.5, 0.5)

# Timings
const IDLE_TIMEOUT := 30.0
const NOTICE_DURATION := 0.6
const GETUP_DURATION := 1.5
const SITDOWN_DURATION := 1.2

# Movement
var move_direction: float = 1.0
var move_speed: float = 0.5
var move_bounds := Vector2(-5.0, 5.0)
var is_moving := false

# Animation player reference (set when model loads)
var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null

func _ready() -> void:
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		last_mouse_move = Time.get_ticks_msec() / 1000.0
		mouse_position = event.position / Vector2(
			get_viewport().get_visible_rect().size
		)

		if current_state == State.SITTING_AWAY:
			_change_state(State.NOTICING)

func update(model: Node3D, delta: float, camera: Camera3D) -> void:
	if not model:
		return

	state_timer += delta
	var now := Time.get_ticks_msec() / 1000.0

	match current_state:
		State.SITTING_AWAY:
			model.rotation.y = PI
			model.position.y = -1.4

		State.NOTICING:
			model.rotation.y = PI
			model.position.y = -1.4
			# Head turn handled by animation blend
			if state_timer >= NOTICE_DURATION:
				_change_state(State.GETTING_UP)

		State.GETTING_UP:
			var t := clampf(state_timer / GETUP_DURATION, 0.0, 1.0)
			var ease_t := t * t * (3.0 - 2.0 * t)  # smoothstep
			model.rotation.y = PI * (1.0 - ease_t)
			model.position.y = -1.4 + 1.0 * ease_t
			if state_timer >= GETUP_DURATION:
				_change_state(State.STANDING)

		State.STANDING:
			model.position.y = -0.4
			if now - last_mouse_move > IDLE_TIMEOUT:
				_change_state(State.SITTING_DOWN)

		State.WALKING:
			model.position.y = -0.4
			_update_movement(model, delta)
			if now - last_mouse_move > IDLE_TIMEOUT:
				_change_state(State.SITTING_DOWN)

		State.TALKING:
			model.position.y = -0.4
			model.rotation.y = 0.0
			_update_head_tracking(model, delta)

		State.CLOSEUP:
			model.position.y = -0.4
			model.rotation.y = 0.0
			_update_head_tracking(model, delta)

		State.SITTING_DOWN:
			var t := clampf(state_timer / SITDOWN_DURATION, 0.0, 1.0)
			var ease_t := t * t * (3.0 - 2.0 * t)
			model.rotation.y = PI * ease_t
			model.position.y = -0.4 - 1.0 * ease_t
			if state_timer >= SITDOWN_DURATION:
				_change_state(State.SITTING_AWAY)

func _change_state(new_state: State) -> void:
	current_state = new_state
	state_timer = 0.0
	state_changed.emit(new_state)
	print("[awareness] → ", State.keys()[new_state])

func _update_movement(model: Node3D, delta: float) -> void:
	model.position.x += move_direction * move_speed * delta

	if model.position.x > move_bounds.y:
		model.position.x = move_bounds.y
		move_direction = -1.0
	elif model.position.x < move_bounds.x:
		model.position.x = move_bounds.x
		move_direction = 1.0

	model.rotation.y = -PI / 2.0 if move_direction > 0 else PI / 2.0

func _update_head_tracking(model: Node3D, delta: float) -> void:
	# Find skeleton and apply head tracking
	var skeleton := _find_skeleton(model)
	if not skeleton:
		return

	var head_idx := skeleton.find_bone("Head")
	var neck_idx := skeleton.find_bone("Neck")

	if head_idx < 0:
		head_idx = skeleton.find_bone("head")
	if neck_idx < 0:
		neck_idx = skeleton.find_bone("neck")

	var yaw := (mouse_position.x - 0.5) * 0.6
	var pitch := (mouse_position.y - 0.5) * -0.3

	if neck_idx >= 0:
		var neck_rot := Quaternion.from_euler(Vector3(pitch * 0.4, yaw * 0.4, 0))
		skeleton.set_bone_pose_rotation(neck_idx, neck_rot)

	if head_idx >= 0:
		var head_rot := Quaternion.from_euler(Vector3(pitch * 0.6, yaw * 0.6, 0))
		skeleton.set_bone_pose_rotation(head_idx, head_rot)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

# External API
func set_talking(talking: bool) -> void:
	if talking and current_state == State.STANDING:
		_change_state(State.TALKING)
	elif not talking and current_state == State.TALKING:
		_change_state(State.STANDING)

func start_walking() -> void:
	if current_state == State.STANDING:
		_change_state(State.WALKING)

func stop_walking() -> void:
	if current_state == State.WALKING:
		_change_state(State.STANDING)
