extends Node3D

# ── References (built in _ready) ─────────────────────────────────────────────
var camera: Camera3D
var avatar_root: Node3D
var text_input: LineEdit
var chat_messages: VBoxContainer
var chat_panel: PanelContainer
# Chat panel and toolbar are now self-contained UI components
var current_model: Node3D = null
var awareness: Node = null
var voice_pipeline: Node = null
var lipsync: Node = null
var anim_system: Node = null
var expressions: Node = null
var _expr_manager: Node = null
var _screen_context: Node = null
var _behavior: Node = null
var _ambient_llm: Node = null
var _persistent_state: Node = null
var _desktop_physics: Node = null
var _screen_listen: Node = null
var _screen_capture: Node = null
var _engagement_mode: Node = null
var _last_screenshot := ""
var _last_audio_transcript := ""
var hub_client: HubClient = null
var connection_manager: ConnectionManager = null
var config: Node = null
var _model_selector: OptionButton = null
var _anim_selector: OptionButton = null
var _tts_selector: OptionButton = null
var _toolbar: PanelContainer = null
var _loader_ref: Node = null
var _model_mapper: Node = null
var _x11_wid: int = 0
var _is_dragging := false
var _last_model_path := ""
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

	# ── Chat Panel (extracted to scripts/ui/chat_panel.gd) ────────────
	chat_panel = preload("res://scripts/ui/chat_panel.gd").new()
	chat_panel.build(config)
	chat_panel.text_submitted.connect(_on_text_submitted)
	chat_panel.center_pressed.connect(func(): awareness.toggle_closeup())
	chat_panel.toggle_pressed.connect(_on_chat_toggle)
	chat_messages = chat_panel.chat_messages
	text_input = chat_panel.text_input
	add_child(chat_panel)

	# ── Engagement Mode ───────────────────────────────────────────────
	_engagement_mode = preload("res://scripts/awareness/engagement_mode.gd").new()
	add_child(_engagement_mode)

	# ── Toolbar (extracted to scripts/ui/toolbar.gd) ──────────────────
	_toolbar = preload("res://scripts/ui/toolbar.gd").new()
	_toolbar.build(config)
	_toolbar.model_selected.connect(_on_model_selected)
	_toolbar.anim_selected.connect(_on_anim_selected)
	_toolbar.tts_selected.connect(_on_tts_selected)
	_toolbar.width_changed.connect(func(v):
		config.set_value("chat_width", int(v))
		chat_panel.set_width(v)
		_refresh_passthrough()
	)
	_toolbar.font_changed.connect(func(v):
		config.set_value("chat_font_size", int(v))
		chat_panel.update_font_size(int(v))
	)
	_toolbar.voice_enabled_changed.connect(_on_voice_toggle)
	_toolbar.mic_enabled_changed.connect(_on_mic_toggle)
	_toolbar.engagement_mode_changed.connect(_on_engagement_mode_changed)
	_toolbar.screenshot_interval_changed.connect(func(v):
		if _screen_context:
			_screen_context.poll_interval = v
	)
	_toolbar.audio_interval_changed.connect(func(v):
		if _screen_listen:
			_screen_listen.capture_interval = v
	)
	_toolbar.focus_window_changed.connect(_on_focus_window_changed)
	_toolbar.screen_listen_changed.connect(func(on):
		if _screen_listen:
			_screen_listen.set_enabled(on)
			add_chat_message("System", "Screen listening " + ("enabled" if on else "disabled"))
	)
	_model_selector = _toolbar.model_selector
	_anim_selector = _toolbar.anim_selector
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
	hub_client.stt_result.connect(_on_stt_result)
	connection_manager.mode_changed.connect(_on_connection_mode_changed)
	connection_manager.setup(hub_client)

	lipsync = preload("res://scripts/avatar/lipsync.gd").new()
	add_child(lipsync)

	expressions = preload("res://scripts/avatar/expressions.gd").new()
	add_child(expressions)

	anim_system = preload("res://scripts/avatar/animation.gd").new()
	add_child(anim_system)
	anim_system.load_all_animations()

	# ExpressionManager orchestrates all three layers
	_expr_manager = preload("res://scripts/avatar/expression_manager.gd").new()
	add_child(_expr_manager)
	voice_pipeline.on_emotion.connect(_on_emotion_received)
	expressions.emotion_changed.connect(_on_emotion_changed)
	expressions.emotion_faded.connect(_on_emotion_faded)

	# ── Screen awareness + behavior tree ──────────────────────────────
	_screen_context = preload("res://scripts/awareness/screen_context.gd").new()
	add_child(_screen_context)

	_behavior = preload("res://scripts/awareness/behavior.gd").new()
	add_child(_behavior)

	_screen_context.context_changed.connect(_behavior.on_context_changed)
	_behavior.wants_animation.connect(_on_behavior_animation)

	# ── Ambient LLM (rate-limited context queries) ────────────────────
	_ambient_llm = preload("res://scripts/awareness/ambient_llm.gd").new()
	add_child(_ambient_llm)
	_ambient_llm.setup(voice_pipeline, hub_client)
	_ambient_llm.query_sent.connect(func(prompt, qtype):
		add_chat_message("System", "[%s]" % qtype)
	)
	_screen_context.context_changed.connect(_ambient_llm.on_context_changed)
	# Route behavior speak requests through ambient LLM (sole path)
	_behavior.wants_to_speak.connect(func(prompt):
		var ctx = _screen_context.get_current()
		_ambient_llm.request_query(prompt, "observation", ctx)
	)
	# Sync behavior state to ambient LLM for filtering
	_behavior.state_changed.connect(func(new_state: String, _old_state: String):
		_ambient_llm.set_behavior_state(new_state)
		print("[main] Behavior: ", _old_state, " -> ", new_state)
	)

	# ── Persistent state (mood, familiarity, facts) ───────────────────
	_persistent_state = preload("res://scripts/awareness/persistent_state.gd").new()
	add_child(_persistent_state)
	# Record app usage when screen context changes
	_screen_context.context_changed.connect(_persistent_state.record_context)
	# Log behavior transitions (attentive = user is chatting, counts as interaction)
	_behavior.state_changed.connect(func(new_state: String, _old_state: String):
		if new_state == "attentive":
			_persistent_state.record_interaction()
	)

	# ── Desktop physics (taskbar, perching, dragging, walking) ────────
	_desktop_physics = preload("res://scripts/avatar/desktop_physics.gd").new()
	add_child(_desktop_physics)
	_desktop_physics.fell.connect(_on_physics_fell)
	_desktop_physics.drag_started.connect(_on_physics_drag_started)
	_desktop_physics.drag_ended.connect(_on_physics_drag_ended)
	_desktop_physics.walking.connect(_on_physics_walking)
	_desktop_physics.state_changed.connect(func(new_state):
		if _expr_manager:
			_expr_manager.set_positional(new_state)
	)

	# ── Screen listener (system audio capture for content awareness) ──
	_screen_listen = preload("res://scripts/awareness/screen_listen.gd").new()
	add_child(_screen_listen)
	_screen_listen.setup(voice_pipeline, hub_client)
	_screen_listen.transcript_ready.connect(_on_screen_transcript)

	# ── Screen capture (screenshots for Live mode vision) ─────────
	_screen_capture = preload("res://scripts/awareness/screen_capture.gd").new()
	add_child(_screen_capture)
	_screen_capture.screenshot_ready.connect(_on_screenshot_ready)

	# ── Model mapper (format-agnostic bone/blend shape mapping) ───────
	# Deferred — model_mapper.gd has strict type issues in Godot 4.6, load safely
	var _mapper_script = load("res://scripts/avatar/model_mapper.gd")
	if _mapper_script and _mapper_script.can_instantiate():
		_model_mapper = _mapper_script.new()
		add_child(_model_mapper)
	else:
		print("[main] Model mapper skipped (parse errors — VRM auto-mapping still works)")

	# ── Load model ────────────────────────────────────────────────────────
	_loader_ref = preload("res://scripts/avatar/loader.gd").new()
	add_child(_loader_ref)
	_loader_ref.model_loaded.connect(_on_model_loaded)
	_loader_ref.model_failed.connect(func(err): add_chat_message("System", "Model error: " + err))

	var model_path = "res://assets/models/default.vrm"
	_last_model_path = model_path
	if FileAccess.file_exists(model_path):
		_loader_ref.load_model(model_path)
	else:
		add_chat_message("System", "No default model found at " + model_path)

	# ── Startup greeting ──────────────────────────────────────────────
	var greeting := _build_startup_greeting()
	add_chat_message("System", greeting)
	print("[main] Ready")

