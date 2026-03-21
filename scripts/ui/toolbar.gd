extends PanelContainer
class_name Toolbar

## F3 toolbar — full configuration panel for Kira.
## Sections: Avatar, Voice, Behavior, Display

signal model_selected(index: int)
signal anim_selected(index: int)
signal tts_selected(index: int)
signal width_changed(value: float)
signal font_changed(value: float)
signal voice_enabled_changed(enabled: bool)
signal mic_enabled_changed(enabled: bool)
signal engagement_mode_changed(mode: String)
signal screenshot_interval_changed(value: float)
signal audio_interval_changed(value: float)
signal focus_window_changed(window_title: String)
signal screen_listen_changed(enabled: bool)
signal reaction_speed_changed(value: float)  # ambient min_interval in seconds
signal initiation_changed(value: float)  # 0.0-1.0
signal resource_preset_changed(preset: String)  # max_quality, optimal, lite, gaming
signal llm_model_changed(model_name: String)  # ollama model name

var _auto_toggle: CheckButton
var model_selector: OptionButton
var anim_selector: OptionButton
var tts_selector: OptionButton
var _engagement_selector: OptionButton
var _aware_sub_selector: OptionButton
var _aware_sub_row: HBoxContainer
var _voice_toggle: CheckButton
var _mic_toggle: CheckButton
var _focus_selector: OptionButton
var _focus_refresh_btn: Button
var _screen_listen_toggle: CheckButton
var _screen_listen_row: HBoxContainer
var _screenshot_slider: HSlider
var _screenshot_row: HBoxContainer
var _screenshot_label: Label
var _audio_slider: HSlider
var _audio_row: HBoxContainer
var _audio_label: Label
var _reaction_slider: HSlider
var _reaction_row: HBoxContainer
var _reaction_label: Label
var _initiation_slider: HSlider
var _initiation_row: HBoxContainer
var _initiation_label: Label
var _focus_row: HBoxContainer
var _status_label: Label
var _llm_selector_ref: OptionButton
var _preset_selector_ref: OptionButton

const MODELS_DIR := "/mnt/storage/staging/ai-models-animations/vrm-models/"


