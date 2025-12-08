import 'dart:async';
import 'dart:typed_data';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import '../protocol/constants.dart';
import 'package:permission_handler/permission_handler.dart';

// Transport layer chunk types
const int _CHUNK_SINGLE = 0x01; // Complete message in one chunk
const int _CHUNK_FIRST = 0x02; // First chunk of multi-chunk message
const int _CHUNK_MIDDLE = 0x03; // Middle chunk
const int _CHUNK_LAST = 0x04; // Last chunk

/// Abstracts BLE operations using dual libraries:
/// - bluetooth_low_energy for Central (scanning/connecting)
/// - ble_peripheral for Peripheral (advertising)
///
/// Includes transport chunking layer for BLE MTU handling
class BLEManager {
  final CentralManager _central;

  // Stream subscriptions
  late final StreamSubscription<DiscoveredEventArgs> _scanSubscription;
  late final StreamSubscription _centralStateChangedSubscription;
  late final StreamSubscription _centralConnectionStateChangedSubscription;
  late final StreamSubscription _characteristicNotifiedSubscription;

  // State
  bool _isScanning = false;
  bool _isAdvertising = false;
  final Map<String, Peripheral> _connectedPeripherals =
      {}; // peripheralId -> Peripheral (as Central)
  final Map<String, List<GATTService>> _discoveredServices =
      {}; // peripheralId -> services

  // Track centrals that have connected to us (as Peripheral) - deviceId -> subscribed characteristics
  final Map<String, Set<String>> _connectedCentrals = {};

  // Transport layer chunk reassembly
  // deviceId -> messageId -> chunks
  final Map<String, Map<int, List<Uint8List>>> _chunkBuffers = {};

  // Callbacks
  void Function(DiscoveredEventArgs)? onDeviceDiscovered;
  void Function(Peripheral, ConnectionState)? onCentralConnectionChanged;
  void Function(String deviceId, Uint8List data)? onDataReceived;
  void Function(String deviceId, String characteristicId, Uint8List data)?
  onCharacteristicDataReceived;

  BLEManager() : _central = CentralManager() {
    _setupSubscriptions();
  }

  void _setupSubscriptions() {
    // Central state changes (for scanning)
    _centralStateChangedSubscription = _central.stateChanged.listen((
      eventArgs,
    ) async {
      print('Central state changed: ${eventArgs.state}');
    });

    // Scan results
    _scanSubscription = _central.discovered.listen((eventArgs) {
      // Filter out unnamed devices
      if (eventArgs.advertisement.name == null ||
          eventArgs.advertisement.name!.isEmpty) {
        return;
      }
      // TODO: filter devices by having necessary GATT services and attributes, maybe manufacturerID?
      onDeviceDiscovered?.call(eventArgs);
    });

    // Central connection state changes (when we connect to someone)
    _centralConnectionStateChangedSubscription = _central.connectionStateChanged
        .listen((eventArgs) {
          final peripheral = eventArgs.peripheral;
          final peripheralId = peripheral.uuid.toString();

          if (eventArgs.state == ConnectionState.connected) {
            _connectedPeripherals[peripheralId] = peripheral;
          } else if (eventArgs.state == ConnectionState.disconnected) {
            _connectedPeripherals.remove(peripheralId);
          }

          onCentralConnectionChanged?.call(peripheral, eventArgs.state);
        });

    // Listen for notifications from peripherals we're connected to (as Central)
    _characteristicNotifiedSubscription = _central.characteristicNotified.listen((
      eventArgs,
    ) {
      final peripheralId = eventArgs.peripheral.uuid.toString();
      final characteristicId = eventArgs.characteristic.uuid.toString();
      final data = eventArgs.value;

      print(
        'Received notification from $peripheralId on $characteristicId: ${data.length} bytes',
      );

      // Handle chunked data
      _handleReceivedChunk(
        peripheralId,
        data,
        characteristicId: characteristicId,
      );
    });

    // Track when centrals subscribe to our characteristics (as Peripheral)
    BlePeripheral.setCharacteristicSubscriptionChangeCallback((
      String deviceId,
      String characteristicId,
      bool isSubscribed,
      String? name,
    ) {
      print(
        'Central $deviceId ($name) ${isSubscribed ? "subscribed to" : "unsubscribed from"} $characteristicId',
      );
      if (isSubscribed) {
        _connectedCentrals[deviceId] ??= {};
        _connectedCentrals[deviceId]!.add(characteristicId);
      } else {
        _connectedCentrals[deviceId]?.remove(characteristicId);
        if (_connectedCentrals[deviceId]?.isEmpty ?? false) {
          _connectedCentrals.remove(deviceId);
        }
      }
    });

    // Setup peripheral write callback with transport chunk reassembly
    // This also passes the characteristic ID so we know which characteristic was written to
    BlePeripheral.setWriteRequestCallback((
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    ) {
      if (value != null) {
        print(
          'Received write on characteristic $characteristicId from $deviceId',
        );
        // Track this central as connected (even if not subscribed yet)
        _connectedCentrals[deviceId] ??= {};

        // Pass characteristic info along with the data
        _handleReceivedChunk(
          deviceId,
          value,
          characteristicId: characteristicId,
        );
      }
      return null; // Return null to accept the write
    });
  }

