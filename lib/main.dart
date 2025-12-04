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
      
      // Setup notification callback for incoming messages
      coordinator.onMessageReceived = _handleIncomingMessage;
      
      // Setup notification callback for friend acceptance
      coordinator.onFriendAdded = _handleFriendAdded;
    });
  }

  void _handleFriendAdded(Peer friend) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('${friend.displayName} is now your friend!'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleIncomingMessage(Message message, Peer sender) {
    // Show a notification banner
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Text(
                sender.displayName[0].toUpperCase(),
                style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sender.displayName,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    message.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Open',
          textColor: Colors.white,
          onPressed: () {
            // Navigate to chat
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => ChatPage(friend: sender)),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = FriendsListPage();
        break;
      case 1:
        page = ChatsPage();
        break;
      case 2:
        page = BluetoothPage();
        break;
      default:
        page = Text('Unknown');
    }

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
                    NavigationRailDestination(
                      icon: Icon(Icons.people),
                      label: Text('Friends'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.chat),
                      label: Text('Chats'),
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
      },
    );
  }
}

// ==================== Friends List Page ====================

class FriendsListPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();
    final friends = coordinator.friends;

    return Scaffold(
      appBar: AppBar(
        title: Text('Friends'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: friends.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No friends yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Go to Bluetooth to discover and pair with nearby users',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: friends.length,
              itemBuilder: (context, index) {
                final friend = friends[index];
                final isInRange = coordinator.isFriendInRange(friend);

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: Text(
                            friend.displayName[0].toUpperCase(),
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        // In-range indicator (green dot)
                        if (isInRange)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(friend.displayName)),
                        if (friend.isVerified) ...[
                          SizedBox(width: 4),
                          Icon(Icons.verified, color: Colors.green, size: 16),
                        ],
                        if (isInRange) ...[
                          SizedBox(width: 4),
                          Icon(
                            Icons.bluetooth_connected,
                            color: Colors.blue,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          '${friend.peerIdHex.substring(0, 16)}...',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        if (isInRange) ...[
                          SizedBox(width: 8),
                          Text(
                            'In Range',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.chat, color: Colors.blue),
                          onPressed: () => _openChat(context, friend),
                          tooltip: 'Open Chat',
                        ),
                        IconButton(
                          icon: Icon(Icons.person_remove, color: Colors.red),
                          onPressed: () =>
                              _confirmRemoveFriend(context, friend),
                          tooltip: 'Remove Friend',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _openChat(BuildContext context, Peer friend) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => ChatPage(friend: friend)));
  }

  void _confirmRemoveFriend(BuildContext context, Peer friend) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Friend'),
        content: Text(
          'Are you sure you want to remove ${friend.displayName} from your friends list? This will also disconnect the Bluetooth connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final coordinator = context.read<AppCoordinator>();
              coordinator.removeFriend(friend);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ==================== Chats Page ====================

class ChatsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();
    final friends = coordinator.friends;

    // Build chat summaries sorted by most recent message
    final chatSummaries = <_ChatSummary>[];
    for (final friend in friends) {
      final messages = coordinator.getChat(friend);
      final lastMessage = messages.isNotEmpty ? messages.last : null;
      chatSummaries.add(
        _ChatSummary(
          friend: friend,
          lastMessage: lastMessage,
          lastMessageTime: lastMessage?.timestamp,
        ),
      );
    }

    // Sort by most recent message (chats with messages first, then by time)
    chatSummaries.sort((a, b) {
      if (a.lastMessageTime == null && b.lastMessageTime == null) {
        return a.friend.displayName.compareTo(b.friend.displayName);
      }
      if (a.lastMessageTime == null) return 1;
      if (b.lastMessageTime == null) return -1;
      return b.lastMessageTime!.compareTo(a.lastMessageTime!);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Chats'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: chatSummaries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No chats yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add friends to start chatting',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: chatSummaries.length,
              itemBuilder: (context, index) {
                final summary = chatSummaries[index];
                return _ChatListTile(summary: summary);
              },
            ),
    );
  }
}

class _ChatSummary {
  final Peer friend;
  final Message? lastMessage;
  final DateTime? lastMessageTime;

  _ChatSummary({required this.friend, this.lastMessage, this.lastMessageTime});
}

class _ChatListTile extends StatelessWidget {
  final _ChatSummary summary;

  const _ChatListTile({required this.summary});

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();
    final friend = summary.friend;
    final lastMessage = summary.lastMessage;
    final isInRange = coordinator.isFriendInRange(friend);
    final hasUnread = coordinator.hasUnreadMessages(friend);
    final unreadCount = coordinator.getUnreadCount(friend);

    // Format time
    String timeStr = '';
    if (lastMessage != null) {
      final now = DateTime.now();
      final messageDate = lastMessage.timestamp;
      if (now.year == messageDate.year &&
          now.month == messageDate.month &&
          now.day == messageDate.day) {
        // Today - show time
        timeStr =
            '${messageDate.hour.toString().padLeft(2, '0')}:${messageDate.minute.toString().padLeft(2, '0')}';
      } else if (now.difference(messageDate).inDays < 7) {
        // This week - show day name
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        timeStr = days[messageDate.weekday - 1];
      } else {
        // Older - show date
        timeStr = '${messageDate.day}/${messageDate.month}/${messageDate.year}';
      }
    }

    // Format last message preview
    String messagePreview = 'No messages yet';
    bool isSentByMe = false;
    if (lastMessage != null) {
      isSentByMe = _bytesEqual(lastMessage.senderId, coordinator.myPeerId);
      messagePreview = lastMessage.content;
      // Truncate to first line and add ellipsis if needed
      final firstLineEnd = messagePreview.indexOf('\n');
      if (firstLineEnd != -1) {
        messagePreview = '${messagePreview.substring(0, firstLineEnd)}...';
      }
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => ChatPage(friend: friend)),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    friend.displayName[0].toUpperCase(),
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
                // In-range indicator (green dot)
                if (isInRange)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              friend.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            if (friend.isVerified) ...[
                              SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                color: Colors.green,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        timeStr,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      if (lastMessage != null && isSentByMe) ...[
                        Icon(
                          _getStatusIcon(lastMessage.status),
                          size: 16,
                          color: _getStatusColor(lastMessage.status),
                        ),
                        SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          messagePreview,
                          style: TextStyle(
                            color: hasUnread ? Colors.black87 : Colors.grey.shade600,
                            fontSize: 14,
                            fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread && unreadCount > 0) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unreadCount.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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

  IconData _getStatusIcon(int status) {
    switch (status) {
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

  Color _getStatusColor(int status) {
    switch (status) {
      case MessageStatus.pending:
        return Colors.grey;
      case MessageStatus.sent:
        return Colors.green;  // Green single checkmark when sent
      case MessageStatus.delivered:
        return Colors.green;  // Green double checkmark when delivered
      case MessageStatus.read:
        return Colors.blue;   // Blue double checkmark when read
      default:
        return Colors.grey;
    }
  }
}

// ==================== Bluetooth Page ====================

class BluetoothPage extends StatefulWidget {
  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  @override
  void initState() {
    super.initState();

    // Setup friend request callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinator = context.read<AppCoordinator>();
      coordinator.onFriendRequestReceived = _handleFriendRequest;
    });
  }

  void _handleFriendRequest(Peer requester) {
    showDialog(
      context: context,
      builder: (context) => FriendRequestDialog(requester: requester),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Nearby Devices'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          // Status indicators
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                // Scanning indicator
                if (coordinator.isScanning)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 4),
                        Text('Scanning', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                // Advertising indicator
                if (coordinator.isAdvertising)
                  Icon(Icons.broadcast_on_home, color: Colors.green, size: 20),
              ],
            ),
          ),
          // Privacy level indicator (tappable to open settings)
          ActionChip(
            label: Text(coordinator.privacyLevelName),
            avatar: Icon(Icons.shield, size: 18),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => SettingsPage()),
              );
            },
          ),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Status banner
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: coordinator.isScanning ? Colors.blue.shade50 : Colors.grey.shade100,
            child: Row(
              children: [
                Icon(
                  coordinator.isScanning ? Icons.radar : Icons.bluetooth,
                  size: 16,
                  color: coordinator.isScanning ? Colors.blue : Colors.grey,
                ),
                SizedBox(width: 8),
                Text(
                  coordinator.isScanning 
                    ? 'Scanning for nearby Grassroots devices...'
                    : 'Paused - will resume shortly',
                  style: TextStyle(
                    fontSize: 13,
                    color: coordinator.isScanning ? Colors.blue.shade700 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // Discovered devices (filtered to compatible only)
          Expanded(
            child: coordinator.scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No Grassroots devices found',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Make sure other devices are running the app',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: coordinator.scanResults.length,
                    itemBuilder: (context, index) {
                      final result = coordinator.scanResults[index];
                      final deviceName =
                          result.advertisement.name ?? 'Unknown Device';
                      final deviceUuid = result.peripheral.uuid.toString();

                      // Check if already friends by matching service UUID
                      Peer? matchedFriend;
                      for (final friend in coordinator.friends) {
                        final friendServiceUUID = friend.deriveServiceUUID().toLowerCase();
                        for (final uuid in result.advertisement.serviceUUIDs) {
                          if (uuid.toString().toLowerCase() == friendServiceUUID) {
                            matchedFriend = friend;
                            break;
                          }
                        }
                        if (matchedFriend != null) break;
                      }
                      final isFriend = matchedFriend != null;
                      
                      // Check if friend request is pending
                      final isPending = coordinator.isPendingFriendRequest(deviceUuid);

                      return Opacity(
                        opacity: isPending ? 0.5 : 1.0,
                        child: ListTile(
                          title: Text(deviceName),
                          subtitle: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  deviceUuid,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isPending)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    'Request sent',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${result.rssi} dBm'),
                              SizedBox(width: 8),
                              if (isFriend)
                                ElevatedButton.icon(
                                  onPressed: () => _confirmRemoveFriend(context, matchedFriend!),
                                  icon: Icon(Icons.person_remove, size: 16),
                                  label: Text('Remove'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                )
                              else if (isPending)
                                ElevatedButton.icon(
                                  onPressed: null,
                                  icon: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  label: Text('Pending'),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: () => _sendFriendRequest(result),
                                  icon: Icon(Icons.person_add, size: 16),
                                  label: Text('Add Friend'),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _sendFriendRequest(dynamic deviceArgs) async {
    final coordinator = context.read<AppCoordinator>();
    await coordinator.sendFriendRequest(deviceArgs);
  }

  void _confirmRemoveFriend(BuildContext context, Peer friend) {
    final coordinator = context.read<AppCoordinator>();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Friend'),
        content: Text(
          'Are you sure you want to remove ${friend.displayName} from your friends list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              coordinator.removeFriend(friend);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text('${friend.displayName} removed from friends'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Remove'),
          ),
        ],
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
  late final AppCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    // Set active chat and mark messages as read when chat is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _coordinator = context.read<AppCoordinator>();
      _coordinator.setActiveChat(widget.friend);
      _coordinator.markMessagesAsRead(widget.friend);
    });
  }

  @override
  void dispose() {
    // Clear active chat when leaving - use stored reference since context may be invalid
    _coordinator.setActiveChat(null);
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

  const _MessageBubble({required this.message, required this.isSentByMe});

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
            Text(message.content, style: TextStyle(fontSize: 16)),
            SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
                if (isSentByMe) ...[
                  SizedBox(width: 4),
                  Icon(_getStatusIcon(), size: 12, color: _getStatusColor()),
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
        return Colors.green;  // Green single checkmark when sent
      case MessageStatus.delivered:
        return Colors.green;  // Green double checkmark when delivered
      case MessageStatus.read:
        return Colors.blue;   // Blue double checkmark when read
      default:
        return Colors.grey;
    }
  }
}
