extends Node
class_name ModelMapper

# Format-agnostic model mapper — scans any humanoid 3D model (VRM, GLTF, GLB,
# Mixamo, Blender, etc.) and produces a unified bone + blend shape mapping.
#
# The mapping is cached per model hash under user://model_maps/ so subsequent
# loads skip the scan entirely.

signal mapping_complete(mapping: Dictionary)
signal mapping_loaded(mapping: Dictionary)   # from cache
signal scan_complete(scan_result: Dictionary) # raw scan before mapping

# ---------------------------------------------------------------------------
# Standard humanoid bone list (camelCase canonical names)
# ---------------------------------------------------------------------------

const HUMANOID_BONES: PackedStringArray = [
	"hips", "spine", "chest", "upperChest", "neck", "head",
	"leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand",
	"rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand",
	"leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes",
	"rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes",
	"leftThumbProximal", "leftThumbIntermediate", "leftThumbDistal",
	"leftIndexProximal", "leftIndexIntermediate", "leftIndexDistal",
	"leftMiddleProximal", "leftMiddleIntermediate", "leftMiddleDistal",
	"leftRingProximal", "leftRingIntermediate", "leftRingDistal",
	"leftLittleProximal", "leftLittleIntermediate", "leftLittleDistal",
	"rightThumbProximal", "rightThumbIntermediate", "rightThumbDistal",
	"rightIndexProximal", "rightIndexIntermediate", "rightIndexDistal",
	"rightMiddleProximal", "rightMiddleIntermediate", "rightMiddleDistal",
	"rightRingProximal", "rightRingIntermediate", "rightRingDistal",
	"rightLittleProximal", "rightLittleIntermediate", "rightLittleDistal",
]

# ---------------------------------------------------------------------------
# Naming convention tables
# ---------------------------------------------------------------------------

# VRM (J_Bip_*) bone mapping
const _VRM_BONES := {
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
	"leftThumbProximal": "J_Bip_L_Thumb1", "leftThumbIntermediate": "J_Bip_L_Thumb2",
	"leftThumbDistal": "J_Bip_L_Thumb3",
	"leftIndexProximal": "J_Bip_L_Index1", "leftIndexIntermediate": "J_Bip_L_Index2",
	"leftIndexDistal": "J_Bip_L_Index3",
	"leftMiddleProximal": "J_Bip_L_Middle1", "leftMiddleIntermediate": "J_Bip_L_Middle2",
	"leftMiddleDistal": "J_Bip_L_Middle3",
	"leftRingProximal": "J_Bip_L_Ring1", "leftRingIntermediate": "J_Bip_L_Ring2",
	"leftRingDistal": "J_Bip_L_Ring3",
	"leftLittleProximal": "J_Bip_L_Little1", "leftLittleIntermediate": "J_Bip_L_Little2",
	"leftLittleDistal": "J_Bip_L_Little3",
	"rightThumbProximal": "J_Bip_R_Thumb1", "rightThumbIntermediate": "J_Bip_R_Thumb2",
	"rightThumbDistal": "J_Bip_R_Thumb3",
	"rightIndexProximal": "J_Bip_R_Index1", "rightIndexIntermediate": "J_Bip_R_Index2",
	"rightIndexDistal": "J_Bip_R_Index3",
	"rightMiddleProximal": "J_Bip_R_Middle1", "rightMiddleIntermediate": "J_Bip_R_Middle2",
	"rightMiddleDistal": "J_Bip_R_Middle3",
	"rightRingProximal": "J_Bip_R_Ring1", "rightRingIntermediate": "J_Bip_R_Ring2",
	"rightRingDistal": "J_Bip_R_Ring3",
	"rightLittleProximal": "J_Bip_R_Little1", "rightLittleIntermediate": "J_Bip_R_Little2",
	"rightLittleDistal": "J_Bip_R_Little3",
}

