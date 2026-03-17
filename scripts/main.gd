extends Node3D

# ── References (built in _ready) ─────────────────────────────────────────────
var camera: Camera3D
var avatar_root: Node3D
var text_input: LineEdit
var chat_messages: VBoxContainer
var chat_panel: PanelContainer
var current_model: Node3D = null
var awareness: Node = null
var voice_pipeline: Node = null
var lipsync: Node = null
var anim_system: Node = null

func _ready() -> void:
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

	# ── UI (no CanvasLayer — avoids second window with transparency) ─────
	chat_panel = PanelContainer.new()
	chat_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	chat_panel.custom_minimum_size = Vector2(420, 0)
	chat_panel.offset_left = -420
	# Semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	style.corner_radius_top_left = 12
	style.corner_radius_bottom_left = 12
	chat_panel.add_theme_stylebox_override("panel", style)
	add_child(chat_panel)

	var vbox = VBoxContainer.new()
	chat_panel.add_child(vbox)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.name = "ChatScroll"
	vbox.add_child(scroll)

	chat_messages = VBoxContainer.new()
	chat_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(chat_messages)

	var input_bar = HBoxContainer.new()
	vbox.add_child(input_bar)

	text_input = LineEdit.new()
	text_input.placeholder_text = "Type a message..."
	text_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.12, 0.12, 0.12, 0.9)
	input_style.border_color = Color(0.35, 0.4, 0.95, 0.5)
	input_style.border_width_bottom = 1
	input_style.border_width_top = 1
	input_style.border_width_left = 1
	input_style.border_width_right = 1
	input_style.corner_radius_top_left = 8
	input_style.corner_radius_top_right = 8
	input_style.corner_radius_bottom_left = 8
	input_style.corner_radius_bottom_right = 8
	input_style.content_margin_left = 12
	input_style.content_margin_right = 12
	input_style.content_margin_top = 8
	input_style.content_margin_bottom = 8
	text_input.add_theme_stylebox_override("normal", input_style)
	text_input.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	text_input.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
	input_bar.add_child(text_input)

	text_input.text_submitted.connect(_on_text_submitted)
	text_input.mouse_filter = Control.MOUSE_FILTER_STOP
	text_input.focus_mode = Control.FOCUS_ALL

	# Make sure parent containers pass mouse events through to children
	chat_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	input_bar.mouse_filter = Control.MOUSE_FILTER_PASS

	# Grab focus on startup so user can type immediately
	text_input.call_deferred("grab_focus")

	# ── Window setup (transparency configured in project.godot) ──────────
	# Skip taskbar so it doesn't show up as a minimizable window
	get_window().set_flag(Window.FLAG_NO_FOCUS, false)
	# Set mouse passthrough after window is ready — transparent areas become click-through
	call_deferred("_setup_passthrough")

	# ── Systems ───────────────────────────────────────────────────────────
	awareness = preload("res://scripts/avatar/awareness.gd").new()
	add_child(awareness)

	voice_pipeline = preload("res://scripts/voice/pipeline.gd").new()
	add_child(voice_pipeline)
	voice_pipeline.on_response.connect(_on_voice_response)
	voice_pipeline.on_state_changed.connect(_on_voice_state_changed)

	lipsync = preload("res://scripts/avatar/lipsync.gd").new()
	add_child(lipsync)

	anim_system = preload("res://scripts/avatar/animation.gd").new()
	add_child(anim_system)
	anim_system.load_all_animations()

	# ── Load model ────────────────────────────────────────────────────────
	var loader = preload("res://scripts/avatar/loader.gd").new()
	add_child(loader)
	loader.model_loaded.connect(_on_model_loaded)
	loader.model_failed.connect(func(err): add_chat_message("System", "Model error: " + err))

	var model_path = "res://assets/models/default.vrm"
	if FileAccess.file_exists(model_path):
		loader.load_model(model_path)
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F2:
				voice_pipeline.toggle_ptt()
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

	# Set up animations for the new model
	if anim_system:
		anim_system.setup(model)
		# Play idle animation if available
		if anim_system.has_animation("VRMA_01"):
			anim_system.play("VRMA_01")
		print("[main] Available animations: ", anim_system.get_available())

	add_chat_message("System", "Model loaded")
	print("[main] Model loaded")

# ── Chat ─────────────────────────────────────────────────────────────────────
func _on_text_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	text_input.clear()
	add_chat_message("You", text)
	voice_pipeline.send_text(text)

func _on_voice_response(text: String) -> void:
	add_chat_message("Kira", text)

func _on_voice_state_changed(state: String) -> void:
	match state:
		"listening":
			add_chat_message("System", "Listening...")
		"processing":
			add_chat_message("System", "Thinking...")
		"speaking":
			if awareness:
				awareness.set_talking(true)
		"idle":
			if awareness:
				awareness.set_talking(false)

func add_chat_message(sender: String, text: String) -> void:
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.text = "[b]%s:[/b] %s" % [sender, text]
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_color_override("default_color", Color(0.88, 0.88, 0.88))
	chat_messages.add_child(label)

	while chat_messages.get_child_count() > 50:
		var old = chat_messages.get_child(0)
		chat_messages.remove_child(old)
		old.queue_free()

# ── Mouse Passthrough ────────────────────────────────────────────────────────
# Define clickable regions — everything else passes through to desktop
func _setup_passthrough() -> void:
	await get_tree().process_frame
	await get_tree().process_frame  # wait 2 frames for layout
	_setup_x11_hints()
	_refresh_passthrough()

func _setup_x11_hints() -> void:
	# Make window skip taskbar/pager so minimize doesn't cascade
	var wid = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	if wid:
		OS.execute("xprop", ["-id", str(wid), "-f", "_NET_WM_STATE", "32a",
			"-set", "_NET_WM_STATE", "_NET_WM_STATE_SKIP_TASKBAR,_NET_WM_STATE_SKIP_PAGER"])
		print("[main] X11: skip taskbar/pager on wid ", wid)

func _refresh_passthrough() -> void:
	var win_size = Vector2(get_window().size)
	# Chat panel region (right 420px)
	var chat_x = win_size.x - 420.0

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

	# Combine: use chat region (avatar clicks handled by proximity check within that)
	# For now, make the full bottom strip + chat panel clickable
	var bottom_y = win_size.y * 0.5
	var region = PackedVector2Array([
		# Bottom half (avatar walks here)
		Vector2(0, bottom_y),
		Vector2(chat_x, bottom_y),
		Vector2(chat_x, 0),
		# Chat panel
		Vector2(win_size.x, 0),
		Vector2(win_size.x, win_size.y),
		Vector2(0, win_size.y),
	])
	DisplayServer.window_set_mouse_passthrough(region)
	print("[main] Passthrough updated")

# ── X11 Window Management ────────────────────────────────────────────────────
func _set_window_below() -> void:
	# TODO: get native X11 window handle for xprop
	# get_window().get_window_id() returns Godot's internal ID, not X11 xid
	print("[main] Window below: not yet implemented for Godot")
