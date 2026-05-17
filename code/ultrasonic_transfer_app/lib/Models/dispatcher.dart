import 'package:ultrasonic_transfer_app/Models/ack_logic.dart';
import 'audio_transmitter_logic.dart';
import 'dart:typed_data';
import 'hand_shake_decoder.dart';
import 'data_frame_builder_logic.dart';
import 'packet_builder_logic.dart';
import 'handshake_frame_builder_logic.dart';
class Dispatcher{

  final List<int> _symbolBuffer = List.filled(24, 0, growable: true);
  final HandshakeDecoder _handshakeDecoder = HandshakeDecoder();
  final Map<int, DateTime> _recentReceivedPackets = {};//this is the saved data of all the recent recived messeges, 
                                                       //its used so we wont accidently re read the same message twice
  final Map<int, Uint8List> _outgoingPackets = {}; // saves packets that we allready sent once so that we will be able to
                                                   // keep track on wheather we recived ack for them or if we need to send them again
  final Map<String, DateTime> _ignorePackets = {};                           
  DataFrameBuilderLogic? _incomingMessage;
  final int _ackSeq = 255;
  late AudioTransmitter _transmitter;//object that transmists
  final List<Uint8List> _dataQueue = [];
  final List<Uint8List> _ackQueue = [];
  final Map<int, int> _packetAttempts = {};// counter for each packet
  bool _isWorkerRunning = false;
  Dispatcher(this._transmitter);
  Future<void> pushSymbol(int symbol, Function(String deviceId) onPacketDetected) async {
      if (symbol == -1) return;
      
      _symbolBuffer.removeAt(0);
      _symbolBuffer.add(symbol);
      
      await _checkFrame(onPacketDetected);
    }
    
