extends Node
class_name DesktopPhysics

## Desktop physics system — makes Kira physically interact with the desktop.
##
## Handles: taskbar standing, window perching, dragging, cursor tracking,
## gravity (falling when a surface disappears), and idle walking.
##
## Call setup() with the avatar root and camera, then call update(delta)
## every frame from _process.

# ── Signals ───────────────────────────────────────────────────────────────────
signal position_changed(screen_pos: Vector2)
signal state_changed(new_state: String)
signal drag_started
signal drag_ended
signal fell
signal walking(direction: int)
signal cursor_position(screen_pos: Vector2)

# ── State enum ────────────────────────────────────────────────────────────────
enum State { STANDING, SITTING, WALKING, FALLING, DRAGGED }

# ── Configuration ─────────────────────────────────────────────────────────────
## Taskbar height in pixels (KDE default panel).
var taskbar_height := 48

## Walking speed in world units per second.
var walk_speed := 0.3

## Gravity acceleration in world units per second squared.
var gravity := 4.0

## Maximum fall velocity.
var terminal_velocity := 6.0

## Radius (in screen pixels) within which the cursor triggers tracking.
var cursor_track_radius := 600.0

## How often to poll X11 window geometry (seconds).
var window_poll_interval := 2.0

## Margin from screen edges where the avatar turns around (pixels).
var edge_margin := 100.0

## Idle time range before starting a walk (seconds). Picks a random value.
var walk_idle_range := Vector2(8.0, 20.0)

## Walk duration range (seconds). Picks a random value.
var walk_duration_range := Vector2(3.0, 8.0)

# ── Internal state ────────────────────────────────────────────────────────────
var current_state: State = State.STANDING

var _avatar_root: Node3D = null
var _camera: Camera3D = null
var _initialized := false

# Screen dimensions (queried once in setup, refreshed on resize).
var _screen_size := Vector2(3440, 1440)

# World-space Y coordinate that corresponds to the taskbar top edge.
var _taskbar_world_y := 0.0

# The avatar's current world position target (we lerp toward this).
var _target_world_pos := Vector3.ZERO

# Falling state
var _fall_velocity := 0.0

# Dragging state
var _drag_offset := Vector2.ZERO  # screen offset from avatar center to mouse

# Walking state
var _walk_direction := 0  # -1 left, 0 stopped, 1 right
var _walk_timer := 0.0
var _walk_duration := 0.0
var _idle_timer := 0.0
var _next_idle_wait := 0.0

# Perched window tracking
var _perched_window_title := ""
var _perched_window_rect := Rect2()  # screen-space rect of the window
var _window_poll_timer := 0.0

# Cursor tracking
var _last_cursor_screen_pos := Vector2.ZERO


# ── Public API ────────────────────────────────────────────────────────────────

func setup(avatar_root: Node3D, camera: Camera3D) -> void:
	_avatar_root = avatar_root
	_camera = camera
	_initialized = true

	_screen_size = Vector2(DisplayServer.window_get_size())
	if _screen_size.x < 1.0:
		_screen_size = Vector2(3440, 1440)

	# Calculate the world-space Y that corresponds to the taskbar top.
	_taskbar_world_y = _screen_y_to_world_y(_screen_size.y - taskbar_height)

	# Place avatar on the taskbar initially.
	_target_world_pos = _avatar_root.position
	_target_world_pos.y = _taskbar_world_y
	_avatar_root.position = _target_world_pos

	_reset_idle_timer()
	print("[desktop_physics] Setup complete. Taskbar world Y: ", _taskbar_world_y,
		" screen: ", _screen_size)


func update(delta: float) -> void:
	if not _initialized or not _avatar_root or not _camera:
		return

	match current_state:
		State.STANDING:
			_update_standing(delta)
		State.SITTING:
			_update_sitting(delta)
		State.WALKING:
			_update_walking(delta)
		State.FALLING:
			_update_falling(delta)
		State.DRAGGED:
			_update_dragged(delta)

	_update_cursor_tracking()

	# Emit screen position
	var screen_pos = _world_to_screen(_avatar_root.position)
	position_changed.emit(screen_pos)


