extends PanelContainer
class_name ChatPanel

## Self-contained chat panel UI — bubbles, input, system log.
## Extracted from main.gd to reduce its size.

signal text_submitted(text: String)
signal center_pressed
signal toggle_pressed
signal web_search_toggled(enabled: bool)

var chat_messages: VBoxContainer
var text_input: LineEdit
var _chat_scroll: ScrollContainer
var _sys_log: Label
var _chat_toggle: Button
var _web_search_btn: Button
var _web_search_enabled := false
var _config: Node


func build(config: Node) -> void:
	_config = config

	var chat_width := float(config.chat_width)
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	custom_minimum_size = Vector2(chat_width, 0)
	offset_left = -chat_width

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	add_child(vbox)

	# Hamburger toggle
	_chat_toggle = Button.new()
	_chat_toggle.text = "\u2630"
	_chat_toggle.add_theme_font_size_override("font_size", 18)
	_chat_toggle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 0.8))
	var toggle_style = StyleBoxFlat.new()
	toggle_style.bg_color = Color(0.1, 0.1, 0.14, 0.5)
	toggle_style.corner_radius_top_left = 8
	toggle_style.corner_radius_top_right = 8
	toggle_style.corner_radius_bottom_left = 8
	toggle_style.corner_radius_bottom_right = 8
	toggle_style.content_margin_left = 8
	toggle_style.content_margin_right = 8
	toggle_style.content_margin_top = 2
	toggle_style.content_margin_bottom = 2
	_chat_toggle.add_theme_stylebox_override("normal", toggle_style)
	var toggle_hover = toggle_style.duplicate()
	toggle_hover.bg_color = Color(0.15, 0.15, 0.2, 0.7)
	_chat_toggle.add_theme_stylebox_override("hover", toggle_hover)
	_chat_toggle.add_theme_stylebox_override("pressed", toggle_hover)
	_chat_toggle.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_chat_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	_chat_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_chat_toggle.pressed.connect(func(): toggle_pressed.emit())
	vbox.add_child(_chat_toggle)

	# Chat scroll
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.name = "ChatScroll"
	_chat_scroll.follow_focus = true
	vbox.add_child(_chat_scroll)

	chat_messages = VBoxContainer.new()
	chat_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_messages.add_theme_constant_override("separation", 4)
	_chat_scroll.add_child(chat_messages)

	# System log strip
	var sys_panel = PanelContainer.new()
	var sys_style = StyleBoxFlat.new()
	sys_style.bg_color = Color(0.06, 0.06, 0.08, 0.5)
	sys_style.corner_radius_top_left = 8
	sys_style.corner_radius_top_right = 8
	sys_style.corner_radius_bottom_left = 8
	sys_style.corner_radius_bottom_right = 8
	sys_style.content_margin_left = 6
	sys_style.content_margin_right = 6
	sys_style.content_margin_top = 2
	sys_style.content_margin_bottom = 2
	sys_panel.add_theme_stylebox_override("panel", sys_style)
	vbox.add_child(sys_panel)
	_sys_log = Label.new()
	_sys_log.text = ""
	_sys_log.add_theme_font_size_override("font_size", 10)
	_sys_log.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.9))
	_sys_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sys_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sys_panel.add_child(_sys_log)

	# Input bar
	var input_bar = HBoxContainer.new()
	input_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(input_bar)

	# Web search toggle button
	_web_search_btn = Button.new()
	_web_search_btn.text = "W"
	_web_search_btn.tooltip_text = "Web search (off)"
	_web_search_btn.add_theme_font_size_override("font_size", 13)
	var ws_style = StyleBoxFlat.new()
	ws_style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	ws_style.corner_radius_top_left = 18
	ws_style.corner_radius_top_right = 18
	ws_style.corner_radius_bottom_left = 18
	ws_style.corner_radius_bottom_right = 18
	ws_style.content_margin_left = 8
	ws_style.content_margin_right = 8
	_web_search_btn.add_theme_stylebox_override("normal", ws_style)
	var ws_hover = ws_style.duplicate()
	ws_hover.bg_color = Color(0.25, 0.25, 0.5, 0.7)
	_web_search_btn.add_theme_stylebox_override("hover", ws_hover)
	_web_search_btn.add_theme_stylebox_override("pressed", ws_hover)
	_web_search_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_web_search_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_web_search_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_web_search_btn.pressed.connect(_toggle_web_search)
	input_bar.add_child(_web_search_btn)

	text_input = LineEdit.new()
	text_input.placeholder_text = "Talk to Kira..."
	text_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = config.chat_input_bg_color
	input_style.border_color = Color(0.4, 0.45, 0.95, 0.3)
	input_style.border_width_bottom = 1
	input_style.border_width_top = 1
	input_style.border_width_left = 1
	input_style.border_width_right = 1
	input_style.corner_radius_top_left = 18
	input_style.corner_radius_top_right = 18
	input_style.corner_radius_bottom_left = 18
	input_style.corner_radius_bottom_right = 18
	input_style.content_margin_left = 14
	input_style.content_margin_right = 14
	input_style.content_margin_top = 8
	input_style.content_margin_bottom = 8
	text_input.add_theme_stylebox_override("normal", input_style)
	var input_focus = input_style.duplicate()
	input_focus.border_color = Color(0.4, 0.45, 0.95, 0.6)
	text_input.add_theme_stylebox_override("focus", input_focus)
	text_input.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	text_input.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.25))
	text_input.add_theme_font_size_override("font_size", config.chat_font_size)
	input_bar.add_child(text_input)

	text_input.text_submitted.connect(func(t): text_submitted.emit(t))
	text_input.mouse_filter = Control.MOUSE_FILTER_STOP
	text_input.focus_mode = Control.FOCUS_ALL

	# Center button
	var center_btn = Button.new()
	center_btn.text = "\u25ce"
	center_btn.add_theme_font_size_override("font_size", 18)
	var cbtn_style = StyleBoxFlat.new()
	cbtn_style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	cbtn_style.corner_radius_top_left = 18
	cbtn_style.corner_radius_top_right = 18
	cbtn_style.corner_radius_bottom_left = 18
	cbtn_style.corner_radius_bottom_right = 18
	cbtn_style.content_margin_left = 8
	cbtn_style.content_margin_right = 8
	center_btn.add_theme_stylebox_override("normal", cbtn_style)
	var cbtn_hover = cbtn_style.duplicate()
	cbtn_hover.bg_color = Color(0.25, 0.25, 0.5, 0.7)
	center_btn.add_theme_stylebox_override("hover", cbtn_hover)
	center_btn.add_theme_stylebox_override("pressed", cbtn_hover)
	center_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	center_btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	center_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	center_btn.pressed.connect(func(): center_pressed.emit())
	input_bar.add_child(center_btn)

	mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_chat_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	input_bar.mouse_filter = Control.MOUSE_FILTER_PASS

	text_input.call_deferred("grab_focus")


