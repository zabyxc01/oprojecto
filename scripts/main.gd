extends Node3D

# ── Core references ──────────────────────────────────────────────────────────
@onready var camera: Camera3D = $Camera3D
@onready var avatar_root: Node3D = $AvatarRoot
@onready var text_input: LineEdit = $UI/ChatPanel/VBox/InputBar/TextInput
@onready var chat_messages: VBoxContainer = $UI/ChatPanel/VBox/ChatLog/ChatMessages
@onready var http: HTTPRequest = $HTTPRequest

# ── Config ───────────────────────────────────────────────────────────────────
const OAIO_URL := "http://127.0.0.1:9000"
const OLLAMA_URL := "http://127.0.0.1:11434"

# ── State ────────────────────────────────────────────────────────────────────
var current_model: Node3D = null
var awareness: Node = null
var voice_pipeline: Node = null

func _ready() -> void:
	# Transparent window setup
	get_window().transparent_bg = true
	get_window().borderless = true

	# X11 window layer — send to back
	_set_window_below()

	# Input
	text_input.text_submitted.connect(_on_text_submitted)

	# Load systems
	awareness = preload("res://scripts/avatar/awareness.gd").new()
	add_child(awareness)

	voice_pipeline = preload("res://scripts/voice/pipeline.gd").new()
	add_child(voice_pipeline)
	voice_pipeline.on_response.connect(_on_voice_response)
	voice_pipeline.on_state_changed.connect(_on_voice_state_changed)

	# Try loading a default model
	var loader = preload("res://scripts/avatar/loader.gd").new()
	add_child(loader)
	loader.model_loaded.connect(_on_model_loaded)
	loader.load_model("res://assets/models/default.vrm")

	add_chat_message("System", "oprojecto ready. Type or press F2 to talk.")

func _process(delta: float) -> void:
	if current_model and awareness:
		awareness.update(current_model, delta, camera)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F2:
				voice_pipeline.toggle_ptt()
			KEY_F5:
				$UI/ChatPanel.visible = !$UI/ChatPanel.visible
			KEY_ESCAPE:
				get_tree().quit()

# ── X11 Window Management ────────────────────────────────────────────────────
func _set_window_below() -> void:
	# Get X11 window ID and set below
	var window_id := get_window().get_window_id()
	var args := ["-id", str(window_id), "-f", "_NET_WM_STATE", "32a", "-set", "_NET_WM_STATE", "_NET_WM_STATE_BELOW"]
	OS.execute("xprop", args)
	print("[main] Set window below: ", window_id)

# ── Model Loading ────────────────────────────────────────────────────────────
func _on_model_loaded(model: Node3D) -> void:
	# Remove old
	if current_model:
		avatar_root.remove_child(current_model)
		current_model.queue_free()

	current_model = model
	avatar_root.add_child(model)
	model.position = Vector3(0, -0.4, 0)
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

func add_chat_message(sender: String, text: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.text = "[b]%s:[/b] %s" % [sender, text]
	label.add_theme_font_size_override("normal_font_size", 13)
	chat_messages.add_child(label)

	# Cap messages
	while chat_messages.get_child_count() > 50:
		var old = chat_messages.get_child(0)
		chat_messages.remove_child(old)
		old.queue_free()

	# Scroll to bottom
	await get_tree().process_frame
	var scroll: ScrollContainer = $UI/ChatPanel/VBox/ChatLog
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
