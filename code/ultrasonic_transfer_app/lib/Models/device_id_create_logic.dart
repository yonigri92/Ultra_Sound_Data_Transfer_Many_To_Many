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
}
