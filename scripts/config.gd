extends Node
class_name AppConfig

# Persistent configuration — saves to user://config.json
# Covers: chat UI appearance, window settings, pipeline defaults

const CONFIG_PATH := "user://config.json"

# Defaults
var chat_width := 340
var chat_font_size := 13
var chat_bubble_user_color := Color(0.2, 0.25, 0.55, 0.7)
var chat_bubble_kira_color := Color(0.12, 0.12, 0.16, 0.7)
var chat_text_user_color := Color(0.95, 0.95, 1.0)
var chat_text_kira_color := Color(0.85, 0.88, 0.92)
var chat_input_bg_color := Color(0.1, 0.1, 0.14, 0.6)
var sys_log_color := Color(0.6, 0.6, 0.7, 0.9)
var window_width := 3440
var window_height := 1440
var window_fullscreen := true
var taskbar_height := 40

signal config_changed

func _ready() -> void:
	load_config()

func load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		save_config()  # create default
		return
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data or not data is Dictionary:
		return

	# Apply loaded values
	chat_width = data.get("chat_width", chat_width)
	chat_font_size = data.get("chat_font_size", chat_font_size)
	chat_bubble_user_color = _parse_color(data.get("chat_bubble_user_color"), chat_bubble_user_color)
	chat_bubble_kira_color = _parse_color(data.get("chat_bubble_kira_color"), chat_bubble_kira_color)
	chat_text_user_color = _parse_color(data.get("chat_text_user_color"), chat_text_user_color)
	chat_text_kira_color = _parse_color(data.get("chat_text_kira_color"), chat_text_kira_color)
	chat_input_bg_color = _parse_color(data.get("chat_input_bg_color"), chat_input_bg_color)
	sys_log_color = _parse_color(data.get("sys_log_color"), sys_log_color)
	window_width = data.get("window_width", window_width)
	window_height = data.get("window_height", window_height)
	window_fullscreen = data.get("window_fullscreen", window_fullscreen)
	taskbar_height = data.get("taskbar_height", taskbar_height)
	print("[config] Loaded from ", CONFIG_PATH)

func save_config() -> void:
	var data = {
		"chat_width": chat_width,
		"chat_font_size": chat_font_size,
		"chat_bubble_user_color": _color_to_str(chat_bubble_user_color),
		"chat_bubble_kira_color": _color_to_str(chat_bubble_kira_color),
		"chat_text_user_color": _color_to_str(chat_text_user_color),
		"chat_text_kira_color": _color_to_str(chat_text_kira_color),
		"chat_input_bg_color": _color_to_str(chat_input_bg_color),
		"sys_log_color": _color_to_str(sys_log_color),
		"window_width": window_width,
		"window_height": window_height,
		"window_fullscreen": window_fullscreen,
		"taskbar_height": taskbar_height,
	}
	var file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	print("[config] Saved to ", CONFIG_PATH)

func set_value(key: String, value) -> void:
	set(key, value)
	save_config()
	config_changed.emit()

func _color_to_str(c: Color) -> String:
	return c.to_html(true)

func _parse_color(val, fallback: Color) -> Color:
	if val == null or val == "":
		return fallback
	return Color.html(val)
