import 'dart:typed_data';

class HandshakeDecoder {
  final List<int> _bitBuffer = List.filled(56, 0, growable: true);

  void pushBit(int bit, Function(String deviceId) onHandshakeDetected) {
    _bitBuffer.removeAt(0);
    _bitBuffer.add(bit);
    _checkFrame(onHandshakeDetected);
  }

  void _checkFrame(Function(String deviceId) onHandshakeDetected) {
    Uint8List frame = Uint8List(7);

    for (int i = 0; i < 7; i++) {
      int byteVal = 0;
      for (int j = 0; j < 8; j++) {
        byteVal = (byteVal << 1) | _bitBuffer[i * 8 + j];
      }
      frame[i] = byteVal;
    }

    if ((frame[0] >> 4) != 0xF) return;

    if ((frame[5] & 0x0F) != 0xF) return;

    int calculatedChecksum = 0;
    for (int i = 0; i < 6; i++) {
      calculatedChecksum = (calculatedChecksum + frame[i]) % 256;
    }

    if (calculatedChecksum != frame[6]) return;

    List<int> extractedUserId = List.filled(5, 0);

    for (int i = 0; i < 5; i++) {
      extractedUserId[i] = ((frame[i] & 0x0F) << 4) | (frame[i + 1] >> 4);
    }

    String deviceId = extractedUserId
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    onHandshakeDetected(deviceId);

    _bitBuffer.fillRange(0, 56, 0);
  }
}
