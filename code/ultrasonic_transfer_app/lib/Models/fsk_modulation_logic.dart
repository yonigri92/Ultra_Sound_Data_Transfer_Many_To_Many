import 'dart:math';
import 'dart:typed_data';

class FskModulationLogic {
  final int sampleRate;
  final int baudRate;
  final List<double> freq;
  

  // Sine Lookup Table (LUT)
  static const int lutSize = 1024;
  final Float32List _sineLUT = Float32List(lutSize);
  late final int _samplesPerBit;
  late final List<double> _phaseInc = List<double>.filled(16, 0.0);
 
  Uint8List _frameToTransmit = Uint8List(0);
  int _totalBitsInFrame = 0;
  int _currentSymbolIndex = 0;
  int _samplesProcessedInCurrentBit = 0;
  double _phase = 0.0;
  bool _isFinished = true;

  // Constructor initializes
  FskModulationLogic({
    this.sampleRate = 44100,
    this.baudRate = 10,      
     this.freq = const [
      17054.3,17226.6,17399.8,17571.1,17743.4,17915.6,18087.9,18260.2,
      18432.4,18604.7,18777.0,18949.2,19121.5,19293.8,19466.0,19638.3],
    // this.sampleRate = 44100,
    // this.baudRate = 2000,
    // this.freq0 = 18000.0,
    // this.freq1 = 20000.0,
  }) {
    // Fill the Sine LUT in memory
    for (int i = 0; i < lutSize; i++) {
      _sineLUT[i] = sin((i / lutSize) * 2 * pi);
    }

    _samplesPerBit = (sampleRate / baudRate).round();
    for(int i = 0 ; i < 16 ; i ++){
       _phaseInc[i] = (2 * pi * freq[i]) / sampleRate;
    }
    }

  void loadFrame(Uint8List frame) {
    _frameToTransmit = frame;
    _totalBitsInFrame = frame.length * 8; 
    _currentSymbolIndex = 0;
    _samplesProcessedInCurrentBit = 0;
    _phase = 0.0;
    _isFinished = false;
  }

  bool get isFinished => _isFinished;

Int16List generateNextBuffer(int bufferLength) {
  Int16List buffer = Int16List(bufferLength);
  int totalSymbolsInFrame = (_totalBitsInFrame / 4).ceil();
  int guardSamples = (_samplesPerBit * 0.15).round(); 
  int activeSamples = _samplesPerBit - guardSamples;

  for (int i = 0; i < bufferLength; i++) {
    if (_currentSymbolIndex < totalSymbolsInFrame) {
      int byteIndex = _currentSymbolIndex >> 1;
      int shift = (_currentSymbolIndex % 2 == 0) ? 4 : 0;
      int symbol = (_frameToTransmit[byteIndex] >> shift) & 15;
    
   
      if (_samplesProcessedInCurrentBit < activeSamples) {
        
        int lutIndex = ((_phase / (2 * pi)) * lutSize).toInt();
        if (lutIndex >= lutSize) lutIndex = lutSize - 1;
        
        buffer[i] = (_sineLUT[lutIndex] * 32767).toInt();
                  
        _phase +=_phaseInc[symbol];
    
        if (_phase >= 2 * pi) _phase -= 2 * pi;
      } else {
       
        buffer[i] = 0;
        
      }

      _samplesProcessedInCurrentBit++;

      if (_samplesProcessedInCurrentBit >= _samplesPerBit) {
        _samplesProcessedInCurrentBit = 0;
        _currentSymbolIndex++;
      
      }
    } else {
      buffer[i] = 0;
      _isFinished = true;
    }
  }
  return buffer;
}
}
