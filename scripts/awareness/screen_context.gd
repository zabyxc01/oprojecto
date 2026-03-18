extends Node
class_name ScreenContext

## Polls the X11 desktop environment for context information.
## Emits context_changed when something meaningful changes.
##
## Polls every poll_interval seconds (default 5). Only emits when the
## context actually differs from the previous poll.

signal context_changed(context: Dictionary)

var poll_interval := 5.0
var _timer := 0.0
var _last_context := {}

# Known app patterns for classification
const APP_PATTERNS := {
	"steam": "gaming",
	"elden ring": "gaming",
	"dark souls": "gaming",
	"baldur": "gaming",
	"cyberpunk": "gaming",
	"firefox": "browsing",
	"chromium": "browsing",
	"chrome": "browsing",
	"brave": "browsing",
	"code": "coding",
	"codium": "coding",
	"neovim": "coding",
	"vim": "coding",
	"godot": "coding",
	"discord": "chatting",
	"slack": "chatting",
	"telegram": "chatting",
	"spotify": "music",
	"vlc": "media",
	"mpv": "media",
	"obs": "streaming",
	"gimp": "creative",
	"blender": "creative",
	"krita": "creative",
	"terminal": "terminal",
	"konsole": "terminal",
	"dolphin": "files",
	"nautilus": "files",
}


func update(delta: float) -> void:
	_timer += delta
	if _timer < poll_interval:
		return
	_timer = 0.0

	var context = _poll_context()
	if _context_differs(context, _last_context):
		_last_context = context
		context_changed.emit(context)


func get_current() -> Dictionary:
	return _last_context


func force_poll() -> Dictionary:
	var context = _poll_context()
	if _context_differs(context, _last_context):
		_last_context = context
		context_changed.emit(context)
	return context


func _poll_context() -> Dictionary:
	var context := {}

	# Active window title
	context["window_title"] = _get_active_window_title()

	# Classify what the user is doing
	context["activity"] = _classify_activity(context["window_title"])

	# Idle time (milliseconds since last input)
	context["idle_ms"] = _get_idle_time()
	context["idle_minutes"] = context["idle_ms"] / 60000.0

	# Time of day
	var time_dict = Time.get_time_dict_from_system()
	context["hour"] = time_dict["hour"]
	context["time_of_day"] = _classify_time(time_dict["hour"])

	# Is audio playing? (check PipeWire sink state)
	context["audio_playing"] = _check_audio_playing()

	return context


func _get_active_window_title() -> String:
	var output := []
	var exit = OS.execute("xdotool", ["getactivewindow", "getwindowname"], output, true)
	if exit == 0 and output.size() > 0:
		return output[0].strip_edges()
	return ""


func _get_idle_time() -> int:
	# Try xprintidle first
	var output := []
	var exit = OS.execute("xprintidle", [], output, true)
	if exit == 0 and output.size() > 0:
		return output[0].strip_edges().to_int()

	# Fallback: xdotool getactivewindow doesn't give idle,
	# but we can use xssstate or default to 0
	return 0


func _check_audio_playing() -> bool:
	var output := []
	# Check if any PipeWire sink is RUNNING
	var exit = OS.execute("bash", ["-c", "pactl list short sinks | grep RUNNING"], output, true)
	return exit == 0 and output.size() > 0 and output[0].strip_edges() != ""


func _classify_activity(window_title: String) -> String:
	var title_lower = window_title.to_lower()
	for pattern in APP_PATTERNS:
		if pattern in title_lower:
			return APP_PATTERNS[pattern]
	return "unknown"


func _classify_time(hour: int) -> String:
	if hour < 6:
		return "late_night"
	elif hour < 12:
		return "morning"
	elif hour < 17:
		return "afternoon"
	elif hour < 21:
		return "evening"
	else:
		return "night"


func _context_differs(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() != b.is_empty():
		return true
	# Meaningful change: window title, activity, or idle state changed
	if a.get("window_title", "") != b.get("window_title", ""):
		return true
	if a.get("activity", "") != b.get("activity", ""):
		return true
	# Idle threshold transitions
	var a_idle = a.get("idle_minutes", 0.0)
	var b_idle = b.get("idle_minutes", 0.0)
	# Crossed a threshold: 1min, 5min, 10min
	for threshold in [1.0, 5.0, 10.0]:
		if (a_idle < threshold) != (b_idle < threshold):
			return true
	return false