func _process(delta: float) -> void:
	if current_model and awareness:
		awareness.update(current_model, delta, camera)
	if _screen_context:
		_screen_context.update(delta)
	if _behavior:
		_behavior.update(delta)
	if _persistent_state:
		_persistent_state.update(delta)
	if _desktop_physics:
		_desktop_physics.update(delta)
	if _screen_listen:
		_screen_listen.update(delta)
	if _screen_capture:
		_screen_capture.update(delta)
	# ExpressionManager handles all three layers: animation, expressions, lip sync
	if _expr_manager:
		var speaking = voice_pipeline and voice_pipeline.current_state == voice_pipeline.PipelineState.SPEAKING
		_expr_manager.set_speaking(speaking)
		_expr_manager.update(delta)
	else:
		# Fallback if no manager
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
				if _mic_enabled:
					voice_pipeline.toggle_ptt()
					if _behavior:
						_behavior.on_user_interaction()
				else:
					add_chat_message("System", "Mic disabled — enable in F3 settings")
			KEY_F3:
				_toolbar.visible = !_toolbar.visible
				_set_window_above(_toolbar.visible)
				_refresh_passthrough()
			KEY_F5:
				chat_panel.visible = !chat_panel.visible
			KEY_ESCAPE:
				if awareness and awareness.current_state == awareness.State.CLOSEUP:
					awareness.set_closeup(false)
				else:
					get_tree().quit()
			KEY_UP:
				if awareness and awareness.current_state == awareness.State.CLOSEUP:
					awareness.move_up()
			KEY_DOWN:
				if awareness and awareness.current_state == awareness.State.CLOSEUP:
					awareness.move_down()

	# Mouse click on avatar → start drag; release → end drag
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if current_model and _desktop_physics and _raycast_hit_model(event.position):
					_is_dragging = true
					_desktop_physics.start_drag(event.position)
					get_viewport().set_input_as_handled()
			else:
				if _is_dragging and _desktop_physics:
					_is_dragging = false
					_desktop_physics.end_drag()
					get_viewport().set_input_as_handled()

	# Scroll wheel zoom in closeup mode
	if event is InputEventMouseButton and event.pressed:
		if awareness and awareness.current_state == awareness.State.CLOSEUP:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				awareness.zoom_in()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				awareness.zoom_out()

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
		print("[main] Available animations: ", anim_system.get_available())

	# Run model mapper to create format-agnostic mapping
	if _model_mapper:
		var mapping = _model_mapper.create_mapping(model, _last_model_path)
		if not mapping.is_empty():
			print("[main] Model mapping: ", mapping.get("format", "?"),
				" (confidence: ", mapping.get("confidence", 0.0), ")")
			# Pass mapping to expressions and animation for mapped name support
			if expressions:
				expressions.set_blend_shape_mapping(mapping.get("blend_shapes", {}))
			if anim_system:
				anim_system.set_bone_mapping(mapping.get("bones", {}))

	# Wire up ExpressionManager (orchestrates all three layers)
	if _expr_manager:
		_expr_manager.setup(expressions, anim_system, lipsync)

	# Wire up desktop physics
	if _desktop_physics:
		_desktop_physics.setup(current_model, camera)

	# Refresh animation selector
	if _toolbar and anim_system:
		_toolbar.refresh_animations(anim_system.get_available())

	add_chat_message("System", "Model loaded")
	print("[main] Model loaded")

