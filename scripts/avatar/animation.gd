extends Node
class_name AvatarAnimation

# Simple VRMA animation player — loads GLTF animations and applies
# bone transforms directly to the target skeleton by matching bone names.

signal animation_loaded(anim_name: String)

var _clips := {}  # name → { skeleton: Skeleton3D, player: AnimationPlayer, scene: Node3D }
var _current_clip := ""
var _target_skeleton: Skeleton3D = null

const ANIMATIONS_DIR := "res://assets/animations"

func load_all_animations() -> void:
	var dir = DirAccess.open(ANIMATIONS_DIR)
	if not dir:
		print("[anim] No animations directory")
		return

	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".vrma") or file.ends_with(".glb"):
			var anim_name = file.get_basename()
			_load_clip(ANIMATIONS_DIR.path_join(file), anim_name)
		file = dir.get_next()

	print("[anim] Loaded ", _clips.size(), " clips")

func _load_clip(path: String, anim_name: String) -> void:
	var gltf = GLTFDocument.new()
	var state = GLTFState.new()

	if gltf.append_from_file(path, state) != OK:
		return

	var scene = gltf.generate_scene(state)
	if not scene:
		return

	var skel = _find_skeleton(scene)
	var player = _find_anim_player(scene)

	if not skel or not player:
		scene.queue_free()
		return

	# Keep the scene alive (hidden) so we can sample its animations
	scene.visible = false
	add_child(scene)

	_clips[anim_name] = {
		"scene": scene,
		"skeleton": skel,
		"player": player,
	}

	# Start playing the animation on the source skeleton
	var anims = player.get_animation_list()
	if anims.size() > 0:
		player.play(anims[0])
		player.seek(0, true)
		print("[anim] Loaded: ", anim_name, " (", anims.size(), " anims, ", skel.get_bone_count(), " bones)")
		animation_loaded.emit(anim_name)

func setup(model: Node3D) -> void:
	_target_skeleton = _find_skeleton(model)
	if not _target_skeleton:
		print("[anim] No skeleton in model")
		return

	print("[anim] Target skeleton: ", _target_skeleton.get_bone_count(), " bones")

func play(anim_name: String) -> void:
	if anim_name not in _clips:
		return
	_current_clip = anim_name
	var clip = _clips[anim_name]
	var anims = clip["player"].get_animation_list()
	if anims.size() > 0:
		clip["player"].play(anims[0])
	print("[anim] Playing: ", anim_name)

func stop() -> void:
	if _current_clip in _clips:
		_clips[_current_clip]["player"].stop()
	_current_clip = ""

func update(delta: float) -> void:
	if _current_clip.is_empty() or not _target_skeleton:
		return
	if _current_clip not in _clips:
		return

	var clip = _clips[_current_clip]
	var src_skel: Skeleton3D = clip["skeleton"]

	# Copy matching bone poses from source to target
	for i in range(src_skel.get_bone_count()):
		var bone_name = src_skel.get_bone_name(i)
		var target_idx = _target_skeleton.find_bone(bone_name)
		if target_idx >= 0:
			_target_skeleton.set_bone_pose_rotation(target_idx, src_skel.get_bone_pose_rotation(i))
			_target_skeleton.set_bone_pose_position(target_idx, src_skel.get_bone_pose_position(i))

func has_animation(name: String) -> bool:
	return name in _clips

func get_available() -> PackedStringArray:
	return PackedStringArray(_clips.keys())

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_anim_player(child)
		if found:
			return found
	return null
