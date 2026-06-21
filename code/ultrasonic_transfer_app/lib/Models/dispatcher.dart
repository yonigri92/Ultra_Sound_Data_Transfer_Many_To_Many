import 'package:ultrasonic_transfer_app/Models/ack_logic.dart';
import 'audio_transmitter_logic.dart';
import 'dart:typed_data';
import 'hand_shake_decoder.dart';
import 'data_frame_builder_logic.dart';
import 'packet_builder_logic.dart';
import 'handshake_frame_builder_logic.dart';
import 'device_id_create_logic.dart';
enum TopologyEvent {
  discoveryStarted,  // "אל תעשה כלום, אנחנו בדיסקברי עכשיו"
  discoveryFinished, // "סיימנו, קח את נתוני המפה"
}
class Dispatcher{
  Function()? onDiscoveryFinished;
  Future<void> Function()? changeToNextStage;
  Future<void> Function()? csmaWait;


  final List<int> _symbolBuffer = List.filled(24, 0, growable: true);
  final HandshakeDecoder _handshakeDecoder = HandshakeDecoder();
  final Map<int, DateTime> _recentReceivedPackets = {};//this is the saved data of all the recent recived messeges, 
                                                       //its used so we wont accidently re read the same message twice
  final Map<int, Uint8List> _outgoingPackets = {}; // saves packets that we allready sent once so that we will be able to
                                                   // keep track on wheather we recived ack for them or if we need to send them again
  final Map<String, DateTime> _ignorePackets = {};                           
  DataFrameBuilderLogic? _incomingMessage;
  final int _ackSeq = 255;
  DateTime _lastChildActivityTime = DateTime.now();
  late AudioTransmitter _transmitter;//object that transmists
  final List<Uint8List> _dataQueue = [];
  final List<Uint8List> _ackQueue = [];
  bool _hasJoinedStage2Chain = false;
  final Map<int, int> _packetAttempts = {};// counter for each packet
  bool _isWorkerRunning = false;
  List<int> latestTopology = [];
  bool get isWorkerRunning => _isWorkerRunning;
  Dispatcher(this._transmitter);
  bool isStage1Allowed = true;
  bool isStage2Allowed = false;
  bool isStage3Allowed = false;
  bool isStage4Allowed = false;
  bool _receivedImplicitAck = false; 
  bool _receivedImplicitAckStage3 = false;
  bool _receivedImplicitAckStage2 = false;
  bool _isLeafNode = false;
  bool _isWatchdogRunning = false;
  bool _stage4TurnExecuted = false;
  int _watchdogCountdown = 10;
  int _watchdogExtensions = 0;
  final Map<int, bool> _myChildrenMap = {}; 
  int _expectedPacketsCount = 0;
  Future<void> pushSymbol(int symbol, Function(String deviceId) onPacketDetected) async {
      if (symbol == -1) return;
      
      _symbolBuffer.removeAt(0);
      _symbolBuffer.add(symbol);
      
      await _checkFrame(onPacketDetected);
    }
    List<int> getSymbolBuffer() {
    return _symbolBuffer;
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
      
      else if ((frame[4] ) == 0x0B) {
        preamble = 0x0B;
        Uint8List alignedFrame = Uint8List(8);
        for (int i = 0; i < 8; i++) {
        alignedFrame[i] = (_symbolBuffer[8 + i * 2] << 4 | _symbolBuffer[8 + i * 2 + 1] & 0x0F);
      }
        frame = alignedFrame; 
      }
      else if ((frame[4] ) == 0x0E) {
            preamble = 0x0E;
            Uint8List alignedFrame = Uint8List(8);
            for (int i = 0; i < 8; i++) {
              alignedFrame[i] = (_symbolBuffer[8 + i * 2] << 4 | _symbolBuffer[8 + i * 2 + 1] & 0x0F);
            }
            frame = alignedFrame; 
      }
      else if ((frame[4] ) == 0x0F) {
        preamble = 0x0F;
        Uint8List alignedFrame = Uint8List(8);
        for (int i = 0; i < 8; i++) {
            alignedFrame[i] = (_symbolBuffer[8 + i * 2] << 4 | _symbolBuffer[8 + i * 2 + 1] & 0x0F);
          }
        frame = alignedFrame; 
      } 
      else if ((frame[4] ) == 0x0A) {
        preamble = 0x0A;
        Uint8List alignedFrame = Uint8List(8);
        for (int i = 0; i < 8; i++) {
            alignedFrame[i] = (_symbolBuffer[8 + i * 2] << 4 | _symbolBuffer[8 + i * 2 + 1] & 0x0F);
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
          _log("Routing to Handshake");
          String handshakeKey = frame.sublist(0, 7).join(',');
          if (_ignorePackets.containsKey(handshakeKey)) {
            _log("Dispatcher: Listening to our own Handshake ignore.");
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
            _log("DEBUG: Handshake Check failed: $e");
          }
          
          break; 
        case 0x0E:
          if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
              _symbolBuffer.fillRange(0, 24, 0);
              break;
            }
            _lastChildActivityTime = DateTime.now();
            if (_isWatchdogRunning) {
              _watchdogCountdown = 12; // מאפסים חזרה ל-12 שניות כי הילד עדיין תקוע בשלב 2
              _log("Dispatcher: Overheard valid Stage 2 frame. Child is still actively trying to join, extending Watchdog.");
            }
          if (isStage3Allowed || isStage4Allowed) {
              _symbolBuffer.fillRange(0, 24, 0);
              break;
          }
            if (!isStage2Allowed) {
            _log("Dispatcher: Overheard Stage 2 Frame but Stage 1 was NOT completed. Dropping.");
            _symbolBuffer.fillRange(0, 24, 0);
            break;
          }
        _symbolBuffer.fillRange(0, 24, 0);
        _log("Routing to Stage 2: Chain Formation");
        await _handleStage2ChainFormation(frame, onPacketDetected);
        break;



        case 0x0F:
          // 1. הגנת ה-CRC של יוני: אם שמענו שלב 3 וה-CRC נכשל, הבן מנסה לדבר!
          if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
            if (_isWatchdogRunning) {
              _watchdogCountdown = 10; // מאפסים את השעון חזרה ל-10 שניות מהרגע הזה!
              _log("Dispatcher: Overheard Stage 3 Preamble but CRC8 Failed. Child is struggling to connect, extending Watchdog window to 10s.");
            }
            _symbolBuffer.fillRange(0, 24, 0);
            break;
          }

          if (!isStage3Allowed) {
            _log("Dispatcher: Overheard Stage 3 Frame but Gate 3 is LOCKED. Dropping.");
            _symbolBuffer.fillRange(0, 24, 0);
            break;
          }

          // אם ה-CRC תקין, נעדכן את השעון ליתר ביטחון ונריץ את המיזוג
          _watchdogCountdown = 10;
          _symbolBuffer.fillRange(0, 24, 0);
          _log("Routing to Stage 3: Return Mechanism");
          await _handleStage3ReturnMechanism(frame);
          break;




        case 0x0A:
          
          // 1. בדיקת שערים בסיסית - האם בכלל מותר לנו להקשיב לשלב 4
          if (!isStage4Allowed && !isStage3Allowed) {
            _log("Dispatcher: Overheard Stage 4 Frame but Gate 4 is LOCKED. Dropping.");
            _symbolBuffer.fillRange(0, 24, 0);
            break;
          }
          
          // 2. בדיקת תקינות ה-CRC8 של הפריים
          if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
            _log("Dispatcher: Overheard Stage 4 Preamble but CRC8 Verification Failed. Dropping.");
            _symbolBuffer.fillRange(0, 24, 0);
            break;
          }
          _symbolBuffer.fillRange(0, 24, 0);
          // 🔥 פיתוח מנגנון המען של יוני: חילוץ המיקום וה-Mask כדי לוודא שזה מיועד אלינו מההורה
          List<int> idSlots = frame.sublist(1, 6);
          String myShortIdStr = await DeviceIdCreateLogic().getShortId();
          int myShortIdByte = int.parse(myShortIdStr, radix: 16);
          
