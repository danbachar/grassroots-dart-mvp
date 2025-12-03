import 'dart:typed_data';
import '../protocol/constants.dart';
import '../protocol/payloads.dart';
import '../protocol/packet.dart';

/// Manages packet fragmentation and reassembly
class FragmentationService {
  // Reassembly buffers: messageId -> {fragmentIndex -> data}
  final Map<int, Map<int, Uint8List>> _fragmentBuffers = {};
  final Map<int, int> _fragmentCounts = {}; // messageId -> totalFragments
  final Map<int, DateTime> _fragmentTimestamps = {}; // messageId -> start time

  /// Fragment a large packet into multiple smaller packets
  /// Always returns fragments, even if the packet fits in one fragment
  List<Packet> fragmentPacket(Packet packet, int maxFragmentSize) {
    final serialized = packet.serialize();

    // Calculate how many fragments we need
    // Reserve 4 bytes for fragment header
    final dataPerFragment = maxFragmentSize - 4;
    final totalFragments = (serialized.length / dataPerFragment).ceil();

    if (totalFragments > Limits.maxFragments) {
      throw ArgumentError('Packet too large: would require $totalFragments fragments');
    }

    // Generate random message ID for this fragmentation
    final messageId = DateTime.now().millisecondsSinceEpoch % 65536; // 2 bytes

    final fragments = <Packet>[];

    for (int i = 0; i < totalFragments; i++) {
      final start = i * dataPerFragment;
      final end = (start + dataPerFragment < serialized.length)
          ? start + dataPerFragment
          : serialized.length;
      final fragmentData = serialized.sublist(start, end);

      // Determine fragment type
      int fragmentType;
      if (i == 0) {
        fragmentType = MessageType.fragmentStart;
      } else if (i == totalFragments - 1) {
        fragmentType = MessageType.fragmentEnd;
      } else {
        fragmentType = MessageType.fragmentContinue;
      }

      // Create fragment header
      final header = FragmentHeader(
        messageId: messageId,
        fragmentIndex: i,
        totalFragments: totalFragments,
      );

      // Create fragment payload
      final fragmentPayload = FragmentPayload(
        header: header,
        data: fragmentData,
        fragmentType: fragmentType,
      );

      // Create fragment packet
      final fragmentPacket = Packet(
        type: fragmentType,
        flags: packet.flags,
        senderId: packet.senderId,
        recipientId: packet.recipientId,
        payload: fragmentPayload.serialize(),
        ttl: packet.ttl,
      );

      fragments.add(fragmentPacket);
    }

    return fragments;
  }

  /// Process an incoming fragment
  /// Returns the reassembled packet if complete, null otherwise
  Packet? processFragment(Packet fragmentPacket) {
    if (fragmentPacket.type != MessageType.fragmentStart &&
        fragmentPacket.type != MessageType.fragmentContinue &&
        fragmentPacket.type != MessageType.fragmentEnd) {
      throw ArgumentError('Packet is not a fragment');
    }

    final fragmentPayload = FragmentPayload.deserialize(
      fragmentPacket.payload,
      fragmentPacket.type,
    );

    final header = fragmentPayload.header;
    final messageId = header.messageId;

    // Initialize buffer if first fragment
    if (header.fragmentIndex == 0) {
      _fragmentBuffers[messageId] = {};
      _fragmentCounts[messageId] = header.totalFragments;
      _fragmentTimestamps[messageId] = DateTime.now();
    }

    // Check if we have a buffer for this message
    if (!_fragmentBuffers.containsKey(messageId)) {
      // Late fragment for unknown message, ignore
      return null;
    }

    // Store fragment data
    _fragmentBuffers[messageId]![header.fragmentIndex] = fragmentPayload.data;

    // Check if we have all fragments
    if (_fragmentBuffers[messageId]!.length == _fragmentCounts[messageId]) {
      // Reassemble
      final reassembled = _reassemblePacket(messageId);

      // Clean up
      _fragmentBuffers.remove(messageId);
      _fragmentCounts.remove(messageId);
      _fragmentTimestamps.remove(messageId);

      return reassembled;
    }

    return null; // Still waiting for more fragments
  }

  /// Reassemble a complete packet from fragments
  Packet _reassemblePacket(int messageId) {
    final fragments = _fragmentBuffers[messageId]!;
    final totalFragments = _fragmentCounts[messageId]!;

    // Concatenate all fragment data in order
    final buffer = BytesBuilder();
    for (int i = 0; i < totalFragments; i++) {
      final fragmentData = fragments[i];
      if (fragmentData == null) {
        throw StateError('Missing fragment $i for message $messageId');
      }
      buffer.add(fragmentData);
    }

    // Deserialize the complete packet
    return Packet.deserialize(buffer.toBytes());
  }

  /// Clean up incomplete fragments that have timed out
  void cleanupTimedOutFragments() {
    final now = DateTime.now();
    final timedOut = <int>[];

    for (final entry in _fragmentTimestamps.entries) {
      final elapsed = now.difference(entry.value);
      if (elapsed.inMilliseconds > Timeouts.fragment) {
        timedOut.add(entry.key);
      }
    }

    for (final messageId in timedOut) {
      _fragmentBuffers.remove(messageId);
      _fragmentCounts.remove(messageId);
      _fragmentTimestamps.remove(messageId);
    }
  }

  /// Get statistics about pending reassemblies
  Map<String, dynamic> getStats() {
    return {
      'pendingReassemblies': _fragmentBuffers.length,
      'fragments': _fragmentBuffers.values
          .map((buf) => buf.length)
          .fold<int>(0, (sum, count) => sum + count),
    };
  }
}
