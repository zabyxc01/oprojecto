extends Node
class_name VoicePipeline

# Voice pipeline — dual mode:
#   HUB mode:    all requests go through oAIo companion WebSocket
#   DIRECT mode: direct HTTP to ollama + kokoro (original behavior, now fallback)

signal on_response(text: String)
signal on_emotion(emotion_data: Variant)
signal on_state_changed(state: String)

enum PipelineState { IDLE, LISTENING, PROCESSING, GENERATING_AUDIO, SPEAKING }

var current_state: PipelineState = PipelineState.IDLE

# Connection mode — set by ConnectionManager
var hub_connected := false
var _audio_queue: Array[Dictionary] = []  # [{data, format}]

# Config (used in direct mode only — hub has its own config)
var ollama_url := "http://127.0.0.1:11434"
var ollama_model := "qwen2.5:7b"
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
var _stt_http: HTTPRequest
var _audio_player: AudioStreamPlayer

# Mic capture
var _mic_record: AudioStreamPlayer
var _capture_effect: AudioEffectCapture
var _is_recording := false
var MIC_SAMPLE_RATE: int
const MIC_BUS_NAME := "MicCapture"

func _ready() -> void:
	_load_history()

	_llm_http = HTTPRequest.new()
	_llm_http.timeout = 60.0
	add_child(_llm_http)

	_tts_http = HTTPRequest.new()
	_tts_http.timeout = 30.0
	add_child(_tts_http)

	_stt_http = HTTPRequest.new()
	_stt_http.timeout = 60.0
	add_child(_stt_http)

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_finished)

	_setup_mic()

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

func on_hub_chat_response(text: String, done: bool, emotion: Variant, objective: bool = false) -> void:
	if done and text != "":
		conversation_history.append({"role": "assistant", "content": text})
		_save_history()
		on_response.emit(text)
		if objective:
			# Objective/factual response — force Thinking animation, suppress persona emotions
			on_emotion.emit({"primary": "thinking", "primary_intensity": 0.7, "secondary": "", "secondary_intensity": 0.0, "objective": true})
		elif emotion is Dictionary:
			var primary: String = emotion.get("primary", "neutral")
			if primary != "neutral":
				on_emotion.emit(emotion)
		elif emotion is String and emotion != "neutral" and emotion != "":
			on_emotion.emit({"primary": emotion, "primary_intensity": 0.7, "secondary": "", "secondary_intensity": 0.0})
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

# ── Mic Setup ─────────────────────────────────────────────────────────────────
func _setup_mic() -> void:
	var bus_idx := AudioServer.get_bus_index(MIC_BUS_NAME)
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, MIC_BUS_NAME)
	AudioServer.set_bus_mute(bus_idx, true)

	# Clear existing effects and add capture
	while AudioServer.get_bus_effect_count(bus_idx) > 0:
		AudioServer.remove_bus_effect(bus_idx, 0)
	_capture_effect = AudioEffectCapture.new()
	_capture_effect.buffer_length = 30.0  # 30 seconds max recording
	AudioServer.add_bus_effect(bus_idx, _capture_effect)

	MIC_SAMPLE_RATE = AudioServer.get_mix_rate()

	_mic_record = AudioStreamPlayer.new()
	var mic_stream := AudioStreamMicrophone.new()
	_mic_record.stream = mic_stream
	_mic_record.bus = MIC_BUS_NAME
	add_child(_mic_record)
	print("[pipeline] Mic setup on bus: ", MIC_BUS_NAME, " @ ", MIC_SAMPLE_RATE, " Hz")

# ── PTT ───────────────────────────────────────────────────────────────────────
func toggle_ptt() -> void:
	match current_state:
		PipelineState.IDLE:
			_start_recording()
		PipelineState.LISTENING:
			_stop_recording()
		_:
			print("[pipeline] PTT ignored — busy (", PipelineState.keys()[current_state], ")")

func _start_recording() -> void:
	if not _capture_effect:
		print("[pipeline] No mic capture available")
		return
	_capture_effect.clear_buffer()
	_mic_record.play()
	_is_recording = true
	_set_state(PipelineState.LISTENING)
	print("[pipeline] Recording started")

