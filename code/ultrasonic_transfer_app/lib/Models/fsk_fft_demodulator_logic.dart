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
    this.baudRate = 2000,    // הורדנו דרסטית ל-20 ביטים בשנייה
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

  double energy0 = magnitudes[_bin0]; // 18kHz
  double energy1 = magnitudes[_bin1]; // 19.5kHz

  // 1. סף רעש מינימלי (Absolute Floor)
  // נוריד אותו ל-0.2 כדי שיוכל לקלוט גם בווליום נמוך
  const double minPower = 0.2; 

  // 2. סף יחס (The Gap)
  // תדר אחד חייב להיות חזק פי 1.5 מהשני כדי שנאמין לו.
  // זה ימנע את ה-"קיר של 1" בווליום גבוה.
  const double ratio = 1.5;

  if (energy1 > minPower && energy1 > energy0 * ratio) {
    return 1;
  } 
  
  if (energy0 > minPower && energy0 > energy1 * ratio) {
    return 0;
  }

  // אם שניהם חלשים מדי או דומים מדי בעוצמה - אל תחליט (נחזיר -1)
  return -1;
}
}
