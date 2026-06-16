import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:async'; // הוספנו בשביל ההאזנה לסטרים
import 'fsk_modulation_logic.dart';
import 'audio_transmitter_logic.dart';
import 'audio_receiver_logic.dart'; 
import 'dispatcher.dart'; 
import 'fsk_control_wrapper_logic.dart'; // תוודא שהקובץ הזה קיים אצלך
import 'control_dispatcher_wrapper_logic.dart'; // תוודא שזה שם הקובץ של הראפר
import 'device_id_create_logic.dart';
class UltraApiInterface extends StatefulWidget {
  const UltraApiInterface({super.key});

  @override
  State<UltraApiInterface> createState() => _UltraApiInterfaceState();
}

class _UltraApiInterfaceState extends State<UltraApiInterface> {
  String status = "Ready";
  String lastReceivedMessage = "------";
  bool isListening = false;

  // === משתנים חדשים לניהול הדיסקברי והמכשירים ===
  List<int> _discoveredDevices = []; 
  int? _selectedTargetDevice; 
  StreamSubscription? _topologySubscription; // שומר על הצינור פתוח

  final TextEditingController _textController = TextEditingController();

  late FskModulationLogic _modulator;
  late AudioTransmitter _transmitter;
  late AudioReceiver _receiver;
  
  // היררכיית השליטה החדשה
  late Dispatcher _dispatcher; 
  late FskControlWrapperLogic _txWrapper;
  late ControlDispatcherWrapper _wrapper; 

  @override
  void initState() {
    super.initState();
    
    // 1. אתחול מנוע השידור
    _modulator = FskModulationLogic(); 
    _transmitter = AudioTransmitter(_modulator);
    _initTransmitterEngine();

    // 2. בניית השרשרת: דיספצ'ר -> שליטת FSK -> מעטפת (ראפר)
    _dispatcher = Dispatcher(_transmitter);
    _txWrapper = FskControlWrapperLogic(_modulator);
    _wrapper = ControlDispatcherWrapper(_dispatcher, _txWrapper);

    // 3. === חיבור הצינור! ה-API מאזין לאירועי הרשת ===
    _topologySubscription = _wrapper.topologyStream.listen((event) {
      if (event == TopologyEvent.discoveryStarted) {
        setState(() {
          status = "Discovery Started! Scanning room...";
          _discoveredDevices.clear();
          _selectedTargetDevice = null;
        });
      } else if (event == TopologyEvent.discoveryFinished) {
        setState(() {
          status = "Discovery Complete!";
          // מושכים את המפה מהדיספצ'ר הישר אל ה-UI
          _discoveredDevices = _dispatcher.latestTopology;
          if (_discoveredDevices.isNotEmpty) {
            _selectedTargetDevice = _discoveredDevices.first; // בוחר את הראשון אוטומטית
          }
        });
      }
    });

    // 4. אתחול המקלט והוספת סינון יעד (Routing)
    _receiver = AudioReceiver(
      onSymbolReceived: (int symbol) async {
        await _wrapper.pushSymbol(symbol, (String decodedText) async {
          
          // שולפים את ה-ID שלנו כדי לדעת אם ההודעה מיועדת אלינו
          String myShortIdStr = await DeviceIdCreateLogic().getShortId();
          
          if (mounted && decodedText.length >= 3 && decodedText[2] == ':') {
            String targetHex = decodedText.substring(0, 2);
            String actualMessage = decodedText.substring(3);

            // בודקים אם היעד הוא אנחנו או שזה שידור לכולם (FF)
            if (targetHex == myShortIdStr || targetHex == "FF") {
              setState(() {
                lastReceivedMessage = actualMessage;
                status = "Message Received Successfully!";
              });
            } else {
              print("API: Message dropped. Target: $targetHex, My ID: $myShortIdStr");
            }
          } else {
             // טיפול במקרה של הודעת מערכת או הודעה ללא ניתוב תקין
             if(mounted){
                setState(() {
                  lastReceivedMessage = decodedText;
                });
             }
          }
        });
      }
    );
  }

  Future<void> _initTransmitterEngine() async {
    try {
      await _transmitter.initEngine();
    } catch (e) {
      print("Error init transmitter engine: $e");
    }
  }

  @override
  void dispose() {
    _topologySubscription?.cancel(); // סוגרים את הברז כשיוצאים מהמסך
    _textController.dispose();
    _transmitter.release();
    _receiver.stopListening();
    super.dispose();
  }