          bool myIdFound = idSlots.contains(myShortIdByte);
          int myIndex = idSlots.indexOf(myShortIdByte);
          
          // חישוב המען האקטיבי מתוך ה-Consumption Mask
          int consumptionMask = frame[6];
          int myBitPosition = 6 - myIndex;
          int leftmostActiveSlot = -1;
          
          for (int i = 5; i >= 1; i--) {
            if (((consumptionMask >> i) & 1) == 1) {
              leftmostActiveSlot = i;
              break;
            }
          }
          
          // תנאי המען הרשמי: המזהה שלי קיים, וזה בדיוק התור שלי בשרשרת (הביט השמאלי הפעיל ביותר)
          bool isPacketDirectlyForMe = myIdFound && (leftmostActiveSlot == myBitPosition);
          
          // 3. אם אנחנו בשלב 3, נתייחס לזה כ-Implicit ACK אך ורק אם הפאקט מיועד אלינו ישירות!
          if (isStage3Allowed && !isStage4Allowed) {
            if (isPacketDirectlyForMe) {
              _log("Dispatcher: Overheard VALID Stage 4 from parent directed to ME! Treating as Stage 3 Implicit ACK.");
              
              _receivedImplicitAckStage3 = true; // עצירת לולאת הרטרייז של שלב 3
              
              if (changeToNextStage != null) {
                await changeToNextStage!(); // מעבר לוגי מיידי לשלב 4 (פתיחת שער 4)
              }
            } else {
              // הפאקט תקין מבחינת CRC, אבל הוא מיועד למכשיר אחר כרגע. 
              // אנחנו מתעלמים וממשיכים להמתין בשלב 3 לפאקט שלנו.
              _log("Dispatcher: Overheard Stage 4 but it's NOT my turn yet. Continuing Stage 3 retries.");
              
              break;
            }
          }
          