func _on_chat_toggle() -> void:
	var scroll = chat_panel._chat_scroll
	scroll.visible = !scroll.visible
	chat_panel._chat_toggle.text = "\u2630" if not scroll.visible else "\u2715"
	var cw = config.chat_width
	if scroll.visible:
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

# ── Model / Animation / TTS Selection ───────────────────────────────────────
func _on_model_selected(idx: int) -> void:
	var name = _model_selector.get_item_text(idx)
	if name == "default":
		_last_model_path = "res://assets/models/default.vrm"
	else:
		_last_model_path = MODELS_DIR + name + ".vrm"
	_loader_ref.load_model(_last_model_path)
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

	# Chat commands — control Kira's attention
	var cmd = text.strip_edges().to_lower()
	if cmd.begins_with("/"):
		_handle_command(cmd)
		return

	add_chat_message("You", text)
	voice_pipeline.send_text(text)
	if _behavior:
		_behavior.on_user_interaction()
	if _persistent_state:
		_persistent_state.record_interaction()


func _handle_command(cmd: String) -> void:
	match cmd:
		"/focus":
			if _engagement_mode and _engagement_mode.get_mode_name() != "aware":
				add_chat_message("System", "Style commands only work in Aware mode")
				return
			if _ambient_llm:
				_ambient_llm.min_interval = 30.0
			if _behavior:
				_behavior.INITIATE_CHANCE = 0.4
			add_chat_message("System", "Kira is focused on you")
		"/chill":
			if _engagement_mode and _engagement_mode.get_mode_name() != "aware":
				add_chat_message("System", "Style commands only work in Aware mode")
				return
			if _ambient_llm:
				_ambient_llm.min_interval = 300.0
			if _behavior:
				_behavior.INITIATE_CHANCE = 0.05
			add_chat_message("System", "Kira is chilling")
		"/quiet":
			if _engagement_mode and _engagement_mode.get_mode_name() != "aware":
				add_chat_message("System", "Style commands only work in Aware mode")
				return
			if _ambient_llm:
				_ambient_llm.min_interval = 99999.0
			add_chat_message("System", "Kira is quiet")
		"/normal":
			if _engagement_mode and _engagement_mode.get_mode_name() != "aware":
				add_chat_message("System", "Style commands only work in Aware mode")
				return
			if _ambient_llm:
				_ambient_llm.min_interval = 120.0
			if _behavior:
				_behavior.INITIATE_CHANCE = 0.15
			add_chat_message("System", "Kira is back to normal")
		"/sleep":
			if _behavior:
				_behavior.current_state = _behavior.State.SLEEPING
				_behavior._state_timer = 0.0
			add_chat_message("System", "Kira is sleeping")
		"/wake":
			if _behavior:
				_behavior.on_user_interaction()
			add_chat_message("System", "Kira is awake")
		"/status":
			var parts := []
			if _behavior:
				parts.append("State: " + _behavior.get_state_name())
			if _ambient_llm:
				parts.append("Ambient interval: " + str(int(_ambient_llm.min_interval)) + "s")
				parts.append("Cooldown: " + str(int(_ambient_llm.get_cooldown_remaining())) + "s")
			if _persistent_state:
				parts.append("Familiarity: " + _persistent_state.get_familiarity_label())
				parts.append("Sessions: " + str(_persistent_state.state.get("total_sessions", 0)))
			add_chat_message("System", "\n".join(parts) if parts.size() > 0 else "No status available")
		"/help":
			add_chat_message("System", "\n".join([
				"[b]Kira Commands[/b]",
				"",
				"[color=#e10600]Engagement Modes[/color]  (F3 toolbar)",
				"  Chat Only — no awareness, just conversation",
				"  Aware — screen context + ambient comments",
				"  Live — vision + audio capture, high engagement",
				"",
				"[color=#e10600]Aware Styles[/color]  (only in Aware mode)",
				"  /focus — watches closely, comments often (30s)",
				"  /chill — relaxed, rare comments (5 min)",
				"  /quiet — no ambient comments at all",
				"  /normal — default behavior (2 min)",
				"",
				"[color=#e10600]State[/color]",
				"  /sleep — she dozes off",
				"  /wake — wake her up",
				"  /status — show behavior state + stats",
				"",
				"[color=#e10600]Controls[/color]",
				"  F2 — push to talk (hold to record)",
				"  F3 — settings panel (model, voice, behavior)",
				"  F5 — toggle chat panel",
				"  ESC — exit closeup / quit",
				"",
				"[color=#888888]You can also just talk to her normally.[/color]",
			]))
		_:
			add_chat_message("System", "Unknown command. Type /help for commands.")

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
			if chat_panel and chat_panel._sys_log:
				chat_panel._sys_log.text = "REC  Listening... (F2 to stop)"
				chat_panel._sys_log.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		"processing":
			if chat_panel and chat_panel._sys_log:
				chat_panel._sys_log.text = "Processing..."
				chat_panel._sys_log.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.9))
		"generating_audio":
			if chat_panel and chat_panel._sys_log:
				chat_panel._sys_log.text = "Generating voice..."
				chat_panel._sys_log.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.9))
		"speaking":
			if awareness:
				awareness.set_talking(true)
			if chat_panel and chat_panel._sys_log:
				chat_panel._sys_log.text = ""
		"idle":
			if awareness:
				awareness.set_talking(false)
			if chat_panel and chat_panel._sys_log:
				chat_panel._sys_log.text = ""