  /// Initialize BLE (request permissions)
  Future<void> initialize() async {
    print('Requesting Central authorization from ble manager...');
    _central
        .authorize()
        .then((isAuthorized) {
          print('Central authorized: $isAuthorized');
        })
        .catchError((error) {
          print('Error during central authorization: $error');
        });

    print('Requesting Peripheral authorization...');
    await BlePeripheral.initialize()
        .then((isAuthorized) {
          print('Peripheral authorized: $isAuthorized');
        })
        .catchError((error) {
          print('Error during peripheral authorization: $error');
        });
  }

  /// Get current BLE state
  BluetoothLowEnergyState get state => _central.state;

  /// Check if scanning
  bool get isScanning => _isScanning;

  /// Check if advertising
  bool get isAdvertising => _isAdvertising;

  /// Start scanning for devices (optionally filter by service UUIDs)
  Future<void> startScan({List<UUID>? serviceUUIDs}) async {
    if (_isScanning) return;

    print('Starting scan...');
    _isScanning = true;
    await _central.startDiscovery(serviceUUIDs: serviceUUIDs);
  }

  /// Stop scanning
  Future<void> stopScan() async {
    if (!_isScanning) return;

    await _central.stopDiscovery();
    _isScanning = false;
    print('Stopped scanning');
  }

  /// Start advertising with given service UUID and device name
  Future<void> startAdvertising({
    required String serviceUUID,
    required String deviceName,
  }) async {
    print("Starting advertising...");
    // if (_isAdvertising) {
    //   print("Returned");
    //   return;
    // }

    // Request BLUETOOTH_ADVERTISE permission at runtime (required for Android 12+)
    var status = await Permission.bluetoothAdvertise.request();
    if (!status.isGranted) {
      print("BLUETOOTH_ADVERTISE permission denied. Cannot start advertising.");
      // Optionally, show a dialog to the user explaining why it's needed
      return;
    }

    // Stop any previous advertising
    await BlePeripheral.stopAdvertising();
    await BlePeripheral.clearServices();
    print("Stopped existing advertising and cleared services");

    // Add GATT service with write-only characteristics
    // New architecture: all characteristics are write-only, sender connects and writes
    print('Adding GATT service: $serviceUUID');
    await BlePeripheral.addService(
      BleService(
        uuid: serviceUUID,
        primary: true,
        characteristics: [
          // Friend request characteristic (sender writes friend requests here)
          BleCharacteristic(
            uuid: FRIEND_REQUEST_CHARACTERISTIC_UUID,
            properties: [
              CharacteristicProperties.write.index,
              CharacteristicProperties.writeWithoutResponse.index,
            ],
            value: null,
            permissions: [AttributePermissions.writeable.index],
          ),
          // Friend response characteristic (sender writes accept/reject here)
          BleCharacteristic(
            uuid: FRIEND_RESPONSE_CHARACTERISTIC_UUID,
            properties: [
              CharacteristicProperties.write.index,
              CharacteristicProperties.writeWithoutResponse.index,
            ],
            value: null,
            permissions: [AttributePermissions.writeable.index],
          ),
          // Message characteristic (sender writes chat messages here)
          BleCharacteristic(
            uuid: MESSAGE_CHARACTERISTIC_UUID,
            properties: [
              CharacteristicProperties.write.index,
              CharacteristicProperties.writeWithoutResponse.index,
            ],
            value: null,
            permissions: [AttributePermissions.writeable.index],
          ),
        ],
      ),
    );

    // Setup advertising status callback
    BlePeripheral.setAdvertisingStatusUpdateCallback((
      bool advertising,
      String? error,
    ) {
      print('Advertising status: $advertising, Error: $error');
    });

    // Start advertising
    print('Starting advertising as $deviceName with service $serviceUUID');
    print("Advertising with manufacturer data");
    var data = ManufacturerData(manufacturerId: 0x539, data: Uint8List.fromList([0x00]));
    await BlePeripheral.startAdvertising(
      services: [serviceUUID],
      localName: deviceName,
      manufacturerData: data,
    );

    _isAdvertising = true;
    print('Started advertising');
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    await BlePeripheral.stopAdvertising();
    _isAdvertising = false;
    print('Stopped advertising');
  }