    Future<void> _checkFrame(Function(String deviceId) onPacketDetected) async {
      Uint8List frame = Uint8List(12);
      for (int i = 0; i < 12; i++) {
        frame[i] =(_symbolBuffer[i * 2]<<4|_symbolBuffer[i * 2 + 1]& 0x0F);
      }

      int preamble = 0;
      
       if (frame[4] == 0x0D) {// since we are getting diffrent sizes of packets we need to send them when they are ready and not wait until buffer is full
        preamble = 0x0D;
        Uint8List alignedFrame = Uint8List(8);
        for (int i = 0; i < 8; i++) {
        alignedFrame[i] = (_symbolBuffer[8 + i * 2] << 4 | _symbolBuffer[8 + i * 2 + 1] & 0x0F);
         }
        frame = alignedFrame;
       } 
      
      else if ((frame[5] >> 4) == 0x0B) {
        preamble = 0x0B;
        Uint8List alignedFrame = Uint8List(8);
        for (int i = 0; i < 7; i++) {
          alignedFrame[i] = (_symbolBuffer[10 + i * 2] << 4 | _symbolBuffer[10 + i * 2 + 1] & 0x0F);
        }
        frame = alignedFrame; 
      } 
      
       else if ((frame[9] >> 4) == 0x0C) {
        preamble = 0x0C;
        Uint8List alignedFrame = Uint8List(8);
        for (int i = 0; i < 3; i++) {
          alignedFrame[i] = (_symbolBuffer[18 + i * 2] << 4 | _symbolBuffer[18 + i * 2 + 1] & 0x0F);
        }
        frame = alignedFrame;
      }
    
     
      switch(preamble){
        case 0x0B:
          // handshake Packet
          print("Routing to Handshake");
          String handshakeKey = frame.sublist(0, 7).join(',');
          if (_ignorePackets.containsKey(handshakeKey)) {
            print("Dispatcher: Listening to our own Handshake ignore.");
            _symbolBuffer.fillRange(0, 24, 0);
            break;
          }
          try{
            int dataPacket;
            DateTime now = DateTime.now();
            dataPacket = await _handshakeDecoder.decodeFrame(frame);
            _symbolBuffer.fillRange(0, 24, 0);
            
            _recentReceivedPackets.removeWhere((id, time) => DateTime.now().difference(time).inSeconds > 8);//run over all messages and delete old ones
            if(_recentReceivedPackets.containsKey(dataPacket) == false ){
            _recentReceivedPackets[dataPacket] = now;
            String deviceIdString = dataPacket.toRadixString(16).toUpperCase().padLeft(10, '0');
            onPacketDetected(deviceIdString);
            
                }
            //await _transmitter.transmitFrame(await AckLogic.buildAckFrame(_ackSeq));
            Uint8List ackFrame = await AckLogic.buildAckFrame(_ackSeq);
            await addACkPacketToQueue(_ackSeq, ackFrame);
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

            String ackKey = frame.sublist(0, 3).join(',');

            if (_ignorePackets.containsKey(ackKey)) {
                print("Dispatcher: Listening to our own Ack ignore.");
                _symbolBuffer.fillRange(0, 24, 0);
                break; 
            }


            Uint8List validatedFrame = await AckLogic.receiveAckFrame(frame);
            int highNibble = validatedFrame[0] & 0x0F;
            int lowNibble = (validatedFrame[1] >> 4) & 0x0F;
            int receivedSeq = (highNibble << 4) | lowNibble;


            if (!_outgoingPackets.containsKey(receivedSeq)) {
                print("Dispatcher: Acoustic echo or invalid ACK for Seq: $receivedSeq. Ignoring.");
                _symbolBuffer.fillRange(0, 24, 0);
                break; 
            }
            //String ackKey = frame.sublist(0, 5).join(',');
            //this part will delete the ack recived from reciver so it we wont send the packet again
            print("Dispatcher: Received ACK for Seq: $receivedSeq.");
            _outgoingPackets.remove(receivedSeq);
            _packetAttempts.remove(receivedSeq);
            
          
            
            
            _symbolBuffer.fillRange(0, 24, 0);
          }
          catch(e){
            print("DEBUG: ACK Check failed: $e");
          }
          break;

       case 0x0D:
          print("Routing to Data");
          print("RAW DATA FRAME FROM AIR: $frame");
          String dataKey = frame.join(',');
          if (_ignorePackets.containsKey(dataKey)) {
            print("Dispatcher: Listening to our own Data ignore.");
            _symbolBuffer.fillRange(0, 24, 0);
            break; 
            }
          int receivedSeq = frame[1]; 
          if (_outgoingPackets.containsKey(receivedSeq)) {
            print("Dispatcher: Acoustic echo of our own Data Packet (Seq: $receivedSeq) detected. Ignoring.");
            _symbolBuffer.fillRange(0, 24, 0);
            break; 
          }



          try {
            if(_incomingMessage == null)
            { _incomingMessage = DataFrameBuilderLogic(256);}
            PacketBuilderLogic? validatedPacket = _incomingMessage!.reciveDataFrameBuilderLogic(frame);
            
            if (validatedPacket != null) {
              int currentSeq = validatedPacket.seq;
              print("Dispatcher: Valid Data Packet received for Seq: $currentSeq");
              Uint8List ackFrame = await AckLogic.buildAckFrame(currentSeq);
              await addACkPacketToQueue(currentSeq, ackFrame);

              //int eofIndex = _incomingMessage!.length;
              bool hasReceivedEOF = _incomingMessage!.messages[255] != null;
              
              if (hasReceivedEOF) {
                try {
                  print("Dispatcher: EOF is present. Trying to reconstruct...");
                  Uint8List fullMessageBytes = _incomingMessage!.reconstruct();
                  
                  String finalMessage = String.fromCharCodes(fullMessageBytes);
                  int messageHash = finalMessage.hashCode;
                  DateTime now = DateTime.now();
                  
                  _recentReceivedPackets.removeWhere((id, time) => now.difference(time).inSeconds > 8);
                  
                  if (_recentReceivedPackets.containsKey(messageHash) == false) {
                    _recentReceivedPackets[messageHash] = now;
                    print("Dispatcher: Success! Delivering new message to UI.");
                    onPacketDetected(finalMessage);
                  } else {
                    print("Dispatcher: Duplicate whole message detected within 3 seconds. Dropping.");
                  }
                  
                  _incomingMessage = null;
                } catch (reconstructError) {
                  print("Dispatcher: Reconstruction failed (Message still incomplete): $reconstructError");
                }
              }
              _symbolBuffer.fillRange(0, 24, 0);
            }
            
            
          } catch (e) {
            print("DEBUG: Data packet processing failed: $e");
          }
          break;

        default:
          // no known data type
          print("Unknown packet type");


      }
    



  }
  Future<void> addHandShakePacketToQueue() async {
    Uint8List handshakeFrame = await HandshakeFrameBuilderLogic().buildHandshakeFrame(); 

    String key = handshakeFrame.sublist(0, 7).join(',');
    // String key = handshakeFrame.join(',');
    _ignorePackets[key] = DateTime.now();

    _ackQueue.add(handshakeFrame);
    _triggerSemaphore();

    Future.delayed(const Duration(seconds: 8), () {
      _ignorePackets.remove(key);
    });
  }

