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

class UltraApiInterface extends StatefulWidget {
  const UltraApiInterface({super.key});

  @override
  State<UltraApiInterface> createState() => _UltraApiInterfaceState();
}

class _UltraApiInterfaceState extends State<UltraApiInterface> {
  String status = "System Idle";
  String lastReceivedMessage = "Waiting for data...";
  bool isListening = false;

  // === משתנים לניהול הטופולוגיה ===
  List<int> _discoveredDevices = []; 
  int? _selectedTargetIndex; 
  int? _myShortIdByte; 

  final TextEditingController _textController = TextEditingController();

  late FskModulationLogic _modulator;
  late AudioTransmitter _transmitter;
  late AudioReceiver _receiver;
  
  late Dispatcher _dispatcher; 
  late FskControlWrapperLogic _txWrapper;
  late ControlDispatcherWrapper _wrapper; 
  StreamSubscription? _topologySubscription;

  @override
  void initState() {
    super.initState();
    _modulator = FskModulationLogic();
    
    _txWrapper = FskControlWrapperLogic(_modulator);
    _transmitter = AudioTransmitter(_txWrapper);
    _initTransmitterEngine();

    _dispatcher = Dispatcher(_transmitter);
    _wrapper = ControlDispatcherWrapper(_dispatcher, _txWrapper, _transmitter);
    _dispatcher.onSessionReleased = () {
      if (mounted) {
        setState(() {
          status = "Channel Idle. Session Unlocked.";
        });
      }
    };
    _loadMyId(); 

    _topologySubscription = _wrapper.topologyStream.listen((event) async { 
      if (event == TopologyEvent.discoveryStarted) {
        setState(() {
          status = "Radar Active: Scanning Topology...";
          _discoveredDevices.clear();
          _selectedTargetIndex = null;
        });
      } else if (event == TopologyEvent.discoveryFinished) {
        setState(() {
          status = "Network Converged!";
          _discoveredDevices = List.from(_dispatcher.latestTopology);
          
          if (_selectedTargetIndex == null) {
            var firstValid = _discoveredDevices.indexWhere((id) => id != 0x00 && id != _myShortIdByte);
            if (firstValid != -1) {
              _selectedTargetIndex = firstValid;
            }
          }
        });
      }
    });

    _receiver = AudioReceiver(
      onWindowAvailable: (List<double> window) => _wrapper.checkRawAudioWindow(window),
      onSymbolReceived: (int symbol) async {
        await _wrapper.pushSymbol(symbol, (String decodedText) async {
          if (mounted && decodedText.length >= 3 && decodedText[2] == ':') {
            String targetHex = decodedText.substring(0, 2);
            String actualMessage = decodedText.substring(3);
            
            String myShortIdStr = _myShortIdByte?.toRadixString(16).toUpperCase().padLeft(2, '0') ?? "XX";

            if (targetHex == myShortIdStr || targetHex == "FF") {
              setState(() {
                lastReceivedMessage = actualMessage;
                status = "Incoming Message Received!";
                
              });
            } else {
              print("API: Message dropped. Target: $targetHex, My ID: $myShortIdStr");
            }
          } else if (mounted) {
             setState(() => lastReceivedMessage = decodedText);
          }
        });
      },
    );
  }

  Future<void> _loadMyId() async {
    String myShortIdStr = await DeviceIdCreateLogic().getShortId();
    setState(() {
      _myShortIdByte = int.parse(myShortIdStr, radix: 16);
    });
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
    _topologySubscription?.cancel(); 
    _textController.dispose();
    _transmitter.release();
    _receiver.stopListening();
    super.dispose();
  }

  void _startRoomDiscovery() async {
    setState(() => status = "Initiating Room Discovery...");
    try {
      await _wrapper.startDiscoveryWorkflow();
    } catch (e) {
      setState(() => status = "Discovery Error: $e");
    }
  }