  /// Connect to a peripheral
  Future<void> connect(Peripheral peripheral) async {
    print('Connecting to ${peripheral.uuid}...');
    await _central.connect(peripheral);
  }

  /// Disconnect from a peripheral
  Future<void> disconnect(Peripheral peripheral) async {
    print('Disconnecting from ${peripheral.uuid}...');
    await _central.disconnect(peripheral);
  }

  /// Discover GATT services on a peripheral
  Future<List<GATTService>> discoverServices(Peripheral peripheral) async {
    final peripheralId = peripheral.uuid.toString();
    print('Discovering GATT services for $peripheralId...');

    // // Try to negotiate a larger MTU for larger packet transfers
    // try {
    //   final mtu = await _central.requestMTU(peripheral, 512);
    //   print('Negotiated MTU: $mtu bytes');
    // } catch (e) {
    //   print('MTU negotiation failed (will use default): $e');
    // }

    final services = await _central.discoverGATT(peripheral);
    _discoveredServices[peripheralId] = services;
    return services;
  }

  /// Subscribe to notifications on a characteristic (as Central)
  Future<void> subscribeToCharacteristic({
    required Peripheral peripheral,
    required GATTCharacteristic characteristic,
  }) async {
    print('Subscribing to notifications on ${characteristic.uuid}...');
    await _central.setCharacteristicNotifyState(
      peripheral,
      characteristic,
      state: true,
    );
    print('Subscribed to ${characteristic.uuid}');
  }

  /// Unsubscribe from notifications on a characteristic (as Central)
  Future<void> unsubscribeFromCharacteristic({
    required Peripheral peripheral,
    required GATTCharacteristic characteristic,
  }) async {
    print('Unsubscribing from notifications on ${characteristic.uuid}...');
    await _central.setCharacteristicNotifyState(
      peripheral,
      characteristic,
      state: false,
    );
    print('Unsubscribed from ${characteristic.uuid}');
  }

  /// Find a characteristic by UUID from discovered services
  GATTCharacteristic? findCharacteristic(
    String peripheralId,
    UUID characteristicUUID,
  ) {
    final services = _discoveredServices[peripheralId];
    if (services == null) return null;

    for (final service in services) {
      for (final char in service.characteristics) {
        if (char.uuid.toString().toLowerCase() ==
            characteristicUUID.toString().toLowerCase()) {
          return char;
        }
      }
    }
    return null;
  }