func _stop_recording() -> void:
	_is_recording = false
	_mic_record.stop()
	_set_state(PipelineState.PROCESSING)

	var frames := _capture_effect.get_buffer(_capture_effect.get_frames_available())
	_capture_effect.clear_buffer()

	if frames.size() == 0:
		print("[pipeline] No audio captured")
		_set_state(PipelineState.IDLE)
		return

	var duration := float(frames.size()) / MIC_SAMPLE_RATE
	print("[pipeline] Captured ", frames.size(), " frames (", "%.1f" % duration, "s)")

	if duration < 0.5:
		print("[pipeline] Too short (< 0.5s), ignoring")
		_set_state(PipelineState.IDLE)
		return

	if duration > 60.0:
		print("[pipeline] Recording too long (", "%.0f" % duration, "s), trimming to 60s")
		frames = frames.slice(0, int(MIC_SAMPLE_RATE * 60.0))
		duration = 60.0

	# Check audio level — reject near-silence
	var peak := 0.0
	for frame in frames:
		var mono := absf((frame.x + frame.y) * 0.5)
		if mono > peak:
			peak = mono
	print("[pipeline] Peak amplitude: ", "%.4f" % peak)
	if peak < 0.01:
		print("[pipeline] Audio too quiet, ignoring")
		_set_state(PipelineState.IDLE)
		return

	var wav_data := _pack_wav(frames)
	print("[pipeline] WAV packed: ", wav_data.size(), " bytes")

	if hub_connected and hub_client:
		print("[pipeline] Sending audio to hub for STT...")
		hub_client.send_audio(wav_data, MIC_SAMPLE_RATE, conversation_history)
		# Hub auto-chains: STT → chat → TTS (auto_chat: true)
		# Response comes back via hub_client signals
	else:
		_transcribe_direct(wav_data)

func _pack_wav(frames: PackedVector2Array) -> PackedByteArray:
	# Convert stereo float frames to mono 16-bit PCM WAV
	var samples := PackedByteArray()
	for frame in frames:
		var mono := (frame.x + frame.y) * 0.5
		var s := clampi(int(mono * 32767.0), -32768, 32767)
		samples.append(s & 0xFF)
		samples.append((s >> 8) & 0xFF)

	var data_size := samples.size()
	var wav := PackedByteArray()
	# RIFF header
	wav.append_array("RIFF".to_ascii_buffer())
	wav.append_array(_int32_le(36 + data_size))
	wav.append_array("WAVE".to_ascii_buffer())
	# fmt chunk
	wav.append_array("fmt ".to_ascii_buffer())
	wav.append_array(_int32_le(16))        # chunk size
	wav.append_array(_int16_le(1))         # PCM
	wav.append_array(_int16_le(1))         # mono
	wav.append_array(_int32_le(MIC_SAMPLE_RATE))
	wav.append_array(_int32_le(MIC_SAMPLE_RATE * 2))  # byte rate
	wav.append_array(_int16_le(2))         # block align
	wav.append_array(_int16_le(16))        # bits per sample
	# data chunk
	wav.append_array("data".to_ascii_buffer())
	wav.append_array(_int32_le(data_size))
	wav.append_array(samples)
	return wav

