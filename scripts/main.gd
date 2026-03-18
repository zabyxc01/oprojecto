extends Node3D

# ── References (built in _ready) ─────────────────────────────────────────────
var camera: Camera3D
var avatar_root: Node3D
var text_input: LineEdit
var chat_messages: VBoxContainer
var chat_panel: PanelContainer
var _sys_log: Label
var _chat_scroll: ScrollContainer
var _chat_toggle: Button
var current_model: Node3D = null
var awareness: Node = null
var voice_pipeline: Node = null
var lipsync: Node = null
var anim_system: Node = null
var expressions: Node = null
var hub_client: HubClient = null
var connection_manager: ConnectionManager = null
var config: Node = null
var _model_selector: OptionButton = null
var _anim_selector: OptionButton = null
var _tts_selector: OptionButton = null
var _toolbar: PanelContainer = null
var _loader_ref: Node = null
var _x11_wid: int = 0
const MODELS_DIR := "/mnt/storage/staging/ai-models-animations/vrm-models/"

func _ready() -> void:
	# ── Config ────────────────────────────────────────────────────────────
	config = preload("res://scripts/config.gd").new()
	add_child(config)

	# ── Camera ────────────────────────────────────────────────────────────
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.24
	camera.position = Vector3(0, 0.7, 4.5)
	# Camera faces -Z by default, which points at the avatar
	add_child(camera)

	# ── Lights ────────────────────────────────────────────────────────────
	var dir_light = DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-30, 20, 0)
	add_child(dir_light)

	var ambient = DirectionalLight3D.new()
	ambient.light_energy = 0.7
	add_child(ambient)

	# ── Avatar root ───────────────────────────────────────────────────────
	avatar_root = Node3D.new()
	avatar_root.name = "AvatarRoot"
	add_child(avatar_root)

	# ── Chat UI (no CanvasLayer — avoids second window with transparency) ─
	var chat_width := float(config.chat_width)
	chat_panel = PanelContainer.new()
	chat_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	chat_panel.custom_minimum_size = Vector2(chat_width, 0)
	chat_panel.offset_left = -chat_width
	# Fully transparent background — just floating bubbles
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	chat_panel.add_theme_stylebox_override("panel", style)
	add_child(chat_panel)

	var vbox = VBoxContainer.new()
	chat_panel.add_child(vbox)

	# Hamburger toggle
	_chat_toggle = Button.new()
	_chat_toggle.text = "☰"
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
	_chat_toggle.pressed.connect(_on_chat_toggle)
	vbox.add_child(_chat_toggle)

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

	# System log strip — static, shows last system message
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

	var input_bar = HBoxContainer.new()
	input_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(input_bar)

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
	# Also style the focus state so it doesn't show a white box
	var input_focus = input_style.duplicate()
	input_focus.border_color = Color(0.4, 0.45, 0.95, 0.6)
	text_input.add_theme_stylebox_override("focus", input_focus)
	text_input.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	text_input.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.25))
	text_input.add_theme_font_size_override("font_size", 13)
	input_bar.add_child(text_input)

	text_input.text_submitted.connect(_on_text_submitted)
	text_input.mouse_filter = Control.MOUSE_FILTER_STOP
	text_input.focus_mode = Control.FOCUS_ALL

	chat_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_chat_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	input_bar.mouse_filter = Control.MOUSE_FILTER_PASS

	# Grab focus on startup so user can type immediately
	text_input.call_deferred("grab_focus")

	# ── Toolbar (model + animation + TTS selectors) ─────────────────
	var tb_style = StyleBoxFlat.new()
	tb_style.bg_color = Color(0.08, 0.08, 0.08, 0.9)
	tb_style.corner_radius_top_left = 8
	tb_style.corner_radius_top_right = 8
	tb_style.corner_radius_bottom_left = 8
	tb_style.corner_radius_bottom_right = 8
	tb_style.content_margin_left = 10
	tb_style.content_margin_right = 10
	tb_style.content_margin_top = 8
	tb_style.content_margin_bottom = 8

	_toolbar = PanelContainer.new()
	_toolbar.add_theme_stylebox_override("panel", tb_style)
	_toolbar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toolbar.position = Vector2(10, 10)
	_toolbar.mouse_filter = Control.MOUSE_FILTER_STOP

	var tb_vbox = VBoxContainer.new()
	_toolbar.add_child(tb_vbox)

	# Row 1: Model + Animation
	var row1 = HBoxContainer.new()
	tb_vbox.add_child(row1)

	_add_tb_label(row1, "Model:")
	_model_selector = _add_tb_dropdown(row1, 160)
	_model_selector.add_item("default", 0)
	var mdir = DirAccess.open(MODELS_DIR)
	if mdir:
		mdir.list_dir_begin()
		var mfile = mdir.get_next()
		var midx = 1
		while mfile != "":
			if mfile.ends_with(".vrm"):
				_model_selector.add_item(mfile.get_basename(), midx)
				midx += 1
			mfile = mdir.get_next()
	_model_selector.item_selected.connect(_on_model_selected)

	_add_tb_spacer(row1)
	_add_tb_label(row1, "Anim:")
	_anim_selector = _add_tb_dropdown(row1, 120)
	_anim_selector.add_item("(none)", 0)
	_anim_selector.item_selected.connect(_on_anim_selected)

	# Row 2: TTS engine
	var row2 = HBoxContainer.new()
	tb_vbox.add_child(row2)

	_add_tb_label(row2, "TTS:")
	_tts_selector = _add_tb_dropdown(row2, 120)
	_tts_selector.add_item("kokoro", 0)
	_tts_selector.add_item("indextts", 1)
	_tts_selector.add_item("oaudio", 2)
	_tts_selector.add_item("f5", 3)
	_tts_selector.item_selected.connect(_on_tts_selected)

	# Row 3: Chat width + font size
	var row3 = HBoxContainer.new()
	tb_vbox.add_child(row3)

	_add_tb_label(row3, "Width:")
	var width_slider = HSlider.new()
	width_slider.min_value = 200
	width_slider.max_value = 600
	width_slider.value = config.chat_width
	width_slider.step = 10
	width_slider.custom_minimum_size = Vector2(100, 0)
	width_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row3.add_child(width_slider)
	width_slider.value_changed.connect(func(v):
		config.set_value("chat_width", int(v))
		chat_panel.custom_minimum_size.x = v
		chat_panel.offset_left = -v
		_refresh_passthrough()
	)

	_add_tb_spacer(row3)
	_add_tb_label(row3, "Font:")
	var font_slider = HSlider.new()
	font_slider.min_value = 10
	font_slider.max_value = 20
	font_slider.value = config.chat_font_size
	font_slider.step = 1
	font_slider.custom_minimum_size = Vector2(80, 0)
	font_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row3.add_child(font_slider)
	font_slider.value_changed.connect(func(v):
		config.set_value("chat_font_size", int(v))
		# Font applies to new messages only
	)

	_toolbar.visible = false  # toggle with F3
	add_child(_toolbar)

	# ── Window setup (transparency configured in project.godot) ──────────
	# Skip taskbar so it doesn't show up as a minimizable window
	get_window().set_flag(Window.FLAG_NO_FOCUS, false)
	# Set mouse passthrough after window is ready — transparent areas become click-through
	if OS.get_name() == "Linux":
		call_deferred("_setup_passthrough")

	# ── Systems ───────────────────────────────────────────────────────────
	awareness = preload("res://scripts/avatar/awareness.gd").new()
	add_child(awareness)

	voice_pipeline = preload("res://scripts/voice/pipeline.gd").new()
	add_child(voice_pipeline)
	voice_pipeline.on_response.connect(_on_voice_response)
	voice_pipeline.on_state_changed.connect(_on_voice_state_changed)

	# ── Network (hub client + connection manager) ─────────────────────
	hub_client = preload("res://scripts/network/hub_client.gd").new()
	add_child(hub_client)

	connection_manager = preload("res://scripts/network/connection_manager.gd").new()
	add_child(connection_manager)

	# Wire hub client to pipeline
	voice_pipeline.hub_client = hub_client
	hub_client.chat_response.connect(voice_pipeline.on_hub_chat_response)
	hub_client.tts_audio.connect(voice_pipeline.on_hub_tts_audio)
	connection_manager.mode_changed.connect(_on_connection_mode_changed)
	connection_manager.setup(hub_client)

	lipsync = preload("res://scripts/avatar/lipsync.gd").new()
	add_child(lipsync)

	expressions = preload("res://scripts/avatar/expressions.gd").new()
	add_child(expressions)
	voice_pipeline.on_emotion.connect(func(e): expressions.set_emotion(e))

	anim_system = preload("res://scripts/avatar/animation.gd").new()
	add_child(anim_system)
	anim_system.load_all_animations()

	# ── Load model ────────────────────────────────────────────────────────
	_loader_ref = preload("res://scripts/avatar/loader.gd").new()
	add_child(_loader_ref)
	_loader_ref.model_loaded.connect(_on_model_loaded)
	_loader_ref.model_failed.connect(func(err): add_chat_message("System", "Model error: " + err))

	var model_path = "res://assets/models/default.vrm"
	if FileAccess.file_exists(model_path):
		_loader_ref.load_model(model_path)
	else:
		add_chat_message("System", "No default model found at " + model_path)

	add_chat_message("System", "oprojecto ready. Type or press F2 to talk.")
	print("[main] Ready")

