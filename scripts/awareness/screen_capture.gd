extends Node
class_name ScreenCapture

## Captures screenshots for Live mode vision queries.
## Uses ImageMagick `import` for X11 screen capture, resizes + compresses,
## then emits the base64-encoded JPEG for vision model consumption.

signal screenshot_ready(image_b64: String)

var enabled := false
var capture_interval := 20.0  # seconds between captures
var _timer := 0.0
var _capturing := false
var _capture_file := "/tmp/kira_screenshot.jpg"
var _capture_pid := -1


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_timer = capture_interval - 2.0  # trigger first capture quickly
		print("[screen_capture] Enabled — interval: %.0fs" % capture_interval)
	else:
		_capturing = false
		_cleanup_file()
		print("[screen_capture] Disabled")


func update(delta: float) -> void:
	if not enabled:
		return

	if _capturing:
		_check_capture_done()
		return

	_timer += delta
	if _timer >= capture_interval:
		_timer = 0.0
		_start_capture()


func _start_capture() -> void:
	if _capturing:
		return

	# Clean up any stale file from a previous capture
	_cleanup_file()

	_capturing = true
	# Use ffmpeg x11grab for non-interactive screenshot capture.
	# Captures full screen, resizes to 960x540, JPEG quality 5 (good enough for vision).
	_capture_pid = OS.create_process("ffmpeg", [
		"-f", "x11grab",
		"-video_size", "3440x1440",
		"-i", ":0",
		"-frames:v", "1",
		"-vf", "scale=960:540",
		"-q:v", "5",
		"-update", "1",
		"-y",
		_capture_file,
	])
	print("[screen_capture] Capture started (pid=%d)" % _capture_pid)


func _check_capture_done() -> void:
	# Check if the file exists and has stabilized (size > 1000 bytes)
	if not FileAccess.file_exists(_capture_file):
		return

	var file := FileAccess.open(_capture_file, FileAccess.READ)
	if file == null:
		return
	var size := file.get_length()
	file.close()

	if size < 1000:
		# File still being written
		return

	# File is ready — read and encode
	_capturing = false
	_capture_pid = -1

	var image_bytes := FileAccess.get_file_as_bytes(_capture_file)
	if image_bytes.is_empty():
		print("[screen_capture] Empty capture file")
		_cleanup_file()
		return

	var b64 := Marshalls.raw_to_base64(image_bytes)
	_cleanup_file()

	print("[screen_capture] Screenshot ready: %dKB JPEG → %dKB base64" % [
		image_bytes.size() / 1024, b64.length() / 1024
	])
	screenshot_ready.emit(b64)


func _cleanup_file() -> void:
	if FileAccess.file_exists(_capture_file):
		DirAccess.remove_absolute(_capture_file)
