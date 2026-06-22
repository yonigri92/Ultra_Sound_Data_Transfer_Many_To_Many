//moveing to short ID created issues so we need to update the code, go back to commit MTM WORKS! if you ever want to return to long ID
import 'dart:typed_data';
import 'device_id_create_logic.dart';
import 'packet_builder_logic.dart';
class HandshakeFrameBuilderLogic {
  //static const int _frameStartingCharacter = 0x0B;
  // שינוי ל-0x00 כדי שההזזה הראשונה תייצר 0x0B נקי ב-frame[0]
  static const int _frameStartingCharacter = 0x00;
  static const int _frameSeparatingCharacter = 0x06;

//   Future<Uint8List> buildHandshakeFrame() async {
//     String uniqueDeviceId = await DeviceIdCreateLogic().get40BitId();
//     List<int> userIdBytes = _hexStringToBytes(uniqueDeviceId);
//     Uint8List frame = Uint8List(7);
//     frame[0] = (_frameStartingCharacter << 4) | (userIdBytes[0] >> 4);

//     for (int i = 0; i < 4; i++) {
//       frame[i + 1] = ((userIdBytes[i] & 0x0F) << 4) | (userIdBytes[i + 1] >> 4);
//     }

//     frame[5] = ((userIdBytes[4] & 0x0F) << 4) | _frameSeparatingCharacter;
 
//     frame[6] = PacketBuilderLogic.crcCheckSum(frame.sublist(0, 6));

//     return frame;
//   }

//   List<int> _hexStringToBytes(String hex) {
//     List<int> bytes = [];
//     for (int i = 0; i < hex.length; i += 2) {
//       bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
//     }
//     return bytes;
//   }

// }
Future<Uint8List> buildHandshakeFrame() async {
    
    String shortIdStr = await DeviceIdCreateLogic().getShortId();
    int myShortIdByte = int.parse(shortIdStr, radix: 16);
    
    
    //List<int> userIdBytes = [0, 0, 0, 0, myShortIdByte];
    List<int> userIdBytes = [0xB5, 0x55, 0x55, 0x55, myShortIdByte];
    
    Uint8List frame = Uint8List(7);
    frame[0] = (_frameStartingCharacter << 4) | (userIdBytes[0] >> 4);

    for (int i = 0; i < 4; i++) {
      frame[i + 1] = ((userIdBytes[i] & 0x0F) << 4) | (userIdBytes[i + 1] >> 4);
    }

    frame[5] = ((userIdBytes[4] & 0x0F) << 4) | _frameSeparatingCharacter;
 
    frame[6] = PacketBuilderLogic.crcCheckSum(frame.sublist(0, 6));

    print("HandshakeBuilder: Created 7-byte Handshake Frame with Short ID (Padded with zeros): $frame");
    return frame;
  }
}