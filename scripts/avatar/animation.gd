extends Node
class_name AvatarAnimation

# VRMA animation player — loads VRMA animations and applies bone transforms
# to the target VRM skeleton.
#
# All animations must be proper VRMA format (VRM humanoid bone names,
# identity source rest). Raw Mixamo files won't work — convert them first.
#
# VRMA files import as Node3D hierarchies (not Skeleton3D), so we read
# Node3D transforms from the animated source tree and map them to
# skeleton bone poses on the target model by matching node names to bone names.
#
# Only body bones are animated. Hair, face, eyes, secondary bones
# are left alone so spring bone physics and expressions still work.

signal animation_loaded(anim_name: String)

var _clips := {}  # name → { scene, player, node_map, bone_map }
var _current_clip := ""
var _target_skeleton: Skeleton3D = null
var debug_anim := false  # toggle: $Animation.debug_anim = true/false

const ANIMATIONS_DIR := "res://assets/animations"

# VRM humanoid bone name → J_Bip_* skeleton bone name mapping
const HUMANOID_TO_JBIP := {
	"hips": "J_Bip_C_Hips", "spine": "J_Bip_C_Spine", "chest": "J_Bip_C_Chest",
	"upperChest": "J_Bip_C_UpperChest", "neck": "J_Bip_C_Neck", "head": "J_Bip_C_Head",
	"leftShoulder": "J_Bip_L_Shoulder", "leftUpperArm": "J_Bip_L_UpperArm",
	"leftLowerArm": "J_Bip_L_LowerArm", "leftHand": "J_Bip_L_Hand",
	"rightShoulder": "J_Bip_R_Shoulder", "rightUpperArm": "J_Bip_R_UpperArm",
	"rightLowerArm": "J_Bip_R_LowerArm", "rightHand": "J_Bip_R_Hand",
	"leftUpperLeg": "J_Bip_L_UpperLeg", "leftLowerLeg": "J_Bip_L_LowerLeg",
	"leftFoot": "J_Bip_L_Foot", "leftToes": "J_Bip_L_ToeBase",
	"rightUpperLeg": "J_Bip_R_UpperLeg", "rightLowerLeg": "J_Bip_R_LowerLeg",
	"rightFoot": "J_Bip_R_Foot", "rightToes": "J_Bip_R_ToeBase",
	"leftThumbMetacarpal": "J_Bip_L_Thumb1", "leftThumbProximal": "J_Bip_L_Thumb2",
	"leftThumbDistal": "J_Bip_L_Thumb3",
	"leftIndexProximal": "J_Bip_L_Index1", "leftIndexIntermediate": "J_Bip_L_Index2",
	"leftIndexDistal": "J_Bip_L_Index3",
	"leftMiddleProximal": "J_Bip_L_Middle1", "leftMiddleIntermediate": "J_Bip_L_Middle2",
	"leftMiddleDistal": "J_Bip_L_Middle3",
	"leftRingProximal": "J_Bip_L_Ring1", "leftRingIntermediate": "J_Bip_L_Ring2",
	"leftRingDistal": "J_Bip_L_Ring3",
	"leftLittleProximal": "J_Bip_L_Little1", "leftLittleIntermediate": "J_Bip_L_Little2",
	"leftLittleDistal": "J_Bip_L_Little3",
	"rightThumbMetacarpal": "J_Bip_R_Thumb1", "rightThumbProximal": "J_Bip_R_Thumb2",
	"rightThumbDistal": "J_Bip_R_Thumb3",
	"rightIndexProximal": "J_Bip_R_Index1", "rightIndexIntermediate": "J_Bip_R_Index2",
	"rightIndexDistal": "J_Bip_R_Index3",
	"rightMiddleProximal": "J_Bip_R_Middle1", "rightMiddleIntermediate": "J_Bip_R_Middle2",
	"rightMiddleDistal": "J_Bip_R_Middle3",
	"rightRingProximal": "J_Bip_R_Ring1", "rightRingIntermediate": "J_Bip_R_Ring2",
	"rightRingDistal": "J_Bip_R_Ring3",
	"rightLittleProximal": "J_Bip_R_Little1", "rightLittleIntermediate": "J_Bip_R_Little2",
	"rightLittleDistal": "J_Bip_R_Little3",
	# PascalCase variants (some VRMA exporters use this)
	"Hips": "J_Bip_C_Hips", "Spine": "J_Bip_C_Spine", "Chest": "J_Bip_C_Chest",
	"UpperChest": "J_Bip_C_UpperChest", "Neck": "J_Bip_C_Neck", "Head": "J_Bip_C_Head",
	"LeftShoulder": "J_Bip_L_Shoulder", "LeftUpperArm": "J_Bip_L_UpperArm",
	"LeftLowerArm": "J_Bip_L_LowerArm", "LeftHand": "J_Bip_L_Hand",
	"RightShoulder": "J_Bip_R_Shoulder", "RightUpperArm": "J_Bip_R_UpperArm",
	"RightLowerArm": "J_Bip_R_LowerArm", "RightHand": "J_Bip_R_Hand",
	"LeftUpperLeg": "J_Bip_L_UpperLeg", "LeftLowerLeg": "J_Bip_L_LowerLeg",
	"LeftFoot": "J_Bip_L_Foot", "LeftToes": "J_Bip_L_ToeBase",
	"RightUpperLeg": "J_Bip_R_UpperLeg", "RightLowerLeg": "J_Bip_R_LowerLeg",
	"RightFoot": "J_Bip_R_Foot", "RightToes": "J_Bip_R_ToeBase",
	"LeftThumbProximal": "J_Bip_L_Thumb1", "LeftThumbIntermediate": "J_Bip_L_Thumb2",
	"LeftThumbDistal": "J_Bip_L_Thumb3",
	"LeftIndexProximal": "J_Bip_L_Index1", "LeftIndexIntermediate": "J_Bip_L_Index2",
	"LeftIndexDistal": "J_Bip_L_Index3",
	"LeftMiddleProximal": "J_Bip_L_Middle1", "LeftMiddleIntermediate": "J_Bip_L_Middle2",
	"LeftMiddleDistal": "J_Bip_L_Middle3",
	"LeftRingProximal": "J_Bip_L_Ring1", "LeftRingIntermediate": "J_Bip_L_Ring2",
	"LeftRingDistal": "J_Bip_L_Ring3",
	"LeftLittleProximal": "J_Bip_L_Little1", "LeftLittleIntermediate": "J_Bip_L_Little2",
	"LeftLittleDistal": "J_Bip_L_Little3",
	"RightThumbProximal": "J_Bip_R_Thumb1", "RightThumbIntermediate": "J_Bip_R_Thumb2",
	"RightThumbDistal": "J_Bip_R_Thumb3",
	"RightIndexProximal": "J_Bip_R_Index1", "RightIndexIntermediate": "J_Bip_R_Index2",
	"RightIndexDistal": "J_Bip_R_Index3",
	"RightMiddleProximal": "J_Bip_R_Middle1", "RightMiddleIntermediate": "J_Bip_R_Middle2",
	"RightMiddleDistal": "J_Bip_R_Middle3",
	"RightRingProximal": "J_Bip_R_Ring1", "RightRingIntermediate": "J_Bip_R_Ring2",
	"RightRingDistal": "J_Bip_R_Ring3",
	"RightLittleProximal": "J_Bip_R_Little1", "RightLittleIntermediate": "J_Bip_R_Little2",
	"RightLittleDistal": "J_Bip_R_Little3",
}

