import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:async'; 
import 'fsk_modulation_logic.dart';
import 'audio_transmitter_logic.dart';
import 'audio_receiver_logic.dart'; 
import 'dispatcher.dart'; 
import 'fsk_control_wrapper_logic.dart'; 
import 'control_dispatcher_wrapper_logic.dart'; 
import 'device_id_create_logic.dart';

enum TopologyEvent {
  discoveryStarted,  // "אל תעשה כלום, אנחנו בדיסקברי עכשיו"
  discoveryFinished, // "סיימנו, קח את נתוני המפה"
}
int? _selectedTargetIndex;
class UltraApiInterface extends StatefulWidget {
  const UltraApiInterface({super.key});

  @override
  State<UltraApiInterface> createState() => _UltraApiInterfaceState();
}

class _UltraApiInterfaceState extends State<UltraApiInterface> {
  String status = "Ready";
  String lastReceivedMessage = "------";
  bool isListening = false;

  // === משתנים לניהול הדיסקברי והמכשירים ברשת ===
  List<int> _discoveredDevices = []; 
  int? _selectedTargetDevice; 
  StreamSubscription? _topologySubscription; // שומר על הצינור פתוח

  final TextEditingController _textController = TextEditingController();

  late FskModulationLogic _modulator;
  late AudioTransmitter _transmitter;
  late AudioReceiver _receiver;
  
  // היררכיית השליטה 
  late Dispatcher _dispatcher; 
  late FskControlWrapperLogic _txWrapper;
  late ControlDispatcherWrapper _wrapper; 

  @override
  void initState() {
    super.initState();
    _modulator = FskModulationLogic();
    
    // J. אתחול מנוע השידור
    _txWrapper = FskControlWrapperLogic(_modulator);
    _transmitter = AudioTransmitter(_txWrapper);
    _initTransmitterEngine();

    // I. בניית השרשרת: דיספצ'ר -> שליטת FSK -> מעטפת (ראפר)
    _dispatcher = Dispatcher(_transmitter);
    _wrapper = ControlDispatcherWrapper(_dispatcher, _txWrapper, _transmitter);

    // H. === חיבור הצינור! ה-API מאזין לאירועי הרשת ===
    _topologySubscription = _wrapper.topologyStream.listen((event) async { // קולבק הפך ל-async לטובת שליפת המזהה העצמי
      if (event == TopologyEvent.discoveryStarted) {
        setState(() {
          status = "Discovery Started! Scanning room...";
          _discoveredDevices.clear();
          _selectedTargetDevice = null;
        });
      } else if (event == TopologyEvent.discoveryFinished) {
        // לא צריך לשלוף את ה-ID בשביל הסינון, אלא בשביל להדגיש את המכשיר שלנו בתצוגה
        String myShortIdStr = await DeviceIdCreateLogic().getShortId();
        int myShortIdByte = int.parse(myShortIdStr, radix: 16);

        setState(() {
          status = "Discovery Complete!";
          
          // 🔥 כאן השינוי: אנחנו לא עושים .where, אלא שומרים את כל המפה בדיוק כפי שהיא התקבלה!
          // ככה ה-0x00 יישארו והמבנה המלא יישמר.
          _discoveredDevices = List.from(_dispatcher.latestTopology);
          
          // הגדרת יעד ראשוני (לחיצת יד) למכשיר הראשון שהוא לא אנחנו ולא 0x00
          if (_selectedTargetIndex == null) {
            var firstValid = _discoveredDevices.indexWhere((id) => id != 0x00 && id != myShortIdByte);
            if (firstValid != -1) {
              _selectedTargetIndex = firstValid;
            }
          }
        });
      }
    });

    // F. בניית המקלט המאוחד: מאזין גם לחלונות גולמיים וגם לסימבולי דאטה
    _receiver = AudioReceiver(
      // צינור א': בדיקת חלונות קול גולמיים לתדרי שליטה (שלב 1)
      onWindowAvailable: (List<double> window) {
        return _wrapper.checkRawAudioWindow(window);
      },
      
      // צינור ב': קבלת סימבולים רגילים של דאטה (שלב 2, 3, 4)
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
             if (mounted) {
               setState(() {
                 lastReceivedMessage = decodedText;
               });
             }
          }
        });
      },
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
      // שרשור מזהה היעד לתחילת המחרוזת בצורת פרוטוקול ניתוב אקוסטי
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

            // === תפריט גלילה לבחירת מכשיר יעד שמופיע רק אם מצאנו משהו ברשת ===
            if (_discoveredDevices.isNotEmpty) ...[
              const Text("Raw Network Topology (Verification Proof):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              _discoveredDevices.map((id) => "0x${id.toRadixString(16).toUpperCase().padLeft(2, '0')}").toString(),
              style: const TextStyle(fontFamily: 'monospace', color: Colors.blue, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
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
                        child: Text(id == 0x00 
                            ? "Empty Slot: 0x00" 
                            : "Device ID: 0x${id.toRadixString(16).toUpperCase().padLeft(2, '0')}"),
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
            
            // תצוגת המידע המשוחזר שנקלט מהאוויר
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
            
            // === תיבת הטקסט וכפתור השליחה יופיעו אך ורק אם קיימים מכשירים ברשת ===
            if (_discoveredDevices.isNotEmpty) ...[
              TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: "Type a message to transmit",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit),
                ),
              ),
              const SizedBox(height: 12),
              
              ElevatedButton.icon(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
                label: const Text("Transmit Data Message"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade100),
              ),
              const Divider(height: 30),
            ],
            
            // === ניהול דינמי של כפתורי השליטה בתחתית המסך כדי למנוע כשלים ===
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // כפתור הנדשייק יוצג אך ורק אם קיימת רשת זמינה לשידור אקטיבי
                if (_discoveredDevices.isNotEmpty) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sendHandshake, 
                      icon: const Icon(Icons.handshake),
                      label: const Text("Handshake"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                
                // כפתור האזנה תמיד מופיע, ומתרחב לכל רוחב הכרטיס אם אין מכשירים זמינים
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