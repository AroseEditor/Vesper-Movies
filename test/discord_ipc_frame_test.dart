import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/player/discord/ipc_frame.dart';

void main() {
  test('encodes opcode and length as little endian headers around the json body', () {
    final frame = encodeFrame(1, {'cmd': 'PING'});
    final header = ByteData.sublistView(frame, 0, 8);

    final body = utf8.encode(jsonEncode({'cmd': 'PING'}));
    expect(header.getInt32(0, Endian.little), 1);
    expect(header.getInt32(4, Endian.little), body.length);
    expect(frame.sublist(8), body);
  });

  test('round trips through json decoding', () {
    final frame = encodeFrame(0, {'v': 1, 'client_id': 'abc'});
    final length = ByteData.sublistView(frame, 0, 8).getInt32(4, Endian.little);
    final decoded = jsonDecode(utf8.decode(frame.sublist(8, 8 + length)));
    expect(decoded, {'v': 1, 'client_id': 'abc'});
  });
}
