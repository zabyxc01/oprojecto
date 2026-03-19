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
var capture_duration := 15.0  # seconds per chunk
var capture_interval := 30.0  # seconds between captures
var _timer := 0.0
var _capturing := false
var _capture_pid := -1
var _capture_file := ""
var _voice_pipeline: Node = null
var _hub_client: Node = null

# PipeWire monitor target — detected at setup
var _monitor_target := ""

# Last transcript to avoid repeating
var _last_transcript := ""


func setup(voice_pipeline: Node, hub_client: Node) -> void:
	_voice_pipeline = voice_pipeline
	_hub_client = hub_client
	_detect_monitor_source()


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_timer = capture_interval - 2.0  # start first capture soon
		print("[screen_listen] Enabled — monitoring: ", _monitor_target)
		listening_started.emit()
	else:
		_stop_capture()
		print("[screen_listen] Disabled")
		listening_stopped.emit()


func update(delta: float) -> void:
	if not enabled:
		return

	# Check if a capture just finished
	if _capturing:
		_check_capture_done()
		return

	_timer += delta
	if _timer >= capture_interval:
		_timer = 0.0
		_start_capture()


func _detect_monitor_source() -> void:
	"""Find the default audio output sink to monitor."""
	var output := []
	# Find audio sinks (output devices)
	var exit = OS.execute("bash", ["-c",
		"pw-cli list-objects 2>/dev/null | grep -B1 'Audio/Sink' | grep node.name | head -1 | sed 's/.*= \"//;s/\"//' "
	], output, true)
	if exit == 0 and output.size() > 0:
		_monitor_target = output[0].strip_edges()
	if _monitor_target.is_empty():
		_monitor_target = "alsa_output.usb-Astro_Gaming_Astro_MixAmp_Pro-00.stereo-game"
	print("[screen_listen] Monitor target: ", _monitor_target)


func _start_capture() -> void:
	"""Start capturing system audio to a temp WAV file."""
	if _monitor_target.is_empty():
		return

	_capture_file = "/tmp/kira_screen_audio_%d.wav" % Time.get_ticks_msec()
	_capturing = true

	# pw-record captures from the monitor source for N seconds
	# Run in background, we'll check when it's done
	var args = [
		"-c", "pw-record --target %s %s & echo $!; sleep %d; kill $! 2>/dev/null" % [
			_monitor_target, _capture_file, int(capture_duration)
		]
	]
	var pid_output := []
	OS.execute("bash", args, pid_output, false)
	# Non-blocking — we'll poll for the file to appear and stabilize

	print("[screen_listen] Capturing %ds of system audio..." % int(capture_duration))


func _check_capture_done() -> void:
	"""Check if the capture file is ready (exists and no longer growing)."""
	if not FileAccess.file_exists(_capture_file):
		# Still recording or failed — check timeout
		if _timer > capture_duration + 5.0:
			print("[screen_listen] Capture timed out")
			_capturing = false
		_timer += get_process_delta_time()
		return

	# Check file size — if it's big enough, the recording is done
	var file = FileAccess.open(_capture_file, FileAccess.READ)
	if not file:
		_capturing = false
		return
	var size = file.get_length()
	file.close()

	# 16kHz mono 16-bit = 32000 bytes/sec. 15s = ~480KB minimum
	if size < 32000 * int(capture_duration * 0.5):
		_timer += get_process_delta_time()
		if _timer > capture_duration + 8.0:
			_capturing = false
			_cleanup_file()
		return

	# File is ready — send to STT
	_capturing = false
	_transcribe_capture()


func _transcribe_capture() -> void:
	"""Send the captured audio to faster-whisper for transcription."""
	if not FileAccess.file_exists(_capture_file):
		return

	var audio_data = FileAccess.get_file_as_bytes(_capture_file)
	_cleanup_file()

	if audio_data.is_empty():
		return

	# Send to hub for STT (but NOT auto_chat — we handle the transcript ourselves)
	if _hub_client and _hub_client._is_connected:
		var b64 = Marshalls.raw_to_base64(audio_data)
		_hub_client._send({
			"type": "stt.audio",
			"id": _hub_client._uuid(),
			"ts": Time.get_unix_time_from_system(),
			"payload": {
				"audio_b64": b64,
				"format": "wav",
				"sample_rate": 48000,
				"auto_chat": false,  # DO NOT auto-chain to chat — we process it
				"history": [],
			},
		})
		# Listen for the transcript response
		if not _hub_client.stt_result.is_connected(_on_stt_transcript):
			_hub_client.stt_result.connect(_on_stt_transcript)
		print("[screen_listen] Sent %dKB to STT" % (audio_data.size() / 1024))


func _on_stt_transcript(text: String) -> void:
	"""Handle STT transcript of system audio."""
	if text.is_empty() or text.begins_with("[STT error"):
		return

	# Skip if same as last transcript (video paused, loop, etc.)
	if text == _last_transcript:
		return
	_last_transcript = text

	# Skip very short transcripts (noise, single words)
	if text.length() < 15:
		return

	print("[screen_listen] Transcript: ", text.substr(0, 100))
	transcript_ready.emit(text, "system_audio")


func _stop_capture() -> void:
	_capturing = false
	# Kill any running pw-record
	OS.execute("bash", ["-c", "pkill -f 'pw-record.*kira_screen_audio' 2>/dev/null"], [], true)
	_cleanup_file()


func _cleanup_file() -> void:
	if _capture_file != "" and FileAccess.file_exists(_capture_file):
		DirAccess.remove_absolute(_capture_file)
	_capture_file = ""