# Mixamo (mixamorig:*) bone mapping
const _MIXAMO_BONES := {
	"hips": "mixamorig:Hips", "spine": "mixamorig:Spine", "chest": "mixamorig:Spine1",
	"upperChest": "mixamorig:Spine2", "neck": "mixamorig:Neck", "head": "mixamorig:Head",
	"leftShoulder": "mixamorig:LeftShoulder", "leftUpperArm": "mixamorig:LeftArm",
	"leftLowerArm": "mixamorig:LeftForeArm", "leftHand": "mixamorig:LeftHand",
	"rightShoulder": "mixamorig:RightShoulder", "rightUpperArm": "mixamorig:RightArm",
	"rightLowerArm": "mixamorig:RightForeArm", "rightHand": "mixamorig:RightHand",
	"leftUpperLeg": "mixamorig:LeftUpLeg", "leftLowerLeg": "mixamorig:LeftLeg",
	"leftFoot": "mixamorig:LeftFoot", "leftToes": "mixamorig:LeftToeBase",
	"rightUpperLeg": "mixamorig:RightUpLeg", "rightLowerLeg": "mixamorig:RightLeg",
	"rightFoot": "mixamorig:RightFoot", "rightToes": "mixamorig:RightToeBase",
	"leftThumbProximal": "mixamorig:LeftHandThumb1",
	"leftThumbIntermediate": "mixamorig:LeftHandThumb2",
	"leftThumbDistal": "mixamorig:LeftHandThumb3",
	"leftIndexProximal": "mixamorig:LeftHandIndex1",
	"leftIndexIntermediate": "mixamorig:LeftHandIndex2",
	"leftIndexDistal": "mixamorig:LeftHandIndex3",
	"leftMiddleProximal": "mixamorig:LeftHandMiddle1",
	"leftMiddleIntermediate": "mixamorig:LeftHandMiddle2",
	"leftMiddleDistal": "mixamorig:LeftHandMiddle3",
	"leftRingProximal": "mixamorig:LeftHandRing1",
	"leftRingIntermediate": "mixamorig:LeftHandRing2",
	"leftRingDistal": "mixamorig:LeftHandRing3",
	"leftLittleProximal": "mixamorig:LeftHandPinky1",
	"leftLittleIntermediate": "mixamorig:LeftHandPinky2",
	"leftLittleDistal": "mixamorig:LeftHandPinky3",
	"rightThumbProximal": "mixamorig:RightHandThumb1",
	"rightThumbIntermediate": "mixamorig:RightHandThumb2",
	"rightThumbDistal": "mixamorig:RightHandThumb3",
	"rightIndexProximal": "mixamorig:RightHandIndex1",
	"rightIndexIntermediate": "mixamorig:RightHandIndex2",
	"rightIndexDistal": "mixamorig:RightHandIndex3",
	"rightMiddleProximal": "mixamorig:RightHandMiddle1",
	"rightMiddleIntermediate": "mixamorig:RightHandMiddle2",
	"rightMiddleDistal": "mixamorig:RightHandMiddle3",
	"rightRingProximal": "mixamorig:RightHandRing1",
	"rightRingIntermediate": "mixamorig:RightHandRing2",
	"rightRingDistal": "mixamorig:RightHandRing3",
	"rightLittleProximal": "mixamorig:RightHandPinky1",
	"rightLittleIntermediate": "mixamorig:RightHandPinky2",
	"rightLittleDistal": "mixamorig:RightHandPinky3",
}

