import 'dart:typed_data';
import 'package:raw_sound/raw_sound_player.dart';
import 'fsk_modulation_logic.dart';
import 'fsk_control_wrapper_logic.dart';

class AudioTransmitter {
  final FskControlWrapperLogic modulator;
  
  final RawSoundPlayer _player = RawSoundPlayer();
  bool _isInitialized = false;

  AudioTransmitter(this.modulator);

  Future<void> initEngine() async {
    await _player.initialize(
        bufferSize: 8192,
        nChannels: 1,
        //sampleRate: modulator.sampleRate,
        sampleRate: 44100,
        pcmType: RawSoundPCMType.PCMI16,
      );
    _isInitialized = true;
  }

// this method gets frame and transmis it
  Future<void> transmitFrame(Uint8List frame) async {
    if (!_isInitialized) return;

    await _player.play();
    modulator.loadFrame(frame);
    await _player.feed(Uint8List(2048));
    
     while (!modulator.isFinished) {
      Int16List intBuffer = modulator.generateNextBuffer(2048);
    //   Int16List intBuffer = modulator.generateNextBuffer(1024);
    //   Uint8List byteBuffer = Uint8List(intBuffer.length * 2);
    //   ByteData byteData = ByteData.view(byteBuffer.buffer);
    //   for (int i = 0; i < intBuffer.length; i++) {
    //     byteData.setInt16(i * 2, intBuffer[i], Endian.little);
    //   }
    Uint8List byteBuffer = intBuffer.buffer.asUint8List(
        intBuffer.offsetInBytes, 
        intBuffer.lengthInBytes
      );
      await _player.feed(byteBuffer);
    }

    await _player.feed(Uint8List(1024));// padding

   // print("DEBUG: Transmission complete",);
  }

  
  Future<void> transmitControlTone() async {
    if (!_isInitialized) return;

    await _player.play();
    await _player.feed(Uint8List(2048)); 
    
    
    while (!modulator.isFinished) {
      Int16List intBuffer = modulator.generateNextBuffer(2048);
      Uint8List byteBuffer = intBuffer.buffer.asUint8List(intBuffer.offsetInBytes, intBuffer.lengthInBytes);
      await _player.feed(byteBuffer);
    }
    
    await _player.feed(Uint8List(1024)); 
  } 

  Future<void> stopStreaming() async {
    await _player.stop();
  }

  Future<void> release() async {
    await _player.release();
  }
}