func build(config: Node) -> void:
	var tb_style = StyleBoxFlat.new()
	tb_style.bg_color = Color(0.06, 0.06, 0.08, 0.92)
	tb_style.corner_radius_top_left = 10
	tb_style.corner_radius_top_right = 10
	tb_style.corner_radius_bottom_left = 10
	tb_style.corner_radius_bottom_right = 10
	tb_style.content_margin_left = 12
	tb_style.content_margin_right = 12
	tb_style.content_margin_top = 10
	tb_style.content_margin_bottom = 10
	tb_style.border_width_bottom = 1
	tb_style.border_width_top = 1
	tb_style.border_width_left = 1
	tb_style.border_width_right = 1
	tb_style.border_color = Color(0.2, 0.2, 0.25, 0.5)

	add_theme_stylebox_override("panel", tb_style)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(10, 10)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(380, 0)

	var tb_vbox = VBoxContainer.new()
	tb_vbox.add_theme_constant_override("separation", 6)
	add_child(tb_vbox)

	# ── Title ──────────────────────────────────────────────────────
	var title = Label.new()
	title.text = "KIRA SETTINGS"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tb_vbox.add_child(title)

	_add_separator(tb_vbox)

	# ══ AVATAR SECTION ═════════════════════════════════════════════
	_add_section_label(tb_vbox, "AVATAR")

	# Model
	var row_model = HBoxContainer.new()
	tb_vbox.add_child(row_model)
	_add_label(row_model, "Model:")
	model_selector = _add_dropdown(row_model, 200)
	model_selector.add_item("default", 0)
	var mdir = DirAccess.open(MODELS_DIR)
	if mdir:
		mdir.list_dir_begin()
		var mfile = mdir.get_next()
		var midx = 1
		while mfile != "":
			if mfile.ends_with(".vrm") or mfile.ends_with(".glb"):
				model_selector.add_item(mfile.get_basename(), midx)
				midx += 1
			mfile = mdir.get_next()
	model_selector.item_selected.connect(func(idx): model_selected.emit(idx))

	# Animation
	var row_anim = HBoxContainer.new()
	tb_vbox.add_child(row_anim)
	_add_label(row_anim, "Animation:")
	anim_selector = _add_dropdown(row_anim, 200)
	anim_selector.add_item("(auto)", 0)
	anim_selector.item_selected.connect(func(idx): anim_selected.emit(idx))

	_add_separator(tb_vbox)

	# ══ RESOURCE PRESET ════════════════════════════════════════════
	_add_section_label(tb_vbox, "RESOURCE PRESET")
	var row_preset = HBoxContainer.new()
	tb_vbox.add_child(row_preset)
	_add_label(row_preset, "Mode:")
	var preset_selector = _add_dropdown(row_preset, 160)
	_preset_selector_ref = preset_selector
	preset_selector.add_item("Max Quality (~10GB)", 0)
	preset_selector.add_item("Optimal (~6GB)", 1)
	preset_selector.add_item("Lite (~3GB)", 2)
	preset_selector.add_item("Gaming (0 VRAM)", 3)
	preset_selector.select(1)  # default: optimal
	preset_selector.mouse_filter = Control.MOUSE_FILTER_STOP
	preset_selector.item_selected.connect(func(idx):
		var presets = ["max_quality", "optimal", "lite", "gaming"]
		if idx < presets.size():
			resource_preset_changed.emit(presets[idx])
	)

	_add_separator(tb_vbox)

	# ══ LLM MODEL ══════════════════════════════════════════════════
	_add_section_label(tb_vbox, "LLM MODEL")
	var row_llm = HBoxContainer.new()
	tb_vbox.add_child(row_llm)
	_add_label(row_llm, "Chat:")
	var _llm_selector = _add_dropdown(row_llm, 160)
	_llm_selector_ref = _llm_selector
	_llm_selector.add_item("qwen2.5:7b", 0)
	_llm_selector.add_item("gemma3:latest", 1)
	_llm_selector.add_item("llama3.1:8b", 2)
	_llm_selector.add_item("phi-3.5:latest", 3)
	_llm_selector.mouse_filter = Control.MOUSE_FILTER_STOP
	_llm_selector.item_selected.connect(func(idx):
		var model = _llm_selector.get_item_text(idx)
		llm_model_changed.emit(model)
	)

	var _llm_status = Label.new()
	_llm_status.text = ""
	_llm_status.add_theme_font_size_override("font_size", 9)
	_llm_status.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	tb_vbox.add_child(_llm_status)

	_add_separator(tb_vbox)

	# ══ VOICE SECTION ══════════════════════════════════════════════
	_add_section_label(tb_vbox, "VOICE")

	# TTS Engine
	var row_tts = HBoxContainer.new()
	tb_vbox.add_child(row_tts)
	_add_label(row_tts, "TTS Engine:")
	tts_selector = _add_dropdown(row_tts, 140)
	tts_selector.add_item("kokoro", 0)
	tts_selector.add_item("indextts", 1)
	tts_selector.add_item("oaudio", 2)
	tts_selector.add_item("f5", 3)
	tts_selector.item_selected.connect(func(idx): tts_selected.emit(idx))

	# Voice output toggle
	var row_voice = HBoxContainer.new()
	tb_vbox.add_child(row_voice)
	_add_label(row_voice, "Voice Output:")
	_voice_toggle = CheckButton.new()
	_voice_toggle.button_pressed = true
	_voice_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_voice_toggle.toggled.connect(func(on): voice_enabled_changed.emit(on))
	row_voice.add_child(_voice_toggle)

	# Mic input toggle
	var row_mic = HBoxContainer.new()
	tb_vbox.add_child(row_mic)
	_add_label(row_mic, "Mic Input (F2):")
	_mic_toggle = CheckButton.new()
	_mic_toggle.button_pressed = true
	_mic_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_mic_toggle.toggled.connect(func(on): mic_enabled_changed.emit(on))
	row_mic.add_child(_mic_toggle)

	_add_separator(tb_vbox)

	# ══ BEHAVIOR SECTION ═══════════════════════════════════════════
	_add_section_label(tb_vbox, "BEHAVIOR")

	# Autonomous toggle — obvious on/off for all autonomous behavior
	var row_auto = HBoxContainer.new()
	tb_vbox.add_child(row_auto)
	_add_label(row_auto, "Autonomous:")
	_auto_toggle = CheckButton.new()
	_auto_toggle.button_pressed = true  # default: ON (Aware mode)
	_auto_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_auto_toggle.toggled.connect(_on_auto_toggled)
	row_auto.add_child(_auto_toggle)

	# Engagement mode selector
	var row_engage = HBoxContainer.new()
	tb_vbox.add_child(row_engage)
	_add_label(row_engage, "Engagement:")
	_engagement_selector = _add_dropdown(row_engage, 140)
	_engagement_selector.add_item("Chat Only", 0)
	_engagement_selector.add_item("Aware", 1)
	_engagement_selector.add_item("Live", 2)
	_engagement_selector.select(0)  # default: Chat Only
	_engagement_selector.mouse_filter = Control.MOUSE_FILTER_STOP
	_engagement_selector.item_selected.connect(_on_engagement_selected)

	# Style sub-selector (Normal / Focus / Chill) — quick presets, only in Aware
	_aware_sub_row = HBoxContainer.new()
	tb_vbox.add_child(_aware_sub_row)
	_add_label(_aware_sub_row, "Style:")
	_aware_sub_selector = _add_dropdown(_aware_sub_row, 140)
	_aware_sub_selector.add_item("Normal", 0)
	_aware_sub_selector.add_item("Focus", 1)
	_aware_sub_selector.add_item("Chill", 2)
	_aware_sub_selector.mouse_filter = Control.MOUSE_FILTER_STOP
	_aware_sub_selector.item_selected.connect(_on_style_preset_selected)
	_aware_sub_row.visible = true  # visible by default (Aware is default)

	# Reaction Speed slider (15-600s, default 120) — Aware & Live
	_reaction_row = HBoxContainer.new()
	tb_vbox.add_child(_reaction_row)
	_add_label(_reaction_row, "React Speed:")
	_reaction_slider = HSlider.new()
	_reaction_slider.min_value = 15
	_reaction_slider.max_value = 600
	_reaction_slider.value = 120
	_reaction_slider.step = 5
	_reaction_slider.custom_minimum_size = Vector2(100, 0)
	_reaction_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_reaction_row.add_child(_reaction_slider)
	_reaction_label = Label.new()
	_reaction_label.text = "120s"
	_reaction_label.add_theme_font_size_override("font_size", 10)
	_reaction_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_reaction_label.custom_minimum_size = Vector2(40, 0)
	_reaction_row.add_child(_reaction_label)
	_reaction_slider.value_changed.connect(func(v):
		_reaction_label.text = str(int(v)) + "s"
		reaction_speed_changed.emit(v)
	)
	_reaction_row.visible = true  # visible by default (Aware is default)

	# Initiation slider (0-100%, default 15%) — Aware & Live
	_initiation_row = HBoxContainer.new()
	tb_vbox.add_child(_initiation_row)
	_add_label(_initiation_row, "Initiation:")
	_initiation_slider = HSlider.new()
	_initiation_slider.min_value = 0
	_initiation_slider.max_value = 100
	_initiation_slider.value = 15
	_initiation_slider.step = 1
	_initiation_slider.custom_minimum_size = Vector2(100, 0)
	_initiation_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_initiation_row.add_child(_initiation_slider)
	_initiation_label = Label.new()
	_initiation_label.text = "15%"
	_initiation_label.add_theme_font_size_override("font_size", 10)
	_initiation_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_initiation_label.custom_minimum_size = Vector2(40, 0)
	_initiation_row.add_child(_initiation_label)
	_initiation_slider.value_changed.connect(func(v):
		_initiation_label.text = str(int(v)) + "%"
		initiation_changed.emit(v / 100.0)
	)
	_initiation_row.visible = true  # visible by default (Aware is default)

	# Live mode: screenshot interval slider (15-120s, default 20)
	_screenshot_row = HBoxContainer.new()
	tb_vbox.add_child(_screenshot_row)
	_add_label(_screenshot_row, "Screenshot:")
	_screenshot_slider = HSlider.new()
	_screenshot_slider.min_value = 15
	_screenshot_slider.max_value = 120
	_screenshot_slider.value = 20
	_screenshot_slider.step = 1
	_screenshot_slider.custom_minimum_size = Vector2(100, 0)
	_screenshot_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_screenshot_row.add_child(_screenshot_slider)
	_screenshot_label = Label.new()
	_screenshot_label.text = "20s"
	_screenshot_label.add_theme_font_size_override("font_size", 10)
	_screenshot_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_screenshot_label.custom_minimum_size = Vector2(30, 0)
	_screenshot_row.add_child(_screenshot_label)
	_screenshot_slider.value_changed.connect(func(v):
		_screenshot_label.text = str(int(v)) + "s"
		screenshot_interval_changed.emit(v)
	)
	_screenshot_row.visible = false  # only visible in Live mode

	# Live mode: audio interval slider (5-60s, default 15)
	_audio_row = HBoxContainer.new()
	tb_vbox.add_child(_audio_row)
	_add_label(_audio_row, "Audio:")
	_audio_slider = HSlider.new()
	_audio_slider.min_value = 5
	_audio_slider.max_value = 60
	_audio_slider.value = 15
	_audio_slider.step = 1
	_audio_slider.custom_minimum_size = Vector2(100, 0)
	_audio_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_audio_row.add_child(_audio_slider)
	_audio_label = Label.new()
	_audio_label.text = "15s"
	_audio_label.add_theme_font_size_override("font_size", 10)
	_audio_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_audio_label.custom_minimum_size = Vector2(30, 0)
	_audio_row.add_child(_audio_label)
	_audio_slider.value_changed.connect(func(v):
		_audio_label.text = str(int(v)) + "s"
		audio_interval_changed.emit(v)
	)
	_audio_row.visible = false  # only visible in Live mode

	# Focus window selector — Aware & Live
	_focus_row = HBoxContainer.new()
	tb_vbox.add_child(_focus_row)
	_add_label(_focus_row, "Watch:")
	_focus_selector = _add_dropdown(_focus_row, 160)
	_focus_selector.add_item("Active Window", 0)
	_focus_selector.mouse_filter = Control.MOUSE_FILTER_STOP
	_focus_selector.item_selected.connect(func(idx):
		if idx == 0:
			focus_window_changed.emit("")  # empty = follow active
		else:
			focus_window_changed.emit(_focus_selector.get_item_text(idx))
	)

	# Refresh windows button
	_focus_refresh_btn = Button.new()
	_focus_refresh_btn.text = "\u21bb"
	_focus_refresh_btn.add_theme_font_size_override("font_size", 14)
	_focus_refresh_btn.custom_minimum_size = Vector2(30, 0)
	_focus_refresh_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var refresh_style = StyleBoxFlat.new()
	refresh_style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	refresh_style.corner_radius_top_left = 4
	refresh_style.corner_radius_top_right = 4
	refresh_style.corner_radius_bottom_left = 4
	refresh_style.corner_radius_bottom_right = 4
	_focus_refresh_btn.add_theme_stylebox_override("normal", refresh_style)
	_focus_refresh_btn.pressed.connect(_refresh_window_list)
	_focus_row.add_child(_focus_refresh_btn)
	_focus_row.visible = true  # visible by default (Aware is default)

	# Screen listen toggle — Aware & Live
	_screen_listen_row = HBoxContainer.new()
	tb_vbox.add_child(_screen_listen_row)
	_add_label(_screen_listen_row, "Listen to screen:")
	_screen_listen_toggle = CheckButton.new()
	_screen_listen_toggle.button_pressed = false
	_screen_listen_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen_listen_toggle.toggled.connect(func(on): screen_listen_changed.emit(on))
	_screen_listen_row.add_child(_screen_listen_toggle)
	_screen_listen_row.visible = true  # visible by default (Aware is default)

	_add_separator(tb_vbox)

	# ══ DISPLAY SECTION ════════════════════════════════════════════
	_add_section_label(tb_vbox, "DISPLAY")

	# Chat width
	var row_width = HBoxContainer.new()
	tb_vbox.add_child(row_width)
	_add_label(row_width, "Chat Width:")
	var width_slider = HSlider.new()
	width_slider.min_value = 200
	width_slider.max_value = 600
	width_slider.value = config.chat_width
	width_slider.step = 10
	width_slider.custom_minimum_size = Vector2(120, 0)
	width_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row_width.add_child(width_slider)
	width_slider.value_changed.connect(func(v): width_changed.emit(v))

	# Font size
	var row_font = HBoxContainer.new()
	tb_vbox.add_child(row_font)
	_add_label(row_font, "Font Size:")
	var font_slider = HSlider.new()
	font_slider.min_value = 10
	font_slider.max_value = 20
	font_slider.value = config.chat_font_size
	font_slider.step = 1
	font_slider.custom_minimum_size = Vector2(120, 0)
	font_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row_font.add_child(font_slider)
	font_slider.value_changed.connect(func(v): font_changed.emit(v))

	_add_separator(tb_vbox)

	# ══ LOG FILTER ═════════════════════════════════════════════════
	_add_section_label(tb_vbox, "LOG FILTER")
	var log_categories := ["anim", "expr_mgr", "desktop_physics", "pipeline",
		"behavior", "ambient", "hub", "main", "screen_capture", "screen_listen"]
	for cat in log_categories:
		var row = HBoxContainer.new()
		tb_vbox.add_child(row)
		_add_label(row, cat + ":")
		var toggle = CheckButton.new()
		toggle.button_pressed = DebugLog.enabled_categories.get(cat, true)
		toggle.mouse_filter = Control.MOUSE_FILTER_STOP
		var cat_name = cat  # capture for closure
		toggle.toggled.connect(func(on): DebugLog.set_category(cat_name, on))
		row.add_child(toggle)

	_add_separator(tb_vbox)

	# ══ STATUS ═════════════════════════════════════════════════════
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tb_vbox.add_child(_status_label)

	visible = false


