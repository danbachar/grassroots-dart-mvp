import 'dart:async';
import 'dart:typed_data';
import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:provider/provider.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'dart:io' show Platform;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Grassroots',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange)),
        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var current = WordPair.random();

  var favorites = <WordPair>[];

  void getNext() {
    current = WordPair.random();
    notifyListeners();
  }

  void toggleFavorite() { 
    if (favorites.contains(current)) {
      favorites.remove(current);
    } else {
      favorites.add(current);
    }
    notifyListeners();
  }

  void removeFavorite(WordPair pair) {
    favorites.remove(pair);
    notifyListeners();
  }
}


class MyHomePage extends StatefulWidget {
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget page = selectedIndex == 0 ? GeneratorPage() : selectedIndex == 1 ? FavoritesPage() : selectedIndex == 2 ? BluetoothPage() : Text('Unknown');
    return LayoutBuilder(
      builder: (context, constraints) {
        var hasEnoughSpace = constraints.maxWidth >= 600;
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  extended: hasEnoughSpace,
                  destinations: [
                    NavigationRailDestination(icon: Icon(Icons.home), label: Text('Home')),
                    NavigationRailDestination(icon: Icon(Icons.favorite), label: Text('Favorites')),
                    NavigationRailDestination(icon: Icon(Icons.bluetooth), label: Text('Bluetooth'))
                  ],
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (value) {
                    setState(() {
                      selectedIndex = value;
                    });
                  },
                ),
              ),
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: page,
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}

class GeneratorPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var pair = appState.current;

    IconData icon;
    if (appState.favorites.contains(pair)) {
      icon = Icons.favorite;
    } else {
      icon = Icons.favorite_border;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BigName(pair: pair),
          SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  appState.toggleFavorite();
                },
                icon: Icon(icon),
                label: Text('Like'),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  appState.getNext();
                },
                child: Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var favorites = appState.favorites;

    var title = favorites.isNotEmpty ? 'You have ${appState.favorites.length} favorites:' : 'No favorites yet';

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(title),
        ),
        for (var pair in favorites)
          ListTile(
            leading: Icon(Icons.favorite),
            title: Text(pair.asLowerCase),
            onTap: () => {
              appState.removeFavorite(pair)
            },  
          ),
      ],
    );

  }
}

class BigName extends StatelessWidget {
  const BigName({
    super.key,
    required this.pair,
  });

  final WordPair pair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displayMedium!.copyWith(
      color: theme.colorScheme.onPrimary,
    );

    return Card(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text(pair.asLowerCase, style: style),
      ),
    );
  }
}

// Models for paired devices and messages
class PairedDevice {
  final String uuid;
  final String name;
  final Peripheral? peripheral;
  
  PairedDevice({required this.uuid, required this.name, this.peripheral});
}

class ChatMessage {
  final String text;
  final DateTime timestamp;
  final bool isSentByMe;
  bool isDelivered;
  
  ChatMessage({
    required this.text,
    required this.timestamp,
    required this.isSentByMe,
    this.isDelivered = false,
  });
}

class BluetoothPage extends StatefulWidget {
  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  final CentralManager _central;
  final PeripheralManager _peripheral;
  List<DiscoveredEventArgs> _scanResults = [];
  List<PairedDevice> _pairedDevices = [];
  Map<String, List<ChatMessage>> _chats = {}; // uuid -> messages
  bool _isScanning = false;
  bool _isAdvertising = false;
  late final GATTService service;
  late final Advertisement advertisement;
  
  late final StreamSubscription<DiscoveredEventArgs> _scanSubscription;
  late final StreamSubscription _centralManagerStateChangedSubscription;
  late final StreamSubscription _peripheralManagerStateChangedSubscription;
  late final StreamSubscription _readRequestedSubscription;
  late final StreamSubscription _writeRequestedSubscription;
  late final StreamSubscription _peripheralConnectionStateChangedSubscription; // this is for the device who was paired with
  late final StreamSubscription _centralConnectionStateChangedSubscription; // this is for the device who initiated the pairing
  late final deviceName = 'Voyager2';