# Generic / Blender-style names (no prefix, PascalCase or camelCase)
# Maps humanoid canonical name to an array of possible bone names to try
const _GENERIC_BONES := {
	"hips": ["Hips", "hips", "pelvis", "Pelvis", "hip", "Hip"],
	"spine": ["Spine", "spine", "Spine1"],
	"chest": ["Chest", "chest", "Spine1", "Spine2", "UpperBody"],
	"upperChest": ["UpperChest", "upperChest", "Spine2", "Spine3", "UpperBody2"],
	"neck": ["Neck", "neck"],
	"head": ["Head", "head"],
	"leftShoulder": ["LeftShoulder", "Left_Shoulder", "shoulder.L", "Shoulder_L"],
	"leftUpperArm": ["LeftUpperArm", "LeftArm", "Left_Arm", "upper_arm.L", "UpperArm_L"],
	"leftLowerArm": ["LeftLowerArm", "LeftForeArm", "Left_ForeArm", "forearm.L", "LowerArm_L"],
	"leftHand": ["LeftHand", "Left_Hand", "hand.L", "Hand_L"],
	"rightShoulder": ["RightShoulder", "Right_Shoulder", "shoulder.R", "Shoulder_R"],
	"rightUpperArm": ["RightUpperArm", "RightArm", "Right_Arm", "upper_arm.R", "UpperArm_R"],
	"rightLowerArm": ["RightLowerArm", "RightForeArm", "Right_ForeArm", "forearm.R", "LowerArm_R"],
	"rightHand": ["RightHand", "Right_Hand", "hand.R", "Hand_R"],
	"leftUpperLeg": ["LeftUpperLeg", "LeftUpLeg", "Left_UpLeg", "thigh.L", "UpperLeg_L"],
	"leftLowerLeg": ["LeftLowerLeg", "LeftLeg", "Left_Leg", "shin.L", "LowerLeg_L"],
	"leftFoot": ["LeftFoot", "Left_Foot", "foot.L", "Foot_L"],
	"leftToes": ["LeftToeBase", "LeftToes", "Left_ToeBase", "toe.L", "Toes_L"],
	"rightUpperLeg": ["RightUpperLeg", "RightUpLeg", "Right_UpLeg", "thigh.R", "UpperLeg_R"],
	"rightLowerLeg": ["RightLowerLeg", "RightLeg", "Right_Leg", "shin.R", "LowerLeg_R"],
	"rightFoot": ["RightFoot", "Right_Foot", "foot.R", "Foot_R"],
	"rightToes": ["RightToeBase", "RightToes", "Right_ToeBase", "toe.R", "Toes_R"],
	"leftThumbProximal": ["LeftHandThumb1", "thumb_01.L", "Thumb1_L"],
	"leftThumbIntermediate": ["LeftHandThumb2", "thumb_02.L", "Thumb2_L"],
	"leftThumbDistal": ["LeftHandThumb3", "thumb_03.L", "Thumb3_L"],
	"leftIndexProximal": ["LeftHandIndex1", "index_01.L", "Index1_L"],
	"leftIndexIntermediate": ["LeftHandIndex2", "index_02.L", "Index2_L"],
	"leftIndexDistal": ["LeftHandIndex3", "index_03.L", "Index3_L"],
	"leftMiddleProximal": ["LeftHandMiddle1", "middle_01.L", "Middle1_L"],
	"leftMiddleIntermediate": ["LeftHandMiddle2", "middle_02.L", "Middle2_L"],
	"leftMiddleDistal": ["LeftHandMiddle3", "middle_03.L", "Middle3_L"],
	"leftRingProximal": ["LeftHandRing1", "ring_01.L", "Ring1_L"],
	"leftRingIntermediate": ["LeftHandRing2", "ring_02.L", "Ring2_L"],
	"leftRingDistal": ["LeftHandRing3", "ring_03.L", "Ring3_L"],
	"leftLittleProximal": ["LeftHandPinky1", "pinky_01.L", "Little1_L"],
	"leftLittleIntermediate": ["LeftHandPinky2", "pinky_02.L", "Little2_L"],
	"leftLittleDistal": ["LeftHandPinky3", "pinky_03.L", "Little3_L"],
	"rightThumbProximal": ["RightHandThumb1", "thumb_01.R", "Thumb1_R"],
	"rightThumbIntermediate": ["RightHandThumb2", "thumb_02.R", "Thumb2_R"],
	"rightThumbDistal": ["RightHandThumb3", "thumb_03.R", "Thumb3_R"],
	"rightIndexProximal": ["RightHandIndex1", "index_01.R", "Index1_R"],
	"rightIndexIntermediate": ["RightHandIndex2", "index_02.R", "Index2_R"],
	"rightIndexDistal": ["RightHandIndex3", "index_03.R", "Index3_R"],
	"rightMiddleProximal": ["RightHandMiddle1", "middle_01.R", "Middle1_R"],
	"rightMiddleIntermediate": ["RightHandMiddle2", "middle_02.R", "Middle2_R"],
	"rightMiddleDistal": ["RightHandMiddle3", "middle_03.R", "Middle3_R"],
	"rightRingProximal": ["RightHandRing1", "ring_01.R", "Ring1_R"],
	"rightRingIntermediate": ["RightHandRing2", "ring_02.R", "Ring2_R"],
	"rightRingDistal": ["RightHandRing3", "ring_03.R", "Ring3_R"],
	"rightLittleProximal": ["RightHandPinky1", "pinky_01.R", "Little1_R"],
	"rightLittleIntermediate": ["RightHandPinky2", "pinky_02.R", "Little2_R"],
	"rightLittleDistal": ["RightHandPinky3", "pinky_03.R", "Little3_R"],
}

# ---------------------------------------------------------------------------
# Blend shape / expression name tables
# ---------------------------------------------------------------------------

# Expression blend shape name variants — maps canonical emotion to known names
const _EXPRESSION_SHAPES := {
	"happy": ["Fcl_ALL_Joy", "Fcl_ALL_Happy", "Joy", "Happy", "happy",
		"mouthSmileLeft", "mouthSmileRight"],
	"angry": ["Fcl_ALL_Angry", "Angry", "angry",
		"browDownLeft", "browDownRight"],
	"sad": ["Fcl_ALL_Sad", "Fcl_ALL_Sorrow", "Sad", "Sorrow", "sad",
		"mouthFrownLeft", "mouthFrownRight"],
	"surprised": ["Fcl_ALL_Surprised", "Surprised", "surprised",
		"jawOpen", "browInnerUp"],
	"relaxed": ["Fcl_ALL_Fun", "Fcl_ALL_Relaxed", "Fun", "Relaxed", "relaxed"],
	"neutral": ["Fcl_ALL_Neutral", "Neutral", "neutral"],
}

# Blink blend shape name variants
const _BLINK_SHAPES := ["Fcl_ALL_Close", "Fcl_EYE_Close", "Blink", "blink",
	"eyeBlinkLeft", "eyeBlinkRight", "EyeBlink_L", "EyeBlink_R"]