func _on_stt_result(text: String) -> void:
	# Skip if this is a screen_listen result (not mic input)
	if _screen_listen and _screen_listen.expecting_result:
		return  # screen_listen handles this via its own signal

	print("[main] STT result: '", text, "'")
	if text.begins_with("[STT error"):
		add_chat_message("System", text)
		voice_pipeline._set_state(VoicePipeline.PipelineState.IDLE)
		return
	if text.is_empty():
		add_chat_message("System", "No speech detected")
		voice_pipeline._set_state(VoicePipeline.PipelineState.IDLE)
		return
	add_chat_message("You", text)
	voice_pipeline.conversation_history.append({"role": "user", "content": text})
	# Hub auto-chains STT → chat, so the response will come via chat_response signal

func _on_emotion_received(emotion_data: Variant) -> void:
	"""Handle emotion from voice pipeline — route to expression manager + persistent state."""
	if not _expr_manager:
		return
	var emotion_dict: Dictionary
	if emotion_data is Dictionary:
		emotion_dict = emotion_data
	elif emotion_data is String:
		emotion_dict = {"primary": emotion_data, "primary_intensity": 0.7, "secondary": "", "secondary_intensity": 0.0}
	else:
		return

	_expr_manager.set_emotion(emotion_dict)

	# Update persistent state mood
	var mood: String = emotion_dict.get("primary", "neutral")
	var momentum: float = emotion_dict.get("primary_intensity", 0.5)
	if _persistent_state:
		_persistent_state.update_mood(mood, momentum)
	# Sync mood to behavior tree and ambient LLM
	if _behavior:
		_behavior.on_mood_changed(mood)
	if _ambient_llm:
		_ambient_llm.set_mood(mood)

