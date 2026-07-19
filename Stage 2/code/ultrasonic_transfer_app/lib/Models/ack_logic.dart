import 'dart:typed_data';
import 'packet_builder_logic.dart';


class AckLogic {
  static const int _frameStartingCharacter = 0x0C;
  static Future<Uint8List> buildAckFrame(int frameSequence) async {
    /*Input: Sequence number of a Frame To become Ack
      Output: Ack that is rellevent to this Frame
    */
    int crc8;
    Uint8List frame = Uint8List(3);
    frame[0] = (_frameStartingCharacter ) << 4 | ((frameSequence & 0xF0)>>4) ;// framestartingchar in bits 4-8 and framesequence in location 0-4
    frame[1] = (frameSequence & 0x0F) << 4;
    crc8 = PacketBuilderLogic.crcCheckSum(frame.sublist(0, 2));
    frame[1] =(frame[1] & 0xF0 |(crc8 & 0xF0)>>4) ;//framesequence in location 4-8 crc8 in 0-4
    frame[2] = ((crc8 & 0x0F)<<4);//crc8 location 0-4 noise not to be sent 4-8
    return frame;
  }
  static Future<Uint8List> receiveAckFrame(Uint8List frame) async {
    /*Input: frame that is suspected of being Ack
      Output: the frame if it is ack or exeption
    */
    frame[2] = (frame[1] << 4 | (frame[2])>>4);
    frame[1] =(frame[1] & 0xF0 ) ;
    if(PacketBuilderLogic.crcCheckSum(frame.sublist(0, 3))!=0x00)
      {throw (Exception("incorrect Crc"));}
    return frame;
  }

  }