# Lip sync / viseme blend shape name variants
const _VISEME_SHAPES := {
	"aa": ["Fcl_MTH_A", "MTH_A", "A", "aa", "vrc.v_aa", "Vowel_A",
		"jawOpen", "viseme_aa"],
	"ih": ["Fcl_MTH_I", "MTH_I", "I", "ih", "vrc.v_ih", "Vowel_I",
		"mouthStretchLeft", "viseme_I"],
	"ou": ["Fcl_MTH_O", "MTH_O", "O", "ou", "vrc.v_ou", "Vowel_O",
		"mouthPucker", "viseme_O"],
	"ee": ["Fcl_MTH_E", "MTH_E", "E", "ee", "vrc.v_ee", "Vowel_E",
		"viseme_E"],
	"uu": ["Fcl_MTH_U", "MTH_U", "U", "uu", "vrc.v_uu", "Vowel_U",
		"viseme_U"],
}

# Keywords that identify jiggle / physics chains (case-insensitive check)
const _JIGGLE_KEYWORDS := [
	"hair", "skirt", "cloth", "tail", "ear", "ribbon", "accessory",
	"breast", "bust", "cape", "ponytail", "braid", "bang", "fringe",
	"ahoge", "antenna", "chain", "pendant", "tie", "scarf",
]

const _CACHE_DIR := "user://model_maps"

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Full pipeline: try cache first, otherwise scan + auto-map + save + emit.
func create_mapping(model: Node3D, model_path: String = "") -> Dictionary:
	# Try loading from cache
	if not model_path.is_empty():
		var cached := load_cached_mapping(model_path)
		if not cached.is_empty():
			print("[mapper] Loaded cached mapping for: ", cached.get("model_name", "?"))
			mapping_loaded.emit(cached)
			return cached

	# Scan the model
	var scan := scan_model(model)
	scan_complete.emit(scan)

	# Detect format
	var format := _detect_format(scan)

	# Build bone mapping
	var bones := _map_bones(scan, format)

	# Build blend shape mapping
	var blend_shapes := _map_blend_shapes(scan)

	# Detect jiggle chains
	var jiggle_chains := _detect_jiggle_chains(scan, bones)

	# Calculate confidence
	var mapped_count := bones.size()
	# Core bones (hips through head + arms + legs = 22 minimum)
	var core_count := 22.0
	var confidence := clampf(float(mapped_count) / core_count, 0.0, 1.0)

	var model_name := model_path.get_file().get_basename() if not model_path.is_empty() else str(model.name)
	var model_hash := compute_model_hash(model_path) if not model_path.is_empty() else ""

	var mapping := {
		"model_name": model_name,
		"model_hash": model_hash,
		"format": format,
		"bones": bones,
		"blend_shapes": blend_shapes,
		"jiggle_chains": jiggle_chains,
		"auto_mapped": true,
		"confidence": confidence,
	}

	# Save to cache
	if not model_hash.is_empty():
		save_mapping(mapping)

	print("[mapper] Mapping complete: ", mapped_count, " bones, ",
		blend_shapes.size(), " blend shapes, ",
		jiggle_chains.size(), " jiggle chains (confidence: ",
		snapped(confidence, 0.01), ")")

	mapping_complete.emit(mapping)
	return mapping


## Scan the model and return raw data about all bones and blend shapes.
func scan_model(model: Node3D) -> Dictionary:
	var skeleton := find_skeleton(model)
	var face_mesh := find_face_mesh(model)

	var bone_data := []  # Array of { name, index, parent_index, parent_name, children }
	var blend_shape_data := []  # Array of { name, index, mesh_name }
	var all_bone_names := PackedStringArray()

	# Scan skeleton
	if skeleton:
		for i in range(skeleton.get_bone_count()):
			var bone_name := skeleton.get_bone_name(i)
			var parent_idx := skeleton.get_bone_parent(i)
			var parent_name := skeleton.get_bone_name(parent_idx) if parent_idx >= 0 else ""
			var children := skeleton.get_bone_children(i)

			bone_data.append({
				"name": bone_name,
				"index": i,
				"parent_index": parent_idx,
				"parent_name": parent_name,
				"children": children,
			})
			all_bone_names.append(bone_name)

	# Scan all meshes for blend shapes (not just face mesh — some models split
	# blend shapes across multiple meshes)
	var meshes := _find_all_meshes_with_blend_shapes(model)
	for mi: MeshInstance3D in meshes:
		var count: int = mi.mesh.get_blend_shape_count()
		for i in range(count):
			blend_shape_data.append({
				"name": mi.mesh.get_blend_shape_name(i),
				"index": i,
				"mesh_name": str(mi.name),
			})

	return {
		"skeleton": skeleton,
		"face_mesh": face_mesh,
		"bone_data": bone_data,
		"bone_names": all_bone_names,
		"blend_shape_data": blend_shape_data,
		"meshes_with_shapes": meshes,
	}


