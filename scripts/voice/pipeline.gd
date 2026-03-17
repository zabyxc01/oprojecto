extends Node
class_name VoicePipeline

# Voice pipeline — talks to ollama, kokoro TTS, faster-whisper STT
# All via HTTP — same services as before, just GDScript instead of JS

signal on_response(text: String)
signal on_state_changed(state: String)

enum PipelineState { IDLE, LISTENING, PROCESSING, SPEAKING }

var current_state: PipelineState = PipelineState.IDLE

# Config
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

# HTTP nodes
var _llm_http: HTTPRequest
var _tts_http: HTTPRequest
var _audio_player: AudioStreamPlayer

func _ready() -> void:
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
	_process_text(text)

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

# ── LLM ──────────────────────────────────────────────────────────────────────
func _process_text(user_text: String) -> void:
	_set_state(PipelineState.PROCESSING)

	conversation_history.append({"role": "user", "content": user_text})
	while conversation_history.size() > MAX_HISTORY:
		conversation_history.pop_front()

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

	on_response.emit(response_text)

	# Send to TTS
	_speak(response_text)

# ── TTS ──────────────────────────────────────────────────────────────────────
func _speak(text: String) -> void:
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

	# Play audio
	var stream := AudioStreamWAV.new()
	stream.data = audio_data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 24000
	stream.stereo = false
	_audio_player.stream = stream
	_audio_player.play()

func _on_audio_finished() -> void:
	_set_state(PipelineState.IDLE)