# Only animate body bones — skip hair, face, eyes, secondary/physics bones
func _is_body_bone(bone_name: String) -> bool:
	if bone_name.begins_with("J_Bip_"):
		return true
	return bone_name in HUMANOID_TO_JBIP

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

	var player = _find_anim_player(scene)
	if not player:
		scene.queue_free()
		return

	# Build a map of all named Node3D nodes in the hierarchy
	var node_map := {}
	_collect_named_nodes(scene, node_map)

	# Keep the scene alive (hidden) so AnimationPlayer can drive it
	scene.visible = false
	add_child(scene)

	# Stop any autoplay, reset to frame 0
	if player.is_playing():
		player.stop()
	player.seek(0, true)
	player.advance(0)

	_clips[anim_name] = {
		"scene": scene,
		"player": player,
		"node_map": node_map,
		"bone_map": {},
	}

	var anims = player.get_animation_list()
	if anims.size() > 0:
		player.play(anims[0])
		player.seek(0, true)
		print("[anim] Loaded: ", anim_name, " (", node_map.size(), " nodes)")
		animation_loaded.emit(anim_name)

func _collect_named_nodes(node: Node, map: Dictionary) -> void:
	if node is Node3D and node.name != "AuxScene":
		map[str(node.name)] = node
	for child in node.get_children():
		if child is Node3D:
			_collect_named_nodes(child, map)

