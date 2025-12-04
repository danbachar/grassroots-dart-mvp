import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/peer.dart';
import '../models/message.dart';

/// SQLite database service for persisting friends and chat messages
class DatabaseService {
  static Database? _database;
  static const String _databaseName = 'grassroots.db';
  static const int _databaseVersion = 1;

  // Table names
  static const String _friendsTable = 'friends';
  static const String _messagesTable = 'messages';

  /// Get the database instance (creates if not exists)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    // Friends table
    await db.execute('''
      CREATE TABLE $_friendsTable (
        peer_id TEXT PRIMARY KEY,
        noise_pk TEXT NOT NULL,
        sign_pk TEXT NOT NULL,
        display_name TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        last_seen INTEGER,
        is_verified INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE $_messagesTable (
        message_id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        recipient_id TEXT,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        status INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0,
        ttl INTEGER NOT NULL DEFAULT 3
      )
    ''');

    // Index for faster message queries by sender/recipient
    await db.execute('''
      CREATE INDEX idx_messages_sender ON $_messagesTable(sender_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_messages_recipient ON $_messagesTable(recipient_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_messages_timestamp ON $_messagesTable(timestamp)
    ''');

    print('Database tables created');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations in future versions
    print('Database upgraded from v$oldVersion to v$newVersion');
  }

  // ==================== Friends CRUD ====================

  /// Insert a new friend
  Future<void> insertFriend(Peer friend) async {
    final db = await database;
    await db.insert(
      _friendsTable,
      _peerToMap(friend),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print('Friend ${friend.displayName} saved to database');
  }

  /// Get all friends
  Future<List<Peer>> getAllFriends() async {
    final db = await database;
    final maps = await db.query(_friendsTable, orderBy: 'added_at DESC');
    return maps.map((map) => _mapToPeer(map)).toList();
  }

  /// Get a friend by peer ID
  Future<Peer?> getFriend(Uint8List peerId) async {
    final db = await database;
    final peerIdHex = _bytesToHex(peerId);
    final maps = await db.query(
      _friendsTable,
      where: 'peer_id = ?',
      whereArgs: [peerIdHex],
    );
    if (maps.isEmpty) return null;
    return _mapToPeer(maps.first);
  }

  /// Update a friend
  Future<void> updateFriend(Peer friend) async {
    final db = await database;
    await db.update(
      _friendsTable,
      _peerToMap(friend),
      where: 'peer_id = ?',
      whereArgs: [_bytesToHex(friend.peerId)],
    );
  }

  /// Update friend's last seen timestamp
  Future<void> updateFriendLastSeen(Uint8List peerId, DateTime lastSeen) async {
    final db = await database;
    await db.update(
      _friendsTable,
      {'last_seen': lastSeen.millisecondsSinceEpoch},
      where: 'peer_id = ?',
      whereArgs: [_bytesToHex(peerId)],
    );
  }

  /// Delete a friend
  Future<void> deleteFriend(Uint8List peerId) async {
    final db = await database;
    await db.delete(
      _friendsTable,
      where: 'peer_id = ?',
      whereArgs: [_bytesToHex(peerId)],
    );
    print('Friend deleted from database');
  }

  /// Check if a peer is a friend
  Future<bool> isFriend(Uint8List peerId) async {
    final friend = await getFriend(peerId);
    return friend != null;
  }

  // ==================== Messages CRUD ====================

  /// Insert a new message
  Future<void> insertMessage(Message message) async {
    final db = await database;
    await db.insert(
      _messagesTable,
      _messageToMap(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all messages
  Future<List<Message>> getAllMessages() async {
    final db = await database;
    final maps = await db.query(_messagesTable, orderBy: 'timestamp ASC');
    return maps.map((map) => _mapToMessage(map)).toList();
  }

  /// Get messages for a specific chat (between user and peer)
  Future<List<Message>> getChatMessages(
    Uint8List myPeerId,
    Uint8List friendPeerId,
  ) async {
    final db = await database;
    final myIdHex = _bytesToHex(myPeerId);
    final friendIdHex = _bytesToHex(friendPeerId);

    final maps = await db.query(
      _messagesTable,
      where: '''
        (sender_id = ? AND recipient_id = ?) OR
        (sender_id = ? AND recipient_id = ?)
      ''',
      whereArgs: [myIdHex, friendIdHex, friendIdHex, myIdHex],
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => _mapToMessage(map)).toList();
  }

  /// Get messages sent by a specific peer
  Future<List<Message>> getMessagesBySender(Uint8List senderId) async {
    final db = await database;
    final maps = await db.query(
      _messagesTable,
      where: 'sender_id = ?',
      whereArgs: [_bytesToHex(senderId)],
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => _mapToMessage(map)).toList();
  }

  /// Get messages for a specific recipient
  Future<List<Message>> getMessagesByRecipient(Uint8List recipientId) async {
    final db = await database;
    final maps = await db.query(
      _messagesTable,
      where: 'recipient_id = ?',
      whereArgs: [_bytesToHex(recipientId)],
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => _mapToMessage(map)).toList();
  }

  /// Update message status
  Future<void> updateMessageStatus(Uint8List messageId, int status) async {
    final db = await database;
    await db.update(
      _messagesTable,
      {'status': status},
      where: 'message_id = ?',
      whereArgs: [_bytesToHex(messageId)],
    );
  }

  /// Delete a message
  Future<void> deleteMessage(Uint8List messageId) async {
    final db = await database;
    await db.delete(
      _messagesTable,
      where: 'message_id = ?',
      whereArgs: [_bytesToHex(messageId)],
    );
  }

  /// Delete all messages with a peer
  Future<void> deleteMessagesWithPeer(
    Uint8List myPeerId,
    Uint8List friendPeerId,
  ) async {
    final db = await database;
    final myIdHex = _bytesToHex(myPeerId);
    final friendIdHex = _bytesToHex(friendPeerId);

    await db.delete(
      _messagesTable,
      where: '''
        (sender_id = ? AND recipient_id = ?) OR
        (sender_id = ? AND recipient_id = ?)
      ''',
      whereArgs: [myIdHex, friendIdHex, friendIdHex, myIdHex],
    );
    print('Messages with peer deleted from database');
  }

  /// Get the last message for each friend (for chat list preview)
  Future<Map<String, Message>> getLastMessagesPerChat(Uint8List myPeerId) async {
    final db = await database;
    final myIdHex = _bytesToHex(myPeerId);

    // Get all messages involving us
    final maps = await db.query(
      _messagesTable,
      where: 'sender_id = ? OR recipient_id = ?',
      whereArgs: [myIdHex, myIdHex],
      orderBy: 'timestamp DESC',
    );

    final lastMessages = <String, Message>{};

    for (final map in maps) {
      final message = _mapToMessage(map);
      
      // Determine the chat partner ID
      String partnerId;
      if (message.senderIdHex == myIdHex) {
        partnerId = message.recipientIdHex;
      } else {
        partnerId = message.senderIdHex;
      }

      // Keep only the most recent message per chat
      if (!lastMessages.containsKey(partnerId)) {
        lastMessages[partnerId] = message;
      }
    }

    return lastMessages;
  }

  // ==================== Conversion Helpers ====================

  /// Convert Peer to database map
  Map<String, dynamic> _peerToMap(Peer peer) {
    return {
      'peer_id': _bytesToHex(peer.peerId),
      'noise_pk': _bytesToHex(peer.noisePk),
      'sign_pk': _bytesToHex(peer.signPk),
      'display_name': peer.displayName,
      'added_at': peer.addedAt.millisecondsSinceEpoch,
      'last_seen': peer.lastSeen?.millisecondsSinceEpoch,
      'is_verified': peer.isVerified ? 1 : 0,
    };
  }

  /// Convert database map to Peer
  Peer _mapToPeer(Map<String, dynamic> map) {
    return Peer(
      peerId: _hexToBytes(map['peer_id'] as String),
      noisePk: _hexToBytes(map['noise_pk'] as String),
      signPk: _hexToBytes(map['sign_pk'] as String),
      displayName: map['display_name'] as String,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
      lastSeen: map['last_seen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_seen'] as int)
          : null,
      isVerified: (map['is_verified'] as int) == 1,
    );
  }

  /// Convert Message to database map
  Map<String, dynamic> _messageToMap(Message message) {
    return {
      'message_id': _bytesToHex(message.messageId),
      'sender_id': _bytesToHex(message.senderId),
      'recipient_id':
          message.recipientId != null ? _bytesToHex(message.recipientId!) : null,
      'content': message.content,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'status': message.status,
      'retry_count': message.retryCount,
      'ttl': message.ttl,
    };
  }

  /// Convert database map to Message
  Message _mapToMessage(Map<String, dynamic> map) {
    return Message(
      messageId: _hexToBytes(map['message_id'] as String),
      senderId: _hexToBytes(map['sender_id'] as String),
      recipientId: map['recipient_id'] != null
          ? _hexToBytes(map['recipient_id'] as String)
          : null,
      content: map['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      status: map['status'] as int,
      retryCount: map['retry_count'] as int,
      ttl: map['ttl'] as int,
    );
  }

  /// Convert bytes to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Close the database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
