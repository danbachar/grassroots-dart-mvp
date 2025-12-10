import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

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
          create: (context) => AppCoordinator(),
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
    super.initState();
    // Initialize BLE permissions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinator = context.read<AppCoordinator>();
      coordinator.initialize();
      
      // Setup notification callback for incoming messages
      coordinator.onMessageReceived = _handleIncomingMessage;

      // Setup notification callback for friend acceptance
      coordinator.onFriendAdded = _handleFriendAdded;

      // Setup notification callback for incoming friend requests
      coordinator.onFriendRequestReceived = _handleFriendRequest;
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

  void _handleFriendRequest(Peer requester) {
    print("Showing dialog for friend request from ${requester.displayName}");
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_add, color: Colors.blue),
            SizedBox(width: 12),
            Text('Friend Request'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${requester.displayName} wants to be your friend',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(
                      requester.displayName[0].toUpperCase(),
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          requester.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Nearby peer',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              final coordinator = context.read<AppCoordinator>();
              coordinator.rejectFriendRequest(requester);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Friend request from ${requester.displayName} declined'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey,
            ),
            child: Text('Decline'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              final coordinator = context.read<AppCoordinator>();
              coordinator.acceptFriendRequest(requester);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 12),
                      Text('You and ${requester.displayName} are now friends!'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            },
            icon: Icon(Icons.check),
            label: Text('Accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
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
        page = NearbyPeersPage();
        // break;
      case 1:
        page = FriendsPage();
        // break;
      case 2:
        page = ChatsPage();
        // break;
      case 3:
        page = BluetoothPage();
        // break;
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
                      label: Text('Nearby'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.group),
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

// ==================== Nearby Peers Page ====================

class NearbyPeersPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();
    final nearbyPeers = coordinator.nearbyPeers;

    return Scaffold(
      appBar: AppBar(
        title: Text('Nearby Peers'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          // Refresh button
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: 'Clear and rescan',
            onPressed: () {
              coordinator.clearAndRescan();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Rescanning for nearby devices...'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          // Scanning indicator
          if (coordinator.isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Scanning...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      body: nearbyPeers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No nearby Grassroots devices',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Make sure other devices are running the app',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  if (coordinator.isScanning)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Scanning for devices...'),
                      ],
                    ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: nearbyPeers.length,
              itemBuilder: (context, index) {
                final peer = nearbyPeers[index];

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: Text(
                            peer.displayName[0].toUpperCase(),
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        // In-range indicator (always green since these are nearby peers)
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
                        Expanded(
                          child: Row(
                            children: [
                              Text(peer.displayName),
                              if (_isNearbyPeerFriend(coordinator, peer)) ...[
                                SizedBox(width: 6),
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.bluetooth_connected,
                          color: Colors.blue,
                          size: 16,
                        ),
                      ],
                    ),
                    subtitle: Text(
                      _isNearbyPeerFriend(coordinator, peer)
                          ? 'Friend • In Range'
                          : 'In Range',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: _buildActionButton(context, coordinator, peer),
                  ),
                );
              },
            ),
    );
  }

  /// Check if a nearby peer is already a friend by comparing service UUIDs
  bool _isNearbyPeerFriend(AppCoordinator coordinator, Peer peer) {
    final peripheralId = peer.peripheral?.uuid.toString();
    if (peripheralId == null) return false;

    // Check if any friend's service UUID matches this peer's advertised services
    for (final friend in coordinator.friends) {
      final friendServiceUUID = friend.deriveServiceUUID().toLowerCase();

      // Look up in scan results to get advertised services
      for (final scanResult in coordinator.scanResults) {
        if (scanResult.peripheral.uuid.toString() == peripheralId) {
          for (final uuid in scanResult.advertisement.serviceUUIDs) {
            if (uuid.toString().toLowerCase() == friendServiceUUID) {
              return true;
            }
          }
          break;
        }
      }
    }

    return false;
  }

  /// Build action button based on peer's friendship status
  Widget _buildActionButton(BuildContext context, AppCoordinator coordinator, Peer peer) {
    final peripheralId = peer.peripheral?.uuid.toString();
    final isFriend = _isNearbyPeerFriend(coordinator, peer);

    if (isFriend) {
      // Already friends - show chat button
      return IconButton(
        icon: Icon(Icons.chat, color: Colors.blue),
        onPressed: () => _openChat(context, peer),
        tooltip: 'Open Chat',
      );
    }

    // Check if there's a pending request for this peer
    final isPending = peripheralId != null && coordinator.isPendingFriendRequest(peripheralId);

    if (isPending) {
      // Pending request - show waiting indicator
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
            ),
            SizedBox(width: 8),
            Text('Pending', style: TextStyle(color: Colors.orange, fontSize: 12)),
          ],
        ),
      );
    }

    // Not a friend and no pending request - show add friend button
    return ElevatedButton.icon(
      onPressed: () => _sendFriendRequest(context, coordinator, peer),
      icon: Icon(Icons.person_add, size: 18),
      label: Text('Add Friend'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  /// Send a friend request to a nearby peer
  Future<void> _sendFriendRequest(BuildContext context, AppCoordinator coordinator, Peer peer) async {
    final peripheralId = peer.peripheral?.uuid.toString();
    if (peripheralId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Device not available')),
      );
      return;
    }

    // Find the DiscoveredEventArgs for this peer
    DiscoveredEventArgs? deviceArgs;
    for (final result in coordinator.scanResults) {
      if (result.peripheral.uuid.toString() == peripheralId) {
        deviceArgs = result;
        break;
      }
    }

    if (deviceArgs == null) {
      // Try allDiscoveredDevices as fallback
      for (final result in coordinator.allDiscoveredDevices) {
        if (result.peripheral.uuid.toString() == peripheralId) {
          deviceArgs = result;
          break;
        }
      }
    }

    if (deviceArgs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Device not found in scan results')),
      );
      return;
    }

    try {
      await coordinator.sendFriendRequest(deviceArgs);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request sent to ${peer.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send friend request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openChat(BuildContext context, Peer peer) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ChatPage(friend: peer)),
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

// ==================== Friends Page ====================

class FriendsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();
    final friends = coordinator.friends;

    return Scaffold(
      appBar: AppBar(
        title: Text('Friends (${friends.length})'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: friends.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No friends yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Send friend requests from the Nearby tab',
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
                    title: Text(
                      friend.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      isInRange ? 'In Range' : 'Not in range',
                      style: TextStyle(
                        color: isInRange ? Colors.green : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Chat button
                        IconButton(
                          icon: Icon(Icons.chat, color: Colors.blue),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ChatPage(friend: friend),
                              ),
                            );
                          },
                          tooltip: 'Open Chat',
                        ),
                        // Delete button
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _showDeleteFriendDialog(context, coordinator, friend),
                          tooltip: 'Delete Friend',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showDeleteFriendDialog(BuildContext context, AppCoordinator coordinator, Peer friend) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 12),
            Text('Delete Friend?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to remove ${friend.displayName} from your friends list?',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will delete your chat history with this friend.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await coordinator.removeFriend(friend);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${friend.displayName} removed from friends'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Delete'),
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
    final nearbyPeers = coordinator.nearbyPeers;

    // Build chat summaries sorted by most recent message
    final chatSummaries = <_ChatSummary>[];
    for (final peer in nearbyPeers) {
      final messages = coordinator.getChat(peer);
      final lastMessage = messages.isNotEmpty ? messages.last : null;
      chatSummaries.add(
        _ChatSummary(
          friend: peer,
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
    // Nearby peers are always in range by definition
    final isInRange = coordinator.isNearbyPeer(friend.peripheral?.uuid.toString() ?? '');
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
      isSentByMe = _bytesEqual(lastMessage.senderId, coordinator.myPublicKey);
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
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Status'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
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
          // Status cards
          Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bluetooth Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  _StatusRow(
                    icon: coordinator.isScanning ? Icons.radar : Icons.search_off,
                    label: 'Scanning',
                    value: coordinator.isScanning ? 'Active' : 'Paused',
                    color: coordinator.isScanning ? Colors.green : Colors.grey,
                  ),
                  SizedBox(height: 8),
                  _StatusRow(
                    icon: coordinator.isAdvertising ? Icons.broadcast_on_home : Icons.broadcast_on_home_outlined,
                    label: 'Advertising',
                    value: coordinator.isAdvertising ? 'Active' : 'Off',
                    color: coordinator.isAdvertising ? Colors.green : Colors.grey,
                  ),
                  SizedBox(height: 8),
                  _StatusRow(
                    icon: Icons.devices,
                    label: 'Nearby Peers',
                    value: '${coordinator.nearbyPeers.length}',
                    color: Colors.blue,
                  ),
                ],
              ),
            ),
          ),
          
          // Info text
          // Padding(
          //   padding: EdgeInsets.symmetric(horizontal: 16),
          //   child: Card(
          //     color: Colors.blue.shade50,
          //     child: Padding(
          //       padding: EdgeInsets.all(16),
          //       child: Row(
          //         children: [
          //           Icon(Icons.info_outline, color: Colors.blue),
          //           SizedBox(width: 12),
          //           Expanded(
          //             child: Text(
          //               'Grassroots devices are automatically discovered and appear in the Nearby tab. No manual pairing required!',
          //               style: TextStyle(color: Colors.blue.shade700),
          //             ),
          //           ),
          //         ],
          //       ),
          //     ),
          //   ),
          // ),
          
          // Raw discovered devices (for debugging)
          Expanded(
            child: coordinator.scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bluetooth_searching, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          coordinator.isScanning 
                            ? 'Scanning for devices...'
                            : 'Scan paused',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Raw Discovered Devices (${coordinator.scanResults.length})',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: coordinator.scanResults.length,
                          itemBuilder: (context, index) {
                            final result = coordinator.scanResults[index];
                            final deviceName = result.advertisement.name ?? 'Unknown';
                            final deviceUuid = result.peripheral.uuid.toString();

                            return ListTile(
                              leading: Icon(Icons.bluetooth, color: Colors.blue),
                              title: Text(deviceName),
                              subtitle: Text(
                                deviceUuid,
                                style: TextStyle(fontSize: 10),
                              ),
                              trailing: Text('${result.rssi} dBm'),
                            );
                          },
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

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: 12),
        Text(label),
        Spacer(),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w500, color: color),
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
                        coordinator.myPublicKey,
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
