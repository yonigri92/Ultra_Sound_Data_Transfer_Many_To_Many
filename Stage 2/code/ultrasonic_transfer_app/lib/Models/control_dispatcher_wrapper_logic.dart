import 'dart:typed_data';
import 'dispatcher.dart'; 
import 'fsk_control_wrapper_logic.dart';
import 'fft_control_wrapper_logic.dart';
import 'dart:async';
import 'package:ultrasonic_transfer_app/Models/device_id_create_logic.dart';
import 'audio_transmitter_logic.dart'; 
import 'fsk_fft_demodulator_logic.dart';
class ControlDispatcherWrapper {
  final Dispatcher _originalDispatcher;
  final FskControlWrapperLogic _txWrapper;
  final AudioTransmitter _transmitter;
  late final FftControlWrapperLogic _rxControlLogic;
  final StreamController<TopologyEvent> _eventController = StreamController<TopologyEvent>.broadcast();
  bool _isCsmaActive = false;
  Stream<TopologyEvent> get topologyStream => _eventController.stream;
  bool _amITheDiscoveryInitiator = false;
  bool _isTransmittingBusy = false;
  DateTime? _backoffUntil;
  bool _isDiscoveryRunning = false;
  int _discoveryAttempts = 0;
  bool _isDiscoveryActive = false;
  static const int _maxDiscoveryAttempts = 5;
  bool _isValidDiscoveryChain = false;
  Timer? _safetyTimeoutTimer;
  DateTime? _lastBusyTxTime;
  int _busySpamCount = 0;
  int? _lastKnownLockedId;



  ControlDispatcherWrapper(this._originalDispatcher, this._txWrapper, this._transmitter) { 
    _rxControlLogic = FftControlWrapperLogic(FskFftDemodulator());
    _originalDispatcher.changeToNextStage = changeToNextStage;
    _originalDispatcher.csmaWait = csmaWait; 
    _originalDispatcher.csmaDataWait = csmaDataWait;
    _originalDispatcher.onDiscoveryFinished = () async {
      if (!_isDiscoveryRunning) {
        _log("Wrapper: Discovery already finished for this cycle. Ignoring duplicate Stage 4 trigger.");
        return;
      }
      _log("Wrapper: Stage 4 Finished and network converged! Releasing the discovery lock.");

      _isDiscoveryRunning = false; 
      _isDiscoveryActive = false;
      _amITheDiscoveryInitiator = false;
      _isValidDiscoveryChain = false;
      await changeToNextStage();
      _eventController.add(TopologyEvent.discoveryFinished);
    };
  }
  
  bool get amITheDiscoveryInitiator => _amITheDiscoveryInitiator;
  
  // getter for original dispacher
  bool get isDeviceTransmittingData => _originalDispatcher.isWorkerRunning; 
  ControlAction checkRawAudioWindow(List<double> window) {
    if (_originalDispatcher.isWorkerRunning) {
      return ControlAction.none;
    }  
    if (_originalDispatcher.lockedPartnerId != null) {
      return ControlAction.none;
    }
    int? currentLockedId = _originalDispatcher.lockedPartnerId;
    if (currentLockedId != _lastKnownLockedId) {
      _lastKnownLockedId = currentLockedId;
      if (currentLockedId != null) {
        _busySpamCount = 0; 
        _log("Wrapper: New locked session detected with 0x${currentLockedId.toRadixString(16).toUpperCase()}. Resetting BUSY counter.");
      }
    }
    bool isLocked = _originalDispatcher.lockedPartnerId != null;
    if (!_originalDispatcher.isStage1Allowed && !isLocked) {
      return ControlAction.none; // ignore discovery freq after stage 1 if not locked
    }

    ControlAction action = _rxControlLogic.processAudioWindow(
      audioWindow: window,
      isDeviceTransmittingData: _originalDispatcher.isWorkerRunning,
      amITheDiscoveryInitiator: _amITheDiscoveryInitiator,
      isSessionLocked: _originalDispatcher.lockedPartnerId != null,
    );

    
    if (action != ControlAction.none) {
      handleControlAction(action);
    }

    return action; 
  }
  Future<void> startDiscoveryWorkflow() async {
    if (_isDiscoveryRunning) {
      _log("Wrapper: Discovery workflow is already active. Ignoring UI request.");
      return;
    }
    _isDiscoveryRunning = true;
    _discoveryAttempts = 0; 
    await _executeDiscoveryAttempt();
  }
  Future<void> _executeDiscoveryAttempt() async {
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      _log("Wrapper: Cannot initiate Discovery yet. Backoff timer is active.");
      _isDiscoveryRunning = false;
      return;
    }
  _discoveryAttempts++;

