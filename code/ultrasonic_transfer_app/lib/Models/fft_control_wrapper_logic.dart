import 'package:fftea/fftea.dart';
import 'fsk_fft_demodulator_logic.dart'; 

enum ControlAction {
  none,                        // irrelivent data
  discoveryDetected,           // heard discovery - transmit discovery freq
  busyDetectedAndAbort,        // heard busy abort discovery sequence and wait befor starting again(its for whoever started discovery)
  busyDetectedAndPropagate,    // heard busy sound the busy horn and get 
  respondWithBusy,
  swallowControlNoise            // i head discovery but im busy so sound the busy horn and continue data transfer
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
  DateTime? _lastDiscoveryTxTime;
  DateTime? _lastBusyTxTime;
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
      if (_lastBusyTxTime != null && DateTime.now().difference(_lastBusyTxTime!).inSeconds < 3) {
          return ControlAction.none;
        }
        _lastBusyTxTime = DateTime.now();
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
        if (_lastDiscoveryTxTime != null && DateTime.now().difference(_lastDiscoveryTxTime!).inSeconds < 2) {
            return ControlAction.none;
        }
        _lastDiscoveryTxTime = DateTime.now();
        // if i hear discovery and i am busy(middle of getting data- stop for a sec i know it will destroy current package but its worth it)
        // transmit busy and continue listening for more data
        if (isDeviceTransmittingData) {
          if (_lastBusyTxTime != null && DateTime.now().difference(_lastBusyTxTime!).inSeconds < 3) {
            return ControlAction.none;
        }
        _lastBusyTxTime = DateTime.now();
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