func set_system_message(text: String) -> void:
	if _sys_log:
		_sys_log.text = text


func add_message(sender: String, text: String) -> void:
	var is_user = (sender == "You")
	var container = HBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_user:
		container.alignment = BoxContainer.ALIGNMENT_END

	var bubble = PanelContainer.new()
	var bubble_style = StyleBoxFlat.new()
	if is_user:
		bubble_style.bg_color = _config.chat_bubble_user_color
	else:
		bubble_style.bg_color = _config.chat_bubble_kira_color
	bubble_style.corner_radius_top_left = 12
	bubble_style.corner_radius_top_right = 12
	bubble_style.corner_radius_bottom_left = 4 if is_user else 12
	bubble_style.corner_radius_bottom_right = 12 if is_user else 4
	bubble_style.content_margin_left = 10
	bubble_style.content_margin_right = 10
	bubble_style.content_margin_top = 6
	bubble_style.content_margin_bottom = 6
	bubble.add_theme_stylebox_override("panel", bubble_style)

	var display_text := text
	if not is_user:
		var directions := []
		var regex = RegEx.new()
		regex.compile("\\(([^)]+)\\)")
		for m in regex.search_all(text):
			directions.append(m.get_string(1))
		var clean = regex.sub(text, "", true).strip_edges()
		while clean.contains("  "):
			clean = clean.replace("  ", " ")
		if directions.size() > 0:
			display_text = "[i][color=#8888aa](" + ", ".join(directions) + ")[/color][/i]\n" + clean
		else:
			display_text = clean

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(240, 0)
	label.add_theme_font_size_override("normal_font_size", _config.chat_font_size)
	if is_user:
		label.add_theme_color_override("default_color", _config.chat_text_user_color)
	else:
		label.add_theme_color_override("default_color", _config.chat_text_kira_color)
	label.text = display_text
	bubble.add_child(label)

	container.add_child(bubble)
	chat_messages.add_child(container)

	# Auto-scroll to bottom
	await get_tree().process_frame
	if _chat_scroll:
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func set_width(w: float) -> void:
	custom_minimum_size.x = w
	offset_left = -w


