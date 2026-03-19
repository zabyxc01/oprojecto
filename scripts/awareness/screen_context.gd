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

	# Audio sources — what apps are actively playing audio (PipeWire)
	var audio_sources = _get_audio_sources()
	context["audio_playing"] = audio_sources.size() > 0
	context["audio_sources"] = audio_sources  # [{app, title, binary}]

	# Background activity — what's playing even if not focused
	context["background_media"] = _extract_background_media(audio_sources, context["window_title"])

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


func _get_audio_sources() -> Array:
	"""Query PipeWire for apps actively playing audio. Returns [{app, title, binary}]."""
	var output := []
	# pw-dump gives full JSON of all PipeWire objects — parse for running playback streams
	var exit = OS.execute("bash", ["-c",
		"pw-dump 2>/dev/null | python3 -c \""
		+ "import json,sys\\n"
		+ "data=json.load(sys.stdin)\\n"
		+ "for o in data:\\n"
		+ "  p=o.get('info',{}).get('props',{})\\n"
		+ "  mc=p.get('media.class','')\\n"
		+ "  if 'Playback' in mc:\\n"
		+ "    s=o.get('info',{}).get('state','')\\n"
		+ "    if s=='running':\\n"
		+ "      a=p.get('application.name','')\\n"
		+ "      m=p.get('media.name','')\\n"
		+ "      b=p.get('application.process.binary','')\\n"
		+ "      if a and a not in ('plasmashell','pipewire','WirePlumber'):\\n"
		+ "        print(a+'|'+m+'|'+b)\\n"
		+ "\""
	], output, true)
	var sources := []
	if exit == 0 and output.size() > 0:
		for line in output[0].strip_edges().split("\n"):
			if line.is_empty():
				continue
			var parts = line.split("|")
			if parts.size() >= 3:
				sources.append({
					"app": parts[0],
					"title": parts[1],
					"binary": parts[2],
				})
	return sources


func _extract_background_media(audio_sources: Array, focused_title: String) -> String:
	"""Extract what's playing in the background (not the focused window)."""
	for src in audio_sources:
		var app: String = src.get("app", "")
		var title: String = src.get("title", "")
		# Skip if this is the focused app (godot/oprojecto is us)
		if app.to_lower() == "oprojecto" or src.get("binary", "") == "godot":
			continue
		# Check if the audio source app is NOT the focused window
		if app.to_lower() not in focused_title.to_lower():
			# This is background audio — extract useful info
			if "youtube" in title.to_lower() or "youtu" in title.to_lower():
				# Extract YT video title — format is usually "(tabid) Title - YouTube"
				var yt_title = title
				# Strip leading tab IDs like "(1234) "
				var paren_end = yt_title.find(") ")
				if paren_end > 0 and paren_end < 10:
					yt_title = yt_title.substr(paren_end + 2)
				# Strip " - YouTube" suffix
				if yt_title.ends_with(" - YouTube"):
					yt_title = yt_title.substr(0, yt_title.length() - 10)
				return "watching YouTube: " + yt_title
			elif "spotify" in app.to_lower() or "music" in title.to_lower():
				return "listening to music: " + title
			elif "twitch" in title.to_lower():
				return "watching Twitch: " + title
			else:
				return app + " playing: " + title
	return ""


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
	# Background media changed (new video, new song)
	if a.get("background_media", "") != b.get("background_media", ""):
		return true
	# Audio started or stopped
	if a.get("audio_playing", false) != b.get("audio_playing", false):
		return true
	# Idle threshold transitions
	var a_idle: float = a.get("idle_minutes", 0.0)
	var b_idle: float = b.get("idle_minutes", 0.0)
	for threshold in [1.0, 5.0, 10.0]:
		if (a_idle < threshold) != (b_idle < threshold):
			return true
	return false