  _BluetoothPageState():  _central = CentralManager(), _peripheral = PeripheralManager() {
    _centralManagerStateChangedSubscription = _central.stateChanged.listen((eventArgs) async {
            if (eventArgs.state == BluetoothLowEnergyState.unauthorized &&
                Platform.isAndroid) {
              await _central.authorize();
            }
          });
    _peripheralManagerStateChangedSubscription = _peripheral.stateChanged.listen((eventArgs) async {
            if (eventArgs.state == BluetoothLowEnergyState.unauthorized &&
                Platform.isAndroid) {
              await _peripheral.authorize();
            }
          });
    _scanSubscription = _central.discovered.listen((eventArgs) {
            final peripheral = eventArgs.peripheral;
            final index = _scanResults.indexWhere((i) => i.peripheral == peripheral);
            if (eventArgs.advertisement.name == null || eventArgs.advertisement.name!.isEmpty) {
              return; // skip unnamed devices
            }
            print("Discovered device: ${eventArgs.advertisement.name} (${peripheral.uuid}), RSSI: ${eventArgs.rssi}");
            var newResults = List<DiscoveredEventArgs>.from(_scanResults);
            if (index < 0) {
              newResults.add(eventArgs);
            } else {
              newResults[index] = eventArgs;
            }
            setState(() {
              _scanResults = newResults;
            });
      });
    _centralConnectionStateChangedSubscription = _central.connectionStateChanged.listen((eventArgs) {
      final peripheral = eventArgs.peripheral;
      final peripheralUuid = peripheral.uuid.toString();
      print("Connection state changed: ${eventArgs.state} for device $peripheralUuid");
      
      if (eventArgs.state == ConnectionState.connected) {
        print("Peripheral device connected: $peripheralUuid");
        
        // Check if already paired
        if (_pairedDevices.any((d) => d.uuid == peripheralUuid)) {
          print("Device already paired: $peripheralUuid");
          return;
        }

        // Add the device to paired devices
        setState(() {
          _pairedDevices.add(PairedDevice(
            uuid: peripheralUuid,
            name: 'TODO',
            peripheral: null,
          ));
          _chats[peripheralUuid] = [];
        });
      } else if (eventArgs.state == ConnectionState.disconnected) {
        print("Peripheral device disconnected: $peripheralUuid");
      }
    });
    _peripheralConnectionStateChangedSubscription = _peripheral.connectionStateChanged.listen((eventArgs) {
      final central = eventArgs.central;
      final centralUuid = central.uuid.toString();
      print("Connection state changed: ${eventArgs.state} for device $centralUuid");
      
      if (eventArgs.state == ConnectionState.connected) {
        print("Central device connected: $centralUuid");
        
        // Check if already paired
        if (_pairedDevices.any((d) => d.uuid == centralUuid)) {
          print("Device already paired: $centralUuid");
          return;
        }
        
        // Add the device to paired devices
        setState(() {
          _pairedDevices.add(PairedDevice(
            uuid: centralUuid,
            name: 'TODO',
            peripheral: null,
          ));
          _chats[centralUuid] = [];
        });
      } else if (eventArgs.state == ConnectionState.disconnected) {
        print("Central device disconnected: $centralUuid");
      }
    });
    _readRequestedSubscription = _peripheral.characteristicReadRequested.listen((eventArgs) {
      print("Read requested for characteristic: ${eventArgs.characteristic.uuid}");
      final request = eventArgs.request;
      final centralUuid = eventArgs.central.uuid.toString();
      
      // Only respond to paired devices
      if (!_pairedDevices.any((d) => d.uuid == centralUuid)) {
        print("Ignoring read request from unpaired device: $centralUuid");
        return;
      }
      
      // Respond with empty data for now
      _peripheral.respondReadRequestWithValue(
        request,
        value: Uint8List.fromList([]),
      );
    });
    _writeRequestedSubscription = _peripheral.characteristicWriteRequested.listen((eventArgs) {
      print("Write requested for characteristic: ${eventArgs.characteristic.uuid}");
      final request = eventArgs.request;
      final centralUuid = eventArgs.central.uuid.toString();
      
      // Only respond to paired devices for regular messages
      if (!_pairedDevices.any((d) => d.uuid == centralUuid)) {
        print("Ignoring write request from unpaired device: $centralUuid");
        return;
      }
      
      // If this is characteristic 201 (our messaging characteristic)
      if (eventArgs.characteristic.uuid == UUID.short(201)) {
        final messageText = String.fromCharCodes(request.value);
        print("Received message: $messageText");
        
        // Add received message to chat
        setState(() {
          final message = ChatMessage(
            text: messageText,
            timestamp: DateTime.now(),
            isSentByMe: false,
          );
          _chats[centralUuid]?.add(message);
        });
        
        // Respond to the write request with success
        _peripheral.respondWriteRequest(request);
      }
    });
  }

  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;
  BluetoothLowEnergyState get state => _central.state;
  List<DiscoveredEventArgs> get scanResults => _scanResults;

