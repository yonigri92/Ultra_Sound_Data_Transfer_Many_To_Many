import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdCreateLogic {
  static final DeviceIdCreateLogic _instance = DeviceIdCreateLogic._internal();

  factory DeviceIdCreateLogic() {
    // Return the singleton object
    return _instance;
  }

  DeviceIdCreateLogic._internal();
  static const String _storageKey = 'unique_device_id';
  // Create an instance of the secure storage.
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _cachedShortId;
  Future<String> getOrCreateId() async {
    // Read the existing ID from the secure storage
    String? existingId = await _secureStorage.read(key: _storageKey);

    if (existingId != null) {
      return existingId;
    }

    var uuid = const Uuid();
    String newId = uuid.v4();
    await _secureStorage.write(key: _storageKey, value: newId);
    return newId;
  }

  Future<String> get40BitId() async {
    String fullUuid = await getOrCreateId();
    return fullUuid.replaceAll('-', '').substring(0, 10);
  }
  Future<String> getShortId() async {
    if (_cachedShortId != null) {
      return _cachedShortId!;
    }

    print("DeviceIdCreateLogic: Short ID Cache is null. Fetching from Storage...");
    String uniqueDeviceId = await get40BitId();

    
    _cachedShortId = uniqueDeviceId.substring(uniqueDeviceId.length - 2).toUpperCase();

    print("DeviceIdCreateLogic: Extracted and cached Short ID String: $_cachedShortId");
    return _cachedShortId!;
  }
}  





