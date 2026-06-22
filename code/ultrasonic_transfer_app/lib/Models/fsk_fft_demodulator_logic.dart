import 'package:fftea/fftea.dart';

class FskFftDemodulator {
  final int sampleRate;
  final List<double> freq;

  final int windowSize;
  final int baudRate;

  late final FFT _fft;
  late final List<int> _bin = List<int>.filled(16, 0);
  FskFftDemodulator({
    this.sampleRate = 44100,
    this.freq = const [
      17054.3,17226.6,17399.8,17571.1,17743.4,17915.6,18087.9,18260.2,
      18432.4,18604.7,18777.0,18949.2,19121.5,19293.8,19466.0,19638.3],
    
    this.windowSize = 512,
    this.baudRate = 10,   
  // FskFftDemodulator({
  //   this.sampleRate = 44100,
  //   this.freq0 = 18000.0,
  //   this.freq1 = 20000.0,
  //   this.windowSize = 128,
  //   this.baudRate = 2000,
   }) {
  
    _fft = FFT(windowSize);
    for(int i = 0; i < 16; i++){
    _bin [i]= ((freq[i] * windowSize) / sampleRate).round();//Frequency Resolution - takes care of possible noises
   
   }
  } 

int detectBit(List<double> audioWindow) {
  final spectrum = _fft.realFft(audioWindow);
  final magnitudes = spectrum.magnitudes();
  List<double> energy = List<double>.filled(16, 0.0);
  for(int i = 0; i < 16; i++){
    energy[i] = magnitudes[_bin[i]]; 
   }
 
 
  const double minPower = 0.2; 

  
  const double ratio = 1.5;
  double energyAvg = 0;
   for(int i = 0; i < 16; i++){
   energyAvg += energy[i];
    
   }
   energyAvg = energyAvg/16;
  double maxEnergy = 0;
  int maxEnergyindex = -1;
  for(int i = 0; i < 16; i++){
    if (maxEnergy<energy[i]){ maxEnergy = energy[i];maxEnergyindex =i;}
   }
   if(maxEnergy > minPower && maxEnergy > energyAvg * ratio)
      {return maxEnergyindex;}

  
  return -1;
}
}