func refresh_animations(available: PackedStringArray) -> void:
	anim_selector.clear()
	anim_selector.add_item("(auto)", 0)
	var idx = 1
	for aname in available:
		anim_selector.add_item(aname, idx)
		idx += 1


func update_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func set_engagement_mode(mode: String) -> void:
	"""Set the engagement dropdown to match the current mode."""
	var modes = ["chat_only", "aware", "live"]
	var idx = modes.find(mode)
	if idx >= 0 and _engagement_selector:
		_engagement_selector.select(idx)
		_update_engagement_visibility(idx)
		if _auto_toggle:
			_auto_toggle.set_pressed_no_signal(idx != 0)


func _on_auto_toggled(on: bool) -> void:
	"""Top-level autonomous behavior toggle. ON = Aware, OFF = Chat Only."""
	if on:
		_engagement_selector.select(1)  # Aware
		_update_engagement_visibility(1)
		engagement_mode_changed.emit("aware")
	else:
		_engagement_selector.select(0)  # Chat Only
		_update_engagement_visibility(0)
		engagement_mode_changed.emit("chat_only")


func _on_engagement_selected(idx: int) -> void:
	"""Handle engagement dropdown selection — update visibility and emit signal."""
	_update_engagement_visibility(idx)
	# Keep the top-level toggle in sync
	if _auto_toggle:
		_auto_toggle.set_pressed_no_signal(idx != 0)
	var modes = ["chat_only", "aware", "live"]
	if idx < modes.size():
		engagement_mode_changed.emit(modes[idx])


