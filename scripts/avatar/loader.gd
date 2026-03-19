extends Node
class_name AvatarLoader

# Loads VRM/GLB/GLTF models into the scene
# For VRM: requires godot-vrm addon
# For GLB/GLTF: uses built-in importer

signal model_loaded(model: Node3D)
signal model_failed(error: String)

func load_model(path: String) -> void:
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		# Try absolute path
		if not FileAccess.file_exists(path):
			print("[loader] Model not found: ", path)
			model_failed.emit("File not found: " + path)
			return

	print("[loader] Loading: ", path)

	if path.ends_with(".vrm"):
		_load_vrm(path)
	elif path.ends_with(".glb") or path.ends_with(".gltf"):
		_load_gltf(path)
	else:
		model_failed.emit("Unsupported format: " + path)

func _load_gltf(path: String) -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()

	var err := gltf.append_from_file(path, state)
	if err != OK:
		model_failed.emit("GLTF load failed: " + str(err))
		return

	var scene := gltf.generate_scene(state)
	if scene:
		model_loaded.emit(scene)
	else:
		model_failed.emit("Failed to generate scene from GLTF")

func _load_vrm(path: String) -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()

	# Register material extensions only — they don't rename/rotate bones
	# VRMC_vrm is NOT registered because it runs perform_retarget() which
	# renames bones (J_Bip_* → Hips/Spine/etc.) and changes rest poses,
	# breaking all animation bone mapping. VRMC_vrm_animation is a stub.
	var exts: Array[GLTFDocumentExtension] = []
	for ext_path in [
		"res://addons/vrm/1.0/VRMC_materials_hdr_emissiveMultiplier.gd",
		"res://addons/vrm/1.0/VRMC_materials_mtoon.gd",
	]:
		var script = load(ext_path)
		if script:
			var inst: GLTFDocumentExtension = script.new()
			GLTFDocument.register_gltf_document_extension(inst)
			exts.append(inst)

	var err := gltf.append_from_file(path, state)
	if err != OK:
		print("[loader] VRM load failed: ", err)
		_unregister_exts(exts)
		model_failed.emit("VRM load failed: " + str(err))
		return

	var scene := gltf.generate_scene(state)
	_unregister_exts(exts)

	if scene:
		print("[loader] VRM loaded (materials active, bones in original space)")
		model_loaded.emit(scene)
	else:
		model_failed.emit("Failed to generate scene from VRM")

func _unregister_exts(exts: Array[GLTFDocumentExtension]) -> void:
	for ext in exts:
		GLTFDocument.unregister_gltf_document_extension(ext)

# Scan a directory for loadable models
static func scan_models(dir_path: String) -> PackedStringArray:
	var models := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if not dir:
		return models

	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".vrm") or file.ends_with(".glb") or file.ends_with(".gltf"):
			models.append(dir_path.path_join(file))
		file = dir.get_next()

	models.sort()
	return models
