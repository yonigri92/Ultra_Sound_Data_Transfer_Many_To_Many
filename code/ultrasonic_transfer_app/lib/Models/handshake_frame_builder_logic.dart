import 'dart:typed_data';
import 'package:flutter_application_1/device_id_create_logic.dart';

class HandshakeFrameBuilderLogic {
  static const int _frameStartingCharacter = 0xF;
  static const int _frameSeparatingCharacter = 0xF;

  Future<Uint8List> buildHandshakeFrame() async {
    String uniqueDeviceId = await DeviceIdCreateLogic().get40BitId();
    List<int> userIdBytes = _hexStringToBytes(uniqueDeviceId);
    Uint8List frame = Uint8List(7);
    frame[0] = (_frameStartingCharacter << 4) | (userIdBytes[0] >> 4);

    for (int i = 0; i < 4; i++) {
      frame[i + 1] = ((userIdBytes[i] & 0x0F) << 4) | (userIdBytes[i + 1] >> 4);
    }

    frame[5] = ((userIdBytes[4] & 0x0F) << 4) | _frameSeparatingCharacter;
    frame[6] = _calculateChecksum(frame.sublist(0, 6));

    return frame;
  }

  List<int> _hexStringToBytes(String hex) {
    List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  int _calculateChecksum(Uint8List data) {
    int sum = 0;
    for (var b in data) {
      sum = (sum + b) % 256;
    }
    return sum;
  }
}
