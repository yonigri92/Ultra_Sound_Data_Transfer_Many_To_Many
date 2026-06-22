//moveing to short ID created issues so we need to update the code, go back to commit MTM WORKS! if you ever want to return to long ID
import 'dart:typed_data';
import 'packet_builder_logic.dart';

//import 'audio_transmitter_logic.dart';
//static const int _AckStartingCharacter = 0x0C;
class HandshakeDecoder {
  // 56 ביטים = 7 בייטים (Preamble, 5 Bytes ID, CRC)
  final List<int> _symbolBuffer = List.filled(14, 0, growable: true);
  
 
 Future<int> decodeFrame(Uint8List frame) async {

  //bool preambleOk = (frame[0] >> 4) == 0x0B;
  bool preambleOk = frame[0] == 0x0B;
  bool separatorOk = (frame[5] & 0x0F) == 0x06;

  if (!preambleOk || !separatorOk) {
    throw Exception("Invalid Handshake Structure");
  }

  print("DEBUG: High Probability Frame Found!");
  print("DEBUG: Raw Bits: ${_symbolBuffer.join('')}");

  int calculatedChecksum = PacketBuilderLogic.crcCheckSum(frame.sublist(0, 6));
  if (calculatedChecksum != frame[6]) {
    print("DEBUG: Structure OK, but CRC failed. Exp: ${frame[6].toRadixString(16)}, Got: ${calculatedChecksum.toRadixString(16)}");
   throw Exception("Handshake CRC mismatch");
  }

  //deletes the preamble{
  List<int> extractedUserId = List.filled(5, 0);
  for (int i = 0; i < 5; i++) {
    extractedUserId[i] = ((frame[i] & 0x0F) << 4) | (frame[i + 1] >> 4);
  }
  //}
  //go over the id bits and extract{
  // int deviceId = 0;
  // for (int byte in extractedUserId) {
  //   deviceId = (deviceId << 8) | byte;
  // }
  //}

  int deviceId = extractedUserId[4];
    print("SUCCESS: Handshake detected! ID: 0x${deviceId.toRadixString(16).toUpperCase()}");
    
    return deviceId;
 
  // return _transmitter.transmitFrame(await AckLogic.buildAckFrame(_ackSeq));
       

  // onPacketDetected(deviceId);

}





}