func _int32_le(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b[0] = v & 0xFF
	b[1] = (v >> 8) & 0xFF
	b[2] = (v >> 16) & 0xFF
	b[3] = (v >> 24) & 0xFF
	return b

func _int16_le(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b[0] = v & 0xFF
	b[1] = (v >> 8) & 0xFF
	return b

func _transcribe_direct(wav_data: PackedByteArray) -> void:
	var boundary := "----GodotBoundary%d" % randi()
	var body := PackedByteArray()
	body.append_array(("--%s\r\n" % boundary).to_ascii_buffer())
	body.append_array("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".to_ascii_buffer())
	body.append_array("Content-Type: audio/wav\r\n\r\n".to_ascii_buffer())
	body.append_array(wav_data)
	body.append_array(("\r\n--%s\r\n" % boundary).to_ascii_buffer())
	body.append_array("Content-Disposition: form-data; name=\"language\"\r\n\r\n".to_ascii_buffer())
	body.append_array("en".to_ascii_buffer())
	body.append_array(("\r\n--%s--\r\n" % boundary).to_ascii_buffer())

	var headers := ["Content-Type: multipart/form-data; boundary=%s" % boundary]
	var err := _stt_http.request_raw(stt_url + "/transcribe", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[pipeline] STT request failed: ", err)
		_set_state(PipelineState.IDLE)
		return

	var result = await _stt_http.request_completed
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]

	if response_code != 200:
		print("[pipeline] STT error: ", response_code)
		_set_state(PipelineState.IDLE)
		return

	var json = JSON.parse_string(response_body.get_string_from_utf8())
	if not json or not json.has("text"):
		print("[pipeline] STT: no text in response")
		_set_state(PipelineState.IDLE)
		return

	var transcript: String = json["text"].strip_edges()
	print("[pipeline] STT transcript: ", transcript)
	if transcript.is_empty():
		print("[pipeline] Empty transcript, ignoring")
		_set_state(PipelineState.IDLE)
		return

	# Feed transcript as if user typed it
	_set_state(PipelineState.IDLE)
	on_response.emit("[You said]: " + transcript)
	send_text(transcript)

# ── Emotion Detection (direct mode) ──────────────────────────────────────────
const _STAGE_DIRECTION_MAP := {
	"smile": "happy", "smiling": "happy", "grin": "happy", "beam": "happy",
	"laugh": "happy", "giggle": "happy", "chuckle": "happy",
	"excited": "happy", "cheerful": "happy", "bright": "happy",
	"wink": "happy", "playful": "happy",
	"sad": "sad", "frown": "sad", "sigh": "sad", "tear": "sad",
	"disappointed": "sad", "down": "sad", "melancholy": "sad",
	"angry": "angry", "glare": "angry", "scowl": "angry", "furious": "angry",
	"irritat": "angry", "annoyed": "angry",
	"surprise": "surprised", "shock": "surprised", "gasp": "surprised",
	"wide eye": "surprised", "stunned": "surprised",
	"calm": "relaxed", "relax": "relaxed", "peaceful": "relaxed",
	"gentle": "relaxed", "warm": "relaxed", "nod": "relaxed",
	"blush": "blush", "fluster": "blush", "shy": "blush",
	"embarrass": "blush", "cute": "blush",
	"sleepy": "sleepy", "yawn": "sleepy", "tired": "sleepy",
	"drowsy": "sleepy", "exhausted": "sleepy",
	"think": "thinking", "ponder": "thinking", "hmm": "thinking",
	"consider": "thinking", "wonder": "thinking", "puzzl": "thinking",
	"confused": "thinking", "curious": "thinking", "tilt": "thinking",
	"thoughtful": "thinking",
}

const _EMOTION_KEYWORDS := {
	"happy": [
		"haha", "lol", "glad", "awesome", "great", "love", "yay", "nice",
		"wonderful", "fantastic", "excited", "fun", "enjoy", "happy", "laugh",
		"hehe", "sweet", "cool", "amazing",
	],
	"angry": [
		"angry", "furious", "mad", "annoyed", "frustrated", "ugh",
		"hate", "pissed", "irritated", "damn", "hell",
	],
	"sad": [
		"sad", "sorry", "unfortunately", "miss", "lonely", "cry",
		"disappointing", "sigh", "heartbreaking",
	],
	"surprised": [
		"wow", "whoa", "oh!", "really?", "seriously?", "no way",
		"unexpected", "surprised", "shocking", "what?!",
	],
	"relaxed": [
		"chill", "relax", "calm", "peaceful", "cozy", "comfy",
		"easy", "mellow", "gentle", "soft", "quiet",
	],
	"blush": [
		"blush", "embarrass", "shy", "fluster", "cute",
	],
	"sleepy": [
		"sleepy", "tired", "yawn", "exhausted", "drowsy", "nap", "bed",
	],
	"thinking": [
		"think", "wonder", "hmm", "ponder", "curious", "consider",
		"puzzl", "confus", "interesting",
	],
}

var _paren_regex: RegEx
var _strip_paren_regex: RegEx

func _init_emotion_regex() -> void:
	_paren_regex = RegEx.new()
	_paren_regex.compile("^\\(([^)]+)\\)")
	_strip_paren_regex = RegEx.new()
	_strip_paren_regex.compile("\\([^)]+\\)\\s*")

func _detect_emotion(text: String) -> String:
	if _paren_regex == null:
		_init_emotion_regex()

	var stripped := text.strip_edges()

	var m := _paren_regex.search(stripped)
	if m:
		var direction := m.get_string(1).to_lower()
		for keyword in _STAGE_DIRECTION_MAP:
			if direction.contains(keyword):
				return _STAGE_DIRECTION_MAP[keyword]

	var text_lower := text.to_lower()
	var best_emotion := "neutral"
	var best_score := 0
	for emotion in _EMOTION_KEYWORDS:
		var score := 0
		for kw in _EMOTION_KEYWORDS[emotion]:
			if text_lower.contains(kw):
				score += 1
		if score > best_score:
			best_score = score
			best_emotion = emotion
	return best_emotion

func _strip_stage_directions(text: String) -> String:
	if _strip_paren_regex == null:
		_init_emotion_regex()
	return _strip_paren_regex.sub(text, "", true).strip_edges()

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

	var emotion := _detect_emotion(response_text)
	print("[pipeline] Detected emotion: ", emotion, " from: ", response_text.substr(0, 80))
	if emotion != "neutral" and emotion != "":
		on_emotion.emit({"primary": emotion, "primary_intensity": 0.7, "secondary": "", "secondary_intensity": 0.0})

	on_response.emit(response_text)

	var tts_text := _strip_stage_directions(response_text)
	if tts_text != "":
		_speak_direct(tts_text)
	else:
		_set_state(PipelineState.IDLE)

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
