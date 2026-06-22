import 'dart:math';
import 'dart:typed_data';
import 'fsk_modulation_logic.dart'; 

class FskControlWrapperLogic {
  
  final FskModulationLogic _originalFsk;

  
  int? _forcedToneIndex;
  int _controlSamplesLeft = 0;
  double _controlPhase = 0.0;
  bool _isControlFinished = true;

  FskControlWrapperLogic(this._originalFsk);

  

  void loadFrame(Uint8List frame) {
    _forcedToneIndex = null; 
    _isControlFinished = true;
    _originalFsk.loadFrame(frame);
  }

  
  bool get isFinished {
    if (_forcedToneIndex != null) {
      return _isControlFinished;
    }
    return _originalFsk.isFinished;
  }

  

  
  void startControlTone(int toneIndex) {
    _forcedToneIndex = toneIndex;
    _controlPhase = 0.0;
    _isControlFinished = false;

    //_controlSamplesLeft = (_originalFsk.sampleRate * 0.5).round();
  
  _controlSamplesLeft = (_originalFsk.sampleRate * 5.0).round();
  
  }


  Int16List generateNextBuffer(int bufferLength) {
    //this part gives priority to control transmissions and will be used if we need to transmit BUSY sound for the discovery system
    // if there is no CONTROL broadcast waiting do this first
    if (_forcedToneIndex == null) {
      return _originalFsk.generateNextBuffer(bufferLength);
    }

    // if we need to transmit control transmission we continue from here
    Int16List buffer = Int16List(bufferLength);
    
    
    double targetFreq = 0.0;
    if (_forcedToneIndex == 0) {
      targetFreq = 20400.0; 
    } else if (_forcedToneIndex == 1) {
      targetFreq = 20800.0; 
    }

    
    double phaseInc = (2 * pi * targetFreq) / _originalFsk.sampleRate;

    for (int i = 0; i < bufferLength; i++) {
      if (_controlSamplesLeft > 0) {
        buffer[i] = (sin(_controlPhase) * 32767).toInt();
        _controlPhase += phaseInc;
        if (_controlPhase >= 2 * pi) _controlPhase -= 2 * pi;
          _controlSamplesLeft--;
        if (_controlSamplesLeft == 0) {
          _isControlFinished = true; 
        }
      } else {
        buffer[i] = 0;
        _isControlFinished = true;
      }
    }
    if (_isControlFinished) {
          _forcedToneIndex = null;
          }
    return buffer;
  }
}