  Future<void> showAppSettings() async {
    await _central.showAppSettings();
  }

  Future<void> startScan({List<UUID>? serviceUUIDs}) async {
    print("Starting scan");
    if (_isScanning) {
      print("Already scanning, cannot start another scan");
      return; // if scanning, dont do anything
    }

    print("Scanning...");
    setState(() {
      _scanResults.clear();
      _isScanning = true;
    });

    await _central.startDiscovery(serviceUUIDs: serviceUUIDs);
    Timer(Duration(seconds: 10), () {
        print('Done scanning');
        stopScan();
      }
    );
  }

  Future<void> stopScan() async {
    if (!_isScanning) {
      return;
    }
    await _central.stopDiscovery();
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) {
      return;
    }
    
    // await _readRequestedSubscription.cancel();
    // await _writeRequestedSubscription.cancel();
    // await _peripheralConnectionStateChangedSubscription.cancel();
    
    await _peripheral.stopAdvertising();
    setState(() {
      _isAdvertising = false;
    });
  }

  Future<void> pairDevice(DiscoveredEventArgs deviceArgs) async {
    final device = deviceArgs.peripheral;
    final deviceName = deviceArgs.advertisement.name ?? 'Unknown Device';
    final deviceUuid = device.uuid.toString();
    
    // Check if already paired
    if (_pairedDevices.any((d) => d.uuid == deviceUuid)) {
      print("Device already paired: $deviceName");
      return;
    }
    
    print("Attempting to connect to $deviceName...");
    await _central.connect(device);
    print("Executed connect to $deviceName, waiting for connection change...");
    
    // // Discover services
    // await _central.discoverGATT(device);
    // print("Discovered GATT services");
    
    // // Add to paired devices on this side
    // setState(() {
    //   _pairedDevices.add(PairedDevice(
    //     uuid: deviceUuid,
    //     name: deviceName,
    //     peripheral: device,
    //   ));
    //   _chats[deviceUuid] = [];
    // });
    
    // print("Successfully paired with $deviceName");
  }

  Future<void> sendMessage(String deviceUuid, String messageText) async {
    final device = _pairedDevices.firstWhere((d) => d.uuid == deviceUuid);
    if (device.peripheral == null) return;
    
    final message = ChatMessage(
      text: messageText,
      timestamp: DateTime.now(),
      isSentByMe: true,
    );
    
    setState(() {
      _chats[deviceUuid]?.add(message);
    });
    
    try {
      // Write message to characteristic 201
      final characteristic = GATTCharacteristic.mutable(
        uuid: UUID.short(201),
        properties: [GATTCharacteristicProperty.write],
        permissions: [GATTCharacteristicPermission.write],
        descriptors: [],
      );
      
      final messageBytes = Uint8List.fromList(messageText.codeUnits);
      await _central.writeCharacteristic(
        device.peripheral!,
        characteristic,
        value: messageBytes,
        type: GATTCharacteristicWriteType.withResponse,
      );
      
      // Mark as delivered
      setState(() {
        message.isDelivered = true;
      });
      print("Message sent and acknowledged");
    } catch (e) {
      print("Error sending message: $e");
    }
  }

  void openChatWindow(String deviceUuid) {
    final device = _pairedDevices.firstWhere((d) => d.uuid == deviceUuid);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatPage(
          device: device,
          messages: _chats[deviceUuid] ?? [],
          onSendMessage: (text) => sendMessage(deviceUuid, text),
        ),
      ),
    );
  }

  Future<void> startAdvertising() async {
    if (_isAdvertising) {
      return;
    }
    if (_isScanning) {
      await stopScan();
    }
    
    await _peripheral.stopAdvertising();

    await _peripheral.removeAllServices();
    await _peripheral.addService(service);

    await _peripheral.startAdvertising(advertisement);

    setState(() {
      _isAdvertising = true;
    });
  }
  
  @override
  void initState() {
    super.initState();

    var elements = List.generate(100, (i) => i % 256);
    var value = Uint8List.fromList(elements);
    var s = GATTService(
      uuid: UUID.short(100),
      isPrimary: true,
      includedServices: [],
      characteristics: [
        GATTCharacteristic.immutable(
          uuid: UUID.short(200),
          value: value,
          descriptors: [],
        ),
        GATTCharacteristic.mutable(
          uuid: UUID.short(201),
          properties: [
            GATTCharacteristicProperty.read,
            GATTCharacteristicProperty.write,
            GATTCharacteristicProperty.writeWithoutResponse,
            GATTCharacteristicProperty.notify,
            GATTCharacteristicProperty.indicate,
          ],
          permissions: [
            GATTCharacteristicPermission.read,
            GATTCharacteristicPermission.write,
          ],
          descriptors: [],
        ),
      ],
    );
    var ad = Advertisement(
      name: deviceName,
      manufacturerSpecificData:
          Platform.isIOS || Platform.isMacOS
              ? []
              : [
                ManufacturerSpecificData( // should contain PK: ES25519 is 32 bytes; this field typically has 26 bytes available
                  id: 0x2e19,
                  data: Uint8List.fromList([0x01, 0x02, 0x03]),
                ),
              ],
    );

    setState(() {
      _scanResults = [];
      _isScanning = false;
      _isAdvertising = false;
      service = s;
      advertisement = ad;
    });
  }

  @override
  void dispose() {
    _centralManagerStateChangedSubscription.cancel();
    _peripheralManagerStateChangedSubscription.cancel();
    _scanSubscription.cancel();
    _readRequestedSubscription.cancel();
    _writeRequestedSubscription.cancel();
    _centralConnectionStateChangedSubscription.cancel();
    _peripheralConnectionStateChangedSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('BLE Scanner'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          // Paired devices list
          if (_pairedDevices.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paired Devices',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  ..._pairedDevices.map((device) => Card(
                    child: ListTile(
                      title: Text(device.name),
                      subtitle: Text(device.uuid),
                      trailing: IconButton(
                        icon: Icon(Icons.chat),
                        onPressed: () => openChatWindow(device.uuid),
                      ),
                    ),
                  )),
                ],
              ),
            ),
          
          // Scan and Advertise buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? stopScan : startScan,
                  icon: Icon(_isScanning ? Icons.stop : Icons.search),
                  label: Text('Scan'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isAdvertising ? stopAdvertising : startAdvertising,
                  icon: Icon(_isAdvertising ? Icons.stop : Icons.broadcast_on_home),
                  label: Text('Advertise'),
                ),
              ),
            ],
          )),
          
          // Discovered devices list
          Expanded(
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final result = _scanResults[index];
                final deviceUuid = result.peripheral.uuid.toString();
                final isPaired = _pairedDevices.any((d) => d.uuid == deviceUuid);
                
                return ListTile(
                  title: Text(result.advertisement.name ?? 'Unknown Device'),
                  subtitle: Text(result.peripheral.uuid.toString()),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${result.rssi} dBm'),
                      SizedBox(width: 8),
                      if (!isPaired)
                        ElevatedButton.icon(
                          onPressed: () => pairDevice(result),
                          icon: Icon(Icons.link, size: 16),
                          label: Text('Pair'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        )
                      else
                        Icon(Icons.check_circle, color: Colors.green),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Chat page for messaging with a paired device
class ChatPage extends StatefulWidget {
  final PairedDevice device;
  final List<ChatMessage> messages;
  final Function(String) onSendMessage;
  
  ChatPage({
    required this.device,
    required this.messages,
    required this.onSendMessage,
  });
  
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  
  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
  
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    widget.onSendMessage(text);
    _messageController.clear();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: widget.messages.length,
              itemBuilder: (context, index) {
                final message = widget.messages[widget.messages.length - 1 - index];
                final timeStr = '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';
                
                return Align(
                  alignment: message.isSentByMe 
                      ? Alignment.centerRight 
                      : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: message.isSentByMe 
                          ? Colors.blue[100] 
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          message.text,
                          style: TextStyle(fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (message.isSentByMe) ...[
                              SizedBox(width: 4),
                              Icon(
                                message.isDelivered 
                                    ? Icons.check 
                                    : Icons.schedule,
                                size: 12,
                                color: message.isDelivered 
                                    ? Colors.blue 
                                    : Colors.grey,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