  Future<void> addDataPacketToQueue(Uint8List data) async {
    DataFrameBuilderLogic packets  = DataFrameBuilderLogic.fromPacket(data);
    
    for(PacketBuilderLogic packet  in packets.messages.whereType<PacketBuilderLogic>()){
    String key = packet.packet.join(',');
    _ignorePackets[key] = DateTime.now();

    _outgoingPackets[packet.seq] = packet.packet;
    _packetAttempts[packet.seq] = 0;
    _dataQueue.add(packet.packet);
    Future.delayed(const Duration(seconds: 8), () {
        _ignorePackets.remove(key);
      });
    }
    
    _triggerSemaphore();
  }
 Future<void> addACkPacketToQueue(int seq, Uint8List packet) async {

    //String key = packet.sublist(0, 5).join(',');
    String key = packet.join(',');
    _ignorePackets[key] = DateTime.now();

    _ackQueue.add(packet);
    _triggerSemaphore();
    Future.delayed(const Duration(seconds: 3), () {
        _ignorePackets.remove(key);
      });
  }
  void _triggerSemaphore() {//this just makes sure that the semaphore queue is running(only once) - singelton
      if (!_isWorkerRunning) {
        _semaphoreQueue();
      }
    }


  Future<void> _semaphoreQueue() async {
    /*
    Logic: first we will transmit all acks asap as the listener only listens 
    for a limited time before he either sends the message again or gives up completely on sending it
    afterwards we will send a every 2 secound since it takes 1.2 sec to send each packet it gives us 0.8 sec to listen for ack
    */
    _isWorkerRunning = true;

    while (_ackQueue.isNotEmpty || _dataQueue.isNotEmpty) {
      if (_ackQueue.isNotEmpty) {
        Uint8List ackFrame = _ackQueue.removeAt(0);
        await _transmitter.transmitFrame(ackFrame);
        await Future.delayed(const Duration(milliseconds: 650)); 
        continue; 
      }

      if (_dataQueue.isNotEmpty) {
        Uint8List dataFrame = _dataQueue.removeAt(0);
        //int seq = dataFrame[1]; // here we need to make sure that the sequence is placed correctly its just something to put atm
        int seq = dataFrame[1] & 0xFF;
        if (!_outgoingPackets.containsKey(seq)) {// if we dont have the packet in the map it means we got ack and need to delete it
          print("Packet $seq already got ACK while waiting in queue. Skipping.");
          continue;
        }
      
        int attempts = (_packetAttempts[seq] ?? 0) + 1;// this must be wrote this way to either initiaise the map to 0 or add 1 if not 0
        _packetAttempts[seq] = attempts;
        print("Worker: Transmitting Data packet (Seq: $seq), Attempt #$attempts");
        await _transmitter.transmitFrame(dataFrame);

        if (attempts < 5) {
          _dataQueue.add(dataFrame);
          await Future.delayed(const Duration(milliseconds: 950));
        } else {
           print("Worker: Packet (Seq: $seq) failed after max retries. Dropping.");
          _outgoingPackets.remove(seq);
          _packetAttempts.remove(seq);
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    }

    _isWorkerRunning = false; 
    print("Worker: All queues empty. Going to sleep.");
  }
}