func _on_emotion_changed(emotion: String, intensity: float) -> void:
	# Expression system notifies us — for UI/logging purposes
	pass

func _on_emotion_faded() -> void:
	# Expression faded back to neutral
	pass

func _on_behavior_animation(anim_name: String) -> void:
	"""Behavior tree requests an animation — routed through priority queue."""
	if _expr_manager:
		_expr_manager.request_animation(anim_name, ExpressionManager.AnimPriority.BEHAVIOR, 5.0)

func _on_physics_fell() -> void:
	"""Avatar fell and landed on the taskbar — play surprised reaction."""
	if _expr_manager:
		_expr_manager.set_emotion({"primary": "surprised", "primary_intensity": 0.8, "secondary": "", "secondary_intensity": 0.0})

func _on_physics_drag_started() -> void:
	"""User started dragging the avatar."""
	if _expr_manager:
		_expr_manager.set_emotion({"primary": "surprised", "primary_intensity": 0.6, "secondary": "", "secondary_intensity": 0.0})

func _on_physics_drag_ended() -> void:
	"""User released the avatar from drag."""
	if _expr_manager:
		_expr_manager.set_emotion({"primary": "happy", "primary_intensity": 0.5, "secondary": "", "secondary_intensity": 0.0})

func _on_physics_walking(direction: int) -> void:
	pass

func _on_screen_transcript(text: String, source: String) -> void:
	"""System audio was transcribed — store for live queries or send directly."""
	_last_audio_transcript = text

	# In Live mode, transcripts feed into combined live queries (vision + audio)
	if _engagement_mode and _engagement_mode.get_mode_name() == "live":
		# Live mode: try combined query with latest screenshot
		if _ambient_llm and _screen_context:
			_ambient_llm.request_live_query(_screen_context.get_current(), _last_screenshot, text)
			_last_screenshot = ""  # consume screenshot
			_last_audio_transcript = ""
		return

	# In Aware mode, send as standalone content observation
	if not _ambient_llm or not _screen_context:
		return
	var ctx = _screen_context.get_current()
	var bg = ctx.get("background_media", "")
	var window = ctx.get("window_title", "")

	var prompt = (
		"You just heard some of what the user is watching/listening to. "
		+ "This is NOT the user talking to you — this is audio from their screen content. "
	)
	if bg != "":
		prompt += "They are %s. " % bg
	elif "youtube" in window.to_lower() or "twitch" in window.to_lower():
		prompt += "They're watching something in %s. " % window.substr(0, 60)
	prompt += 'Here\'s what was said in the content: "%s" ' % text.substr(0, 300)
	prompt += "React to this naturally — comment on what they're watching, not what they said to you. Keep it brief."
	_ambient_llm.request_query(prompt, "comment", ctx)


