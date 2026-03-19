#!/usr/bin/env node
// Converts Mixamo GLB/VRMA files to proper VRMA with VRM humanoid bone names.
// Reads GLB, remaps mixamorig_ node names, normalizes rest to identity,
// adjusts animation keyframes, outputs clean VRMA.

import { NodeIO } from '@gltf-transform/core';
import { readdir, stat } from 'fs/promises';
import { join, basename, extname } from 'path';
import { Quaternion } from './quat.mjs';

// Mixamo colon naming (inside GLB) → VRM humanoid camelCase
const BONE_MAP = {
  'mixamorig:Hips': 'hips',
  'mixamorig:Spine': 'spine',
  'mixamorig:Spine1': 'chest',
  'mixamorig:Spine2': 'upperChest',
  'mixamorig:Neck': 'neck',
  'mixamorig:Head': 'head',
  'mixamorig:LeftShoulder': 'leftShoulder',
  'mixamorig:LeftArm': 'leftUpperArm',
  'mixamorig:LeftForeArm': 'leftLowerArm',
  'mixamorig:LeftHand': 'leftHand',
  'mixamorig:RightShoulder': 'rightShoulder',
  'mixamorig:RightArm': 'rightUpperArm',
  'mixamorig:RightForeArm': 'rightLowerArm',
  'mixamorig:RightHand': 'rightHand',
  'mixamorig:LeftUpLeg': 'leftUpperLeg',
  'mixamorig:LeftLeg': 'leftLowerLeg',
  'mixamorig:LeftFoot': 'leftFoot',
  'mixamorig:LeftToeBase': 'leftToes',
  'mixamorig:RightUpLeg': 'rightUpperLeg',
  'mixamorig:RightLeg': 'rightLowerLeg',
  'mixamorig:RightFoot': 'rightFoot',
  'mixamorig:RightToeBase': 'rightToes',
  'mixamorig:LeftHandThumb1': 'leftThumbMetacarpal',
  'mixamorig:LeftHandThumb2': 'leftThumbProximal',
  'mixamorig:LeftHandThumb3': 'leftThumbDistal',
  'mixamorig:LeftHandIndex1': 'leftIndexProximal',
  'mixamorig:LeftHandIndex2': 'leftIndexIntermediate',
  'mixamorig:LeftHandIndex3': 'leftIndexDistal',
  'mixamorig:LeftHandMiddle1': 'leftMiddleProximal',
  'mixamorig:LeftHandMiddle2': 'leftMiddleIntermediate',
  'mixamorig:LeftHandMiddle3': 'leftMiddleDistal',
  'mixamorig:LeftHandRing1': 'leftRingProximal',
  'mixamorig:LeftHandRing2': 'leftRingIntermediate',
  'mixamorig:LeftHandRing3': 'leftRingDistal',
  'mixamorig:LeftHandPinky1': 'leftLittleProximal',
  'mixamorig:LeftHandPinky2': 'leftLittleIntermediate',
  'mixamorig:LeftHandPinky3': 'leftLittleDistal',
  'mixamorig:RightHandThumb1': 'rightThumbMetacarpal',
  'mixamorig:RightHandThumb2': 'rightThumbProximal',
  'mixamorig:RightHandThumb3': 'rightThumbDistal',
  'mixamorig:RightHandIndex1': 'rightIndexProximal',
  'mixamorig:RightHandIndex2': 'rightIndexIntermediate',
  'mixamorig:RightHandIndex3': 'rightIndexDistal',
  'mixamorig:RightHandMiddle1': 'rightMiddleProximal',
  'mixamorig:RightHandMiddle2': 'rightMiddleIntermediate',
  'mixamorig:RightHandMiddle3': 'rightMiddleDistal',
  'mixamorig:RightHandRing1': 'rightRingProximal',
  'mixamorig:RightHandRing2': 'rightRingIntermediate',
  'mixamorig:RightHandRing3': 'rightRingDistal',
  'mixamorig:RightHandPinky1': 'rightLittleProximal',
  'mixamorig:RightHandPinky2': 'rightLittleIntermediate',
  'mixamorig:RightHandPinky3': 'rightLittleDistal',
};

// Compute world rest quaternion for a node by walking up parents
function getWorldRest(node) {
  const q = new Quaternion(...node.getRotation());
  let parent = node.getParentNode();
  while (parent) {
    const pq = new Quaternion(...parent.getRotation());
    q.premultiply(pq);
    parent = parent.getParentNode();
  }
  return q;
}

