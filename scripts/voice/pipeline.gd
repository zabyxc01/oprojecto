extends Node
class_name VoicePipeline

# Voice pipeline — dual mode:
#   HUB mode:    all requests go through oAIo companion WebSocket
#   DIRECT mode: direct HTTP to ollama + kokoro (original behavior, now fallback)

signal on_response(text: String)
signal on_emotion(emotion: String)
signal on_state_changed(state: String)

enum PipelineState { IDLE, LISTENING, PROCESSING, GENERATING_AUDIO, SPEAKING }

var current_state: PipelineState = PipelineState.IDLE

# Connection mode — set by ConnectionManager
var hub_connected := false
var _audio_queue: Array[Dictionary] = []  # [{data, format}]

# Config (used in direct mode only — hub has its own config)
var ollama_url := "http://127.0.0.1:11434"
var ollama_model := "gemma3:latest"
var tts_url := "http://127.0.0.1:8000"
var tts_voice := "af_heart"
var stt_url := "http://127.0.0.1:8003"

var system_prompt := "Your name is Kira. You are a desktop companion AI with an anime avatar.
You speak casually and naturally. Keep responses SHORT (1-3 sentences unless asked for detail).
Be warm, slightly playful, and genuine. Never use emojis or markdown."

var conversation_history: Array[Dictionary] = []
const MAX_HISTORY := 40
const HISTORY_FILE := "user://chat_history.json"

# Hub client reference — set by main.gd
var hub_client: HubClient

# HTTP nodes (direct mode)
var _llm_http: HTTPRequest
var _tts_http: HTTPRequest
var _audio_player: AudioStreamPlayer

func _ready() -> void:
	_load_history()

	_llm_http = HTTPRequest.new()
	_llm_http.timeout = 60.0
	add_child(_llm_http)

	_tts_http = HTTPRequest.new()
	_tts_http.timeout = 30.0
	add_child(_tts_http)

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_finished)

func _set_state(state: PipelineState) -> void:
	current_state = state
	var keys = PipelineState.keys()
	var state_name = str(keys[state]).to_lower()
	on_state_changed.emit(state_name)
	print("[pipeline] ", state_name)

# ── Text Input ───────────────────────────────────────────────────────────────
func send_text(text: String) -> void:
	if current_state != PipelineState.IDLE:
		return

	conversation_history.append({"role": "user", "content": text})
	while conversation_history.size() > MAX_HISTORY:
		conversation_history.pop_front()

	if hub_connected and hub_client:
		_send_via_hub(text)
	else:
		_process_text_direct(text)

# ── Hub Mode ─────────────────────────────────────────────────────────────────
func _send_via_hub(text: String) -> void:
	_set_state(PipelineState.PROCESSING)
	hub_client.send_chat(text, conversation_history)
	# Response arrives via hub_client signals → on_hub_chat_response / on_hub_tts_audio

var _tts_timeout_timer: SceneTreeTimer = null

func on_hub_chat_response(text: String, done: bool, emotion: String) -> void:
	if done and text != "":
		conversation_history.append({"role": "assistant", "content": text})
		_save_history()
		on_response.emit(text)
		if emotion != "neutral" and emotion != "":
			on_emotion.emit(emotion)
		# Waiting for TTS audio to arrive
		_set_state(PipelineState.GENERATING_AUDIO)
		_tts_timeout_timer = get_tree().create_timer(30.0)
		_tts_timeout_timer.timeout.connect(_on_tts_timeout)

func on_hub_tts_audio(data: PackedByteArray, format: String) -> void:
	# Cancel timeout — audio arrived
	_tts_timeout_timer = null
	if current_state == PipelineState.SPEAKING:
		# Already playing — queue this chunk
		_audio_queue.append({"data": data, "format": format})
		print("[pipeline] Queued audio chunk (", _audio_queue.size(), " in queue)")
	else:
		# Play immediately
		if format == "mp3":
			play_mp3_from_bytes(data)
		else:
			play_audio_from_bytes(data)

func _on_tts_timeout() -> void:
	if current_state == PipelineState.PROCESSING or current_state == PipelineState.GENERATING_AUDIO:
		print("[pipeline] TTS timeout — returning to idle")
		_set_state(PipelineState.IDLE)