  // 🔥 פונקציית העזר לשליחת הנדשייק כחלק מה-Pipeline האוטומטי
  Future<void> _executeHandshakeWorkflow(int targetId) async {
    _dispatcher.lockedPartnerId = targetId; 
    _log("API: Auto-Locking session with 0x${targetId.toRadixString(16).toUpperCase()}");
    
    setState(() => status = "Auto Handshake initiated...");
    await _dispatcher.addHandShakePacketToQueue();
    await _dispatcher.waitForHandshakeACK();
    // ⏳ מחכים 800 מילישניות שההנדשייק ייפלט לאוויר וייקלט בצד השני לפני שנציף את התור בדאטה
    await Future.delayed(const Duration(milliseconds: 800));
  }

  // 🔥 כפתור השידור המאוחד והחכם שלך!
  void _sendMessage() async {
    if (_textController.text.trim().isEmpty) return;
    if (_selectedTargetIndex == null) {
      setState(() => status = "Please select a target device!");
      return;
    }

    int targetId = _discoveredDevices[_selectedTargetIndex!];
    String targetHex = targetId.toRadixString(16).toUpperCase().padLeft(2, '0');
    String textToSend = _textController.text;

    try {
      // 🔒 שלב א': אם המערכת עדיין לא ביצעה הנדשייק רשמי, היא תעשה זאת כעת אוטומטית!
      if (_dispatcher.lockedPartnerId == null) {
        _log("API: No active lock found. Executing automatic Handshake pipeline.");
        await _executeHandshakeWorkflow(targetId);
      }

      // שלב ב': שליחת הודעת הדאטה המנותבת לערוץ הנעול
      setState(() => status = "Transmitting Payload to 0x$targetHex...");
      String routedMessage = "$targetHex:$textToSend";
      Uint8List dataBytes = Uint8List.fromList(routedMessage.codeUnits);
      
      await _wrapper.addDataPacketToQueue(dataBytes); 
      _textController.clear(); 
      setState(() => status = "Data packet pushed to queue successfully.");
    } catch (e) {
      setState(() => status = "Transmission Error: $e");
    }

    // ❌ שים לב: מחקנו מפה את השורה ההרסנית: _dispatcher.lockedPartnerId = null;
    // המנעול ישתחרר בצורה מאובטחת רק על ידי ה-Safety Cooldown טיימר שבנינו בדיספצ'ר!
  }

  // פונקציה אופציונלית לשחרור ידני של המנעול במידת הצורך
  void _forceReleaseSession() {
    setState(() {
      _dispatcher.lockedPartnerId = null;
      status = "Session lock forcefully released.";
    });
  }

  void _toggleListening() async {
    if (isListening) {
      await _receiver.stopListening();
      setState(() {
        isListening = false;
        status = "Mic Off";
      });
      return;
    }

    var permStatus = await Permission.microphone.request();
    if (!permStatus.isGranted) {
      setState(() => status = "Permission Denied");
      openAppSettings();
      return;
    }

    setState(() {
      isListening = true;
      status = "Listening to Acoustic Channel...";
    });

    try {
      await _receiver.startListening();
    } catch (e) {
      if (mounted) setState(() => status = "Receiver Error");
    }
  }

