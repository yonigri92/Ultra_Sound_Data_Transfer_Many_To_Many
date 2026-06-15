import 'package:ultrasonic_transfer_app/Models/ack_logic.dart';
import 'audio_transmitter_logic.dart';
import 'dart:typed_data';
import 'hand_shake_decoder.dart';
import 'data_frame_builder_logic.dart';
import 'packet_builder_logic.dart';
import 'handshake_frame_builder_logic.dart';
import 'device_id_create_logic.dart';
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
  bool get isWorkerRunning => _isWorkerRunning;
  Dispatcher(this._transmitter);

  bool _receivedImplicitAck = false; 
  bool _isLeafNode = false;
  final Map<int, bool> _myChildrenMap = {}; 
  int _expectedPacketsCount = 0;
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
      else if ((frame[5] >> 4) == 0x0E) {
            preamble = 0x0E;
            Uint8List alignedFrame = Uint8List(8);
            for (int i = 0; i < 7; i++) {
              alignedFrame[i] = (_symbolBuffer[10 + i * 2] << 4 | _symbolBuffer[10 + i * 2 + 1] & 0x0F);
            }
            frame = alignedFrame; 
      }
      else if ((frame[5] >> 4) == 0x0F) {
        preamble = 0x0F;
        Uint8List alignedFrame = Uint8List(8);
        for (int i = 0; i < 7; i++) {
          alignedFrame[i] = (_symbolBuffer[10 + i * 2] << 4 | _symbolBuffer[10 + i * 2 + 1] & 0x0F);
        }
        frame = alignedFrame; 
      } 
      else if ((frame[5] >> 4) == 0x0A) {
        preamble = 0x0A;
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
        case 0x0E:
        print("Routing to Stage 2: Chain Formation");
        _handleStage2ChainFormation(frame, onPacketDetected);
        break;
        case 0x0F:
          print("Routing to Stage 3: Return Mechanism");
          _handleStage3ReturnMechanism(frame);
          break;
        case 0x0A:
          print("Routing to Stage 4: Final Distribution & Consumption Mask");
          _handleStage4Distribution(frame);
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
  void resetTopology() {
  _recentReceivedPackets.clear();
  print("Dispatcher: Topology table cleared successfully.");
}
//stage 2:!!!!!!!!!!!!!!!!!!!!
    Future<void> _handleStage2ChainFormation(Uint8List frame, Function(String deviceId) onPacketDetected) async {
    String chainKey = frame.sublist(0, 7).join(',');
    
    if (_ignorePackets.containsKey(chainKey)) {
      print("Dispatcher: Listening to our own Chain Frame. Ignoring.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }
    
    if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
      print("Dispatcher: Stage 2 CRC8 Verification Failed. Dropping frame.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }

    try {
     
      String myShortIdStr = await DeviceIdCreateLogic().getShortId();
      int myShortIdByte = int.parse(myShortIdStr, radix: 16);
      print("Dispatcher: Processing Verified Stage 2 Frame: $frame");


      
      bool myIdFound = frame.sublist(1, 6).contains(myShortIdByte);

      if (myIdFound) {
        print("Dispatcher: Received Implicit ACK for String ID $myShortIdStr. Stopping retries.");
        _receivedImplicitAck = true; 

        
        List<int> idSlots = frame.sublist(1, 6); 
        int myIndexInSlots = idSlots.indexOf(myShortIdByte);
        
       
        if (myIndexInSlots != -1 && myIndexInSlots < idSlots.length - 1) {
          int childId = idSlots[myIndexInSlots + 1];
          
          if (childId != 0x00) {
            
            if (!_myChildrenMap.containsKey(childId)) {
              _myChildrenMap[childId] = true; 
              _expectedPacketsCount++;       
              print("Dispatcher: Direct child detected! Child ID: $childId. Total expected return packets: $_expectedPacketsCount");
            }
          }
        }

        _symbolBuffer.fillRange(0, 24, 0);
        return; 
      }

      int backoffMs = _calculateHashBackoff(myShortIdStr);
      print("Dispatcher: ID not in frame. Waiting backoff of ${backoffMs}ms."); 
      await Future.delayed(Duration(milliseconds: backoffMs));

      
      int nextFreeIndex = _findNextAvailableSlotIndex(frame.sublist(1, 6));

      if (nextFreeIndex != -1) {
        Uint8List outboundFrame = Uint8List.fromList(frame);
        
        
        outboundFrame[1 + nextFreeIndex] = myShortIdByte;
        
        outboundFrame[6] = 0x00; 
        outboundFrame[7] = PacketBuilderLogic.crcCheckSum(outboundFrame.sublist(0, 7));


        _receivedImplicitAck = false; 
        _transmitChainWithRetries(outboundFrame, 1);
      } else {
        print("Dispatcher: Chain is full, no space for another 4-byte String ID.");
      }

      _symbolBuffer.fillRange(0, 24, 0); 
    } catch(e) {
      print("DEBUG: Stage 2 processing failed: $e");
    }
  }

void _transmitChainWithRetries(Uint8List packet, int attempt) async {
    if (_receivedImplicitAck) {
      print("Dispatcher: Implicit ACK received, stopping chain retry chain."); 
      return;
    }

    if (attempt > 5) {
      print("Dispatcher: No response after 5 attempts. Confirmed: I am a Leaf Node!"); 
      _isLeafNode = true;
      _initiateStage3Return(packet); 
      return;
    }

    print("Dispatcher: Transmitting Chain Packet, Attempt #$attempt out of 5");
    
    String outboundKey = packet.sublist(0, 7).join(',');
    _ignorePackets[outboundKey] = DateTime.now();
    Future.delayed(const Duration(seconds: 8), () {
      _ignorePackets.remove(outboundKey);
    });

    await _transmitter.transmitFrame(packet); 

    Future.delayed(const Duration(milliseconds: 1600), () {
      _transmitChainWithRetries(packet, attempt + 1); 
    });
  }
  

  
  int _findNextAvailableSlotIndex(Uint8List slotRegion) {
    for (int i = 0; i < slotRegion.length; i++) {
      if (slotRegion[i] == 0x00) {
        return i; 
      }
    }
    return -1;
  }
int _calculateHashBackoff(String idStr) {
    int val1 = int.parse(idStr[0], radix: 16); 
    int val2 = int.parse(idStr[1], radix: 16); 

    int largeVal = val1 > val2 ? val1 : val2;
    int smallVal = val1 > val2 ? val2 : val1;

    int largeTimer = largeVal * 40; 
    int smallTimer = smallVal * 10; 

    int tieBreaker = ((idStr.hashCode % 4) + 1) * 25; 
    int baseDelay = 100; 

    int totalBackoff = baseDelay + largeTimer + smallTimer + tieBreaker;
    
    print("Backoff Math for $idStr -> Char1: $val1, Char2: $val2 | Large: $largeVal, Small: $smallVal -> Total Delay: ${totalBackoff}ms");
    return totalBackoff;
}
//STAGE 3 BACKWARD
void _initiateStage3Return(Uint8List stage2Packet) async {
    print("Dispatcher: Leaf Node initiating Stage 3 Return Mechanism.");
    String myShortIdStr = await DeviceIdCreateLogic().getShortId();
    int myShortIdByte = int.parse(myShortIdStr, radix: 16);
    
    List<int> idSlots = stage2Packet.sublist(1, 6);
    int myIndex = idSlots.indexOf(myShortIdByte);
    
    if (myIndex > 0) {
      int parentId = idSlots[myIndex - 1];  
      
      Uint8List stage3Frame = Uint8List.fromList(stage2Packet);
      stage3Frame[0] = 0x0F;        // שינוי פריאמבל לשלב 3 רשמי
      stage3Frame[6] = parentId;    // השתלת ה-Target ID בבייט 6
      stage3Frame[7] = PacketBuilderLogic.crcCheckSum(stage3Frame.sublist(0, 7)); // חישוב CRC טאבולרי מעודכן
      
      _receivedImplicitAck = false;
      _transmitStage3WithRetries(stage3Frame, 1);
    } else {
      print("Dispatcher: Error - Leaf Node is at index 0? Structural failure.");
    }
  }

  // תיקון 2: מתודת השידור החוזר המשלש של שלב 3 שהייתה חסרה אצלך
  void _transmitStage3WithRetries(Uint8List packet, int attempt) async {
    if (_receivedImplicitAck) {
      print("Dispatcher: Stage 3 Implicit ACK received from Parent. Stopping retries.");
      return;
    }

    if (attempt > 5) {
      print("Dispatcher: Stage 3 Parent node failed to respond after 5 attempts.");
      return;
    }

    print("Dispatcher: Transmitting Stage 3 Return Packet, Attempt #$attempt out of 5");
    String outboundKey = packet.sublist(0, 7).join(',');
    _ignorePackets[outboundKey] = DateTime.now();
    Future.delayed(const Duration(seconds: 8), () {
      _ignorePackets.remove(outboundKey);
    });

    await _transmitter.transmitFrame(packet);

    Future.delayed(const Duration(milliseconds: 1600), () {
      _transmitStage3WithRetries(packet, attempt + 1);
    });
  }

  Future<void> _handleStage3ReturnMechanism(Uint8List frame) async {
    String returnKey = frame.sublist(0, 7).join(',');
    
    if (_ignorePackets.containsKey(returnKey)) {
      print("Dispatcher: Listening to our own Stage 3 Frame. Ignoring.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }
    
    if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
      print("Dispatcher: Stage 3 CRC8 Verification Failed. Dropping frame.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }

    try {
      String myShortIdStr = await DeviceIdCreateLogic().getShortId();
      int myShortIdByte = int.parse(myShortIdStr, radix: 16);
      
      int targetId = frame[6]; 
      List<int> idSlots = frame.sublist(1, 6);
      int myIndex = idSlots.indexOf(myShortIdByte);

      
      if (myIndex != -1) {
        for (int i = 0; i < myIndex; i++) {
          if (idSlots[i] != 0x00 && frame[6] == idSlots[i]) {
             print("Dispatcher: Overheard active ancestor upstream transmission. Stopping our Stage 3 retries.");
             _receivedImplicitAck = true;
             _symbolBuffer.fillRange(0, 24, 0);
             return;
          }
        }
      }

      
      if (targetId == myShortIdByte) {
        if (myIndex != -1 && myIndex < idSlots.length - 1) {
          int senderId = idSlots[myIndex + 1];
          
        
          if (_myChildrenMap.containsKey(senderId) && _myChildrenMap[senderId] == true) {
            _myChildrenMap[senderId] = false; 
            _expectedPacketsCount--;        
            print("Dispatcher: Valid Stage 3 packet received from child $senderId. Remaining children to wait for: $_expectedPacketsCount");
            
            // (Join Barrier) 
            if (_expectedPacketsCount == 0) {
              print("Dispatcher: Join Barrier Broken! All expected children branches merged.");
              
              if (myIndex == 0) {
                print("Dispatcher: Root Node received all branches! Transitioning to Stage 4 (Final Distribution).");
                _initiateStage4Distribution(frame);
              } else {
               //combine brothers
                int myParentId = idSlots[myIndex - 1];
                Uint8List combinedFrame = Uint8List(8);
                
                combinedFrame[0] = 0x0F; 
                
                
                for (int i = 0; i <= myIndex; i++) {
                  combinedFrame[1 + i] = idSlots[i];
                }
                
                
                int nextSlotIdx = myIndex + 1;
                _myChildrenMap.forEach((childId, _) {
                  if (nextSlotIdx < 5) {
                    combinedFrame[1 + nextSlotIdx] = childId;
                    nextSlotIdx++;
                  }
                });
                
                combinedFrame[6] = myParentId;
                combinedFrame[7] = PacketBuilderLogic.crcCheckSum(combinedFrame.sublist(0, 7));
                
                print("Dispatcher: Upstream Merged Frame Created: $combinedFrame");
                _receivedImplicitAck = false;
                _transmitStage3WithRetries(combinedFrame, 1);
              }
            } else {
              print("Dispatcher: Join Barrier Active. Still holding packet upstream until all branches arrive.");
            }
          }
        }
      }
      _symbolBuffer.fillRange(0, 24, 0);
    } catch(e) {
      print("DEBUG: Stage 3 handling failed: $e");
    }
    
  
  }
  // --- STAGE 4 IMPLEMENTATION ---
  Future<void> _handleStage4Distribution(Uint8List frame) async {
    String stage4Key = frame.sublist(0, 7).join(',');
    
    if (_ignorePackets.containsKey(stage4Key)) {
      print("Dispatcher: Listening to our own Stage 4 Frame. Ignoring.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }
    
    if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
      print("Dispatcher: Stage 4 CRC8 Verification Failed. Dropping frame.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }

    try {
      String myShortIdStr = await DeviceIdCreateLogic().getShortId();
      int myShortIdByte = int.parse(myShortIdStr, radix: 16);
      
      List<int> idSlots = frame.sublist(1, 6); 
      bool myIdFound = idSlots.contains(myShortIdByte);
      int myIndex = idSlots.indexOf(myShortIdByte);

      if (!myIdFound) {
        print("Dispatcher: Stage 4 Overheard, but my short ID ($myShortIdStr) is missing from topology.");
        print("Dispatcher: Confirmed - I am excluded from this network instance. Resetting to Idle.");
        
        resetTopology(); 
        _symbolBuffer.fillRange(0, 24, 0);
        return; 
      }

      print("Dispatcher: Confirmed! I am part of the active network topology. Processing Consumption Mask...");
      int consumptionMask = frame[6]; 

     
      int myBitPosition = 6 - myIndex;
      
      int leftmostActiveSlot = -1;
      for (int i = 5; i >= 1; i--) {
        if (((consumptionMask >> i) & 1) == 1) {
          leftmostActiveSlot = i;
          break; 
        }
      }

      if (leftmostActiveSlot == myBitPosition) {
        print("Dispatcher: It's my turn in Stage 4! Slot Index: $myIndex, Bit Position: $myBitPosition");
        
        
        Uint8List nextFrame = Uint8List.fromList(frame);
        nextFrame[6] = consumptionMask & ~(1 << myBitPosition); //turn off personal bit
        nextFrame[7] = PacketBuilderLogic.crcCheckSum(nextFrame.sublist(0, 7)); 
        ////////////// תריך להוסיף פה הוספת הפקטא למאגר הנתונים שלנו סוג של RETURN לAPI ובוא רשימת המכשירים הקיימים ברשת
        
        print("Dispatcher: Propagating updated Stage 4 frame down the chain: $nextFrame");
        _receivedImplicitAck = false;
        _transmitStage4WithRetries(nextFrame, 1);  
        
      } else {
        // if who ever tranmitted is child
        if (leftmostActiveSlot < myBitPosition && leftmostActiveSlot != -1) {
          print("Dispatcher: Overheard my child/descendant transmitting updated mask. Stage 4 Implicit ACK confirmed.");
          _receivedImplicitAck = true; 
        }
        
        _symbolBuffer.fillRange(0, 24, 0);
        return;
      }

      _symbolBuffer.fillRange(0, 24, 0);
    } catch (e) {
      print("DEBUG: Stage 4 handling failed: $e");
    }
  }
  //init stage 4 root
  void _initiateStage4Distribution(Uint8List stage3Packet) async {
    print("Dispatcher: Root Node initiating Stage 4 Final Distribution.");
    List<int> idSlots = stage3Packet.sublist(1, 6);
    
    Uint8List stage4Frame = Uint8List(8);
    stage4Frame[0] = 0x0A; 
    
    
    for (int i = 0; i < 5; i++) {
      stage4Frame[1 + i] = idSlots[i];
    }
    
    
    int mask = 0;
    for (int i = 1; i < 5; i++) {
      if (idSlots[i] != 0x00) {
        mask |= (1 << (6 - i));
      }
    }
    stage4Frame[6] = mask; 
    
    
    stage4Frame[7] = PacketBuilderLogic.crcCheckSum(stage4Frame.sublist(0, 7));
    
    print("Dispatcher: Stage 4 Initial Frame Created by Root (No Target ID): $stage4Frame");
    _receivedImplicitAck = false;
    _transmitStage4WithRetries(stage4Frame, 1);
  }
  void _transmitStage4WithRetries(Uint8List packet, int attempt) async {
   
    if (_receivedImplicitAck) {
      print("Dispatcher: Stage 4 ACK / Implicit ACK received. Stopping distribution retries.");
      return;
    }

    if (attempt > 5) {
      print("Dispatcher: Stage 4 Distribution failed to reach child after 5 attempts. Path broken.");
      return;
    }

    print("Dispatcher: Transmitting Stage 4 Distribution Packet, Attempt #$attempt out of 5");
    String outboundKey = packet.sublist(0, 7).join(',');
    _ignorePackets[outboundKey] = DateTime.now();
    Future.delayed(const Duration(seconds: 8), () {
      _ignorePackets.remove(outboundKey);
    });

    await _transmitter.transmitFrame(packet);

    
    Future.delayed(const Duration(milliseconds: 1600), () {
      _transmitStage4WithRetries(packet, attempt + 1);
    });
  }
}