func _toggle_web_search() -> void:
	_web_search_enabled = !_web_search_enabled
	if _web_search_enabled:
		_web_search_btn.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		_web_search_btn.tooltip_text = "Web search (on)"
		var on_style = StyleBoxFlat.new()
		on_style.bg_color = Color(0.1, 0.25, 0.35, 0.8)
		on_style.corner_radius_top_left = 18
		on_style.corner_radius_top_right = 18
		on_style.corner_radius_bottom_left = 18
		on_style.corner_radius_bottom_right = 18
		on_style.content_margin_left = 8
		on_style.content_margin_right = 8
		_web_search_btn.add_theme_stylebox_override("normal", on_style)
	else:
		_web_search_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		_web_search_btn.tooltip_text = "Web search (off)"
		var off_style = StyleBoxFlat.new()
		off_style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
		off_style.corner_radius_top_left = 18
		off_style.corner_radius_top_right = 18
		off_style.corner_radius_bottom_left = 18
		off_style.corner_radius_bottom_right = 18
		off_style.content_margin_left = 8
		off_style.content_margin_right = 8
		_web_search_btn.add_theme_stylebox_override("normal", off_style)
	web_search_toggled.emit(_web_search_enabled)


func set_web_search_enabled(on: bool) -> void:
	"""Set web search state without emitting signal (for hub sync)."""
	_web_search_enabled = on
	if not _web_search_btn:
		return
	if on:
		_web_search_btn.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		_web_search_btn.tooltip_text = "Web search (on)"
		var on_style = StyleBoxFlat.new()
		on_style.bg_color = Color(0.1, 0.25, 0.35, 0.8)
		on_style.corner_radius_top_left = 18
		on_style.corner_radius_top_right = 18
		on_style.corner_radius_bottom_left = 18
		on_style.corner_radius_bottom_right = 18
		on_style.content_margin_left = 8
		on_style.content_margin_right = 8
		_web_search_btn.add_theme_stylebox_override("normal", on_style)
	else:
		_web_search_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		_web_search_btn.tooltip_text = "Web search (off)"
		var off_style = StyleBoxFlat.new()
		off_style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
		off_style.corner_radius_top_left = 18
		off_style.corner_radius_top_right = 18
		off_style.corner_radius_bottom_left = 18
		off_style.corner_radius_bottom_right = 18
		off_style.content_margin_left = 8
		off_style.content_margin_right = 8
		_web_search_btn.add_theme_stylebox_override("normal", off_style)


func set_web_search_active(active: bool) -> void:
	"""Show visual feedback when a web search is in progress."""
	if not _sys_log:
		return
	if active:
		_sys_log.text = "Searching web..."
		_sys_log.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0, 0.9))
	else:
		_sys_log.text = ""
		_sys_log.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.9))


func update_font_size(size: int) -> void:
	for msg_container in chat_messages.get_children():
		for bubble in msg_container.get_children():
			for child in bubble.get_children():
				if child is RichTextLabel:
					child.add_theme_font_size_override("normal_font_size", size)
	text_input.add_theme_font_size_override("font_size", size)
