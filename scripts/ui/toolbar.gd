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
signal attention_changed(mode: String)
signal focus_window_changed(window_title: String)
signal screen_listen_changed(enabled: bool)

var model_selector: OptionButton
var anim_selector: OptionButton
var tts_selector: OptionButton
var _attention_selector: OptionButton
var _voice_toggle: CheckButton
var _mic_toggle: CheckButton
var _focus_selector: OptionButton
var _focus_refresh_btn: Button
var _screen_listen_toggle: CheckButton
var _status_label: Label

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

	# Attention mode
	var row_att = HBoxContainer.new()
	tb_vbox.add_child(row_att)
	_add_label(row_att, "Attention:")
	_attention_selector = _add_dropdown(row_att, 140)
	_attention_selector.add_item("Normal", 0)
	_attention_selector.add_item("Focus", 1)
	_attention_selector.add_item("Chill", 2)
	_attention_selector.add_item("Quiet", 3)
	_attention_selector.add_item("Sleep", 4)
	_attention_selector.mouse_filter = Control.MOUSE_FILTER_STOP
	_attention_selector.item_selected.connect(func(idx):
		var modes = ["normal", "focus", "chill", "quiet", "sleep"]
		if idx < modes.size():
			attention_changed.emit(modes[idx])
	)

	# Focus window selector
	var row_focus = HBoxContainer.new()
	tb_vbox.add_child(row_focus)
	_add_label(row_focus, "Watch:")
	_focus_selector = _add_dropdown(row_focus, 160)
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
	_focus_refresh_btn.text = "↻"
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
	row_focus.add_child(_focus_refresh_btn)

	# Screen listen toggle — captures system audio to understand content
	var row_listen = HBoxContainer.new()
	tb_vbox.add_child(row_listen)
	_add_label(row_listen, "Listen to screen:")
	_screen_listen_toggle = CheckButton.new()
	_screen_listen_toggle.button_pressed = false
	_screen_listen_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen_listen_toggle.toggled.connect(func(on): screen_listen_changed.emit(on))
	row_listen.add_child(_screen_listen_toggle)

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


func set_attention_mode(mode: String) -> void:
	"""Set the attention dropdown to match the current mode."""
	var modes = ["normal", "focus", "chill", "quiet", "sleep"]
	var idx = modes.find(mode)
	if idx >= 0 and _attention_selector:
		_attention_selector.select(idx)


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