          // 4. ניתוח הפאקט ועיבוד ה-Consumption Mask בשלב 4 (ירוץ רק אם אנחנו בשלב 4 או שזה עתה עברנו אליו)
          _log("Routing to Stage 4: Final Distribution & Consumption Mask");
          await _handleStage4Distribution(frame);
          
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
            _log("Routing to ACK");

            String ackKey = frame.sublist(0, 3).join(',');

            if (_ignorePackets.containsKey(ackKey)) {
                _log("Dispatcher: Listening to our own Ack ignore.");
                _symbolBuffer.fillRange(0, 24, 0);
                break; 
            }


            Uint8List validatedFrame = await AckLogic.receiveAckFrame(frame);
            int highNibble = validatedFrame[0] & 0x0F;
            int lowNibble = (validatedFrame[1] >> 4) & 0x0F;
            int receivedSeq = (highNibble << 4) | lowNibble;


            if (!_outgoingPackets.containsKey(receivedSeq)) {
                _log("Dispatcher: Acoustic echo or invalid ACK for Seq: $receivedSeq. Ignoring.");
                _symbolBuffer.fillRange(0, 24, 0);
                break; 
            }
            //String ackKey = frame.sublist(0, 5).join(',');
            //this part will delete the ack recived from reciver so it we wont send the packet again
            _log("Dispatcher: Received ACK for Seq: $receivedSeq.");
            _outgoingPackets.remove(receivedSeq);
            _packetAttempts.remove(receivedSeq);
            
          
            
            
            _symbolBuffer.fillRange(0, 24, 0);
          }
          catch(e){
            _log("DEBUG: ACK Check failed: $e");
          }
          break;

       case 0x0D:
          _log("Routing to Data");
          _log("RAW DATA FRAME FROM AIR: $frame");
          String dataKey = frame.join(',');
          if (_ignorePackets.containsKey(dataKey)) {
            _log("Dispatcher: Listening to our own Data ignore.");
            _symbolBuffer.fillRange(0, 24, 0);
            break; 
            }
          int receivedSeq = frame[1]; 
          if (_outgoingPackets.containsKey(receivedSeq)) {
            _log("Dispatcher: Acoustic echo of our own Data Packet (Seq: $receivedSeq) detected. Ignoring.");
            _symbolBuffer.fillRange(0, 24, 0);
            break; 
          }



          try {
            if(_incomingMessage == null)
            { _incomingMessage = DataFrameBuilderLogic(256);}
            PacketBuilderLogic? validatedPacket = _incomingMessage!.reciveDataFrameBuilderLogic(frame);
            
            if (validatedPacket != null) {
              int currentSeq = validatedPacket.seq;
              _log("Dispatcher: Valid Data Packet received for Seq: $currentSeq");
              Uint8List ackFrame = await AckLogic.buildAckFrame(currentSeq);
              await addACkPacketToQueue(currentSeq, ackFrame);

              //int eofIndex = _incomingMessage!.length;
              bool hasReceivedEOF = _incomingMessage!.messages[255] != null;
              
              if (hasReceivedEOF) {
                try {
                  _log("Dispatcher: EOF is present. Trying to reconstruct...");
                  Uint8List fullMessageBytes = _incomingMessage!.reconstruct();
                  
                  String finalMessage = String.fromCharCodes(fullMessageBytes);
                  int messageHash = finalMessage.hashCode;
                  DateTime now = DateTime.now();
                  
                  _recentReceivedPackets.removeWhere((id, time) => now.difference(time).inSeconds > 8);
                  
                  if (_recentReceivedPackets.containsKey(messageHash) == false) {
                    _recentReceivedPackets[messageHash] = now;
                    _log("Dispatcher: Success! Delivering new message to UI.");
                    onPacketDetected(finalMessage);
                  } else {
                    _log("Dispatcher: Duplicate whole message detected within 3 seconds. Dropping.");
                  }
                  
                  _incomingMessage = null;
                } catch (reconstructError) {
                  _log("Dispatcher: Reconstruction failed (Message still incomplete): $reconstructError");
                }
              }
              _symbolBuffer.fillRange(0, 24, 0);
            }
            
            
          } catch (e) {
            _log("DEBUG: Data packet processing failed: $e");
          }
          break;

        // default:
        //   // no known data type
        //   print("Unknown packet type");


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
          _log("Packet $seq already got ACK while waiting in queue. Skipping.");
          continue;
        }
      
        int attempts = (_packetAttempts[seq] ?? 0) + 1;// this must be wrote this way to either initiaise the map to 0 or add 1 if not 0
        _packetAttempts[seq] = attempts;
        _log("Worker: Transmitting Data packet (Seq: $seq), Attempt #$attempts");
        await _transmitter.transmitFrame(dataFrame);

        if (attempts < 5) {
          _dataQueue.add(dataFrame);
          await Future.delayed(const Duration(milliseconds: 950));
        } else {
           _log("Worker: Packet (Seq: $seq) failed after max retries. Dropping.");
          _outgoingPackets.remove(seq);
          _packetAttempts.remove(seq);
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    }

    _isWorkerRunning = false; 
    _log("Worker: All queues empty. Going to sleep.");
  }
  void resetTopology() {
    _recentReceivedPackets.clear();
    _myChildrenMap.clear(); // מומלץ לנקות גם את זה
    _expectedPacketsCount = 0; // מומלץ לנקות גם את זה
    _hasJoinedStage2Chain = false; // 🔥 מאפסים את חסם השרשרת
    _stage4TurnExecuted = false;
    _watchdogExtensions = 0;
    _dataQueue.clear();
    _ackQueue.clear();
    _outgoingPackets.clear();
    _packetAttempts.clear();
    _log("Dispatcher: Topology table cleared successfully.");


  }
