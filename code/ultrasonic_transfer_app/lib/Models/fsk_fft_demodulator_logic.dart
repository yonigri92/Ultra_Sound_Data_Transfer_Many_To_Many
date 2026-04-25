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
    this.freq1 = 19000.0, // עדיף להוריד ל-19k, חלק מהמכשירים חירשים ב-20k
    this.windowSize = 512, // הגדלנו כדי לקבל דיוק בתדרים
    this.baudRate = 20,    // הורדנו דרסטית ל-20 ביטים בשנייה
  // FskFftDemodulator({
  //   this.sampleRate = 44100,
  //   this.freq0 = 18000.0,
  //   this.freq1 = 20000.0,
  //   this.windowSize = 128,
  //   this.baudRate = 2000,
   }) {
  
    _fft = FFT(windowSize);
    _bin0 = ((freq0 * windowSize) / sampleRate).round();//Frequency Resolution - takes care of possible noises
    _bin1 = ((freq1 * windowSize) / sampleRate).round();
  }

  int detectBit(List<double> audioWindow) {
    final spectrum = _fft.realFft(audioWindow);
    final magnitudes = spectrum.magnitudes();

    double energy0 = magnitudes[_bin0];
    double energy1 = magnitudes[_bin1];

    double noiseThreshold = 0.3;

    if (energy0 < noiseThreshold && energy1 < noiseThreshold) {
      return -1;
    }

    return (energy1 > energy0) ? 1 : 0;
  }
}