## Load a cached mapping from user://model_maps/{hash}.json
func load_cached_mapping(model_path: String) -> Dictionary:
	var model_hash := compute_model_hash(model_path)
	if model_hash.is_empty():
		return {}

	var cache_path := _CACHE_DIR.path_join(model_hash + ".json")
	if not FileAccess.file_exists(cache_path):
		return {}

	var file := FileAccess.open(cache_path, FileAccess.READ)
	if not file:
		return {}

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		print("[mapper] Cache parse error: ", json.get_error_message())
		return {}

	var data = json.data
	if data is Dictionary:
		return data

	return {}


## Save a mapping to user://model_maps/{hash}.json
func save_mapping(mapping: Dictionary) -> void:
	var model_hash: String = mapping.get("model_hash", "")
	if model_hash.is_empty():
		print("[mapper] Cannot save mapping without model_hash")
		return

	# Ensure cache directory exists
	if not DirAccess.dir_exists_absolute(_CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(_CACHE_DIR)

	var cache_path := _CACHE_DIR.path_join(model_hash + ".json")

	# Build a serialisable copy (strip non-JSON-safe values like object refs)
	var save_data: Dictionary = _make_serialisable(mapping)

	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if not file:
		print("[mapper] Failed to write cache: ", cache_path)
		return

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("[mapper] Saved mapping: ", cache_path)


## Look up a bone index by humanoid name, using a mapping + skeleton.
func get_bone_index(mapping: Dictionary, humanoid_name: String, skeleton: Skeleton3D) -> int:
	var bones: Dictionary = mapping.get("bones", {})
	var actual_name = bones.get(humanoid_name, "")
	if actual_name is String and not actual_name.is_empty():
		return skeleton.find_bone(actual_name)
	return -1


## Look up a blend shape index by canonical expression name.
func get_blend_shape_index(mapping: Dictionary, expression_name: String) -> int:
	var shapes: Dictionary = mapping.get("blend_shapes", {})
	var idx = shapes.get(expression_name, -1)
	if idx is float:
		return int(idx)
	if idx is int:
		return idx
	return -1


## Return all jiggle chains from a mapping.
func get_jiggle_chains(mapping: Dictionary) -> Array:
	return mapping.get("jiggle_chains", [])


# ---------------------------------------------------------------------------
# Static helpers
# ---------------------------------------------------------------------------

## Recursively find the first Skeleton3D in a node tree.
static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found:
			return found
	return null


## Recursively find the MeshInstance3D with the most blend shapes (face mesh).
static func find_face_mesh(node: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_count := 0
	_find_face_mesh_recursive(node, best, best_count)
	# The recursive helper can't modify best/best_count by reference in GDScript,
	# so we do a flat search instead.
	return _find_face_mesh_flat(node)


static func _find_face_mesh_flat(node: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_count := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mi := current as MeshInstance3D
			if mi.mesh and mi.mesh.get_blend_shape_count() > best_count:
				best = mi
				best_count = mi.mesh.get_blend_shape_count()
		for child in current.get_children():
			stack.push_back(child)
	return best


static func _find_face_mesh_recursive(_node: Node, _best: MeshInstance3D, _best_count: int) -> void:
	# Unused — kept for interface compatibility. See _find_face_mesh_flat.
	pass


## Compute a stable hash for a model file path + size.
static func compute_model_hash(path: String) -> String:
	if path.is_empty():
		return ""
	# Use file path + modification time + size for a stable-enough key
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		# Fallback: hash the path string itself
		return str(path.hash())
	var size := file.get_length()
	file.close()

	# Read modification time if available
	var mod_time := FileAccess.get_modified_time(path)

	var hash_input := path.get_file() + "|" + str(size) + "|" + str(mod_time)
	return str(hash_input.hash())


# ---------------------------------------------------------------------------
# Format detection
# ---------------------------------------------------------------------------

func _detect_format(scan: Dictionary) -> String:
	var bone_names: PackedStringArray = scan.get("bone_names", PackedStringArray())

	# Check for VRM J_Bip_ prefix
	for bone_name in bone_names:
		if bone_name.begins_with("J_Bip_") or bone_name.begins_with("J_Sec_") or bone_name.begins_with("J_Adj_"):
			return "vrm"

	# Check for Mixamo prefix
	for bone_name in bone_names:
		if bone_name.begins_with("mixamorig:"):
			return "mixamo"

	# Check for Blender-style Armature prefix
	for bone_name in bone_names:
		if bone_name.begins_with("Armature/"):
			return "blender"

	return "gltf"


# ---------------------------------------------------------------------------
# Bone mapping
# ---------------------------------------------------------------------------

func _map_bones(scan: Dictionary, format: String) -> Dictionary:
	var skeleton: Skeleton3D = scan.get("skeleton")
	if not skeleton:
		return {}

	var bone_names: PackedStringArray = scan.get("bone_names", PackedStringArray())
	# Build a set for fast lookup
	var bone_set := {}
	for bn in bone_names:
		bone_set[bn] = true

	var result := {}

	match format:
		"vrm":
			result = _map_bones_from_table(_VRM_BONES, bone_set)
		"mixamo":
			result = _map_bones_from_table(_MIXAMO_BONES, bone_set)
		_:
			result = _map_bones_generic(bone_set, skeleton)

	return result


## Map bones using a known convention table (VRM or Mixamo).
func _map_bones_from_table(table: Dictionary, bone_set: Dictionary) -> Dictionary:
	var result := {}
	for humanoid_name in table:
		var actual_name: String = table[humanoid_name]
		if actual_name in bone_set:
			result[humanoid_name] = actual_name
	return result


## Generic bone mapping — try multiple naming conventions + fuzzy matching.
func _map_bones_generic(bone_set: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	var result := {}

	for humanoid_name in HUMANOID_BONES:
		# 1. Try generic name table first
		if humanoid_name in _GENERIC_BONES:
			for candidate: String in _GENERIC_BONES[humanoid_name]:
				if candidate in bone_set:
					result[humanoid_name] = candidate
					break
				# Try with "Armature/" prefix (Blender export)
				var armature_name := "Armature/" + candidate
				if armature_name in bone_set:
					result[humanoid_name] = armature_name
					break

		# 2. If still not found, try case-insensitive match against all bones
		if humanoid_name not in result:
			var lower_target := humanoid_name.to_lower()
			for bone_name in bone_set:
				var stripped := bone_name as String
				# Strip common prefixes
				for prefix in ["Armature/", "Armature_", "Root/", "Skeleton/"]:
					if stripped.begins_with(prefix):
						stripped = stripped.substr(prefix.length())
						break
				if stripped.to_lower() == lower_target:
					result[humanoid_name] = bone_name
					break

	# 3. If very few bones matched, try structural heuristic:
	#    Find a root bone (no parent or parent is root) and walk the tree
	if result.size() < 5 and skeleton.get_bone_count() > 10:
		var structural := _map_bones_structural(skeleton, bone_set, result)
		for key in structural:
			if key not in result:
				result[key] = structural[key]

	return result


## Structural heuristic: use skeleton hierarchy to guess humanoid bones.
## Looks for the characteristic humanoid tree shape:
##   root → hips → spine → chest → neck → head
##                                → L shoulder → L upper arm → ...
##                                → R shoulder → R upper arm → ...
##                → L upper leg → L lower leg → L foot
##                → R upper leg → R lower leg → R foot
func _map_bones_structural(skeleton: Skeleton3D, bone_set: Dictionary, existing: Dictionary) -> Dictionary:
	var result := {}
	var bone_count := skeleton.get_bone_count()

	# Find root candidates (bones with no parent)
	var roots := []
	for i in range(bone_count):
		if skeleton.get_bone_parent(i) < 0:
			roots.append(i)

	if roots.is_empty():
		return result

	# Find the root with the most descendants (likely the armature root)
	var best_root: int = roots[0]
	var best_descendants := 0
	for root_idx in roots:
		var count: int = _count_descendants(skeleton, root_idx)
		if count > best_descendants:
			best_descendants = count
			best_root = root_idx

	# Walk down from root to find hips (first bone with 3+ children, or first child)
	var hips_idx := _find_hips_structural(skeleton, best_root)
	if hips_idx < 0:
		return result

	result["hips"] = skeleton.get_bone_name(hips_idx)

	# From hips, find children — expect: spine, left leg, right leg
	var hips_children := skeleton.get_bone_children(hips_idx)
	if hips_children.size() >= 3:
		# Sort children by x-position of rest pose to identify left/right
		var sorted_children := _sort_bones_by_x(skeleton, hips_children)

		# Middle child(ren) = spine chain; outer = legs
		# Typically: leftLeg, spine, rightLeg (sorted by X)
		if sorted_children.size() >= 3:
			result["leftUpperLeg"] = skeleton.get_bone_name(sorted_children[0])
			result["rightUpperLeg"] = skeleton.get_bone_name(sorted_children[-1])

			# The spine is somewhere in the middle
			var spine_idx: int = sorted_children[sorted_children.size() / 2]
			_map_spine_chain(skeleton, spine_idx, result)

			# Map leg chains
			_map_limb_chain(skeleton, sorted_children[0], "left", "Leg", result)
			_map_limb_chain(skeleton, sorted_children[-1], "right", "Leg", result)

	return result


func _find_hips_structural(skeleton: Skeleton3D, root_idx: int) -> int:
	# Hips is typically the first bone with 3+ children (spine + 2 legs)
	# or if root has exactly one child, go one deeper
	var children := skeleton.get_bone_children(root_idx)
	if children.size() >= 3:
		return root_idx
	if children.size() == 1:
		return _find_hips_structural(skeleton, children[0])
	if children.size() == 2:
		# Could be hips with only legs (no spine as child) — unlikely but possible
		# Or could be one level above hips
		for child_idx in children:
			var grandchildren := skeleton.get_bone_children(child_idx)
			if grandchildren.size() >= 3:
				return child_idx
		return root_idx
	return root_idx


func _map_spine_chain(skeleton: Skeleton3D, start_idx: int, result: Dictionary) -> void:
	var chain_names := ["spine", "chest", "upperChest", "neck", "head"]
	var current := start_idx
	var chain_pos := 0

	while chain_pos < chain_names.size() and current >= 0:
		var children := skeleton.get_bone_children(current)

		# If this bone already has a name match, skip assignment
		var bone_name := skeleton.get_bone_name(current)
		if chain_names[chain_pos] not in result:
			result[chain_names[chain_pos]] = bone_name

		chain_pos += 1

		# At chest/upperChest level, look for shoulder branches
		if chain_pos >= 2 and chain_pos <= 3 and children.size() >= 3:
			var sorted := _sort_bones_by_x(skeleton, children)
			if sorted.size() >= 3:
				# Leftmost = left shoulder chain, rightmost = right shoulder chain
				_map_arm_chain(skeleton, sorted[0], "left", result)
				_map_arm_chain(skeleton, sorted[-1], "right", result)
				# Continue spine with the middle bone
				current = sorted[sorted.size() / 2]
				continue

		# Follow the child that leads to more descendants (spine direction)
		if children.is_empty():
			break
		elif children.size() == 1:
			current = children[0]
		else:
			# Pick child with most descendants
			var best := children[0]
			var best_count := 0
			for child_idx in children:
				var c := _count_descendants(skeleton, child_idx)
				if c > best_count:
					best_count = c
					best = child_idx
			current = best


func _map_arm_chain(skeleton: Skeleton3D, start_idx: int, side: String, result: Dictionary) -> void:
	var chain_names := [side + "Shoulder", side + "UpperArm", side + "LowerArm", side + "Hand"]
	var current := start_idx
	for i in range(chain_names.size()):
		if current < 0:
			break
		if chain_names[i] not in result:
			result[chain_names[i]] = skeleton.get_bone_name(current)
		var children := skeleton.get_bone_children(current)
		current = children[0] if children.size() > 0 else -1


func _map_limb_chain(skeleton: Skeleton3D, start_idx: int, side: String, limb: String, result: Dictionary) -> void:
	var chain_names: Array
	if limb == "Leg":
		chain_names = [side + "UpperLeg", side + "LowerLeg", side + "Foot", side + "Toes"]
	else:
		chain_names = [side + "UpperArm", side + "LowerArm", side + "Hand"]

	var current := start_idx
	for i in range(chain_names.size()):
		if current < 0:
			break
		if chain_names[i] not in result:
			result[chain_names[i]] = skeleton.get_bone_name(current)
		var children := skeleton.get_bone_children(current)
		# Follow the child with the most descendants (main chain vs toes/fingers)
		if children.is_empty():
			current = -1
		elif children.size() == 1:
			current = children[0]
		else:
			var best := children[0]
			var best_count := 0
			for child_idx in children:
				var c := _count_descendants(skeleton, child_idx)
				if c > best_count:
					best_count = c
					best = child_idx
			current = best


func _count_descendants(skeleton: Skeleton3D, bone_idx: int) -> int:
	var count := 0
	var children := skeleton.get_bone_children(bone_idx)
	for child_idx in children:
		count += 1 + _count_descendants(skeleton, child_idx)
	return count


func _sort_bones_by_x(skeleton: Skeleton3D, bone_indices: PackedInt32Array) -> Array:
	var sorted := Array(bone_indices)
	sorted.sort_custom(func(a: int, b: int) -> bool:
		var pos_a := skeleton.get_bone_rest(a).origin.x
		var pos_b := skeleton.get_bone_rest(b).origin.x
		return pos_a < pos_b
	)
	return sorted


# ---------------------------------------------------------------------------
# Blend shape mapping
# ---------------------------------------------------------------------------

func _map_blend_shapes(scan: Dictionary) -> Dictionary:
	var blend_data: Array = scan.get("blend_shape_data", [])
	if blend_data.is_empty():
		return {}

	var result := {}

	# Build name → index lookup from all blend shapes
	var name_to_index := {}
	for entry in blend_data:
		name_to_index[entry["name"]] = entry["index"]

	# Map expressions
	for emotion in _EXPRESSION_SHAPES:
		for variant: String in _EXPRESSION_SHAPES[emotion]:
			if variant in name_to_index:
				result[emotion] = name_to_index[variant]
				break
			# Try suffix match (VRM sometimes prefixes mesh name)
			for shape_name in name_to_index:
				if (shape_name as String).ends_with(variant):
					result[emotion] = name_to_index[shape_name]
					break
			if emotion in result:
				break

	# Map blink
	for variant: String in _BLINK_SHAPES:
		if variant in name_to_index:
			result["blink"] = name_to_index[variant]
			break
		for shape_name in name_to_index:
			if (shape_name as String).ends_with(variant):
				result["blink"] = name_to_index[shape_name]
				break
		if "blink" in result:
			break

	# Map visemes (lip sync)
	for viseme in _VISEME_SHAPES:
		for variant: String in _VISEME_SHAPES[viseme]:
			if variant in name_to_index:
				result[viseme] = name_to_index[variant]
				break
			for shape_name in name_to_index:
				if (shape_name as String).ends_with(variant):
					result[viseme] = name_to_index[shape_name]
					break
			if viseme in result:
				break

	return result


# ---------------------------------------------------------------------------
# Jiggle chain detection
# ---------------------------------------------------------------------------

func _detect_jiggle_chains(scan: Dictionary, bone_mapping: Dictionary) -> Array:
	var skeleton: Skeleton3D = scan.get("skeleton")
	if not skeleton:
		return []

	# Build set of mapped humanoid bone names for exclusion
	var humanoid_set := {}
	for humanoid_name in bone_mapping:
		humanoid_set[bone_mapping[humanoid_name]] = true

	var chains := []
	var visited := {}

	for bone_entry in scan.get("bone_data", []):
		var bone_name: String = bone_entry["name"]
		var bone_idx: int = bone_entry["index"]

		# Skip already-visited or humanoid-mapped bones
		if bone_name in visited or bone_name in humanoid_set:
			continue

		# Check if this bone could be a jiggle chain root
		if not _is_potential_jiggle_root(bone_name, bone_idx, skeleton, humanoid_set):
			continue

		# Walk the chain
		var chain_bones := _walk_chain(skeleton, bone_idx, humanoid_set)
		if chain_bones.size() < 2:
			continue

		for cb in chain_bones:
			visited[cb] = true

		# Determine stiffness/drag based on chain length
		var chain_len := chain_bones.size()
		var stiffness := clampf(1.0 / float(chain_len), 0.1, 0.8)
		var drag := clampf(0.1 + 0.1 * float(chain_len), 0.1, 0.6)

		chains.append({
			"root": chain_bones[0],
			"bones": chain_bones,
			"stiffness": snapped(stiffness, 0.01),
			"drag": snapped(drag, 0.01),
		})

	return chains


func _is_potential_jiggle_root(bone_name: String, bone_idx: int, skeleton: Skeleton3D, humanoid_set: Dictionary) -> bool:
	# Check if name contains jiggle keywords
	var lower_name := bone_name.to_lower()
	for keyword in _JIGGLE_KEYWORDS:
		if lower_name.contains(keyword):
			return true

	# Check if parent is a humanoid bone (jiggle chains often hang off humanoid bones)
	var parent_idx := skeleton.get_bone_parent(bone_idx)
	if parent_idx >= 0:
		var parent_name := skeleton.get_bone_name(parent_idx)
		if parent_name in humanoid_set:
			# This bone hangs off a humanoid bone but isn't one itself — candidate
			# Only if it has children (a single leaf bone isn't a chain)
			var children := skeleton.get_bone_children(bone_idx)
			if children.size() > 0:
				return true

	# VRM secondary bones
	if bone_name.begins_with("J_Sec_") or bone_name.begins_with("J_Adj_"):
		return true

	return false


func _walk_chain(skeleton: Skeleton3D, start_idx: int, humanoid_set: Dictionary) -> Array:
	var chain := [skeleton.get_bone_name(start_idx)]
	var current := start_idx

	while true:
		var children := skeleton.get_bone_children(current)
		if children.is_empty():
			break

		# Follow the first non-humanoid child (single chain walk)
		var found_next := false
		for child_idx in children:
			var child_name := skeleton.get_bone_name(child_idx)
			if child_name not in humanoid_set:
				chain.append(child_name)
				current = child_idx
				found_next = true
				break

		if not found_next:
			break

		# Safety limit
		if chain.size() > 50:
			break

	return chain


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

func _find_all_meshes_with_blend_shapes(node: Node) -> Array:
	var result := []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mi := current as MeshInstance3D
			if mi.mesh and mi.mesh.get_blend_shape_count() > 0:
				result.append(mi)
		for child in current.get_children():
			stack.push_back(child)
	return result


# ---------------------------------------------------------------------------
# Serialisation helper
# ---------------------------------------------------------------------------

## Strip non-JSON-safe values (Object references, PackedInt32Array, etc.)
func _make_serialisable(data: Variant) -> Variant:
	if data is Dictionary:
		var result := {}
		for key in data:
			# Skip keys that hold engine objects
			if key in ["skeleton", "face_mesh", "meshes_with_shapes"]:
				continue
			result[key] = _make_serialisable(data[key])
		return result
	elif data is Array:
		var result := []
		for item in data:
			result.append(_make_serialisable(item))
		return result
	elif data is PackedInt32Array:
		var result := []
		for v in data:
			result.append(v)
		return result
	elif data is Object:
		return null
	else:
		return data
