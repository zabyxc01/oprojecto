extends Node
class_name HubClient

# WebSocket client for oAIo companion extension protocol.
# Connects to ws://<hub>/extensions/companion/ws
# Sends: chat.request, stt.audio, state.sync, ping
# Receives: chat.response, tts.audio, stt.transcript, state.sync, pong

signal connected
signal disconnected
signal chat_response(text: String, done: bool, emotion: Variant)
signal tts_audio(data: PackedByteArray, format: String)
signal stt_result(text: String)
signal hub_state(services: Dictionary)

var _ws := WebSocketPeer.new()
var _hub_url := ""
var _is_connected := false
var _ping_timer := 0.0
const PING_INTERVAL := 15.0

func is_connected_to_hub() -> bool:
	return _is_connected

func connect_to_hub(url: String) -> void:
	_hub_url = url
	var ws_url = url.replace("http://", "ws://").replace("https://", "wss://")
	if not ws_url.ends_with("/"):
		ws_url += "/"
	ws_url += "extensions/companion/ws"

	# Close any existing connection before reconnecting
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()
		_is_connected = false

	# Need a fresh peer for each connection attempt
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1048576   # 1MB — TTS audio can be large
	_ws.outbound_buffer_size = 4194304   # 4MB — base64 audio can be large

	print("[hub] connecting to ", ws_url)
	var err = _ws.connect_to_url(ws_url)
	if err != OK:
		print("[hub] connection failed: ", err)

func disconnect_from_hub() -> void:
	_ws.close()
	_is_connected = false

func send_chat(text: String, history: Array) -> void:
	if not _is_connected:
		return
	_send({
		"type": "chat.request",
		"id": _uuid(),
		"ts": Time.get_unix_time_from_system(),
		"payload": {
			"text": text,
			"history": history,
		},
	})

func send_audio(audio_data: PackedByteArray, sample_rate: int = 44100, history: Array = []) -> void:
	if not _is_connected:
		return
	_send({
		"type": "stt.audio",
		"id": _uuid(),
		"ts": Time.get_unix_time_from_system(),
		"payload": {
			"audio_b64": Marshalls.raw_to_base64(audio_data),
			"format": "wav",
			"sample_rate": sample_rate,
			"auto_chat": true,
			"history": history,
		},
	})

func _send_state_sync() -> void:
	_send({
		"type": "state.sync",
		"id": _uuid(),
		"ts": Time.get_unix_time_from_system(),
		"payload": {
			"client_type": "desktop" if OS.get_name() != "Android" else "phone",
			"platform": OS.get_name(),
			"name": OS.get_environment("HOSTNAME") if OS.get_environment("HOSTNAME") != "" else "oprojecto",
			"capabilities": ["render", "audio_playback"],
		},
	})

func _send(data: Dictionary) -> void:
	_ws.send_text(JSON.stringify(data))

func _uuid() -> String:
	return str(randi() ^ int(Time.get_unix_time_from_system() * 1000)).md5_text().substr(0, 12)

func _process(delta: float) -> void:
	_ws.poll()

	var state = _ws.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				_is_connected = true
				print("[hub] connected")
				_send_state_sync()
				connected.emit()

			# Read messages
			while _ws.get_available_packet_count() > 0:
				var raw = _ws.get_packet().get_string_from_utf8()
				_handle_message(raw)

			# Keepalive
			_ping_timer += delta
			if _ping_timer >= PING_INTERVAL:
				_ping_timer = 0.0
				_send({"type": "ping", "id": _uuid(), "ts": Time.get_unix_time_from_system(), "payload": {}})

		WebSocketPeer.STATE_CLOSING:
			pass  # Wait for full close

		WebSocketPeer.STATE_CLOSED:
			if _is_connected:
				_is_connected = false
				var code = _ws.get_close_code()
				var reason = _ws.get_close_reason()
				print("[hub] disconnected (code=", code, " reason=", reason, ")")
				disconnected.emit()

		WebSocketPeer.STATE_CONNECTING:
			pass  # Still connecting

func _handle_message(raw: String) -> void:
	var data = JSON.parse_string(raw)
	if not data or not data is Dictionary:
		return

	var msg_type: String = data.get("type", "")
	var payload: Dictionary = data.get("payload", {})

	match msg_type:
		"chat.response":
			var emotion_raw = payload.get("emotion", "neutral")
			# Support both old string format and new dict format
			var emotion_data: Variant
			if emotion_raw is Dictionary:
				emotion_data = emotion_raw
			else:
				emotion_data = {"primary": str(emotion_raw), "primary_intensity": 0.7, "secondary": "", "secondary_intensity": 0.0}
			chat_response.emit(payload.get("text", ""), payload.get("done", true), emotion_data)

		"tts.audio":
			var b64: String = payload.get("audio_b64", "")
			if b64 != "":
				var audio_bytes = Marshalls.base64_to_raw(b64)
				var fmt: String = payload.get("format", "wav")
				tts_audio.emit(audio_bytes, fmt)

		"stt.transcript":
			stt_result.emit(payload.get("text", ""))

		"state.sync":
			hub_state.emit(payload.get("services", {}))

		"pong":
			pass  # keepalive response