func set_taskbar_height(height: int) -> void:
	taskbar_height = height
	if _initialized:
		_taskbar_world_y = _screen_y_to_world_y(_screen_size.y - taskbar_height)
		# If standing, update position
		if current_state == State.STANDING or current_state == State.WALKING:
			_target_world_pos.y = _taskbar_world_y


func start_drag(mouse_pos: Vector2) -> void:
	if current_state == State.DRAGGED:
		return
	var avatar_screen = _world_to_screen(_avatar_root.position + Vector3(0, 0.5, 0))
	_drag_offset = avatar_screen - mouse_pos
	_set_state(State.DRAGGED)
	drag_started.emit()


func end_drag() -> void:
	if current_state != State.DRAGGED:
		return
	drag_ended.emit()
	# Check if we are above the taskbar — if so, fall. Otherwise, land.
	var screen_pos = _world_to_screen(_avatar_root.position)
	if screen_pos.y < _screen_size.y - taskbar_height - 20:
		# Above taskbar — start falling
		_fall_velocity = 0.0
		_set_state(State.FALLING)
	else:
		return_to_taskbar()


func perch_on_window(window_title: String) -> bool:
	var rect = _query_window_geometry(window_title)
	if rect == Rect2():
		print("[desktop_physics] Window not found: ", window_title)
		return false

	_perched_window_title = window_title
	_perched_window_rect = rect

	# Place avatar on top of the window (at the title bar).
	var perch_screen_x = rect.position.x + rect.size.x * 0.5
	var perch_screen_y = rect.position.y  # top edge of the window
	var world_pos = _screen_to_world(Vector2(perch_screen_x, perch_screen_y))
	_target_world_pos = world_pos
	_set_state(State.SITTING)
	print("[desktop_physics] Perched on: ", window_title, " at ", rect)
	return true


func return_to_taskbar() -> void:
	_perched_window_title = ""
	_perched_window_rect = Rect2()
	_target_world_pos.y = _taskbar_world_y
	_set_state(State.STANDING)
	_reset_idle_timer()


# ── State updates ─────────────────────────────────────────────────────────────

func _update_standing(delta: float) -> void:
	# Lerp to target position (snap to taskbar Y).
	_target_world_pos.y = _taskbar_world_y
	_avatar_root.position = _avatar_root.position.lerp(_target_world_pos, delta * 5.0)

	# Count down to idle walk.
	_idle_timer += delta
	if _idle_timer >= _next_idle_wait:
		_start_walking()


func _update_sitting(delta: float) -> void:
	# Lerp to perch position.
	_avatar_root.position = _avatar_root.position.lerp(_target_world_pos, delta * 5.0)

	# Periodically check if the window still exists.
	_window_poll_timer += delta
	if _window_poll_timer >= window_poll_interval:
		_window_poll_timer = 0.0
		if _perched_window_title != "":
			var rect = _query_window_geometry(_perched_window_title)
			if rect == Rect2():
				# Window disappeared — fall!
				print("[desktop_physics] Perched window disappeared, falling")
				_perched_window_title = ""
				_perched_window_rect = Rect2()
				_fall_velocity = 0.0
				_set_state(State.FALLING)
			else:
				# Window may have moved — update perch position.
				_perched_window_rect = rect
				var perch_screen_x = rect.position.x + rect.size.x * 0.5
				var perch_screen_y = rect.position.y
				_target_world_pos = _screen_to_world(
					Vector2(perch_screen_x, perch_screen_y))