  _amITheDiscoveryInitiator = true;
  _txWrapper.startControlTone(0);


  while (!_txWrapper.isFinished) {
      await _transmitter.transmitControlTone();
      
      await Future.delayed(const Duration(milliseconds: 40));
    }


  _isValidDiscoveryChain = true;

  Future.delayed(const Duration(seconds: 1), () {
      if (_amITheDiscoveryInitiator && _isDiscoveryRunning){
        _log("Wrapper: 1 second passed with clean air. I am the Leader! Proceeding to Stage 2.");
        _originalDispatcher.resetTopology(); 
        _discoveryAttempts = 0; 
        _amITheDiscoveryInitiator = false;
        _proceedToNextStage(asRoot: true);
      }
    });
  }





  /// initiate discovery
  Future<void> initiateDiscoverySequence() async {
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      _log("Wrapper: Cannot initiate Discovery. 5-second ba ckoff timer is active.");
      return;
    }
    
    _log("Wrapper: Initiating Discovery signal.");
    _amITheDiscoveryInitiator = true;
    _txWrapper.startControlTone(0); //transmit discovery
    while (!_txWrapper.isFinished) {
      await _transmitter.transmitControlTone();
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  /// logic from input here
  
  Future<void> handleControlAction(ControlAction action) async {
    if (_originalDispatcher.lockedPartnerId != null) {
       _log("Wrapper: Session locked on 0x${_originalDispatcher.lockedPartnerId!.toRadixString(16)}. Muting Discovery/Busy logic.");
       return;
    }
    bool isPastStage1 = !_originalDispatcher.isStage1Allowed;

    if (_isDiscoveryActive && action == ControlAction.discoveryDetected) {
    _log("Wrapper: Discovery already active. Ignoring duplicate trigger.");
    return;
  }
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      return;
    }

    switch (action) {
      
      case ControlAction.swallowControlNoise:
        break;
      case ControlAction.respondWithBusy:
        if (isPastStage1) return;
        if (_isTransmittingBusy) return;
        if (_lastBusyTxTime != null && DateTime.now().difference(_lastBusyTxTime!).inMilliseconds < 1500) {
          return;
        }
        _lastBusyTxTime = DateTime.now();
        _isTransmittingBusy = true;
        _log("Wrapper: Heard Discovery while busy. Transmitting BUSY horn.");
        _txWrapper.startControlTone(1); // transmit busy
    //     while (!_txWrapper.isFinished) {
    //           await _transmitter.transmitControlTone();
    //           await Future.delayed(const Duration(milliseconds: 40));
    // }
        await _transmitter.transmitControlTone();
        // await Future.delayed(const Duration(milliseconds: 500));
        _isTransmittingBusy = false;
        _lastBusyTxTime = DateTime.now();
        break;

      case ControlAction.discoveryDetected:
        if (_isDiscoveryRunning) {
          break; 
        }
        _isDiscoveryActive = true;
        _isDiscoveryRunning = true;
        
        _log("Wrapper: Valid Discovery detected. Requesting topology reset from original dispatcher.");
        _amITheDiscoveryInitiator = false;
        
        
        _txWrapper.startControlTone(0); 
        while (!_txWrapper.isFinished) {
            await _transmitter.transmitControlTone();
            await Future.delayed(const Duration(milliseconds: 40));
          }
        _isValidDiscoveryChain = true; 
        
        Future.delayed(const Duration(seconds: 4), () {
          
          if (_isValidDiscoveryChain) {
            _log("Wrapper: 4 seconds passed without BUSY. Proceeding to Stage 2.");
            _originalDispatcher.resetTopology(); 
            _proceedToNextStage(asRoot: false);
            
            
          }else {
          _log("Wrapper: Discovery chain became invalid (BUSY signal detected). Resetting lock.");
          _isDiscoveryRunning = false;
          _isDiscoveryActive = false;
          _resetAllDispatcherGates();
        }
        });
        break;

      case ControlAction.busyDetectedAndAbort:
        _log("Wrapper: I started Discovery but room is BUSY! Activating 5-second backoff.");
        _amITheDiscoveryInitiator = false;
        _backoffUntil = DateTime.now().add(const Duration(seconds: 5));
        
       
        if (_discoveryAttempts < _maxDiscoveryAttempts) {
          Future.delayed(const Duration(seconds: 5), () {
            _executeDiscoveryAttempt();
          });
        } else {
          _log("Wrapper: Max discovery attempts reached. Cannot start DISCOVERY.");
          _isDiscoveryRunning = false;
          _resetAllDispatcherGates();
          
        }
        break;

      case ControlAction.busyDetectedAndPropagate:
        if (isPastStage1) {
           _log("Wrapper: Ignoring BUSY propagation signal because we are already past Stage 1.");
           break;
        }
        if (_isTransmittingBusy) return;
        if (_lastBusyTxTime != null && DateTime.now().difference(_lastBusyTxTime!).inMilliseconds < 1500) {
          return;
        }
        _isTransmittingBusy = true;
        _log("Wrapper: Heard BUSY from peer. Propagating BUSY horn.");
        _txWrapper.startControlTone(1);
        while (!_txWrapper.isFinished) {
            await _transmitter.transmitControlTone();
            await Future.delayed(const Duration(milliseconds: 40));
          }
          await Future.delayed(const Duration(milliseconds: 500));
          _isTransmittingBusy = false;
        _isValidDiscoveryChain = false; 
        _isDiscoveryRunning = false;
        _resetAllDispatcherGates();
        break;
      case ControlAction.externalDiscoveryOverheard:
      if (isPastStage1) break;
        if (_isTransmittingBusy) break;
        if (_lastBusyTxTime != null && DateTime.now().difference(_lastBusyTxTime!).inMilliseconds < 1500) {
          break;
        }
        
        
        if (_originalDispatcher.lockedPartnerId == null) {
          _busySpamCount = 0;
        }

        
        if (_busySpamCount >= 3) {
          _log("Wrapper: Max BUSY threshold reached (3/3) for this lock instance. Suppressing horn to guard data stream.");
          break;
        }
        
        _busySpamCount++; 
        _log("Wrapper: Device is in locked session. Overheard external Discovery, responding with BUSY to protect channel (Attempt $_busySpamCount/3).");
        handleControlAction(ControlAction.respondWithBusy); 
        break;
        case ControlAction.none:
        break;
    }

  }
      Future<void> changeToNextStage() async {

  if (_originalDispatcher.isStage1Allowed) {
    _originalDispatcher.isStage1Allowed = false;
    _originalDispatcher.isStage2Allowed = true;
    _log("Wrapper: Transitioned to Stage 2");
  } else if (_originalDispatcher.isStage2Allowed) {
    _originalDispatcher.isStage2Allowed = false;
    _originalDispatcher.isStage3Allowed = true;
    _log("Wrapper: Transitioned to Stage 3");
  } else if (_originalDispatcher.isStage3Allowed) {
    _originalDispatcher.isStage3Allowed = false;
    _originalDispatcher.isStage4Allowed = true;
    _log("Wrapper: Transitioned to Stage 4");
  }else if (_originalDispatcher.isStage4Allowed) {
      _originalDispatcher.isStage4Allowed = false;
      _originalDispatcher.isStage1Allowed = true; 
      _log("Wrapper: Stage 4 Completed. Resetting Dispatcher gates back to Stage 1 (Idle Mode)");
    }
  
  _isCsmaActive = false;
}
  Future<void> csmaDataWait() async {
    if (_isCsmaActive) return;
    _isCsmaActive = true; 

    bool isChannelBusy = true;
    _log("Wrapper: CSMA DATA Carrier Sensing STARTED (Active Listen).");
    
    while (isChannelBusy) {
      
      final int msSinceLastSymbol = DateTime.now().difference(_originalDispatcher.lastReceivedSymbolTime).inMilliseconds;
      
      
      bool isOtherDeviceTransmitting = msSinceLastSymbol < 500; 
      bool isBusyToneActive = _isTransmittingBusy;

      if (isOtherDeviceTransmitting || isBusyToneActive) {
       
        await Future.delayed(const Duration(milliseconds: 40));
      } else {
       
        isChannelBusy = false;
      }
    }
    
    _log("Wrapper: CSMA DATA FINISHED. Air is clear, releasing frame safely.");
    _isCsmaActive = false;
  }
  Future<void> csmaWait() async {
    if (_isCsmaActive) {
      _log("${DateTime.now().toIso8601String()} | Wrapper: CSMA already active, blocking this request.");
      return;
    }
    _isCsmaActive = true; 

    _originalDispatcher.getSymbolBuffer().fillRange(0, 24, 0);
   
    bool isChannelBusy = true;
    int quietCheckCount = 0;
    
    _log("${DateTime.now().toIso8601String()} | Wrapper: Carrier Sensing STARTED.");
    
    while (isChannelBusy) {
      bool hasFskSymbols = _originalDispatcher.getSymbolBuffer().any((sym) => sym != 0);
      bool isDataWorkerRunning = _originalDispatcher.isWorkerRunning;
      bool isBusyToneActive = _isTransmittingBusy;

      if (hasFskSymbols || isDataWorkerRunning || isBusyToneActive) {
        quietCheckCount = 0;
        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        quietCheckCount++;
        if (quietCheckCount >= 5) {
          isChannelBusy = false;
        } else {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    
    
    _log("${DateTime.now().toIso8601String()} | Wrapper: CSMA FINISHED. Air is clear.");
    _isCsmaActive = false;
  }
void _proceedToNextStage({required bool asRoot}) async {
    _log("Wrapper: Transitioning to Stage 2. Mode -> asRoot: $asRoot");
    _isValidDiscoveryChain = false; 
    
    
    await changeToNextStage();
    _log("Wrapper: Gate 2 is OPEN. Gates 3 and 4 are LOCKED.");
    _eventController.add(TopologyEvent.discoveryStarted); 
    _safetyTimeoutTimer?.cancel();
    _safetyTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_isDiscoveryRunning && 
          _originalDispatcher.isStage3Allowed == false && 
          _originalDispatcher.isStage4Allowed == false) {
        _log("Wrapper: WATCHDOG TIMEOUT! Discovery got stuck or orphaned. Force resetting to Stage 1 Idle.");
        _isDiscoveryRunning = false;
        _isDiscoveryActive = false;
        _amITheDiscoveryInitiator = false;
        _isValidDiscoveryChain = false;
        
        _resetAllDispatcherGates(); 
        _originalDispatcher.isStage1Allowed = true; 
        _originalDispatcher.resetTopology();
        _eventController.add(TopologyEvent.discoveryFinished);
      }
    });
    if (asRoot) {
      String myShortIdStr = await DeviceIdCreateLogic().getShortId();
      int myShortIdByte = int.parse(myShortIdStr, radix: 16);
      
      _originalDispatcher.initiateStage2AsRoot(myShortIdByte); 
    } else {
      
      
      print("Wrapper: Flag changed successfully. Device is now a verified Stage 2 Follower.");
    }
  }









  void _resetAllDispatcherGates() {
    _originalDispatcher.isStage2Allowed = false;
    _originalDispatcher.isStage3Allowed = false;
    _originalDispatcher.isStage4Allowed = false;
    print("Wrapper: All linear gatekeepers locked (false).");
  }
  Future<void> pushSymbol(int symbol, Function(String deviceId) onPacketDetected) =>
      _originalDispatcher.pushSymbol(symbol, onPacketDetected);

  
  Future<void> addDataPacketToQueue(Uint8List data) =>
      _originalDispatcher.addDataPacketToQueue(data);

      void _log(String message) {
    
    String timeOnly = DateTime.now().toIso8601String().substring(11, 23);
    print("$timeOnly | $message");
  }
}
