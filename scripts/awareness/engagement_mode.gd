extends Node
class_name EngagementMode

enum Mode { CHAT_ONLY, AWARE, LIVE }
signal mode_changed(new_mode: String)

var current_mode: Mode = Mode.CHAT_ONLY

func set_mode(mode: Mode) -> void:
	current_mode = mode
	mode_changed.emit(get_mode_name())

func get_mode_name() -> String:
	match current_mode:
		Mode.CHAT_ONLY: return "chat_only"
		Mode.AWARE: return "aware"
		Mode.LIVE: return "live"
	return "aware"

func set_mode_by_name(name: String) -> void:
	match name:
		"chat_only": set_mode(Mode.CHAT_ONLY)
		"aware": set_mode(Mode.AWARE)
		"live": set_mode(Mode.LIVE)
