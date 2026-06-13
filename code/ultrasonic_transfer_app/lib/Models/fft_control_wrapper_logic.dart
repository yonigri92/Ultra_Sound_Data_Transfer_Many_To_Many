import 'package:fftea/fftea.dart';
import 'fsk_fft_demodulator_logic.dart'; // תוודא שהנתיב לקוד שלך נכון

enum ControlAction {
  none,                        // שקט או דאטה רגיל - אין שינוי
  discoveryDetected,           // זוהה אות DISCOVERY רצוף (איפוס רשת)
  busyDetectedAndAbort,        // אני יזמתי דיסקוברי אבל שמעתי BUSY - עוצרים הכל ולוקחים השהייה (Backoff)
  busyDetectedAndPropagate,    // שמעתי BUSY מאחרים - משדר BUSY בחזרה ולא מוחק את הרשת הקרובה
  respondWithBusy              // שמעתי DISCOVERY בזמן שאני באמצע שידור - צריך לענות ב-BUSY
}

class FftControlWrapperLogic {
  final FskFftDemodulator _originalDemodulator;
  late final FFT _controlFft;

  
  late final int _discoveryBin;
  late final int _busyBin;
  final double _busyFreq = 20400.0;
  final double _discoveryFreq = 20000.0;
  
  int _consecutiveDiscoveryCount = 0;
  int _consecutiveBusyCount = 0;
  DateTime? _lastTransmissionTime;
  FftControlWrapperLogic(this._originalDemodulator) {
    
    _controlFft = FFT(_originalDemodulator.windowSize);

    
    _discoveryBin = ((_discoveryFreq * _originalDemodulator.windowSize) / _originalDemodulator.sampleRate).round();
    _busyBin = ((_busyFreq * _originalDemodulator.windowSize) / _originalDemodulator.sampleRate).round();
  }

  
  ControlAction processAudioWindow({
    required List<double> audioWindow,
    required bool isDeviceTransmittingData,
    required bool amITheDiscoveryInitiator,
  }) {
  
    final spectrum = _controlFft.realFft(audioWindow);
    final magnitudes = spectrum.magnitudes();

    double discoveryEnergy = magnitudes[_discoveryBin];
    double busyEnergy = magnitudes[_busyBin];

    
    const double minPower = 0.2;
    const double ratio = 1.5;

    // Busy freq
    if (busyEnergy > minPower && busyEnergy > discoveryEnergy * ratio) {
      _consecutiveDiscoveryCount = 0; // reset discovery freq counter- used to make sure we really heard discovery and not noise
      _consecutiveBusyCount++;

      if (_consecutiveBusyCount >= 3) {
        _consecutiveBusyCount = 0; // reset  busy counter- used to make sure we really heard busy and not noise

        //  i started discovery heard busy- stop all
        if (amITheDiscoveryInitiator) {

          return ControlAction.busyDetectedAndAbort;
        }
      if (_lastTransmissionTime != null && DateTime.now().difference(_lastTransmissionTime!).inSeconds < 2) {
          return ControlAction.none;
        }
        _lastTransmissionTime = DateTime.now();
        //  i didnt start  discovery & heard busy- propagate and sound busy as well
        return ControlAction.busyDetectedAndPropagate;
      }
      return ControlAction.none;
    }

    // heard discovery 
    if (discoveryEnergy > minPower && discoveryEnergy > busyEnergy * ratio) {
      _consecutiveBusyCount = 0; // reset  busy counter- used to make sure we really heard busy and not noise
      _consecutiveDiscoveryCount++;

      if (_consecutiveDiscoveryCount >= 3) {
        _consecutiveDiscoveryCount = 0; // reset after true identefication
        if (_lastTransmissionTime != null && DateTime.now().difference(_lastTransmissionTime!).inSeconds < 2) {
            return ControlAction.none;
          }
        _lastTransmissionTime = DateTime.now();
        // if i hear discovery and i am busy(middle of getting data- stop for a sec i know it will destroy current package but its worth it)
        // transmit busy and continue listening for more data
        if (isDeviceTransmittingData) {
          return ControlAction.respondWithBusy;
        }
        
        // if none of the above - heard discovery and free - transmit discovery
        return ControlAction.discoveryDetected;
      }
      return ControlAction.none;
    }

    //heard nothing or noise reset counters
    _consecutiveDiscoveryCount = 0;
    _consecutiveBusyCount = 0;
    
    return ControlAction.none;
  }
}