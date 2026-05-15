import 'package:ultrasonic_transfer_app/Models/ack_logic.dart';

import 'dart:typed_data';
import 'hand_shake_decoder.dart';


class Dispatcher{
  final List<int> _symbolBuffer = List.filled(14, 0, growable: true);
  final HandshakeDecoder _handshakeDecoder = HandshakeDecoder();
  Future<void> pushSymbol(int symbol, Function(String deviceId) onPacketDetected) async {
      if (symbol == -1) return;
      
      _symbolBuffer.removeAt(0);
      _symbolBuffer.add(symbol);
      
      await _checkFrame(onPacketDetected);
    }
    
    Future<void> _checkFrame(Function(String deviceId) onPacketDetected) async {
      Uint8List frame = Uint8List(7);
      for (int i = 0; i < 7; i++) {
        frame[i] =(_symbolBuffer[i * 2]<<4|_symbolBuffer[i * 2 + 1]& 0x0F);
      }

      int preambleOk = (frame[0] >> 4) ;
      
     
      switch(preambleOk){
        case 0x0B:
          // handshake Packet
          print("Routing to Handshake");
          
          try{
            await _handshakeDecoder.decodeFrame(frame,onPacketDetected);
              _symbolBuffer.fillRange(0, 14, 0);
          }catch(e){
            print("DEBUG: Handshake Check failed: $e");
          }
          
          break; 
          
        case 0x0C:
          // ACK Packet
          try{
            print("Routing to ACK");
            await AckLogic.receiveAckFrame(frame);
            _symbolBuffer.fillRange(0, 14, 0);
          }
          catch(e){
            print("DEBUG: ACK Check failed: $e");
          }
          break;

        case 0x0D:
          // Data Packet
          print("Routing to Data");
          _symbolBuffer.fillRange(0, 14, 0);
          break;

        default:
          // no known data type
          print("Unknown packet type");


      }
    



  }




}