async function convertFile(inputPath, outputPath) {
  const io = new NodeIO();
  const doc = await io.read(inputPath);
  const root = doc.getRoot();

  // Build node lookup and check if it's Mixamo
  const allNodes = root.listNodes();
  const isMixamo = allNodes.some(n => (n.getName() || '').startsWith('mixamorig:'));
  if (!isMixamo) {
    console.log(`  SKIP (not Mixamo): ${basename(inputPath)}`);
    return false;
  }

  // Compute world rest quaternions BEFORE modifying anything
  const worldRests = new Map();
  const parentWorldRests = new Map();
  for (const node of allNodes) {
    const name = node.getName();
    if (name && name in BONE_MAP) {
      worldRests.set(name, getWorldRest(node));
      const parent = node.getParentNode();
      if (parent) {
        parentWorldRests.set(name, getWorldRest(parent));
      } else {
        parentWorldRests.set(name, new Quaternion(0, 0, 0, 1));
      }
    }
  }

  // Process animations: normalize keyframe quaternions using three-vrm formula
  // normalized = parentWorldRest * trackQuat * boneWorldRest.inverse()
  for (const anim of root.listAnimations()) {
    for (const channel of anim.listChannels()) {
      const targetNode = channel.getTargetNode();
      if (!targetNode) continue;
      const nodeName = targetNode.getName();
      if (!nodeName || !(nodeName in BONE_MAP)) continue;

      const path = channel.getTargetPath();
      if (path !== 'rotation') continue;

      const sampler = channel.getSampler();
      if (!sampler) continue;
      const output = sampler.getOutput();
      if (!output) continue;

      const boneWorldRest = worldRests.get(nodeName);
      const parentWorld = parentWorldRests.get(nodeName);
      if (!boneWorldRest || !parentWorld) continue;

      const boneWorldRestInv = boneWorldRest.clone().invert();
      const count = output.getCount();
      const buf = new Float32Array(4);

      for (let i = 0; i < count; i++) {
        output.getElement(i, buf);
        const q = new Quaternion(buf[0], buf[1], buf[2], buf[3]);
        // three-vrm formula: parentWorldRest * trackQuat * boneWorldRest^-1
        q.premultiply(parentWorld).multiply(boneWorldRestInv);
        buf[0] = q.x; buf[1] = q.y; buf[2] = q.z; buf[3] = q.w;
        output.setElement(i, buf);
      }
    }

    // Also handle translation channels (hips)
    for (const channel of anim.listChannels()) {
      const targetNode = channel.getTargetNode();
      if (!targetNode) continue;
      const nodeName = targetNode.getName();
      if (nodeName !== 'mixamorig:Hips') continue;
      // Translation: keep as-is, just rename the target
    }
  }

  // Rename nodes and reset rest to identity
  for (const node of allNodes) {
    const name = node.getName();
    if (name && name in BONE_MAP) {
      node.setName(BONE_MAP[name]);
      node.setRotation([0, 0, 0, 1]); // identity rest
    }
  }

  // Remove meshes/skins (animation only)
  for (const mesh of root.listMeshes()) mesh.dispose();
  for (const skin of root.listSkins()) skin.dispose();
  for (const material of root.listMaterials()) material.dispose();
  for (const texture of root.listTextures()) texture.dispose();

  const glb = await io.writeBinary(doc);
  const { writeFile } = await import('fs/promises');
  await writeFile(outputPath, Buffer.from(glb));
  console.log(`  OK: ${basename(inputPath)} → ${basename(outputPath)} (${glb.byteLength} bytes)`);
  return true;
}

// Main
const inputDir = process.argv[2];
const outputDir = process.argv[3];

if (!inputDir || !outputDir) {
  console.log('Usage: node convert.mjs <input_dir> <output_dir>');
  process.exit(1);
}

const files = await readdir(inputDir);
let converted = 0, skipped = 0;

for (const file of files.sort()) {
  if (!file.endsWith('.vrma') && !file.endsWith('.glb')) continue;
  const inputPath = join(inputDir, file);
  const s = await stat(inputPath);
  if (!s.isFile()) continue;

  const outName = basename(file, extname(file)) + '.vrma';
  const outputPath = join(outputDir, outName);
  try {
    const ok = await convertFile(inputPath, outputPath);
    if (ok) converted++; else skipped++;
  } catch (e) {
    console.error(`  FAIL: ${file}: ${e.message}`);
    skipped++;
  }
}

console.log(`\nDone: ${converted} converted, ${skipped} skipped`);