  Widget _buildNetworkNode(int index, int id) {
    bool isEmpty = id == 0x00;
    bool isMe = id == _myShortIdByte;
    
    Color nodeColor = isMe ? Colors.blue.shade700 : (isEmpty ? Colors.grey.shade300 : Colors.purple.shade600);
    Color textColor = isEmpty ? Colors.grey.shade600 : Colors.white;
    String textLabel = isMe ? "ME" : (isEmpty ? "Empty" : "0x${id.toRadixString(16).toUpperCase().padLeft(2, '0')}");

    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: nodeColor,
            shape: BoxShape.circle,
            border: isEmpty ? Border.all(color: Colors.grey.shade400, width: 2) : null,
            boxShadow: isEmpty ? [] : [
              BoxShadow(color: nodeColor.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)
            ],
          ),
          alignment: Alignment.center,
          child: Text(textLabel, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        const SizedBox(height: 6),
        Text("Slot $index", style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🔒 בדיקה אם יש כרגע סשן נעול ומאושר בפרוטוקול
    bool isSessionLocked = _dispatcher.lockedPartnerId != null;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_tethering, size: 32, color: Colors.deepPurple),
                const SizedBox(width: 10),
                const Text("UltraSync Interface", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87)),
              ],
            ),
            if (_myShortIdByte != null) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  "MY DEVICE ID: 0x${_myShortIdByte!.toRadixString(16).toUpperCase().padLeft(2, '0')}",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.deepPurple.shade700, letterSpacing: 1.2),
                ),
              ),
            ],
            const SizedBox(height: 15),

            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isListening ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isListening ? Colors.green.shade200 : Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isListening ? Icons.hearing : Icons.info_outline, size: 16, color: isListening ? Colors.green.shade700 : Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(status, style: TextStyle(color: isListening ? Colors.green.shade700 : Colors.blue.shade700, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),
            TextButton.icon(
              onPressed: isSessionLocked ? null : () {
                setState(() {
                  status = "Network Converged! (SIMULATION)";
                  _discoveredDevices = [_myShortIdByte ?? 0xAA, 0xDB, 0x19, 0x00, 0x00];
                  _selectedTargetIndex = 1; 
                });
              },
              icon: const Icon(Icons.bug_report, color: Colors.orange),
              label: const Text("Debug: Simulate Found Device", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: isSessionLocked ? null : _startRoomDiscovery, 
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 5,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radar, size: 24),
                  SizedBox(width: 10),
                  Text("Initiate Topology Discovery", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 25),

            if (_discoveredDevices.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10, spreadRadius: 1)],
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.hub, color: Colors.deepPurple, size: 20),
                        SizedBox(width: 8),
                        Text("Live Network Topology", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const Divider(height: 20),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(_discoveredDevices.length, (index) {
                        return _buildNetworkNode(index, _discoveredDevices[index]);
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text("Target Configuration:", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                    value: _selectedTargetIndex, 
                    hint: const Text("Select Target Device"),
                    // 🔥 נעילת ה-Dropdown: אם קיים מנעול סשן אקטיבי, onChanged מקבל null ומקפיא את הבחירה!
                    onChanged: isSessionLocked ? null : (int? newIndex) => setState(() => _selectedTargetIndex = newIndex),
                    items: [
                      for (int index = 0; index < _discoveredDevices.length; index++) ...[
                        if (_discoveredDevices[index] != _myShortIdByte) 
                          DropdownMenuItem<int>(
                            value: index, 
                            enabled: _discoveredDevices[index] != 0x00, 
                            child: Text(_discoveredDevices[index] == 0x00 
                                ? "Slot $index: Empty" 
                                : "Slot $index: Device 0x${_discoveredDevices[index].toRadixString(16).toUpperCase().padLeft(2, '0')}${isSessionLocked && index == _selectedTargetIndex ? ' 🔒 (LOCKED)' : ''}"),
                          )
                      ]
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 25),
            ],

            if (_discoveredDevices.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10, spreadRadius: 1)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.message, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text("Data Transfer", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        labelText: "Enter payload...",
                        filled: true,
                        fillColor: Colors.blue.shade50.withOpacity(0.5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.edit_note),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _sendMessage,
                        icon: const Icon(Icons.send),
                        label: const Text("Transmit Payload"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
            ],

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.grey.shade800, Colors.black87], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  const Text("LATEST INCOMING DATA", style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(
                    lastReceivedMessage, 
                    style: const TextStyle(fontSize: 18, color: Colors.greenAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            Row(
              children: [
                if (isSessionLocked) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _forceReleaseSession, 
                      icon: const Icon(Icons.lock_open),
                      label: const Text("Unlock"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade700, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleListening, 
                    icon: Icon(isListening ? Icons.stop_circle : Icons.mic),
                    label: Text(isListening ? "Stop Mic" : "Start Mic"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isListening ? Colors.red.shade500 : Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _log(String message) {
    print("${DateTime.now().toIso8601String().substring(11, 23)} | $message");
  }
}