  /// Write data to a peripheral's characteristic with transport layer chunking
  Future<void> writeCharacteristic({
    required Peripheral peripheral,
    required UUID characteristicUUID,
    required Uint8List data,
    GATTCharacteristicWriteType writeType =
        GATTCharacteristicWriteType.withResponse,
  }) async {
    final peripheralId = peripheral.uuid.toString();

    // Try to find the actual discovered characteristic
    var characteristic = findCharacteristic(peripheralId, characteristicUUID);

    if (characteristic == null) {
      // Fallback: create a mutable characteristic (may not work with all BLE stacks)
      print(
        'Warning: Characteristic not found in discovered services, creating mutable one',
      );
      characteristic = GATTCharacteristic.mutable(
        uuid: characteristicUUID,
        properties: [
          GATTCharacteristicProperty.write,
          GATTCharacteristicProperty.writeWithoutResponse,
        ],
        permissions: [GATTCharacteristicPermission.write],
        descriptors: [],
      );
    }

    // Transport layer chunking
    // Chunk header: [type(1), messageId(2)] = 3 bytes
    // Max data per chunk: 18 - 3 = 15 bytes
    const int maxChunkSize = 18;
    const int headerSize = 3;
    const int maxDataPerChunk = maxChunkSize - headerSize;

    if (data.length <= maxDataPerChunk) {
      // Single chunk
      final messageId = DateTime.now().millisecondsSinceEpoch % 65536;
      final chunk = _createChunk(_CHUNK_SINGLE, messageId, 0, 1, data);
      print('Sending single chunk: ${chunk.length} bytes');

      await _central.writeCharacteristic(
        peripheral,
        characteristic,
        value: chunk,
        type: writeType,
      );
    } else {
      // Multiple chunks
      final messageId = DateTime.now().millisecondsSinceEpoch % 65536;
      final totalChunks = (data.length / maxDataPerChunk).ceil();

      print('Chunking ${data.length} bytes into $totalChunks chunks');

      for (int i = 0; i < totalChunks; i++) {
        final start = i * maxDataPerChunk;
        final end = (start + maxDataPerChunk < data.length)
            ? start + maxDataPerChunk
            : data.length;
        final chunkData = data.sublist(start, end);

        // Determine chunk type
        int chunkType;
        if (i == 0) {
          chunkType = _CHUNK_FIRST;
        } else if (i == totalChunks - 1) {
          chunkType = _CHUNK_LAST;
        } else {
          chunkType = _CHUNK_MIDDLE;
        }

        final chunk = _createChunk(
          chunkType,
          messageId,
          i,
          totalChunks,
          chunkData,
        );
        print('Sending chunk ${i + 1}/$totalChunks: ${chunk.length} bytes');

        await _central.writeCharacteristic(
          peripheral,
          characteristic,
          value: chunk,
          type: writeType,
        );

        // Small delay between chunks
        if (i < totalChunks - 1) {
          await Future.delayed(Duration(milliseconds: 10));
        }
      }
    }

    print('Transport write completed');
  }

  /// Create a transport chunk with header
  Uint8List _createChunk(
    int type,
    int messageId,
    int chunkIndex,
    int totalChunks,
    Uint8List data,
  ) {
    final buffer = BytesBuilder();

    // Header: type(1) + messageId(2) = 3 bytes
    buffer.addByte(type);
    buffer.addByte((messageId >> 8) & 0xFF); // messageId high byte
    buffer.addByte(messageId & 0xFF); // messageId low byte

    // Data
    buffer.add(data);

    return buffer.toBytes();
  }

  /// Handle received transport chunk and reassemble
  void _handleReceivedChunk(
    String deviceId,
    Uint8List chunk, {
    String? characteristicId,
  }) {
    if (chunk.length < 3) {
      print('Invalid chunk: too short');
      return;
    }

    // Parse header
    final chunkType = chunk[0];
    final messageId = (chunk[1] << 8) | chunk[2];
    final data = chunk.sublist(3);

    print(
      'Received chunk type=$chunkType, messageId=$messageId, data=${data.length} bytes',
    );

    if (chunkType == _CHUNK_SINGLE) {
      // Complete message in one chunk
      print('Complete message in single chunk');
      if (characteristicId != null) {
        onCharacteristicDataReceived?.call(deviceId, characteristicId, data);
      }
      onDataReceived?.call(deviceId, data);
      return;
    }

    // Multi-chunk message
    _chunkBuffers[deviceId] ??= {};

    if (chunkType == _CHUNK_FIRST) {
      // First chunk - initialize buffer
      _chunkBuffers[deviceId]![messageId] = [data];
      print('First chunk buffered');
    } else if (chunkType == _CHUNK_MIDDLE) {
      // Middle chunk - append
      if (_chunkBuffers[deviceId]!.containsKey(messageId)) {
        _chunkBuffers[deviceId]![messageId]!.add(data);
        print(
          'Middle chunk appended (total: ${_chunkBuffers[deviceId]![messageId]!.length})',
        );
      } else {
        print('Warning: Middle chunk for unknown message');
      }
    } else if (chunkType == _CHUNK_LAST) {
      // Last chunk - reassemble and deliver
      if (_chunkBuffers[deviceId]!.containsKey(messageId)) {
        final chunks = _chunkBuffers[deviceId]![messageId]!;
        chunks.add(data);

        // Reassemble all chunks
        final buffer = BytesBuilder();
        for (final chunkData in chunks) {
          buffer.add(chunkData);
        }

        final completeMessage = buffer.toBytes();
        print(
          'Message reassembled: ${completeMessage.length} bytes from ${chunks.length} chunks',
        );

        // Clean up
        _chunkBuffers[deviceId]!.remove(messageId);

        // Deliver complete message
        if (characteristicId != null) {
          onCharacteristicDataReceived?.call(
            deviceId,
            characteristicId,
            completeMessage,
          );
        }
        onDataReceived?.call(deviceId, completeMessage);
      } else {
        print('Warning: Last chunk for unknown message');
      }
    }
  }