func _update_walking(delta: float) -> void:
	_walk_timer += delta

	# Move horizontally in world space.
	var world_step = _walk_direction * walk_speed * delta
	_avatar_root.position.x += world_step
	_target_world_pos.x = _avatar_root.position.x

	# Keep on taskbar Y.
	_avatar_root.position.y = lerpf(_avatar_root.position.y, _taskbar_world_y, delta * 5.0)

	# Check screen edge bounds — turn around.
	var screen_pos = _world_to_screen(_avatar_root.position)
	if screen_pos.x <= edge_margin:
		_walk_direction = 1
		walking.emit(_walk_direction)
	elif screen_pos.x >= _screen_size.x - edge_margin:
		_walk_direction = -1
		walking.emit(_walk_direction)

	# End walk after duration.
	if _walk_timer >= _walk_duration:
		_stop_walking()


func _update_falling(delta: float) -> void:
	# Accelerate downward (world Y is inverted relative to screen Y for ortho).
	_fall_velocity += gravity * delta
	_fall_velocity = minf(_fall_velocity, terminal_velocity)

	# In Godot's orthographic setup, lower screen Y = lower world Y.
	# The taskbar is at the bottom of the screen, which is a lower world Y.
	# Move avatar toward taskbar.
	var direction = signf(_taskbar_world_y - _avatar_root.position.y)
	_avatar_root.position.y += direction * _fall_velocity * delta

	# Check if we have reached (or passed) the taskbar.
	var past_taskbar: bool
	if direction >= 0:
		past_taskbar = _avatar_root.position.y >= _taskbar_world_y
	else:
		past_taskbar = _avatar_root.position.y <= _taskbar_world_y

	if past_taskbar:
		_avatar_root.position.y = _taskbar_world_y
		_target_world_pos = _avatar_root.position
		_fall_velocity = 0.0
		fell.emit()
		_set_state(State.STANDING)
		_reset_idle_timer()
		print("[desktop_physics] Landed on taskbar")


func _update_dragged(_delta: float) -> void:
	var mouse_screen = Vector2(get_viewport().get_mouse_position())
	# Apply offset so the avatar doesn't snap to cursor center.
	var target_screen = mouse_screen + _drag_offset
	var world_pos = _screen_to_world(target_screen)
	# Lerp for slight smoothness during drag.
	_avatar_root.position = _avatar_root.position.lerp(world_pos, _delta * 15.0)
	_target_world_pos = _avatar_root.position


# ── Cursor tracking ──────────────────────────────────────────────────────────

func _update_cursor_tracking() -> void:
	var mouse_screen = Vector2(get_viewport().get_mouse_position())
	var avatar_screen = _world_to_screen(
		_avatar_root.position + Vector3(0, 0.5, 0))
	var dist = mouse_screen.distance_to(avatar_screen)

	if dist <= cursor_track_radius:
		_last_cursor_screen_pos = mouse_screen
		cursor_position.emit(mouse_screen)


# ── Walking helpers ──────────────────────────────────────────────────────────

func _start_walking() -> void:
	# Pick a random direction.
	_walk_direction = 1 if randf() > 0.5 else -1

	# Check which direction has more room.
	var screen_pos = _world_to_screen(_avatar_root.position)
	if screen_pos.x < _screen_size.x * 0.3:
		_walk_direction = 1  # near left edge, walk right
	elif screen_pos.x > _screen_size.x * 0.7:
		_walk_direction = -1  # near right edge, walk left

	_walk_timer = 0.0
	_walk_duration = randf_range(walk_duration_range.x, walk_duration_range.y)
	_set_state(State.WALKING)
	walking.emit(_walk_direction)


func _stop_walking() -> void:
	_walk_direction = 0
	walking.emit(0)
	_set_state(State.STANDING)
	_reset_idle_timer()


func _reset_idle_timer() -> void:
	_idle_timer = 0.0
	_next_idle_wait = randf_range(walk_idle_range.x, walk_idle_range.y)


# ── Coordinate conversion ───────────────────────────────────────────────────
#
# The transparent window covers the full screen, so screen coords = viewport
# coords. The camera is orthographic, facing -Z. We project between screen
# space and world space using the Camera3D projection helpers.

