import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'fsk_fft_demodulator_logic.dart';
import 'handshake_decoder_logic.dart';

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

  Future<void> startListening() async {
    if (await _audioRecorder.hasPermission()) {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 44100,
          numChannels: 1,
        ),
      );
      _micSubscription = stream.listen(_processAudioChunk);
      print("DEBUG: AudioReceiver Started listening");
    } else {
      print("DEBUG: Error, Microphone permission denied.");
    }
  }

  void _processAudioChunk(Uint8List pcmBytes) {
    ByteData byteData = ByteData.sublistView(pcmBytes);

    for (int i = 0; i < pcmBytes.length; i += 2) {
      if (i + 1 < pcmBytes.length) {
        double sample = byteData.getInt16(i, Endian.little) / 32768.0;
        _sampleBuffer.add(sample);
      }
    }

    double hopSize = _demodulator.windowSize / 2;
    int framesPerBit =
    (_demodulator.sampleRate / _demodulator.baudRate / hopSize).round();

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

        if (_consecutiveCount == framesPerBit) {
          _decoder.pushBit(currentBit, onHandshakeReceived);
          print("DEBUG: Bit Sync: $currentBit (Pushed to Decoder)");

          _consecutiveCount = -100;
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
    await _audioRecorder.dispose();
    print("DEBUG: AudioReceiver: Stopped listening");
  }
}
