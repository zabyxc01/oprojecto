extends Node
class_name ConnectionManager

# Manages connection to oAIo hub with fallback to direct HTTP.
# Priority: oAIo WebSocket → direct HTTP → offline

signal mode_changed(mode: String)  # "hub", "direct", "offline"

enum Mode { HUB, DIRECT, OFFLINE }

var current_mode: Mode = Mode.OFFLINE
var hub_client: HubClient
var hub_url := "http://127.0.0.1:9000"

# Direct service URLs (fallback when hub is down)
var ollama_url := "http://127.0.0.1:11434"
var tts_url := "http://127.0.0.1:8000"

var _reconnect_timer := 0.0
var _reconnect_delay := 5.0
const MAX_RECONNECT_DELAY := 30.0
var _waiting_for_connect := false
var _connect_wait_timer := 0.0
const CONNECT_TIMEOUT := 5.0

func _ready() -> void:
	pass

func setup(client: HubClient) -> void:
	hub_client = client
	hub_client.connected.connect(_on_hub_connected)
	hub_client.disconnected.connect(_on_hub_disconnected)

	# Try hub first
	hub_client.connect_to_hub(hub_url)
	_waiting_for_connect = true
	_connect_wait_timer = 0.0

func _on_hub_connected() -> void:
	_waiting_for_connect = false
	_reconnect_delay = 5.0
	_reconnect_timer = 0.0
	_set_mode(Mode.HUB)
	print("[conn] hub mode — connected to ", hub_url)

func _on_hub_disconnected() -> void:
	print("[conn] hub disconnected")
	_set_mode(Mode.DIRECT)

func _set_mode(mode: Mode) -> void:
	if current_mode == mode:
		return
	current_mode = mode
	var mode_name = ["hub", "direct", "offline"][mode]
	print("[conn] mode: ", mode_name)
	mode_changed.emit(mode_name)

func _process(delta: float) -> void:
	# Waiting for initial connect attempt to resolve
	if _waiting_for_connect:
		_connect_wait_timer += delta
		if _connect_wait_timer >= CONNECT_TIMEOUT:
			_waiting_for_connect = false
			if not hub_client.is_connected_to_hub():
				print("[conn] hub connect timeout, falling back to direct")
				_set_mode(Mode.DIRECT)
		return

	# Already connected — nothing to do
	if hub_client.is_connected_to_hub():
		return

	# Auto-reconnect to hub
	_reconnect_timer += delta
	if _reconnect_timer >= _reconnect_delay:
		_reconnect_timer = 0.0
		_reconnect_delay = minf(_reconnect_delay * 1.5, MAX_RECONNECT_DELAY)
		print("[conn] attempting reconnect (next in ", _reconnect_delay, "s)")
		hub_client.connect_to_hub(hub_url)
		_waiting_for_connect = true
		_connect_wait_timer = 0.0
