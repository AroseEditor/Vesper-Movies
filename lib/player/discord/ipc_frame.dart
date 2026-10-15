import 'dart:convert';
import 'dart:typed_data';

Uint8List encodeFrame(int opcode, Map<String, dynamic> payload) {
  final json = utf8.encode(jsonEncode(payload));
  final bytes = Uint8List(8 + json.length);
  final header = ByteData.view(bytes.buffer);
  header.setInt32(0, opcode, Endian.little);
  header.setInt32(4, json.length, Endian.little);
  bytes.setRange(8, 8 + json.length, json);
  return bytes;
}
