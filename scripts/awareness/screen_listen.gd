extends Node
class_name ScreenListen

## Captures system audio output (what's playing through speakers) and
## periodically transcribes it via faster-whisper STT. Feeds transcripts
## to the ambient LLM so Kira can comment on content being watched/listened to.
##
## This is NOT mic input — it's monitor capture of the audio output.
## Kira understands this is content being viewed, not the user speaking.

signal transcript_ready(text: String, source_app: String)
signal listening_started
signal listening_stopped

var enabled := false
var capture_duration := 15.0
var capture_interval := 30.0
var _timer := 0.0
var _capturing := false
var _capture_file := ""
var _capture_start := 0.0
var _voice_pipeline: Node = null
var _hub_client: Node = null

var _monitor_target := ""
var _last_transcript := ""
var _stt_connected := false
var expecting_result := false  # flag so main.gd knows to skip display


func setup(voice_pipeline: Node, hub_client: Node) -> void:
	_voice_pipeline = voice_pipeline
	_hub_client = hub_client
	_detect_monitor_source()


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_timer = capture_interval - 2.0
		print("[screen_listen] Enabled — monitoring: ", _monitor_target)
		listening_started.emit()
	else:
		_stop_capture()
		print("[screen_listen] Disabled")
		listening_stopped.emit()


func update(delta: float) -> void:
	if not enabled:
		return

	if _capturing:
		# Wait for capture to finish (duration elapsed)
		var elapsed = (Time.get_ticks_msec() - _capture_start) / 1000.0
		if elapsed >= capture_duration + 2.0:
			_capturing = false
			_transcribe_capture()
		return

	_timer += delta
	if _timer >= capture_interval:
		_timer = 0.0
		_start_capture()


func _detect_monitor_source() -> void:
	var output := []
	# Use pw-cli to find the first audio sink
	var exit = OS.execute("pw-cli", ["list-objects"], output, true)
	if exit == 0 and output.size() > 0:
		var lines = output[0].split("\n")
		for i in range(lines.size()):
			if "Audio/Sink" in lines[i] and i > 0:
				# Look backwards for node.name
				for j in range(max(0, i - 5), i):
					if "node.name" in lines[j]:
						var parts = lines[j].split("\"")
						if parts.size() >= 2:
							_monitor_target = parts[1]
							break
				if not _monitor_target.is_empty():
					break

	if _monitor_target.is_empty():
		_monitor_target = "alsa_output.usb-Astro_Gaming_Astro_MixAmp_Pro-00.stereo-game"
	print("[screen_listen] Monitor target: ", _monitor_target)


func _start_capture() -> void:
	if _monitor_target.is_empty():
		return

	_capture_file = "/tmp/kira_screen_audio.wav"
	_capturing = true
	_capture_start = Time.get_ticks_msec()

	# Use OS.create_process for non-blocking execution
	# pw-record defaults to float32 stereo — convert to 16kHz mono PCM WAV for STT
	OS.create_process("bash", [
		"-c",
		"timeout %d pw-record --target %s --format s16 --rate 16000 --channels 1 %s 2>/dev/null" % [
			int(capture_duration), _monitor_target, _capture_file
		]
	])

	print("[screen_listen] Capturing %ds of system audio..." % int(capture_duration))


func _transcribe_capture() -> void:
	if not FileAccess.file_exists(_capture_file):
		print("[screen_listen] No capture file found")
		return

	var audio_data = FileAccess.get_file_as_bytes(_capture_file)
	_cleanup_file()

	if audio_data.size() < 10000:
		print("[screen_listen] Capture too small: ", audio_data.size(), " bytes")
		return

	if _hub_client and _hub_client._is_connected:
		var b64 = Marshalls.raw_to_base64(audio_data)

		# Connect to STT result if not already
		if not _stt_connected:
			_hub_client.stt_result.connect(_on_stt_transcript)
			_stt_connected = true

		_hub_client._send({
			"type": "stt.audio",
			"id": _hub_client._uuid(),
			"ts": Time.get_unix_time_from_system(),
			"payload": {
				"audio_b64": b64,
				"format": "wav",
				"sample_rate": 16000,
				"auto_chat": false,
				"history": [],
			},
		})
		expecting_result = true
		print("[screen_listen] Sent %dKB to STT" % (audio_data.size() / 1024))
	else:
		print("[screen_listen] Hub not connected, skipping transcription")


func _on_stt_transcript(text: String) -> void:
	if not expecting_result:
		return  # this STT result is from mic, not us
	expecting_result = false

	if text.is_empty() or text.begins_with("[STT error"):
		return
	if text == _last_transcript:
		return
	_last_transcript = text
	if text.length() < 15:
		return

	print("[screen_listen] Transcript: ", text.substr(0, 100))
	transcript_ready.emit(text, "system_audio")


func _stop_capture() -> void:
	_capturing = false
	var kill_output := []
	OS.execute("pkill", ["-f", "pw-record.*kira_screen_audio"], kill_output, true)
	_cleanup_file()


func _cleanup_file() -> void:
	if _capture_file != "" and FileAccess.file_exists(_capture_file):
		DirAccess.remove_absolute(_capture_file)
