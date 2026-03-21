extends Node

## Category-based log filter. Toggle categories on/off at runtime.
## Autoloaded as DebugLog singleton.
## Usage: DebugLog.log("anim", "Playing: Idle")

var enabled_categories := {
	"anim": true,
	"expr_mgr": true,
	"desktop_physics": true,
	"pipeline": true,
	"behavior": true,
	"ambient": true,
	"hub": true,
	"main": true,
	"screen_capture": true,
	"screen_listen": true,
	"mapper": true,
	"loader": true,
	"expressions": true,
	"lipsync": true,
	"config": true,
	"conn": true,
}


func log(category: String, msg: String) -> void:
	if enabled_categories.get(category, true):
		print("[%s] %s" % [category, msg])


func set_category(category: String, on: bool) -> void:
	enabled_categories[category] = on


func toggle_category(category: String) -> void:
	enabled_categories[category] = not enabled_categories.get(category, true)


func set_all(on: bool) -> void:
	for key in enabled_categories:
		enabled_categories[key] = on