func _world_to_screen(world_pos: Vector3) -> Vector2:
	if not _camera:
		return Vector2.ZERO
	return _camera.unproject_position(world_pos)


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	## Convert a screen position to a world position on the avatar's Z plane.
	if not _camera:
		return Vector3.ZERO
	var origin = _camera.project_ray_origin(screen_pos)
	var direction = _camera.project_ray_normal(screen_pos)
	# Intersect with the plane at Z = avatar Z (typically 0).
	var avatar_z = _avatar_root.position.z if _avatar_root else 0.0
	if absf(direction.z) < 0.0001:
		return Vector3(origin.x, origin.y, avatar_z)
	var t = (avatar_z - origin.z) / direction.z
	return origin + direction * t


func _screen_y_to_world_y(screen_y: float) -> float:
	## Convert a screen Y coordinate to a world Y coordinate.
	var world_pos = _screen_to_world(Vector2(_screen_size.x * 0.5, screen_y))
	return world_pos.y


# ── X11 window queries ──────────────────────────────────────────────────────

func _query_window_geometry(window_title: String) -> Rect2:
	## Query X11 for a window's geometry by title. Returns Rect2() on failure.
	## Uses xdotool search + getwindowgeometry.
	var output := []
	# First, find window IDs matching the title.
	var exit_code = OS.execute("xdotool",
		["search", "--name", window_title], output, true)
	if exit_code != 0 or output.is_empty():
		return Rect2()

	var window_ids_str: String = output[0].strip_edges()
	if window_ids_str.is_empty():
		return Rect2()

	# Take the first matching window ID.
	var lines = window_ids_str.split("\n", false)
	if lines.is_empty():
		return Rect2()
	var wid = lines[0].strip_edges()

	# Get geometry for this window.
	output.clear()
	exit_code = OS.execute("xdotool",
		["getwindowgeometry", "--shell", wid], output, true)
	if exit_code != 0 or output.is_empty():
		return Rect2()

	return _parse_window_geometry(output[0])


func _query_active_window_geometry() -> Rect2:
	## Query the active (focused) window's geometry.
	var output := []
	var exit_code = OS.execute("xdotool",
		["getactivewindow", "getwindowgeometry", "--shell"], output, true)
	if exit_code != 0 or output.is_empty():
		return Rect2()
	return _parse_window_geometry(output[0])


func _parse_window_geometry(raw: String) -> Rect2:
	## Parse xdotool --shell geometry output into a Rect2.
	## Format:
	##   WINDOW=12345
	##   X=100
	##   Y=200
	##   WIDTH=800
	##   HEIGHT=600
	var x := 0
	var y := 0
	var w := 0
	var h := 0

	for line in raw.split("\n", false):
		line = line.strip_edges()
		if line.begins_with("X="):
			x = line.substr(2).to_int()
		elif line.begins_with("Y="):
			y = line.substr(2).to_int()
		elif line.begins_with("WIDTH="):
			w = line.substr(6).to_int()
		elif line.begins_with("HEIGHT="):
			h = line.substr(7).to_int()

	if w <= 0 or h <= 0:
		return Rect2()
	return Rect2(x, y, w, h)


# ── State management ─────────────────────────────────────────────────────────

func _set_state(new_state: State) -> void:
	if new_state == current_state:
		return
	var old_name = _state_name(current_state)
	current_state = new_state
	var new_name = _state_name(new_state)
	print("[desktop_physics] ", old_name, " -> ", new_name)
	state_changed.emit(new_name)


func _state_name(s: State) -> String:
	match s:
		State.STANDING: return "standing"
		State.SITTING: return "sitting"
		State.WALKING: return "walking"
		State.FALLING: return "falling"
		State.DRAGGED: return "dragged"
	return "unknown"


func get_state_name() -> String:
	return _state_name(current_state)
