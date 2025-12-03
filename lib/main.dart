import 'dart:async';
import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_coordinator.dart';
import 'models/peer.dart';
import 'models/message.dart';
import 'protocol/constants.dart';
import 'pages/settings_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => MyAppState()),
        ChangeNotifierProvider(
          create: (context) => AppCoordinator(myDisplayName: 'User'),
        ),
      ],
      child: MaterialApp(
        title: 'Grassroots',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        ),
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
  void initState() {
    print("Servus");
    super.initState();
    // Initialize BLE permissions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinator = context.read<AppCoordinator>();
      print("Initializing BLE coordinator...");
      coordinator.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = GeneratorPage();
        break;
      case 1:
        page = FavoritesPage();
        break;
      case 2:
        page = BluetoothPage();
        break;
      default:
        page = Text('Unknown');
    }

    return LayoutBuilder(builder: (context, constraints) {
      var hasEnoughSpace = constraints.maxWidth >= 600;
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                extended: hasEnoughSpace,
                destinations: [
                  NavigationRailDestination(
                    icon: Icon(Icons.home),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.favorite),
                    label: Text('Favorites'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.bluetooth),
                    label: Text('Bluetooth'),
                  ),
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
    });
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

    var title = favorites.isNotEmpty
        ? 'You have ${appState.favorites.length} favorites:'
        : 'No favorites yet';

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
            onTap: () => {appState.removeFavorite(pair)},
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

// ==================== Bluetooth Page ====================

class BluetoothPage extends StatefulWidget {
  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();

    // Setup friend request callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinator = context.read<AppCoordinator>();
      coordinator.onFriendRequestReceived = _handleFriendRequest;
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  void _handleFriendRequest(Peer requester) {
    showDialog(
      context: context,
      builder: (context) => FriendRequestDialog(requester: requester),
    );
  }

  Future<void> _toggleScan() async {
    final coordinator = context.read<AppCoordinator>();

    if (coordinator.isScanning) {
      await coordinator.stopScan();
      _scanTimer?.cancel();
    } else {
      await coordinator.startScan();

      // Auto-stop after 10 seconds
      _scanTimer = Timer(Duration(seconds: 10), () {
        if (mounted) {
          coordinator.stopScan();
        }
      });
    }
  }

  Future<void> _toggleAdvertising() async {
    final coordinator = context.read<AppCoordinator>();

    if (coordinator.isAdvertising) {
      await coordinator.stopAdvertising();
    } else {
      await coordinator.startAdvertising();
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Grassroots BLE'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          // Privacy level indicator (tappable to open settings)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: ActionChip(
                label: Text(coordinator.privacyLevelName),
                avatar: Icon(Icons.shield, size: 18),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SettingsPage(),
                    ),
                  );
                },
              ),
            ),
          ),
          // Settings button
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Friends section
          if (coordinator.friends.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Friends (${coordinator.friends.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  ...coordinator.friends.map((friend) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(friend.displayName[0].toUpperCase()),
                          ),
                          title: Text(friend.displayName),
                          subtitle: Text(
                            '${friend.peerIdHex.substring(0, 16)}...',
                            style: TextStyle(fontFamily: 'monospace'),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (friend.isVerified)
                                Icon(Icons.verified, color: Colors.green, size: 16),
                              SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.chat),
                                onPressed: () => _openChat(friend),
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),

          // Scan/Advertise controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleScan,
                    icon: Icon(
                      coordinator.isScanning ? Icons.stop : Icons.search,
                    ),
                    label: Text(coordinator.isScanning ? 'Stop Scan' : 'Scan'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleAdvertising,
                    icon: Icon(
                      coordinator.isAdvertising
                          ? Icons.stop
                          : Icons.broadcast_on_home,
                    ),
                    label: Text(
                      coordinator.isAdvertising
                          ? 'Stop Advertise'
                          : 'Advertise',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Discovered devices
          Expanded(
            child: coordinator.scanResults.isEmpty
                ? Center(
                    child: Text(
                      coordinator.isScanning
                          ? 'Scanning...'
                          : 'No devices found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: coordinator.scanResults.length,
                    itemBuilder: (context, index) {
                      final result = coordinator.scanResults[index];
                      final deviceName =
                          result.advertisement.name ?? 'Unknown Device';
                      final deviceUuid = result.peripheral.uuid.toString();

                      // Check if already friends
                      final isFriend = coordinator.friends.any(
                        (f) => f.peripheral?.uuid.toString() == deviceUuid,
                      );

                      return ListTile(
                        title: Text(deviceName),
                        subtitle: Text(deviceUuid),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${result.rssi} dBm'),
                            SizedBox(width: 8),
                            if (!isFriend)
                              ElevatedButton.icon(
                                onPressed: () => _pairDevice(result),
                                icon: Icon(Icons.link, size: 16),
                                label: Text('Pair'),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
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

  void _pairDevice(dynamic deviceArgs) async {
    final coordinator = context.read<AppCoordinator>();
    await coordinator.pairDevice(deviceArgs);
  }

  void _openChat(Peer friend) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatPage(friend: friend),
      ),
    );
  }
}

// ==================== Friend Request Dialog ====================

class FriendRequestDialog extends StatelessWidget {
  final Peer requester;

  const FriendRequestDialog({Key? key, required this.requester})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final coordinator = context.read<AppCoordinator>();

    return AlertDialog(
      title: Text('Friend Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${requester.displayName} wants to be friends'),
          SizedBox(height: 8),
          Text(
            'Peer ID: ${requester.peerIdHex.substring(0, 16)}...',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            coordinator.rejectFriendRequest(requester);
            Navigator.of(context).pop();
          },
          child: Text('Reject'),
        ),
        ElevatedButton(
          onPressed: () {
            coordinator.acceptFriendRequest(requester);
            Navigator.of(context).pop();
          },
          child: Text('Accept'),
        ),
      ],
    );
  }
}

// ==================== Chat Page ====================

class ChatPage extends StatefulWidget {
  final Peer friend;

  const ChatPage({Key? key, required this.friend}) : super(key: key);

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

    final coordinator = context.read<AppCoordinator>();
    coordinator.sendMessage(widget.friend, text);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();
    final messages = coordinator.getChat(widget.friend);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.friend.displayName),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      final isSentByMe = _bytesEqual(
                        message.senderId,
                        coordinator.myPeerId,
                      );

                      return _MessageBubble(
                        message: message,
                        isSentByMe: isSentByMe,
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

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isSentByMe;

  const _MessageBubble({
    required this.message,
    required this.isSentByMe,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSentByMe ? Colors.blue[100] : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.content,
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
                if (isSentByMe) ...[
                  SizedBox(width: 4),
                  Icon(
                    _getStatusIcon(),
                    size: 12,
                    color: _getStatusColor(),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (message.status) {
      case MessageStatus.pending:
        return Icons.schedule;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
      default:
        return Icons.schedule;
    }
  }

  Color _getStatusColor() {
    switch (message.status) {
      case MessageStatus.pending:
        return Colors.grey;
      case MessageStatus.sent:
        return Colors.grey;
      case MessageStatus.delivered:
        return Colors.blue;
      case MessageStatus.read:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
