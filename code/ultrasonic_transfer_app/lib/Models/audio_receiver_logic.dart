import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'fsk_fft_demodulator_logic.dart';
import 'HandshakeDecoder.dart';

class AudioReceiver {
  final FskFftDemodulator _demodulator = FskFftDemodulator();
  final HandshakeDecoder _decoder = HandshakeDecoder();
  final AudioRecorder _audioRecorder = AudioRecorder();

  StreamSubscription<Uint8List>? _micSubscription;
  final List<double> _sampleBuffer = [];

  int _lastBit = -1;
  int _consecutiveCount = 0;

  final Function(String senderId) onHandshakeReceived;

  AudioReceiver({required this.onHandshakeReceived});
  //this is the Listening method, 1. wait for premission from phone to record. 
  Future<void> startListening() async {
    if (await _audioRecorder.hasPermission()) { 
      final stream = await _audioRecorder.startStream(// waiting until OS will finish initializing audio recording
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits, // dont cut sample edges- mp3 for instance will cut 20mkh because its useless for music
          sampleRate: 44100,// how fast we sample
          numChannels: 1,// use mono
        ),
      );
      _micSubscription = stream.listen(_processAudioChunk);// micsub will allow to start or stop listening,listen will send the audio to the audiocunk function
      //print("DEBUG: AudioReceiver Started listening");
    } else {
      //print("DEBUG: Error, Microphone permission denied.");
    }
  }

  void _processAudioChunk(Uint8List pcmBytes) {
    ByteData byteData = ByteData.sublistView(pcmBytes);// this says to the os dont copy the data just take it from where recived it and work on it call it byte data

    for (int i = 0; i < pcmBytes.length; i += 2) {
      if (i + 1 < pcmBytes.length) {
        double sample = byteData.getInt16(i, Endian.little) / 32768.0;// take to consecitive bytes concacnate them in little endian and make it easyer to work(the divison)
        _sampleBuffer.add(sample);
      }
    }

    double hopSize = _demodulator.windowSize / 2;
    int framesPerBit = (_demodulator.sampleRate / _demodulator.baudRate / hopSize).round().clamp(2, 100);

    while (_sampleBuffer.length >= _demodulator.windowSize) {
      final window = _sampleBuffer.sublist(0, _demodulator.windowSize);
      int currentBit = _demodulator.detectBit(window);

      if (currentBit != -1) {
        if (currentBit == _lastBit) {
           _consecutiveCount++;
        } else {
          _consecutiveCount = 1;
          _lastBit = currentBit;
        }

        int targetCount = (framesPerBit * 0.8).round().clamp(2, framesPerBit);

     if (_consecutiveCount >= targetCount) {
        _decoder.pushBit(currentBit, onHandshakeReceived);
        
    

        int remainingFrames = framesPerBit - _consecutiveCount;
        int samplesToSkip = (remainingFrames * (_demodulator.windowSize ~/ 2));
        _consecutiveCount = 0;
        _lastBit = -1; 
        if (_sampleBuffer.isNotEmpty) {
            int finalSkip = samplesToSkip.clamp(0, _sampleBuffer.length);
          _sampleBuffer.removeRange(0, finalSkip);
        }
        
         break; 
      }
      } else {
        _lastBit = -1;
        _consecutiveCount = 0;
      }

      _sampleBuffer.removeRange(0, _demodulator.windowSize ~/ 2);
    }

    if (_sampleBuffer.length > 10000) {
      _sampleBuffer.clear();
    }
  }

  Future<void> stopListening() async {
    await _micSubscription?.cancel();
    await _audioRecorder.stop();
    
    //print("DEBUG: AudioReceiver: Stopped listening");
  }
}
