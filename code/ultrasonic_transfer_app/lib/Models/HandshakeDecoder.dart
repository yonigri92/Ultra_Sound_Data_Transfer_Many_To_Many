import 'dart:typed_data';
import 'packet_builder_logic.dart';
class HandshakeDecoder {
  final List<int> _bitBuffer = List.filled(56, 0, growable: true);

  void pushBit(int bit, Function(String deviceId) onHandshakeDetected) {//this is the listening, it keeps looking for handshake request
    _bitBuffer.removeAt(0);
    _bitBuffer.add(bit);
    _checkFrame(onHandshakeDetected);
  }

  void _checkFrame(Function(String deviceId) onHandshakeDetected) {
    // יצירת מערך בייטים מהביטים שנמצאים כרגע ב-Buffer (56 ביטים = 7 בייטים)
    Uint8List frame = Uint8List(7);
    for (int i = 0; i < 7; i++) {
      int byteVal = 0;
      for (int j = 0; j < 8; j++) {
        byteVal = (byteVal << 1) | _bitBuffer[i * 8 + j];
      }
      frame[i] = byteVal;
    }

    // 1. בדיקת Preamble (4 ביטים עליונים בבייט הראשון חייבים להיות 0xF)
    if ((frame[0] >> 4) != 0x0F) {
      return; // עדיין לא מיושר או לא פריים תקין
    }

    // 2. בדיקת Separator (4 ביטים תחתונים בבייט השישי חייבים להיות 0xF)
    // הערה: לפי הלוג שלך [fc, 5a, c0, 1e, 3f, 8b, 58], כאן זה נכשל בגלל ה-0x8B
    if ((frame[5] & 0x0F) != 0x0F) {
      return;
    }

    // 3. בדיקת CRC - אימות שלמות הנתונים
    int calculatedChecksum = PacketBuilderLogic.crcCheckSum(frame.sublist(0, 6));
    if (calculatedChecksum != frame[6]) {
      // אם ה-Preamble וה-Separator תקינים אבל ה-CRC לא, יש כנראה שגיאת ביט (Noise/Underrun)
      print("DEBUG: Frame structure OK, but CRC Mismatch: Exp ${frame[6].toRadixString(16)}, Got ${calculatedChecksum.toRadixString(16)}");
      return;
    }

    // 4. חילוץ ה-Device ID (היפוך של לוגיקת ה-Packing)
    // ה-ID מפוזר על פני ה-Nibbles הפנימיים של פריים האולטרסאונד
    List<int> extractedUserId = List.filled(5, 0);
    for (int i = 0; i < 5; i++) {
      // לוקחים 4 ביטים תחתונים של בייט נוכחי ו-4 עליונים של הבייט הבא
      extractedUserId[i] = ((frame[i] & 0x0F) << 4) | (frame[i + 1] >> 4);
    }

    // המרה למחרוזת הקסדצימלית קריאה
    String deviceId = extractedUserId
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    print("SUCCESS: Handshake detected! Device ID: $deviceId");

    // קריאה ל-Callback
    onHandshakeDetected(deviceId);

    // ניקוי ה-Buffer כדי למנוע זיהוי כפול של אותו פריים
    _bitBuffer.fillRange(0, 56, 0);
  }
}