func _update_engagement_visibility(idx: int) -> void:
	"""Show/hide sub-controls based on engagement mode.
	Chat Only (0): hide everything except autonomous toggle + engagement dropdown.
	Aware (1): style preset, reaction speed, initiation, watch, screen listen.
	Live (2): reaction speed, initiation, screenshot, audio, watch, screen listen."""
	var is_aware = (idx == 1)
	var is_live = (idx == 2)
	var is_active = is_aware or is_live
	# Style preset: Aware only
	if _aware_sub_row:
		_aware_sub_row.visible = is_aware
	# Reaction speed & initiation: Aware + Live
	if _reaction_row:
		_reaction_row.visible = is_active
	if _initiation_row:
		_initiation_row.visible = is_active
	# Screenshot & audio sliders: Live only
	if _screenshot_row:
		_screenshot_row.visible = is_live
	if _audio_row:
		_audio_row.visible = is_live
	# Watch (focus window): Aware + Live
	if _focus_row:
		_focus_row.visible = is_active
	# Screen listen: Aware + Live
	if _screen_listen_row:
		_screen_listen_row.visible = is_active


func _on_style_preset_selected(idx: int) -> void:
	"""Apply style presets to reaction speed and initiation sliders."""
	# Presets: [reaction_speed, initiation_percent]
	var presets = [
		[120, 15],  # Normal
		[30, 40],   # Focus
		[300, 5],   # Chill
	]
	if idx < presets.size():
		var speed = presets[idx][0]
		var init = presets[idx][1]
		if _reaction_slider:
			_reaction_slider.value = speed  # triggers value_changed -> signal
		if _initiation_slider:
			_initiation_slider.value = init  # triggers value_changed -> signal
	# Also emit the aware sub-mode signal
	var styles = ["normal", "focus", "chill"]
	if idx < styles.size():
		engagement_mode_changed.emit("aware_" + styles[idx])


