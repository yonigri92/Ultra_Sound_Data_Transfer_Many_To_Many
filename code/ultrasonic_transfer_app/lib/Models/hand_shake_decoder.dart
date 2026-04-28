import 'dart:typed_data';
import 'packet_builder_logic.dart';

class HandshakeDecoder {
  // 56 ביטים = 7 בייטים (Preamble, 5 Bytes ID, CRC)
  final List<int> _symbolBuffer = List.filled(14, 0, growable: true);

  void pushSymbol(int symbol, Function(String deviceId) onHandshakeDetected) {
    if (symbol == -1) return;
    
    _symbolBuffer.removeAt(0);
    _symbolBuffer.add(symbol);
    
    _checkFrame(onHandshakeDetected);
  }

void _checkFrame(Function(String deviceId) onHandshakeDetected) {
  Uint8List frame = Uint8List(7);
  for (int i = 0; i < 7; i++) {
    frame[i] =(_symbolBuffer[i * 2]<<4|_symbolBuffer[i * 2 + 1]& 0x0F);
  }

  // בדיקה משולבת: גם Preamble וגם Separator חייבים להיות תקינים
  bool preambleOk = (frame[0] >> 4) == 0x0B;
  bool separatorOk = (frame[5] & 0x0F) == 0x06;

  // אם אחד מהם לא תקין, אנחנו מתעלמים בשקט (זה כנראה רעש)
  if (!preambleOk || !separatorOk) {
    return;
  }

  // אם הגענו לכאן, יש סיכוי גבוה מאוד שזה פריים אמיתי!
  print("DEBUG: High Probability Frame Found!");
  print("DEBUG: Raw Bits: ${_symbolBuffer.join('')}");

  // בדיקת CRC
  int calculatedChecksum = PacketBuilderLogic.crcCheckSum(frame.sublist(0, 6));
  if (calculatedChecksum != frame[6]) {
    print("DEBUG: Structure OK, but CRC failed. Exp: ${frame[6].toRadixString(16)}, Got: ${calculatedChecksum.toRadixString(16)}");
    return;
  }

  // חילוץ ה-ID
  List<int> extractedUserId = List.filled(5, 0);
  for (int i = 0; i < 5; i++) {
    extractedUserId[i] = ((frame[i] & 0x0F) << 4) | (frame[i + 1] >> 4);
  }

  String deviceId = extractedUserId.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  print("SUCCESS: Handshake detected! ID: $deviceId");
  onHandshakeDetected(deviceId);

  _symbolBuffer.fillRange(0, 14, 0);
}
}