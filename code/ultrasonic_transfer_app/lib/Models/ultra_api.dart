import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'handshake_frame_builder_logic.dart'; // תוודא שזה השם המדויק של הקובץ
import 'fsk_modulation_logic.dart';
import 'audio_transmitter_logic.dart';
import 'audio_receiver_logic.dart'; 

class UltraApiInterface extends StatefulWidget {// statefull live changeing screen 
  const UltraApiInterface({super.key});

  @override
  State<UltraApiInterface> createState() => _UltraApiInterfaceState();
}

class _UltraApiInterfaceState extends State<UltraApiInterface> {
  String status = "Ready";
  String lastReceivedId = "------";
  
  bool isTransmittingLoop = false;
  bool isListening = false;

  late FskModulationLogic _modulator;//object that changes bits into  fsk frequencies before transmisstion
  late AudioTransmitter _transmitter;//object that transmistts
  late AudioReceiver _receiver;//object that listens

  @override
  void initState() {
    super.initState();
    
    _modulator = FskModulationLogic(); 
    _transmitter = AudioTransmitter(_modulator);
    _initTransmitterEngine();

    _receiver = AudioReceiver(
      onPacketReceived: (String senderId) {
        if (mounted) {
          setState(() {
            lastReceivedId = senderId;
            status = "message recived";
            isListening = false;
          });
        }
      
        _receiver.stopListening();
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
    _transmitter.release();
    _receiver.stopListening();
    super.dispose();
  }

  void _toggleTransmitterLoop() async {
    if (isTransmittingLoop) {
      setState(() {
        isTransmittingLoop = false;
        status = "Stopped";
      });
      return;
    }

    setState(() {
      isTransmittingLoop = true;
      status = "Transmitting";
    });

    int frameCounter = 1;
    while (isTransmittingLoop) {
      try {
        Uint8List handshakeFrame = await HandshakeFrameBuilderLogic().buildHandshakeFrame();
        
        print("DEBUG: Sending Handshake Frame...");

        await _transmitter.transmitFrame(handshakeFrame);
        
        frameCounter++;
        await Future.delayed(const Duration(milliseconds: 2000));
      } catch (e) {
        print("Transmitter Error: $e");
        if (mounted) {
          setState(() {
            isTransmittingLoop = false;
            status = "Transmitting Failed";
          });
        }
      }
    }
  }


  void _toggleListening() async {
  
    if (isListening) {
      await _receiver.stopListening();
      setState(() {
        isListening = false;
        status = "stopped listening";
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
      status = "listening";
      lastReceivedId = "---";
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
            Text("status: $status", 
              style: TextStyle(
                color: (isTransmittingLoop || isListening) ? Colors.blue : Colors.black, 
                fontWeight: FontWeight.w500
              )
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("recived info: "),
                Text(lastReceivedId, style: const TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: isListening ? null : _toggleTransmitterLoop, 
                  icon: Icon(isTransmittingLoop ? Icons.stop : Icons.sensors),
                  label: Text(isTransmittingLoop ? "Stop" : "Transmit"),
                  style: ElevatedButton.styleFrom(backgroundColor: isTransmittingLoop ? Colors.red.shade100 : Colors.orange.shade100),
                ),
              
                ElevatedButton.icon(
                  onPressed: isTransmittingLoop ? null : _toggleListening, 
                  icon: Icon(isListening ? Icons.stop : Icons.mic),
                  label: Text(isListening ? "Stop" : "Listen"),
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