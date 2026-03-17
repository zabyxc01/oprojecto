extends Node
class_name WindowLayer

# X11 window management — below/above toggling
# Uses xprop to set window state (same approach, native Godot execution)

static var _is_below := false

static func set_below() -> void:
	var window_id := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	var args := PackedStringArray([
		"-id", str(window_id),
		"-f", "_NET_WM_STATE", "32a",
		"-set", "_NET_WM_STATE", "_NET_WM_STATE_BELOW"
	])
	OS.execute("xprop", args)
	_is_below = true
	print("[window] Set BELOW: ", window_id)

static func set_foreground() -> void:
	var window_id := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	var args := PackedStringArray([
		"-id", str(window_id),
		"-f", "_NET_WM_STATE", "32a",
		"-set", "_NET_WM_STATE", "0"
	])
	OS.execute("xprop", args)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_is_below = false
	print("[window] Set FOREGROUND: ", window_id)

static func toggle() -> bool:
	if _is_below:
		set_foreground()
	else:
		set_below()
	return _is_below

static func is_below() -> bool:
	return _is_below

# Detect if a fullscreen app is running (for auto-hide during gaming)
static func is_fullscreen_app_active() -> bool:
	var output := []
	OS.execute("xprop", ["-root", "_NET_ACTIVE_WINDOW"], output)
	if output.is_empty():
		return false

	# Get the active window ID and check if it's fullscreen
	var active_str: String = output[0]
	var parts := active_str.split("# ")
	if parts.size() < 2:
		return false

	var active_id := parts[1].strip_edges()
	var state_output := []
	OS.execute("xprop", ["-id", active_id, "_NET_WM_STATE"], state_output)
	if state_output.is_empty():
		return false

	return "_NET_WM_STATE_FULLSCREEN" in state_output[0]