func _process(delta: float) -> void:
	if current_model and awareness:
		awareness.update(current_model, delta, camera)
	if anim_system:
		anim_system.update(delta)
	if lipsync:
		var speaking = voice_pipeline and voice_pipeline.current_state == voice_pipeline.PipelineState.SPEAKING
		lipsync.update(delta, speaking)
	if expressions:
		expressions.update(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F2:
				voice_pipeline.toggle_ptt()
			KEY_F3:
				_toolbar.visible = !_toolbar.visible
				_set_window_above(_toolbar.visible)
				_refresh_passthrough()
			KEY_F5:
				chat_panel.visible = !chat_panel.visible
			KEY_ESCAPE:
				get_tree().quit()

	# Click on avatar → toggle closeup
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_model and _raycast_hit_model(event.position):
			awareness.toggle_closeup()
			# Update passthrough when she moves center
			call_deferred("_refresh_passthrough")

func _raycast_hit_model(screen_pos: Vector2) -> bool:
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var space = get_world_3d().direct_space_state
	var result = space.intersect_ray(query)
	if not result.is_empty():
		return true
	# Fallback: simple distance check from click to model screen position
	var model_screen = camera.unproject_position(current_model.position + Vector3(0, 0.5, 0))
	return screen_pos.distance_to(model_screen) < 200.0

# ── Model Loading ────────────────────────────────────────────────────────────
func _on_model_loaded(model: Node3D) -> void:
	if current_model:
		avatar_root.remove_child(current_model)
		current_model.queue_free()

	current_model = model
	avatar_root.add_child(model)
	model.position = Vector3(0, -0.4, 0)

	# Set up lip sync for the new model
	if lipsync:
		lipsync.setup(model)

	# Set up expressions for the new model
	if expressions:
		expressions.setup(model)

	# Set up animations for the new model
	if anim_system:
		anim_system.setup(model)
		# Play idle animation if available
		if anim_system.has_animation("VRMA_01"):
			anim_system.play("VRMA_01")
		print("[main] Available animations: ", anim_system.get_available())

	# Refresh animation selector
	if _anim_selector:
		_anim_selector.clear()
		_anim_selector.add_item("(none)", 0)
		if anim_system:
			var idx = 1
			for aname in anim_system.get_available():
				_anim_selector.add_item(aname, idx)
				idx += 1

	add_chat_message("System", "Model loaded")
	print("[main] Model loaded")

func _on_chat_toggle() -> void:
	_chat_scroll.visible = !_chat_scroll.visible
	_chat_toggle.text = "☰" if not _chat_scroll.visible else "✕"
	# When collapsed, anchor to bottom-right growing upward. When expanded, full height.
	var cw = config.chat_width
	if _chat_scroll.visible:
		chat_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		chat_panel.offset_left = -cw
		chat_panel.offset_top = 0
		chat_panel.offset_bottom = 0
	else:
		chat_panel.anchor_left = 1.0
		chat_panel.anchor_right = 1.0
		chat_panel.anchor_top = 1.0
		chat_panel.anchor_bottom = 1.0
		chat_panel.offset_left = -cw
		chat_panel.offset_right = 0
		var tb = config.taskbar_height
		chat_panel.offset_bottom = -tb
		chat_panel.offset_top = -(tb + 80)

# ── Toolbar Helpers ──────────────────────────────────────────────────────────
func _add_tb_label(parent: Control, text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(label)
	return label

func _add_tb_dropdown(parent: Control, width: float) -> OptionButton:
	var btn = OptionButton.new()
	btn.custom_minimum_size = Vector2(width, 0)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_ALL
	parent.add_child(btn)
	return btn

func _add_tb_spacer(parent: Control) -> void:
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(16, 0)
	parent.add_child(spacer)

# ── Model / Animation / TTS Selection ───────────────────────────────────────
func _on_model_selected(idx: int) -> void:
	var name = _model_selector.get_item_text(idx)
	if name == "default":
		_loader_ref.load_model("res://assets/models/default.vrm")
	else:
		var path = MODELS_DIR + name + ".vrm"
		_loader_ref.load_model(path)
	add_chat_message("System", "Loading model: " + name)

func _on_anim_selected(idx: int) -> void:
	var name = _anim_selector.get_item_text(idx)
	if name == "(none)":
		if anim_system:
			anim_system.stop()
	else:
		if anim_system:
			anim_system.play(name)

func _on_tts_selected(idx: int) -> void:
	var engine = _tts_selector.get_item_text(idx)
	add_chat_message("System", "Switching TTS to: " + engine)
	# Call oAIo companion config API
	var http = HTTPRequest.new()
	add_child(http)
	var body = JSON.stringify({"tts_engine": engine})
	http.request("http://127.0.0.1:9000/extensions/companion/config",
		["Content-Type: application/json"], HTTPClient.METHOD_PATCH, body)
	http.request_completed.connect(func(_r, code, _h, _b):
		if code == 200:
			add_chat_message("System", "TTS: " + engine)
		else:
			add_chat_message("System", "TTS switch failed: " + str(code))
		http.queue_free()
	)

# ── Chat ─────────────────────────────────────────────────────────────────────
func _on_text_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	text_input.clear()
	add_chat_message("You", text)
	voice_pipeline.send_text(text)

func _on_voice_response(text: String) -> void:
	add_chat_message("Kira", text)

func _on_connection_mode_changed(mode: String) -> void:
	voice_pipeline.hub_connected = (mode == "hub")
	# Reset pipeline if we lost connection mid-request
	if mode != "hub" and voice_pipeline.current_state in [voice_pipeline.PipelineState.PROCESSING, voice_pipeline.PipelineState.GENERATING_AUDIO]:
		voice_pipeline._set_state(voice_pipeline.PipelineState.IDLE)
	var status = {"hub": "Connected to oAIo", "direct": "Direct mode (no hub)", "offline": "Offline"}
	add_chat_message("System", status.get(mode, mode))

func _on_voice_state_changed(state: String) -> void:
	match state:
		"listening":
			add_chat_message("System", "Listening...")
		"processing":
			add_chat_message("System", "Thinking...")
		"generating_audio":
			add_chat_message("System", "Generating voice...")
		"speaking":
			if awareness:
				awareness.set_talking(true)
		"idle":
			if awareness:
				awareness.set_talking(false)
			if _sys_log:
				_sys_log.text = ""

func add_chat_message(sender: String, text: String) -> void:
	# System messages — update the static log strip, don't add to chat
	if sender == "System":
		if _sys_log:
			_sys_log.text = text
		return
	else:
		# Chat bubble
		var is_user = (sender == "You")
		var container = HBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_user:
			container.alignment = BoxContainer.ALIGNMENT_END

		var bubble = PanelContainer.new()
		var bubble_style = StyleBoxFlat.new()
		if is_user:
			bubble_style.bg_color = config.chat_bubble_user_color
		else:
			bubble_style.bg_color = config.chat_bubble_kira_color
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
		# For Kira's messages: extract stage directions, show as header
		if not is_user:
			var directions := []
			var regex = RegEx.new()
			regex.compile("\\(([^)]+)\\)")
			for m in regex.search_all(text):
				directions.append(m.get_string(1))
			var clean = regex.sub(text, "", true).strip_edges()
			# Replace multiple spaces from removal
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
		label.text = display_text
		label.add_theme_font_size_override("normal_font_size", config.chat_font_size)
		if is_user:
			label.add_theme_color_override("default_color", config.chat_text_user_color)
		else:
			label.add_theme_color_override("default_color", config.chat_text_kira_color)
		label.custom_minimum_size.x = 240
		bubble.add_child(label)
		container.add_child(bubble)
		chat_messages.add_child(container)

	# Trim old messages
	while chat_messages.get_child_count() > 50:
		var old = chat_messages.get_child(0)
		chat_messages.remove_child(old)
		old.queue_free()

	# Auto-scroll to bottom
	await get_tree().process_frame
	var scroll_node = chat_messages.get_parent() as ScrollContainer
	if scroll_node:
		scroll_node.scroll_vertical = int(scroll_node.get_v_scroll_bar().max_value)

# ── Mouse Passthrough ────────────────────────────────────────────────────────
# Define clickable regions — everything else passes through to desktop
func _setup_passthrough() -> void:
	await get_tree().process_frame
	await get_tree().process_frame  # wait 2 frames for layout
	_setup_x11_hints()
	_refresh_passthrough()

func _setup_x11_hints() -> void:
	_x11_wid = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	if _x11_wid:
		# Skip taskbar/pager + set below other windows
		OS.execute("xprop", ["-id", str(_x11_wid), "-f", "_NET_WM_STATE", "32a",
			"-set", "_NET_WM_STATE",
			"_NET_WM_STATE_SKIP_TASKBAR,_NET_WM_STATE_SKIP_PAGER,_NET_WM_STATE_BELOW"])
		print("[main] X11: skip taskbar/pager + below on wid ", _x11_wid)

func _set_window_above(above: bool) -> void:
	if not _x11_wid:
		return
	if above:
		OS.execute("xprop", ["-id", str(_x11_wid), "-f", "_NET_WM_STATE", "32a",
			"-set", "_NET_WM_STATE",
			"_NET_WM_STATE_SKIP_TASKBAR,_NET_WM_STATE_SKIP_PAGER,_NET_WM_STATE_ABOVE"])
	else:
		OS.execute("xprop", ["-id", str(_x11_wid), "-f", "_NET_WM_STATE", "32a",
			"-set", "_NET_WM_STATE",
			"_NET_WM_STATE_SKIP_TASKBAR,_NET_WM_STATE_SKIP_PAGER,_NET_WM_STATE_BELOW"])

func _refresh_passthrough() -> void:
	var win_size = Vector2(get_window().size)
	# Chat panel region (right 420px)
	var chat_x = win_size.x - float(config.chat_width)

	# Avatar clickable region (around model position)
	var avatar_region = PackedVector2Array()
	if current_model:
		var model_screen = camera.unproject_position(current_model.position + Vector3(0, 0.5, 0))
		var ax = clampf(model_screen.x - 200, 0, win_size.x)
		var ay = clampf(model_screen.y - 400, 0, win_size.y)
		var bx = clampf(model_screen.x + 200, 0, win_size.x)
		var by = clampf(model_screen.y + 200, 0, win_size.y)
		avatar_region = PackedVector2Array([
			Vector2(ax, ay), Vector2(bx, ay),
			Vector2(bx, by), Vector2(ax, by),
		])

	# Chat panel region
	var chat_region = PackedVector2Array([
		Vector2(chat_x, 0),
		Vector2(win_size.x, 0),
		Vector2(win_size.x, win_size.y),
		Vector2(chat_x, win_size.y),
	])

	# When toolbar is open, capture full screen so dropdowns work
	# When closed, only chat panel captures clicks
	if _toolbar and _toolbar.visible:
		var full_screen = PackedVector2Array([
			Vector2(0, 0),
			Vector2(win_size.x, 0),
			Vector2(win_size.x, win_size.y),
			Vector2(0, win_size.y),
		])
		DisplayServer.window_set_mouse_passthrough(full_screen)
	else:
		DisplayServer.window_set_mouse_passthrough(chat_region)
	print("[main] Passthrough updated")

# ── X11 Window Management ────────────────────────────────────────────────────
func _set_window_below() -> void:
	# TODO: get native X11 window handle for xprop
	# get_window().get_window_id() returns Godot's internal ID, not X11 xid
	print("[main] Window below: not yet implemented for Godot")
