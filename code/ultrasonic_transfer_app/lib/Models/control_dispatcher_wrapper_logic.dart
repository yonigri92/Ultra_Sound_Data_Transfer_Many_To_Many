import 'dart:typed_data';
import 'dispatcher.dart'; 
import 'fsk_control_wrapper_logic.dart';
import 'fft_control_wrapper_logic.dart';

class ControlDispatcherWrapper {
  final Dispatcher _originalDispatcher;
  final FskControlWrapperLogic _txWrapper;

  
  bool _amITheDiscoveryInitiator = false;
  DateTime? _backoffUntil;

  int _discoveryAttempts = 0;
  static const int _maxDiscoveryAttempts = 5;
  bool _isValidDiscoveryChain = false;
  ControlDispatcherWrapper(this._originalDispatcher, this._txWrapper);

  
  bool get amITheDiscoveryInitiator => _amITheDiscoveryInitiator;
  
  // getter for original dispacher
  bool get isDeviceTransmittingData => _originalDispatcher.isWorkerRunning; 

  Future<void> startDiscoveryWorkflow() async {
    _discoveryAttempts = 0; 
    await _executeDiscoveryAttempt();
  }
  Future<void> _executeDiscoveryAttempt() async {
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      print("Wrapper: Cannot initiate Discovery yet. Backoff timer is active.");
      return;
    }
  _discoveryAttempts++;

  _amITheDiscoveryInitiator = true;
  _txWrapper.startControlTone(0);
  Future.delayed(const Duration(seconds: 1), () {
      if (_amITheDiscoveryInitiator) {
        print("Wrapper: 1 second passed with clean air. I am the Leader! Proceeding to Stage 2.");
        _originalDispatcher.resetTopology(); 
        _discoveryAttempts = 0; 
        _amITheDiscoveryInitiator = false;
        _proceedToNextStage();
      }
    });
  }





  /// initiate discovery
  Future<void> initiateDiscoverySequence() async {
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      print("Wrapper: Cannot initiate Discovery. 5-second ba ckoff timer is active.");
      return;
    }
    
    print("Wrapper: Initiating Discovery signal.");
    _amITheDiscoveryInitiator = true;
    _txWrapper.startControlTone(0); //transmit discovery
  }

  /// logic from input here
  void handleControlAction(ControlAction action) {
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      return;
    }

    switch (action) {
      case ControlAction.respondWithBusy:
        print("Wrapper: Heard Discovery while busy. Transmitting BUSY horn.");
        _txWrapper.startControlTone(1); // transmit busy
        break;

      case ControlAction.discoveryDetected:
        print("Wrapper: Valid Discovery detected. Requesting topology reset from original dispatcher.");
        _amITheDiscoveryInitiator = false;
        
        // הוא אמור להמשיך את האות ולחכות 4 שניות כמו מי שהתחיל
        _txWrapper.startControlTone(0); // המשך האות
        _isValidDiscoveryChain = true; // סימון שהתחלנו שרשרת תקינה
        
        Future.delayed(const Duration(seconds: 4), () {
          // ואם הכל תקין - לא שמע BUSY ב4 שניות הבאות, למחוק את רשימת המכשירים המוכרים ולעבור לשלב ב
          if (_isValidDiscoveryChain) {
            print("Wrapper: 4 seconds passed without BUSY. Proceeding to Stage 2.");
            _originalDispatcher.resetTopology(); // מחיקת מכשירים מוכרים
            _proceedToNextStage(); // מעבר לשלב ב'
          }
        });
        break;

      case ControlAction.busyDetectedAndAbort:
        print("Wrapper: I started Discovery but room is BUSY! Activating 5-second backoff.");
        _amITheDiscoveryInitiator = false;
        _backoffUntil = DateTime.now().add(const Duration(seconds: 5));
        
        // חכה 5 שניות לפני שמנסים שוב ותעלה COUNTER (ה-counter כבר עלה ב-execute הקודם)
        if (_discoveryAttempts < _maxDiscoveryAttempts) {
          Future.delayed(const Duration(seconds: 5), () {
            _executeDiscoveryAttempt();
          });
        } else {
          print("Wrapper: Max discovery attempts reached. Cannot start DISCOVERY.");
        }
        break;

      case ControlAction.busyDetectedAndPropagate:
        print("Wrapper: Heard BUSY from peer. Propagating BUSY horn.");
        _txWrapper.startControlTone(1);
        _isValidDiscoveryChain = false; // חותך את הרצף של ה-4 שניות ומבטל את המעבר לשלב ב'
        break;

      case ControlAction.none:
        break;
    }
  }


  Future<void> pushSymbol(int symbol, Function(String deviceId) onPacketDetected) =>
      _originalDispatcher.pushSymbol(symbol, onPacketDetected);

  Future<void> addDataPacketToQueue(Uint8List data) =>
      _originalDispatcher.addDataPacketToQueue(data);
  void _proceedToNextStage() {
    print("Wrapper: Transitioning to Stage 2.");
    // כאן יבוא הקוד שלכם שמפעיל את השלב הבא בפרוטוקול 
  }
}