func setup(model: Node3D) -> void:
	_target_skeleton = _find_skeleton(model)
	if not _target_skeleton:
		print("[anim] No skeleton in model")
		return

	print("[anim] Target skeleton: ", _target_skeleton.get_bone_count(), " bones")

	for clip_name in _clips:
		var clip = _clips[clip_name]
		var node_map: Dictionary = clip["node_map"]
		var bone_map := {}  # node_name → target_bone_index
		var matched := 0

		for node_name in node_map:
			if not _is_body_bone(node_name):
				continue

			# Try direct match first (J_Bip_* names)
			var bone_idx = _target_skeleton.find_bone(node_name)

			# Try humanoid → J_Bip translation
			if bone_idx < 0 and node_name in HUMANOID_TO_JBIP:
				bone_idx = _target_skeleton.find_bone(HUMANOID_TO_JBIP[node_name])

			if bone_idx >= 0:
				bone_map[node_name] = bone_idx
				matched += 1

		clip["bone_map"] = bone_map
		print("[anim] ", clip_name, ": ", matched, " body bones matched")

func set_bone_mapping(mapping: Dictionary) -> void:
	"""Apply a model_mapper bone mapping — supplements existing mappings.
	mapping keys are humanoid canonical names (hips, spine, etc.),
	values are actual bone names in the model's skeleton.
	Only re-maps clips that had poor initial matching (< 10 bones)."""
	if not _target_skeleton:
		return
	for clip_name in _clips:
		var clip = _clips[clip_name]
		var existing_map: Dictionary = clip["bone_map"]

		if existing_map.size() >= 10:
			print("[anim] Keeping existing mapping for ", clip_name, ": ", existing_map.size(), " bones")
			continue

		var node_map: Dictionary = clip["node_map"]
		var bone_map := {}
		var matched := 0

		for node_name in node_map:
			var bone_idx = _target_skeleton.find_bone(node_name)

			if bone_idx < 0 and node_name in mapping:
				bone_idx = _target_skeleton.find_bone(mapping[node_name])

			if bone_idx < 0 and node_name in HUMANOID_TO_JBIP:
				bone_idx = _target_skeleton.find_bone(HUMANOID_TO_JBIP[node_name])

			if bone_idx >= 0:
				bone_map[node_name] = bone_idx
				matched += 1

		clip["bone_map"] = bone_map
		print("[anim] Re-mapped ", clip_name, " with model_mapper: ", matched, " bones")


func play(anim_name: String) -> void:
	if anim_name not in _clips:
		return
	# Stop current clip
	if _current_clip in _clips:
		_clips[_current_clip]["player"].stop()
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
	var player: AnimationPlayer = clip["player"]
	var node_map: Dictionary = clip["node_map"]
	var bone_map: Dictionary = clip["bone_map"]

	if not player.is_playing():
		var anims = player.get_animation_list()
		if anims.size() > 0:
			player.play(anims[0])

	# VRMA animations: direct quaternion copy.
	# Proper VRMA files have identity source rest and VRM-compatible bone orientations.
	# In Godot 4, set_bone_pose_rotation IS the final local rotation (not delta from rest).
	for node_name in bone_map:
		var bone_idx: int = bone_map[node_name]
		var src_node: Node3D = node_map[node_name]

		_target_skeleton.set_bone_pose_rotation(bone_idx, src_node.quaternion)

		if node_name.ends_with("Hips") or node_name == "hips" or node_name == "Hips":
			_target_skeleton.set_bone_pose_position(bone_idx, src_node.position)

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
