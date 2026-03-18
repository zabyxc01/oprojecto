extends Node
class_name AvatarAwareness

enum State { IDLE, CLOSEUP }

signal state_changed(new_state: State)

var current_state: State = State.IDLE
var mouse_position := Vector2(0.5, 0.5)

# Idle position (right side of screen)
const IDLE_POS := Vector3(1.2, -0.4, 0.0)
# Center stage position
const CENTER_POS := Vector3(0.0, -0.4, 0.0)

# Smooth movement
var _target_pos := IDLE_POS
var _move_speed := 3.0

# Camera zoom/position (only active in CLOSEUP)
var _camera_ref: Camera3D = null
var _base_camera_size := 2.24
var _zoom_level := 1.0  # 1.0 = default, smaller = zoomed in
var _y_offset := 0.0    # vertical offset from center pos

func _process(_dt: float) -> void:
	var mpos = get_viewport().get_mouse_position()
	var vsize = get_viewport().get_visible_rect().size
	if vsize.x > 0 and vsize.y > 0:
		mouse_position = mpos / vsize

func update(model: Node3D, delta: float, camera: Camera3D) -> void:
	if not model:
		return
	_camera_ref = camera

	# Apply Y offset in closeup mode
	var target = _target_pos
	if current_state == State.CLOSEUP:
		target = Vector3(CENTER_POS.x, CENTER_POS.y + _y_offset, CENTER_POS.z)

	# Smooth position lerp
	model.position = model.position.lerp(target, delta * _move_speed)
	model.rotation.y = 0.0

	# Smooth zoom
	if camera:
		var target_size = _base_camera_size * _zoom_level
		camera.size = lerp(camera.size, target_size, delta * _move_speed)

	# Head tracking in both states
	_update_head_tracking(model)

func set_closeup(enabled: bool) -> void:
	if enabled:
		current_state = State.CLOSEUP
		_target_pos = CENTER_POS
	else:
		current_state = State.IDLE
		_target_pos = IDLE_POS
		# Reset zoom and offset when leaving closeup
		_zoom_level = 1.0
		_y_offset = 0.0
	state_changed.emit(current_state)
	print("[awareness] → ", State.keys()[current_state])

func toggle_closeup() -> void:
	set_closeup(current_state != State.CLOSEUP)

func zoom_in() -> void:
	_zoom_level = maxf(_zoom_level - 0.15, 0.3)

func zoom_out() -> void:
	_zoom_level = minf(_zoom_level + 0.15, 3.0)

func move_up() -> void:
	_y_offset += 0.1

func move_down() -> void:
	_y_offset -= 0.1

func set_talking(talking: bool) -> void:
	pass

func _update_head_tracking(model: Node3D) -> void:
	var skeleton = _find_skeleton(model)
	if not skeleton:
		return

	var head_idx = skeleton.find_bone("Head")
	var neck_idx = skeleton.find_bone("Neck")
	if head_idx < 0:
		head_idx = skeleton.find_bone("head")
	if neck_idx < 0:
		neck_idx = skeleton.find_bone("neck")

	var yaw = (mouse_position.x - 0.5) * 0.6
	var pitch = (mouse_position.y - 0.5) * -0.3

	if neck_idx >= 0:
		skeleton.set_bone_pose_rotation(neck_idx, Quaternion.from_euler(Vector3(pitch * 0.4, yaw * 0.4, 0)))
	if head_idx >= 0:
		skeleton.set_bone_pose_rotation(head_idx, Quaternion.from_euler(Vector3(pitch * 0.6, yaw * 0.6, 0)))

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null