func _refresh_window_list() -> void:
	"""Scan open windows and populate the focus selector."""
	_focus_selector.clear()
	_focus_selector.add_item("Active Window", 0)

	# Get window IDs first, then query each name individually
	var id_output := []
	var exit = OS.execute("xdotool", ["search", "--onlyvisible", "--name", "."], id_output, true)
	if exit != 0 or id_output.is_empty():
		return

	var seen := {}
	var idx = 1
	for wid in id_output[0].strip_edges().split("\n"):
		if wid.strip_edges().is_empty():
			continue
		var name_output := []
		OS.execute("xdotool", ["getwindowname", wid.strip_edges()], name_output, true)
		if name_output.is_empty():
			continue
		var title = name_output[0].strip_edges()
		if title.is_empty() or title.length() < 3:
			continue
		# Skip our own window and desktop
		if title.begins_with("oprojecto") or "Plasma" in title:
			continue
		# Deduplicate
		var short = title.substr(0, 50) if title.length() > 50 else title
		if short in seen:
			continue
		seen[short] = true
		# Truncate for display
		if title.length() > 55:
			title = title.substr(0, 52) + "..."
		_focus_selector.add_item(title, idx)
		idx += 1


func _add_section_label(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(lbl)


func _add_separator(parent: Node) -> void:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	parent.add_child(sep)


func _add_label(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	lbl.custom_minimum_size = Vector2(90, 0)
	parent.add_child(lbl)


func _add_dropdown(parent: Node, min_width: int) -> OptionButton:
	var dd = OptionButton.new()
	dd.custom_minimum_size = Vector2(min_width, 0)
	dd.add_theme_font_size_override("font_size", 11)
	dd.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dd)
	return dd


func _add_spacer(parent: Node) -> void:
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	parent.add_child(spacer)


func apply_hub_config(cfg: Dictionary) -> void:
	"""Update toolbar dropdowns to match hub config. Called on connect + push."""
	# LLM model
	var model: String = cfg.get("ollama_model", "")
	if model != "" and _llm_selector_ref:
		var found := false
		for i in _llm_selector_ref.item_count:
			if _llm_selector_ref.get_item_text(i) == model:
				_llm_selector_ref.select(i)
				found = true
				break
		if not found:
			_llm_selector_ref.add_item(model, _llm_selector_ref.item_count)
			_llm_selector_ref.select(_llm_selector_ref.item_count - 1)

	# Resource preset
	var preset: String = cfg.get("resource_preset", "")
	if preset != "" and _preset_selector_ref:
		var preset_map := {"max_quality": 0, "optimal": 1, "lite": 2, "gaming": 3}
		if preset in preset_map:
			_preset_selector_ref.select(preset_map[preset])

	print("[toolbar] Applied hub config: model=%s preset=%s" % [model, preset])
