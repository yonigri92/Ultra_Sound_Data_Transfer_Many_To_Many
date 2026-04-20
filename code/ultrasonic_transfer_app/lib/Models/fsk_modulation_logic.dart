import 'dart:math';
import 'dart:typed_data';

class FskModulationLogic {
  final int sampleRate;
  final int baudRate;
  final double freq0;
  final double freq1;

  // Sine Lookup Table (LUT)
  static const int lutSize = 1024;
  final Float32List _sineLUT = Float32List(lutSize);
  late final int _samplesPerBit;
  late final double _phaseInc0;
  late final double _phaseInc1;

  Uint8List _frameToTransmit = Uint8List(0);
  int _totalBitsInFrame = 0;
  int _currentTotalBitIndex = 0;
  int _samplesProcessedInCurrentBit = 0;
  double _phase = 0.0;
  bool _isFinished = true;

  // Constructor initializes
  FskModulationLogic({
    this.sampleRate = 44100,
    this.baudRate = 20,      // שונה מ-2000 ל-20 (חייב להתאים למקלט!)
    this.freq0 = 18000.0,
    this.freq1 = 19000.0,

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
    _phaseInc0 = (2 * pi * freq0) / sampleRate;
    _phaseInc1 = (2 * pi * freq1) / sampleRate;
  }

  void loadFrame(Uint8List frame) {
    _frameToTransmit = frame;
    _totalBitsInFrame = frame.length * 8; // 7 bytes * 8 = 56 bits
    _currentTotalBitIndex = 0;
    _samplesProcessedInCurrentBit = 0;
    _phase = 0.0;
    _isFinished = false;
  }

  bool get isFinished => _isFinished;

  Int16List generateNextBuffer(int bufferLength) {
    Int16List buffer = Int16List(bufferLength);

    for (int i = 0; i < bufferLength; i++) {
      if (_currentTotalBitIndex < _totalBitsInFrame) {
        int byteIndex = _currentTotalBitIndex >> 3;
        int bitPositionWithinByte = 7 - (_currentTotalBitIndex & 7);
        int bit = (_frameToTransmit[byteIndex] >> bitPositionWithinByte) & 1;
        int lutIndex = ((_phase / (2 * pi)) * lutSize).toInt();

        if (lutIndex >= lutSize) {
          lutIndex = lutSize - 1;
        }

        // multiple by 32767 for maximum amplitude
        buffer[i] = (_sineLUT[lutIndex] * 32767).toInt();

        _phase += (bit == 1) ? _phaseInc1 : _phaseInc0;

        if (_phase >= 2 * pi) {
          _phase -= 2 * pi;
        }

        _samplesProcessedInCurrentBit++;

        if (_samplesProcessedInCurrentBit >= _samplesPerBit) {
          _samplesProcessedInCurrentBit = 0;
          _currentTotalBitIndex++;
        }
      } else {
        buffer[i] = 0;
        _isFinished = true;
      }
    }
    return buffer;
  }
}