  // הפעלת שרשרת הגילוי האוטומטית (שלבים 1 עד 4)
  void _startRoomDiscovery() async {
    setState(() => status = "Initiating Room Discovery...");
    try {
      await _wrapper.startDiscoveryWorkflow();
    } catch (e) {
      setState(() => status = "Discovery Error: $e");
    }
  }

  void _sendHandshake() async {
    setState(() => status = "Enqueuing Handshake...");
    try {
      await _dispatcher.addHandShakePacketToQueue();
      setState(() => status = "Handshake sent to queue");
    } catch (e) {
      setState(() => status = "Error sending Handshake: $e");
    }
  }

  void _sendMessage() async {
    if (_textController.text.trim().isEmpty) return;
    
    // מזהה ברירת המחדל לשידור לכולם הוא FF
    String targetHex = "FF"; 
    if (_discoveredDevices.isNotEmpty) {
      if (_selectedTargetDevice == null) {
        setState(() => status = "Please select a target device first!");
        return;
      }
      targetHex = _selectedTargetDevice!.toRadixString(16).toUpperCase().padLeft(2, '0');
    }

    String textToSend = _textController.text;
    setState(() => status = "Sending Message to $targetHex...");
    
    try {
      // === התיקון הקריטי: שרשור מזהה היעד לתחילת המחרוזת ===
      String routedMessage = "$targetHex:$textToSend";
      Uint8List dataBytes = Uint8List.fromList(routedMessage.codeUnits);
      
      await _wrapper.addDataPacketToQueue(dataBytes); // שידור ההודעה המנותבת
      
      _textController.clear(); 
      setState(() => status = "Message sent to queue");
    } catch (e) {
      setState(() => status = "Error sending message: $e");
    }
  }

  void _toggleListening() async {
    if (isListening) {
      await _receiver.stopListening();
      setState(() {
        isListening = false;
        status = "Stopped listening";
      });
      return;
    }

    var permStatus = await Permission.microphone.request();
    if (!permStatus.isGranted) {
      setState(() => status = "Error: need permission");
      openAppSettings();
      return;
    }

    setState(() {
      isListening = true;
      status = "Listening for ultrasonic data...";
    });

    try {
      await _receiver.startListening();
    } catch (e) {
      print("Receiver Error: $e");
      if (mounted) {
        setState(() {
          isListening = false;
          status = "Error: cant start listening";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Ultra API Monitor", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const Divider(),
            
            // תצוגת סטטוס המערכת
            Text("Status: $status", 
              style: TextStyle(
                color: isListening ? Colors.green : Colors.blue, 
                fontWeight: FontWeight.w500
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),

            // === כפתור דיסקברי בולט במרכז ===
            ElevatedButton.icon(
              onPressed: _startRoomDiscovery, 
              icon: const Icon(Icons.radar, size: 28),
              label: const Text("Start Network Discovery", style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade100,
                padding: const EdgeInsets.symmetric(vertical: 12)
              ),
            ),
            const SizedBox(height: 15),

            // === תפריט גלילה (Dropdown) לבחירת מכשיר יעד שמופיע רק אם מצאנו משהו ===
            if (_discoveredDevices.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _selectedTargetDevice,
                    hint: const Text("Select Target Device"),
                    items: _discoveredDevices.map((id) {
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text("Device ID: 0x${id.toRadixString(16).toUpperCase().padLeft(2, '0')}"),
                      );
                    }).toList(),
                    onChanged: (int? newValue) {
                      setState(() {
                        _selectedTargetDevice = newValue;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // תצוגת המידע המשוחזר שנקלט
            Column(
              children: [
                const Text("Last Received Message:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    lastReceivedMessage, 
                    style: const TextStyle(fontSize: 16, color: Colors.purple, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // תיבת טקסט להקלדת הודעות
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: "Type a message to transmit",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
            ),
            const SizedBox(height: 12),
            
            // כפתור שליחת ההודעה מהתיבה
            ElevatedButton.icon(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send),
              label: const Text("Transmit Data Message"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade100),
            ),
            const Divider(height: 30),
            
            // כפתורי הנדשייק והאזנה
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sendHandshake, 
                    icon: const Icon(Icons.handshake),
                    label: const Text("Handshake"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleListening, 
                    icon: Icon(isListening ? Icons.stop : Icons.mic),
                    label: Text(isListening ? "Stop Listen" : "Start Listen"),
                    style: ElevatedButton.styleFrom(backgroundColor: isListening ? Colors.red.shade100 : Colors.green.shade100),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}