func _on_screenshot_ready(image_b64: String) -> void:
	"""Screenshot captured — store for live query or send immediately."""
	_last_screenshot = image_b64

	# In Live mode, try combined query with latest audio
	if _engagement_mode and _engagement_mode.get_mode_name() == "live":
		if _ambient_llm and _screen_context:
			_ambient_llm.request_live_query(
				_screen_context.get_current(), image_b64, _last_audio_transcript
			)
			_last_audio_transcript = ""  # consume transcript
			_last_screenshot = ""

# ── Toolbar handlers ─────────────────────────────────────────────────────────
var _voice_enabled := true
var _mic_enabled := true
var _focus_window := ""  # empty = follow active window

func _on_voice_toggle(enabled: bool) -> void:
	_voice_enabled = enabled
	if voice_pipeline:
		voice_pipeline.set_meta("voice_enabled", enabled)
	add_chat_message("System", "Voice " + ("enabled" if enabled else "disabled"))

func _on_mic_toggle(enabled: bool) -> void:
	_mic_enabled = enabled
	add_chat_message("System", "Mic " + ("enabled" if enabled else "disabled"))

func _on_engagement_mode_changed(mode: String) -> void:
	# Handle aware sub-styles (aware_normal, aware_focus, aware_chill)
	if mode.begins_with("aware_"):
		var style = mode.substr(6)  # strip "aware_"
		_handle_command("/" + style)
		return

	if _engagement_mode:
		_engagement_mode.set_mode_by_name(mode)

	match mode:
		"chat_only":
			if _screen_context: _screen_context.poll_interval = 999.0
			if _screen_listen: _screen_listen.set_enabled(false)
			if _screen_capture: _screen_capture.set_enabled(false)
			if _ambient_llm: _ambient_llm.min_interval = 99999.0
			if _behavior: _behavior.INITIATE_CHANCE = 0.0
			add_chat_message("System", "Chat Only mode")
		"aware":
			if _screen_capture: _screen_capture.set_enabled(false)
			if _screen_context: _screen_context.poll_interval = 5.0
			if _ambient_llm: _ambient_llm.min_interval = 120.0
			if _behavior: _behavior.INITIATE_CHANCE = 0.15
			add_chat_message("System", "Aware mode")
		"live":
			if _screen_context: _screen_context.poll_interval = 3.0
			if _screen_listen:
				_screen_listen.set_enabled(true)
				_screen_listen.capture_duration = 10.0
				_screen_listen.capture_interval = 12.0
			if _screen_capture: _screen_capture.set_enabled(true)
			if _ambient_llm: _ambient_llm.min_interval = 15.0
			if _behavior: _behavior.INITIATE_CHANCE = 0.5
			add_chat_message("System", "Live mode \u2014 vision + audio active")

func _on_focus_window_changed(window_title: String) -> void:
	_focus_window = window_title
	if _screen_context:
		_screen_context.set_meta("focus_window", window_title)
	if window_title.is_empty():
		add_chat_message("System", "Watching: active window")
	else:
		add_chat_message("System", "Watching: " + window_title)

func _build_startup_greeting() -> String:
	"""Build a greeting based on persistent state."""
	if not _persistent_state:
		return "oprojecto ready. Type or press F2 to talk."

	var ctx = _persistent_state.get_greeting_context()
	var time_since: float = ctx.get("seconds_since_last_seen", -1.0)
	var session_count: int = ctx.get("session_count", 1)

	if session_count <= 1 or time_since < 0:
		return "Nice to meet you! Type or press F2 to talk."
	elif time_since > 3600:
		return "Hey, it's been a while! Welcome back."
	else:
		return "Hey again! Ready when you are."

func add_chat_message(sender: String, text: String) -> void:
	if sender == "System":
		chat_panel.set_system_message(text)
		return
	chat_panel.add_message(sender, text)

	# Trim old messages
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