# ── Audio Playback (shared) ──────────────────────────────────────────────────
func play_audio_from_bytes(audio_data: PackedByteArray) -> void:
	_set_state(PipelineState.SPEAKING)

	# Parse WAV header to extract format info and raw PCM data
	var pcm_data := audio_data
	var sample_rate := 24000
	var bits := 16
	var channels := 1

	# Check for RIFF/WAV header
	if audio_data.size() > 44 and audio_data.slice(0, 4).get_string_from_ascii() == "RIFF":
		# Parse WAV header
		channels = audio_data.decode_u16(22)
		sample_rate = audio_data.decode_u32(24)
		bits = audio_data.decode_u16(34)
		# Find data chunk (usually at offset 36, data starts at 44)
		var i := 36
		while i < audio_data.size() - 8:
			var chunk_id = audio_data.slice(i, i + 4).get_string_from_ascii()
			var chunk_size = audio_data.decode_u32(i + 4)
			if chunk_id == "data":
				pcm_data = audio_data.slice(i + 8, i + 8 + chunk_size)
				break
			i += 8 + chunk_size
		print("[pipeline] WAV: ", sample_rate, "Hz ", bits, "bit ", channels, "ch, PCM=", pcm_data.size(), " bytes")

	var stream := AudioStreamWAV.new()
	stream.data = pcm_data
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = (channels == 2)
	_audio_player.stream = stream
	_audio_player.play()

func play_mp3_from_bytes(mp3_data: PackedByteArray) -> void:
	_set_state(PipelineState.SPEAKING)
	var stream = AudioStreamMP3.new()
	stream.data = mp3_data
	_audio_player.stream = stream
	_audio_player.play()
	print("[pipeline] MP3: ", mp3_data.size(), " bytes")

func _on_audio_finished() -> void:
	# Check queue for next chunk
	if _audio_queue.size() > 0:
		var next = _audio_queue.pop_front()
		print("[pipeline] Playing next chunk (", _audio_queue.size(), " remaining)")
		if next["format"] == "mp3":
			play_mp3_from_bytes(next["data"])
		else:
			play_audio_from_bytes(next["data"])
	else:
		_set_state(PipelineState.IDLE)

# ── History Persistence ──────────────────────────────────────────────────────
func _save_history() -> void:
	var file = FileAccess.open(HISTORY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(conversation_history))
		print("[pipeline] History saved (", conversation_history.size(), " messages)")

func _load_history() -> void:
	if not FileAccess.file_exists(HISTORY_FILE):
		return
	var file = FileAccess.open(HISTORY_FILE, FileAccess.READ)
	if not file:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data and data is Array:
		conversation_history.assign(data)
		print("[pipeline] History loaded (", conversation_history.size(), " messages)")

# ── PTT (placeholder — needs mic capture implementation) ──────────────────────
func toggle_ptt() -> void:
	match current_state:
		PipelineState.IDLE:
			_set_state(PipelineState.LISTENING)
			# TODO: start mic recording
			print("[pipeline] PTT: start listening (mic capture TODO)")
		PipelineState.LISTENING:
			_set_state(PipelineState.PROCESSING)
			# TODO: stop recording, send to STT, then process
			print("[pipeline] PTT: stop listening (STT TODO)")
			_set_state(PipelineState.IDLE)

# ── Direct Mode (fallback) ───────────────────────────────────────────────────
func _process_text_direct(user_text: String) -> void:
	_set_state(PipelineState.PROCESSING)

	var messages: Array[Dictionary] = []
	messages.append({"role": "system", "content": system_prompt})
	messages.append_array(conversation_history)

	var body := JSON.stringify({
		"model": ollama_model,
		"messages": messages,
		"stream": false,
	})

	var headers := ["Content-Type: application/json"]
	var err := _llm_http.request(ollama_url + "/api/chat", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[pipeline] LLM request failed: ", err)
		_set_state(PipelineState.IDLE)
		return

	var result = await _llm_http.request_completed
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code != 200:
		print("[pipeline] LLM error: ", response_code)
		_set_state(PipelineState.IDLE)
		return

	var json = JSON.parse_string(response_body.get_string_from_utf8())
	if not json or not json.has("message"):
		print("[pipeline] LLM: no message in response")
		_set_state(PipelineState.IDLE)
		return

	var response_text: String = json["message"]["content"]
	conversation_history.append({"role": "assistant", "content": response_text})
	_save_history()

	on_response.emit(response_text)

	# Send to TTS
	_speak_direct(response_text)

func _speak_direct(text: String) -> void:
	_set_state(PipelineState.SPEAKING)

	var body := JSON.stringify({
		"input": text,
		"voice": tts_voice,
		"response_format": "wav",
	})

	var headers := ["Content-Type: application/json"]
	var err := _tts_http.request(tts_url + "/v1/audio/speech", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[pipeline] TTS request failed: ", err)
		_set_state(PipelineState.IDLE)
		return

	var result = await _tts_http.request_completed
	var response_code: int = result[1]
	var audio_data: PackedByteArray = result[3]

	if response_code != 200:
		print("[pipeline] TTS error: ", response_code)
		_set_state(PipelineState.IDLE)
		return

	print("[pipeline] TTS direct: received ", audio_data.size(), " bytes")
	play_audio_from_bytes(audio_data)