  /// Get peripheral by UUID string
  Peripheral? getPeripheral(String peripheralId) {
    return _connectedPeripherals[peripheralId];
  }

  /// Get list of connected central device IDs (devices that connected to us as Peripheral)
  List<String> get connectedCentralIds => _connectedCentrals.keys.toList();

  /// Check if a central is subscribed to a characteristic
  bool isCentralSubscribed(String deviceId, String characteristicId) {
    return _connectedCentrals[deviceId]?.contains(
          characteristicId.toUpperCase(),
        ) ??
        false;
  }

  /// Send notification to a connected central device (as Peripheral)
  /// This is used to send responses back to centrals that connected to us
  Future<void> notifyCharacteristic({
    required String deviceId,
    required String characteristicId,
    required Uint8List data,
  }) async {
    print(
      'Notifying central $deviceId on characteristic $characteristicId with ${data.length} bytes',
    );

    // Transport layer chunking for notifications
    const int maxChunkSize = 18;
    const int headerSize = 3;
    const int maxDataPerChunk = maxChunkSize - headerSize;

    if (data.length <= maxDataPerChunk) {
      // Single chunk
      final messageId = DateTime.now().millisecondsSinceEpoch % 65536;
      final chunk = _createChunk(_CHUNK_SINGLE, messageId, 0, 1, data);

      await BlePeripheral.updateCharacteristic(
        characteristicId: characteristicId,
        value: chunk,
        deviceId: deviceId,
      );
    } else {
      // Multiple chunks
      final messageId = DateTime.now().millisecondsSinceEpoch % 65536;
      final totalChunks = (data.length / maxDataPerChunk).ceil();

      print(
        'Chunking notification ${data.length} bytes into $totalChunks chunks',
      );

      for (int i = 0; i < totalChunks; i++) {
        final start = i * maxDataPerChunk;
        final end = (start + maxDataPerChunk < data.length)
            ? start + maxDataPerChunk
            : data.length;
        final chunkData = data.sublist(start, end);

        int chunkType;
        if (i == 0) {
          chunkType = _CHUNK_FIRST;
        } else if (i == totalChunks - 1) {
          chunkType = _CHUNK_LAST;
        } else {
          chunkType = _CHUNK_MIDDLE;
        }

        final chunk = _createChunk(
          chunkType,
          messageId,
          i,
          totalChunks,
          chunkData,
        );

        await BlePeripheral.updateCharacteristic(
          characteristicId: characteristicId,
          value: chunk,
          deviceId: deviceId,
        );

        // Small delay between chunks
        if (i < totalChunks - 1) {
          await Future.delayed(Duration(milliseconds: 10));
        }
      }
    }

    print('Notification sent to $deviceId');
  }

  /// Show app settings (for permissions)
  Future<void> showAppSettings() async {
    await _central.showAppSettings();
  }

  /// Dispose and clean up
  void dispose() {
    _centralStateChangedSubscription.cancel();
    _scanSubscription.cancel();
    _centralConnectionStateChangedSubscription.cancel();
    _characteristicNotifiedSubscription.cancel();
  }
}
