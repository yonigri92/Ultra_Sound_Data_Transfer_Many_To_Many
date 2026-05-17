import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'fsk_modulation_logic.dart';
import 'audio_transmitter_logic.dart';
import 'audio_receiver_logic.dart'; 
import 'dispatcher.dart'; // ייבוא של הדיספצ'ר שתיקנו

class UltraApiInterface extends StatefulWidget {
  const UltraApiInterface({super.key});

  @override
  State<UltraApiInterface> createState() => _UltraApiInterfaceState();
}

class _UltraApiInterfaceState extends State<UltraApiInterface> {
  String status = "Ready";
  String lastReceivedMessage = "------";
  bool isListening = false;

  // בקר לתיבת הטקסט החדשה שנוספה לשליחת הודעות
  final TextEditingController _textController = TextEditingController();

  late FskModulationLogic _modulator;
  late AudioTransmitter _transmitter;
  late AudioReceiver _receiver;
  late Dispatcher _dispatcher; // המוח המרכזי החדש של ה-UI

  @override
  void initState() {
    super.initState();
    
    // 1. אתחול מנוע השידור
    _modulator = FskModulationLogic(); 
    _transmitter = AudioTransmitter(_modulator);
    _initTransmitterEngine();

    // 2. אתחול ה-Dispatcher וקישורו לטראנסמיטר
    _dispatcher = Dispatcher(_transmitter);

    // 3. אתחול המקלט - המיקרופון זורק סימבולים גולמיים ישירות לתוך ה-pushSymbol של הדיספצ'ר!
    _receiver = AudioReceiver(
      onSymbolReceived: (int symbol) async {
        // המיקרופון קלט סימבול אקוסטי באוויר? דוחפים אותו ישר לדיספצ'ר
        await _dispatcher.pushSymbol(symbol, (String decodedText) {
          // הקולבק יופעל רק כשהדיספצ'ר יסיים לאסוף את כל הפאקטות וישחזר משפט שלם!
          if (mounted) {
            setState(() {
              lastReceivedMessage = decodedText;
              status = "Message Received Successfully!";
            });
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
    _textController.dispose();
    _transmitter.release();
    _receiver.stopListening();
    super.dispose();
  }

  // פונקציה לביצוע לחיצת יד (Handshake) דרך ה-Dispatcher
  void _sendHandshake() async {
    setState(() => status = "Enqueuing Handshake...");
    try {
      // הדיספצ'ר יבנה את הפריים, ידחוף לתור, ישלח, ויבדוק אם התקבל ACK או שצריך רטריי!
      await _dispatcher.addHandShakePacketToQueue();
      setState(() => status = "Handshake sent to queue");
    } catch (e) {
      setState(() => status = "Error sending Handshake: $e");
    }
  }

  // פונקציה לשליחת הודעת טקסט חופשית מה-TextField
  void _sendMessage() async {
    if (_textController.text.trim().isEmpty) return;

    String textToSend = _textController.text;
    setState(() => status = "Sending Message: '$textToSend'...");
    
    try {
      // המרת הטקסט למערך בייטים גולמי (Uint8List)
      Uint8List dataBytes = Uint8List.fromList(textToSend.codeUnits);
      
      // הדיספצ'ר אוטומטית יחתוך את זה לבלוקים של 5 בתים, יחשב CRC8 לכל פאקט,
      // וינהל את כל ה-ARQ (בדיקת ה-ACKים מהמכשיר השני) בצורה עצמאית לחלוטין ברקע!
      await _dispatcher.addDataPacketToQueue(dataBytes);
      
      _textController.clear(); // ניקוי התיבה לאחר השליחה
      setState(() => status = "Message sent to queue");
    } catch (e) {
      setState(() => status = "Error sending message: $e");
    }
  }

  // הפעלת/הפסקת האזנה למיקרופון
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
          children: [
            const Text("Ultra API Monitor", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            
            // תצוגת סטטוס המערכת
            Text("Status: $status", 
              style: TextStyle(
                color: isListening ? Colors.green : Colors.blue, 
                fontWeight: FontWeight.w500
              )
            ),
            const SizedBox(height: 10),
            
            // תצוגת המידע המשוחזר שנקלט
            Column(
              children: [
                const Text("Last Received Message:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    lastReceivedMessage, 
                    style: const TextStyle(fontSize: 15, color: Colors.purple, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // תיבת טקסט חדשה להקלדת הודעות דאטה לפרוטוקול
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
                label: const Text("Transmit Data Message"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade100),
              ),
            ),
            const Divider(height: 30),
            
            // כפתורי הנדשייק והאזנה
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _sendHandshake, 
                  icon: const Icon(Icons.handshake),
                  label: const Text("Handshake"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                ),
              
                ElevatedButton.icon(
                  onPressed: _toggleListening, 
                  icon: Icon(isListening ? Icons.stop : Icons.mic),
                  label: Text(isListening ? "Stop Listen" : "Start Listen"),
                  style: ElevatedButton.styleFrom(backgroundColor: isListening ? Colors.red.shade100 : Colors.green.shade100),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}