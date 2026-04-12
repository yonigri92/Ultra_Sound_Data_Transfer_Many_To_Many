import 'package:fftea/fftea.dart';

class FskFftDemodulator {
  final int sampleRate;
  final double freq0;
  final double freq1;
  final int windowSize;
  final int baudRate;

  late final FFT _fft;
  late final int _bin0;
  late final int _bin1;

  FskFftDemodulator({
    this.sampleRate = 44100,
    this.freq0 = 18000.0,
    this.freq1 = 20000.0,
    this.windowSize = 128,
    this.baudRate = 2000,
  }) {
    _fft = FFT(windowSize);
    _bin0 = ((freq0 * windowSize) / sampleRate).round();
    _bin1 = ((freq1 * windowSize) / sampleRate).round();
  }

  int detectBit(List<double> audioWindow) {
    final spectrum = _fft.realFft(audioWindow);
    final magnitudes = spectrum.magnitudes();

    double energy0 = magnitudes[_bin0];
    double energy1 = magnitudes[_bin1];

    double noiseThreshold = 1.0;
    if (energy0 > 0.8 || energy1 > 0.8) {
      print("FFT DEBUG: F0: ${energy0.toStringAsFixed(1)} | F1(4k): ${energy1.toStringAsFixed(1)}",);
    }
    if (energy0 < noiseThreshold && energy1 < noiseThreshold) {
      return -1;
    }

    return (energy1 > energy0) ? 1 : 0;
  }
}