//stage 2:!!!!!!!!!!!!!!!!!!!!
    void initiateStage2AsRoot(int myShortIdByte) {
    Uint8List rootFrame = Uint8List(8);
    rootFrame[0] = 0x0E;          
    rootFrame[1] = myShortIdByte;
    
    rootFrame[6] = 0x00; 
    rootFrame[7] = PacketBuilderLogic.crcCheckSum(rootFrame.sublist(0, 7)); // ה-CRC8 הטאבולרי שלך

    _log("Dispatcher: Root initiating Stage 2 Discovery Chain: $rootFrame");
    _receivedImplicitAckStage2 = false;
    
   
    _transmitChainWithRetries(rootFrame, 1); 
  }



    Future<void> _handleStage2ChainFormation(Uint8List frame, Function(String deviceId) onPacketDetected) async {
    String chainKey = frame.sublist(0, 7).join(',');
    
    if (_ignorePackets.containsKey(chainKey)) {
      DateTime txTime = _ignorePackets[chainKey]!;
      if (DateTime.now().difference(txTime).inSeconds < 6) {
        _log("Dispatcher: Overheard our own recently transmitted Chain Frame. Ignoring echo.");
        _symbolBuffer.fillRange(0, 24, 0);
        return;
      }
    }
    if (_hasJoinedStage2Chain) {
      _log("Dispatcher: Already joined Stage 2 Chain instance. Dropping duplicate root trigger.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }
    if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
      _log("Dispatcher: Stage 2 CRC8 Verification Failed. Dropping frame.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }

    try {
     
      String myShortIdStr = await DeviceIdCreateLogic().getShortId();
      int myShortIdByte = int.parse(myShortIdStr, radix: 16);
      _log("Dispatcher: Processing Verified Stage 2 Frame: $frame");


      
      
      List<int> idSlots = frame.sublist(1, 6); 
      int myIndexInSlots = idSlots.indexOf(myShortIdByte);
      bool myIdFound = myIndexInSlots != -1;
      if (myIdFound) {  
        bool isImplicitAckValid = false;
        // 🔥 הגנה: רק אם זו הפעם הראשונה שאנחנו מקבלים את האישור, מקדמים את השלב הלוגי
        if (myIndexInSlots == 0) {
          // אם אני השורש (אינדקס 0), פאקט נחשב כאישור אך ורק אם המקום הבא אחריו אינו ריק!
          if (idSlots[1] != 0x00) {
            isImplicitAckValid = true;
          } else {
            _log("Dispatcher: Overheard my own Root frame echo, but no children joined yet. Continuing Stage 2 discovery.");
          }
        } else {
          // אם אני Follower, עצם קיום ה-ID שלי אומר שהתקבלתי לשרשרת
          isImplicitAckValid = true;
        }
        
        
        
        if (isImplicitAckValid && !_receivedImplicitAckStage2) {
          List<int> idSlots = frame.sublist(1, 6); 
          int myIndexInSlots = idSlots.indexOf(myShortIdByte);
          _log("Dispatcher: Received Implicit ACK for String ID $myShortIdStr. Stopping retries.");
          _receivedImplicitAckStage2 = true; 
          
          if (changeToNextStage != null) {
            await changeToNextStage!();
          }
          _log("Dispatcher: Gate 3 is now OPEN.");
          
          // 🔥 אם אני השורש (אינדקס 0), זה הזמן להפעיל את הווטשדוג של שלב 3!
          if (myIndexInSlots == 0) {
            _startStage3Watchdog(frame);
          }
          
          
          
          if (myIndexInSlots != -1 && myIndexInSlots < idSlots.length - 1) {
            int childId = idSlots[myIndexInSlots + 1];
            if (childId != 0x00) {
              if (!_myChildrenMap.containsKey(childId)) {
                _myChildrenMap[childId] = true; 
                _expectedPacketsCount++;       
                _log("Dispatcher: Direct child detected! Child ID: $childId. Total expected return packets: $_expectedPacketsCount");
              }
            }
          }
        } else {
          // חבילה כפולה באוויר - מתעלמים ולא מקדמים שלב פעם שנייה בטעות
          _log("Dispatcher: Duplicate implicit ACK overheard. Already in Stage 3. Ignoring.");
        }

        _symbolBuffer.fillRange(0, 24, 0);
        return; 
      }
      _hasJoinedStage2Chain = true;
      int backoffMs = _calculateHashBackoff(myShortIdStr);
      _log("Dispatcher: ID not in frame. Waiting backoff of ${backoffMs}ms."); 
      await Future.delayed(Duration(milliseconds: backoffMs));

      
      int nextFreeIndex = _findNextAvailableSlotIndex(frame.sublist(1, 6));

      if (nextFreeIndex != -1) {
        Uint8List outboundFrame = Uint8List.fromList(frame);
        
        
        outboundFrame[1 + nextFreeIndex] = myShortIdByte;
        
        outboundFrame[6] = 0x00; 
        outboundFrame[7] = PacketBuilderLogic.crcCheckSum(outboundFrame.sublist(0, 7));


        _receivedImplicitAckStage2 = false; 
        _transmitChainWithRetries(outboundFrame, 1);
      } else {
        _log("Dispatcher: Chain is full, no space for another 4-byte String ID.");
        _hasJoinedStage2Chain = false;
      }

      _symbolBuffer.fillRange(0, 24, 0); 
    } catch(e) {
      _log("DEBUG: Stage 2 processing failed: $e");
      _hasJoinedStage2Chain = false;
    }
  }

void _transmitChainWithRetries(Uint8List packet, int attempt) async {
    if (!isStage2Allowed) {
        _log("Dispatcher: Stage 2 was aborted. Stopping zombie transmission attempt #$attempt.");
        return;
      }
    if (_receivedImplicitAckStage2) {
      _log("Dispatcher: Implicit ACK received, stopping chain retry chain."); 
      return;
    }

    if (attempt > 8) {
      _log("Dispatcher: No response after 8 attempts. Confirmed: I am a Leaf Node!"); 
      _isLeafNode = true;
      _initiateStage3Return(packet); 
      return;
    }
    if (csmaWait != null) {
      await csmaWait!();
    }
    _log("Dispatcher: Transmitting Chain Packet, Attempt #$attempt out of 8");
    
    String outboundKey = packet.sublist(0, 7).join(',');
    _ignorePackets[outboundKey] = DateTime.now();
    
    // Future.delayed(const Duration(seconds: 8), () {
    //   _ignorePackets.remove(outboundKey);
    // });

    await _transmitter.transmitFrame(packet); 

    Future.delayed(const Duration(milliseconds: 4000), () {
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
    
    _log("Backoff Math for $idStr -> Char1: $val1, Char2: $val2 | Large: $largeVal, Small: $smallVal -> Total Delay: ${totalBackoff}ms");
    return totalBackoff;
}
//STAGE 3 BACKWARD
void _initiateStage3Return(Uint8List stage2Packet) async {
    _log("Dispatcher: Leaf Node initiating Stage 3 Return Mechanism.");
    String myShortIdStr = await DeviceIdCreateLogic().getShortId();
    int myShortIdByte = int.parse(myShortIdStr, radix: 16);
    
    List<int> idSlots = stage2Packet.sublist(1, 6);
    int myIndex = idSlots.indexOf(myShortIdByte);
    
    if (myIndex > 0) {
      if (changeToNextStage != null) {
                  await changeToNextStage!();
                }
    _log("Dispatcher: Leaf Node opened Gate 3.");
      int parentId = idSlots[myIndex - 1];  
      
      Uint8List stage3Frame = Uint8List.fromList(stage2Packet);
      stage3Frame[0] = 0x0F;        // שינוי פריאמבל לשלב 3 רשמי
      stage3Frame[6] = parentId;    // השתלת ה-Target ID בבייט 6
      stage3Frame[7] = PacketBuilderLogic.crcCheckSum(stage3Frame.sublist(0, 7)); // חישוב CRC טאבולרי מעודכן
      
      _receivedImplicitAckStage3 = false;
      _transmitStage3WithRetries(stage3Frame, 1);
    } else if (myIndex == 0) {
      // 🔥 תיקון יציאת שלב 3 של יוני: פותחים את שער 3 ומאזינים לבנים איטיים
      _log("Dispatcher: Root node finished Stage 2 attempts. Opening Gate 3 and starting Watchdog to listen for late children.");
      if (changeToNextStage != null) {
        await changeToNextStage!(); 
      }
      _startStage3Watchdog(stage2Packet);
    } else {
      _log("Dispatcher: Error - Leaf Node is at index 0? Structural failure.");
    }
  }

  // תיקון 2: מתודת השידור החוזר המשלש של שלב 3 שהייתה חסרה אצלך
  void _transmitStage3WithRetries(Uint8List packet, int attempt) async {
    if (_receivedImplicitAckStage3) {
      _log("Dispatcher: Stage 3 Implicit ACK received from Parent. Stopping retries.");
      return;
    }

    if (attempt > 5) {
      _log("Dispatcher: Stage 3 Parent node failed to respond after 5 attempts.");
      return;
    }
    if (csmaWait != null) {
      await csmaWait!();
    }
    _log("Dispatcher: Transmitting Stage 3 Return Packet, Attempt #$attempt out of 5");
    String outboundKey = packet.sublist(0, 7).join(',');
    _ignorePackets[outboundKey] = DateTime.now();
    Future.delayed(const Duration(seconds: 8), () {
      _ignorePackets.remove(outboundKey);
    });

    await _transmitter.transmitFrame(packet);
    await Future.delayed(const Duration(milliseconds: 500));
    Future.delayed(const Duration(milliseconds: 3000), () {
      _transmitStage3WithRetries(packet, attempt + 1);
    });
  }

  Future<void> _handleStage3ReturnMechanism(Uint8List frame) async {
    String returnKey = frame.sublist(0, 7).join(',');
    
    if (_ignorePackets.containsKey(returnKey)) {
      _log("Dispatcher: Listening to our own Stage 3 Frame. Ignoring.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }
    
    if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
      _log("Dispatcher: Stage 3 CRC8 Verification Failed. Dropping frame.");
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
             _log("Dispatcher: Overheard active ancestor upstream transmission. Stopping our Stage 3 retries.");
             
             // 🔥 הגנה: עוברים לשלב 4 רק אם עוד לא עברנו אליו קודם
             if (!isStage4Allowed) {
               _receivedImplicitAckStage3 = true;
               if (changeToNextStage != null) {
                 await changeToNextStage!();
               }
               _log("Dispatcher: Gate 4 is now OPEN.");
             }
             
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
            _log("Dispatcher: Valid Stage 3 packet received from child $senderId. Remaining children to wait for: $_expectedPacketsCount");
            
            // (Join Barrier) 
            if (_expectedPacketsCount == 0) {
              _log("Dispatcher: Join Barrier Broken! All expected children branches merged.");
              
              if (myIndex == 0) {
                _log("Dispatcher: Root Node received all branches! Stopping Watchdog and transitioning to Stage 4.");
                _isWatchdogRunning = false; // 🔥 עצירה מיידית של הלולאה, קיבלנו פקטה תקינה ואין מה לחכות יותר
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
                
            
                _log("Dispatcher: Upstream Merged Frame Created: $combinedFrame");
                _receivedImplicitAckStage3 = false;
                _transmitStage3WithRetries(combinedFrame, 1);
                if (changeToNextStage != null) {
                  await changeToNextStage!();
                }
                _log("Dispatcher: Gate 4 is now OPEN for final distribution listening.");
              }
            } else {
              _log("Dispatcher: Join Barrier Active. Still holding packet upstream until all branches arrive.");
            }
          }
        }
      }
      _symbolBuffer.fillRange(0, 24, 0);
    } catch(e) {
      _log("DEBUG: Stage 3 handling failed: $e");
    }
    
  
  }
  void _startStage3Watchdog(Uint8List packet) {
    if (_isWatchdogRunning) return;
    _isWatchdogRunning = true;
    _watchdogCountdown = 12; // חלון זמן ראשוני של 12 שניות
    _runWatchdogTick(packet);
  }

  void _runWatchdogTick(Uint8List packet) {
    if (!_isWatchdogRunning) return;
    
    
    if (_watchdogCountdown <= 0) {
      if (_expectedPacketsCount == 0) {
        _log("Watchdog: Network is quiet and all branches merged. Transitioning to Stage 4.");
        _isWatchdogRunning = false;
        _watchdogExtensions = 0;
        _initiateStage4Distribution(packet);
        return;
      } else {
       
       if (_watchdogExtensions >= 5) {
          _log("Watchdog: CRITICAL TIMEOUT! Giving up on missing children. Forcing Stage 4.");
          _isWatchdogRunning = false;
          _watchdogExtensions = 0;
          _initiateStage4Distribution(packet);
          return;
      }
      _watchdogExtensions++;
        _log("Watchdog: Still waiting for $_expectedPacketsCount children. Extending window (Extension $_watchdogExtensions/3).");
        _watchdogCountdown = 5;
    }}

    
    _log("Watchdog: Waiting in Stage 3... $_watchdogCountdown seconds remaining. Expected children: $_expectedPacketsCount");
    _watchdogCountdown--;

    Future.delayed(const Duration(seconds: 1), () {
      _runWatchdogTick(packet);
    });
  }
  // --- STAGE 4 IMPLEMENTATION ---
  Future<void> _handleStage4Distribution(Uint8List frame) async {
    String stage4Key = frame.sublist(0, 7).join(',');
    
    if (_ignorePackets.containsKey(stage4Key)) {
      _log("Dispatcher: Listening to our own Stage 4 Frame. Ignoring.");
      _symbolBuffer.fillRange(0, 24, 0);
      return;
    }
    
    if (PacketBuilderLogic.crcCheckSum(frame) != 0) {
      _log("Dispatcher: Stage 4 CRC8 Verification Failed. Dropping frame.");
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
        _log("Dispatcher: Stage 4 Overheard, but my short ID ($myShortIdStr) is missing from topology.");
        _log("Dispatcher: Confirmed - I am excluded from this network instance. Resetting to Idle.");
        
        resetTopology(); 
        _symbolBuffer.fillRange(0, 24, 0);
        return; 
      }
      _receivedImplicitAck = true;
      
      _log("Dispatcher: Confirmed! I am part of the active network topology. Processing Consumption Mask...");
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
        if (_stage4TurnExecuted) {
          _log("Dispatcher: Stage 4 turn already executed for this cycle. Ignoring duplicate parent frame.");
          _symbolBuffer.fillRange(0, 24, 0);
          return;
        }
        _stage4TurnExecuted = true;
        _log("Dispatcher: It's my turn in Stage 4! Slot Index: $myIndex, Bit Position: $myBitPosition");
        
        
        Uint8List nextFrame = Uint8List.fromList(frame);
        nextFrame[6] = consumptionMask & ~(1 << myBitPosition); //turn off personal bit
        nextFrame[7] = PacketBuilderLogic.crcCheckSum(nextFrame.sublist(0, 7)); 
        ////////////// תריך להוסיף פה הוספת הפקטא למאגר הנתונים שלנו סוג של RETURN לAPI ובוא רשימת המכשירים הקיימים ברשת
        latestTopology = List.from(idSlots);
        
        _log("Dispatcher: Propagating updated Stage 4 frame down the chain: $nextFrame");
        _receivedImplicitAck = false;
        _transmitStage4WithRetries(nextFrame, 1);  
        
      } else {
        // if who ever tranmitted is child
        if (leftmostActiveSlot == -1 || (leftmostActiveSlot < myBitPosition && leftmostActiveSlot != -1)) {
          _log("Dispatcher: Overheard convergence/child mask. Stage 4 Implicit ACK confirmed. Stopping retries.");
          _receivedImplicitAck = true; 
        }
        if (leftmostActiveSlot == -1 && myIndex == 0 && isStage4Allowed) { 
           
            latestTopology = List.from(idSlots);
            _log("Dispatcher: Root overheard convergence frame. Process successfully finished! Final topology: $latestTopology");
            onDiscoveryFinished?.call();
            // if (changeToNextStage != null) {
            //   await changeToNextStage!();
            // }
          }
        
        _symbolBuffer.fillRange(0, 24, 0);
        return;
      }
      
      _symbolBuffer.fillRange(0, 24, 0);
    } catch (e) {
      _log("DEBUG: Stage 4 handling failed: $e");
    }
  }
  //init stage 4 root
  void _initiateStage4Distribution(Uint8List stage3Packet) async {
    _log("Dispatcher: Root Node initiating Stage 4 Final Distribution.");
    if (changeToNextStage != null) {
      await changeToNextStage!();
    }
    List<int> idSlots = stage3Packet.sublist(1, 6);
    
  
    _log("Dispatcher: Root opened Gate 4.");
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
    
    _log("Dispatcher: Stage 4 Initial Frame Created by Root (No Target ID): $stage4Frame");
    _receivedImplicitAck = false;
    _transmitStage4WithRetries(stage4Frame, 1);
  }
  void _transmitStage4WithRetries(Uint8List packet, int attempt) async {
   
    if (_receivedImplicitAck) {
      _log("Dispatcher: Stage 4 ACK / Implicit ACK received. Stopping distribution retries.");
      onDiscoveryFinished?.call();
      return;
    }

    if (attempt > 5) {
     
      List<int> idSlots = packet.sublist(1, 6);
      String myShortIdStr = await DeviceIdCreateLogic().getShortId();
      int myShortIdByte = int.parse(myShortIdStr, radix: 16);
      int myIndex = idSlots.indexOf(myShortIdByte);

      // 2. תנאי ההתכנסות המאוחד של יוני:
      // אני עלה שהצליח אם: המאסק ריק (0), או שאני האינדקס האחרון (4), או שהמקום הבא אחרי בטבלה ריק (0)
      bool isLeafTermination = (packet[6] == 0) || 
                               (myIndex == 4) || 
                               (myIndex != -1 && idSlots[myIndex + 1] == 0x00);

      if (isLeafTermination) {
        _log("Dispatcher: I am structurally a Leaf Node or network converged. Completed 5 redundant attempts for parent safety. Finishing process with success!");
        
        // עדכון ה-UI ומעבר השלב המבוקר קורים רק עכשיו, בסוף פעימות היתירות
        onDiscoveryFinished?.call();
        // if (changeToNextStage != null) {
        //   await changeToNextStage!();
        // }
      } else {
        // אם הגענו לניסיון 6 ואני לא עלה, סימן שלא קיבלתי Implicit ACK מהילד שלי והנתיב נשבר
        _log("Dispatcher: Stage 4 Distribution failed to reach child after 5 attempts. Path broken.");
        onDiscoveryFinished?.call();
      }
      
      return; // 🔒 ה-return המאובטח ברמת הבלוק הראשי! חוסם ומסיים את הפונקציה הרמטית בכל מצב.
    }
    if (csmaWait != null) {
      await csmaWait!();
    }
    _log("Dispatcher: Transmitting Stage 4 Distribution Packet, Attempt #$attempt out of 5");
    String outboundKey = packet.sublist(0, 7).join(',');
    _ignorePackets[outboundKey] = DateTime.now();
    Future.delayed(const Duration(seconds: 8), () {
      _ignorePackets.remove(outboundKey);
    });

    await _transmitter.transmitFrame(packet);
    await Future.delayed(const Duration(milliseconds: 500));
    
    Future.delayed(const Duration(milliseconds: 3000), () {
      _transmitStage4WithRetries(packet, attempt + 1);
    });
  }
  void _log(String message) {
    print("${DateTime.now().toIso8601String()} | $message");
  }
}




