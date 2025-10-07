import 'dart:convert';
import 'dart:typed_data';

class GltfService {
  // Build a minimal glTF 2.0 JSON string containing a single plane mesh
  // with a PBR material using the provided PNG as baseColorTexture.
  static String buildTexturedPlaneGltfJson(Uint8List pngBytes) {
    // Geometry data
    final Float32List positions = Float32List.fromList(<double>[
      -0.5, 0.0, -0.5,
       0.5, 0.0, -0.5,
      -0.5, 0.0,  0.5,
       0.5, 0.0,  0.5,
    ]);
    final Float32List normals = Float32List.fromList(<double>[
      0.0, 1.0, 0.0,
      0.0, 1.0, 0.0,
      0.0, 1.0, 0.0,
      0.0, 1.0, 0.0,
    ]);
    final Float32List uvs = Float32List.fromList(<double>[
      0.0, 0.0,
      1.0, 0.0,
      0.0, 1.0,
      1.0, 1.0,
    ]);
    final Uint16List indices = Uint16List.fromList(<int>[
      0, 1, 2,
      2, 1, 3,
    ]);

    // Concatenate into one buffer
    final int positionsOffset = 0;
    final int positionsLength = positions.lengthInBytes; // 4*3*4 = 48
    final int normalsOffset = positionsOffset + positionsLength; // 48
    final int normalsLength = normals.lengthInBytes; // 48
    final int uvsOffset = normalsOffset + normalsLength; // 96
    final int uvsLength = uvs.lengthInBytes; // 32
    final int indicesOffset = uvsOffset + uvsLength; // 128
    final int indicesLength = indices.lengthInBytes; // 12
    final int totalBufferLength = indicesOffset + indicesLength; // 140

    final Uint8List buffer = Uint8List(totalBufferLength);
    buffer.setRange(positionsOffset, positionsOffset + positionsLength, positions.buffer.asUint8List());
    buffer.setRange(normalsOffset, normalsOffset + normalsLength, normals.buffer.asUint8List());
    buffer.setRange(uvsOffset, uvsOffset + uvsLength, uvs.buffer.asUint8List());
    buffer.setRange(indicesOffset, indicesOffset + indicesLength, indices.buffer.asUint8List());

    final String bufferBase64 = base64Encode(buffer);
    final String imageBase64 = base64Encode(pngBytes);

    final Map<String, dynamic> gltf = {
      "asset": {"version": "2.0", "generator": "FertiLitef-textured-plane"},
      "buffers": [
        {
          "byteLength": totalBufferLength,
          "uri": "data:application/octet-stream;base64,$bufferBase64"
        }
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": positionsOffset, "byteLength": positionsLength, "target": 34962}, // ARRAY_BUFFER
        {"buffer": 0, "byteOffset": normalsOffset,   "byteLength": normalsLength,   "target": 34962},
        {"buffer": 0, "byteOffset": uvsOffset,       "byteLength": uvsLength,       "target": 34962},
        {"buffer": 0, "byteOffset": indicesOffset,   "byteLength": indicesLength,   "target": 34963}, // ELEMENT_ARRAY_BUFFER
      ],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [-0.5, 0.0, -0.5], "max": [0.5, 0.0, 0.5]},
        {"bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC3"},
        {"bufferView": 2, "componentType": 5126, "count": 4, "type": "VEC2"},
        {"bufferView": 3, "componentType": 5123, "count": 6, "type": "SCALAR"},
      ],
      "images": [
        {"mimeType": "image/png", "uri": "data:image/png;base64,$imageBase64"}
      ],
      "samplers": [
        {"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497} // LINEAR, TRILINEAR, REPEAT
      ],
      "textures": [
        {"sampler": 0, "source": 0}
      ],
      "materials": [
        {
          "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0},
            "roughnessFactor": 1.0,
            "metallicFactor": 0.0
          }
        }
      ],
      "meshes": [
        {
          "primitives": [
            {
              "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
              "indices": 3,
              "material": 0
            }
          ]
        }
      ],
      "nodes": [
        {"mesh": 0}
      ],
      "scenes": [
        {"nodes": [0]}
      ],
      "scene": 0
    };

    return jsonEncode(gltf);
  }

  static String gltfJsonToDataUri(String json) {
    final b64 = base64Encode(utf8.encode(json));
    return 'data:model/gltf+json;base64,$b64';
  }
}
