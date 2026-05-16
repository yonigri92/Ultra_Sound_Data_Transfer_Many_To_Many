import 'package:ultrasonic_transfer_app/Models/ack_logic.dart';
import 'audio_transmitter_logic.dart';
import 'dart:typed_data';
import 'hand_shake_decoder.dart';


class Dispatcher{
  final List<int> _symbolBuffer = List.filled(14, 0, growable: true);
  final HandshakeDecoder _handshakeDecoder = HandshakeDecoder();
  // this will keep all recent masseges recived incase we recive the same message twice we will be able to return ack again
  final Map<int, DateTime> _recentMessagesCache = {};
  final int _ackSeq = 255;
  late AudioTransmitter _transmitter;//object that transmistts
  
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

      int preamble = (frame[0] >> 4) ;
      
     
      switch(preamble){
        case 0x0B:
          // handshake Packet
          print("Routing to Handshake");
          
          try{
            int dataPacket;
            DateTime now = DateTime.now();
            dataPacket = await _handshakeDecoder.decodeFrame(frame);
            _symbolBuffer.fillRange(0, 14, 0);
            
            _recentMessagesCache.removeWhere((id, time) => DateTime.now().difference(time).inSeconds > 3);//run over all messages and delete old ones
            if(_recentMessagesCache.containsKey(dataPacket) == false ){
            _recentMessagesCache[dataPacket] = now;
            String deviceIdString = dataPacket.toRadixString(16).toUpperCase().padLeft(10, '0');
            onPacketDetected(deviceIdString);
            
                }
            await _transmitter.transmitFrame(await AckLogic.buildAckFrame(_ackSeq));
            
            

          }catch(e){
            print("DEBUG: Handshake Check failed: $e");
          }
          
          break; 
          
        case 0x0C:
          // ACK Packet
          /*
          because we transmit datapacket in the air
          and we want to keep things orginised in the code the datapacket 
          is being transmitted and lightly as possible only 20 bits
          so we orginize it back to a way the 
          code knows to handle before continueing
                    */
          try{
            print("Routing to ACK");
            Uint8List validatedFrame = await AckLogic.receiveAckFrame(frame);
            int lowNibble = validatedFrame[0] & 0x0F;// because o
            int highNibble = (validatedFrame[1] >> 4) & 0x0F;
            int receivedSeq = (highNibble << 4) | lowNibble;
            onAckDetected(receivedSeq);//this method will return the ack recived to the transmitter so it wont send the packet again
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