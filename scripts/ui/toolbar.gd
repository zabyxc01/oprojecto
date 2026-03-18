extends PanelContainer
class_name Toolbar

## Self-contained toolbar — model/anim/TTS selectors, width/font sliders.
## Extracted from main.gd.

signal model_selected(index: int)
signal anim_selected(index: int)
signal tts_selected(index: int)
signal width_changed(value: float)
signal font_changed(value: float)

var model_selector: OptionButton
var anim_selector: OptionButton
var tts_selector: OptionButton

const MODELS_DIR := "/mnt/storage/staging/ai-models-animations/vrm-models/"


func build(config: Node) -> void:
	var tb_style = StyleBoxFlat.new()
	tb_style.bg_color = Color(0.08, 0.08, 0.08, 0.9)
	tb_style.corner_radius_top_left = 8
	tb_style.corner_radius_top_right = 8
	tb_style.corner_radius_bottom_left = 8
	tb_style.corner_radius_bottom_right = 8
	tb_style.content_margin_left = 10
	tb_style.content_margin_right = 10
	tb_style.content_margin_top = 8
	tb_style.content_margin_bottom = 8

	add_theme_stylebox_override("panel", tb_style)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(10, 10)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var tb_vbox = VBoxContainer.new()
	add_child(tb_vbox)

	# Row 1: Model + Animation
	var row1 = HBoxContainer.new()
	tb_vbox.add_child(row1)

	_add_label(row1, "Model:")
	model_selector = _add_dropdown(row1, 160)
	model_selector.add_item("default", 0)
	var mdir = DirAccess.open(MODELS_DIR)
	if mdir:
		mdir.list_dir_begin()
		var mfile = mdir.get_next()
		var midx = 1
		while mfile != "":
			if mfile.ends_with(".vrm"):
				model_selector.add_item(mfile.get_basename(), midx)
				midx += 1
			mfile = mdir.get_next()
	model_selector.item_selected.connect(func(idx): model_selected.emit(idx))

	_add_spacer(row1)
	_add_label(row1, "Anim:")
	anim_selector = _add_dropdown(row1, 120)
	anim_selector.add_item("(none)", 0)
	anim_selector.item_selected.connect(func(idx): anim_selected.emit(idx))

	# Row 2: TTS engine
	var row2 = HBoxContainer.new()
	tb_vbox.add_child(row2)

	_add_label(row2, "TTS:")
	tts_selector = _add_dropdown(row2, 120)
	tts_selector.add_item("kokoro", 0)
	tts_selector.add_item("indextts", 1)
	tts_selector.add_item("oaudio", 2)
	tts_selector.add_item("f5", 3)
	tts_selector.item_selected.connect(func(idx): tts_selected.emit(idx))

	# Row 3: Chat width + font size
	var row3 = HBoxContainer.new()
	tb_vbox.add_child(row3)

	_add_label(row3, "Width:")
	var width_slider = HSlider.new()
	width_slider.min_value = 200
	width_slider.max_value = 600
	width_slider.value = config.chat_width
	width_slider.step = 10
	width_slider.custom_minimum_size = Vector2(100, 0)
	width_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row3.add_child(width_slider)
	width_slider.value_changed.connect(func(v): width_changed.emit(v))

	_add_spacer(row3)
	_add_label(row3, "Font:")
	var font_slider = HSlider.new()
	font_slider.min_value = 10
	font_slider.max_value = 20
	font_slider.value = config.chat_font_size
	font_slider.step = 1
	font_slider.custom_minimum_size = Vector2(80, 0)
	font_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row3.add_child(font_slider)
	font_slider.value_changed.connect(func(v): font_changed.emit(v))

	visible = false


func refresh_animations(available: PackedStringArray) -> void:
	anim_selector.clear()
	anim_selector.add_item("(none)", 0)
	var idx = 1
	for aname in available:
		anim_selector.add_item(aname, idx)
		idx += 1


func _add_label(parent: Node, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	parent.add_child(lbl)


func _add_dropdown(parent: Node, min_width: int) -> OptionButton:
	var dd = OptionButton.new()
	dd.custom_minimum_size = Vector2(min_width, 0)
	dd.add_theme_font_size_override("font_size", 11)
	dd.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dd)
	return dd


func _add_spacer(parent: Node) -> void:
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	parent.add_child(spacer)
