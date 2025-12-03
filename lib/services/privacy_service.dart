import '../protocol/constants.dart';

/// Manages privacy level settings and behaviors
class PrivacyService {
  int _privacyLevel = PrivacyLevel.visible; // Default to Level 2

  /// Get current privacy level
  int get privacyLevel => _privacyLevel;

  /// Set privacy level (1-4)
  void setPrivacyLevel(int level) {
    if (level < PrivacyLevel.silent || level > PrivacyLevel.social) {
      throw ArgumentError('Privacy level must be 1-4');
    }
    _privacyLevel = level;
  }

  /// Check if should advertise based on privacy level
  bool get shouldAdvertise {
    return _privacyLevel >= PrivacyLevel.visible;
  }

  /// Check if should scan for all devices (or just friends)
  bool get shouldScanAll {
    return _privacyLevel >= PrivacyLevel.open;
  }

  /// Check if should share display name in advertisement
  bool get shouldAdvertiseName {
    return _privacyLevel >= PrivacyLevel.open;
  }

  /// Check if should share friend list
  bool get shouldShareFriendList {
    return _privacyLevel >= PrivacyLevel.social;
  }

  /// Check if should relay messages for friends/friends-of-friends
  bool get shouldRelayMessages {
    return _privacyLevel >= PrivacyLevel.visible;
  }

  /// Check if should accept friend requests from strangers in proximity
  bool get shouldAcceptProximityRequests {
    return _privacyLevel >= PrivacyLevel.open;
  }

  /// Get privacy level name
  String get privacyLevelName {
    switch (_privacyLevel) {
      case PrivacyLevel.silent:
        return 'Silent';
      case PrivacyLevel.visible:
        return 'Visible';
      case PrivacyLevel.open:
        return 'Open';
      case PrivacyLevel.social:
        return 'Social';
      default:
        return 'Unknown';
    }
  }

  /// Get privacy level description
  String get privacyLevelDescription {
    switch (_privacyLevel) {
      case PrivacyLevel.silent:
        return 'No advertising. Can only connect to known friends. No message relay.';
      case PrivacyLevel.visible:
        return 'Advertise with UUID. Can be discovered by friends. Relay messages.';
      case PrivacyLevel.open:
        return 'Advertise with name. Can be found by strangers nearby.';
      case PrivacyLevel.social:
        return 'Share friend list for introductions. Enable social discovery.';
      default:
        return '';
    }
  }

  /// Get list of all privacy levels with descriptions
  List<Map<String, dynamic>> getAllPrivacyLevels() {
    return [
      {
        'level': PrivacyLevel.silent,
        'name': 'Silent',
        'description': 'No advertising. Can only connect to known friends. No message relay.',
      },
      {
        'level': PrivacyLevel.visible,
        'name': 'Visible',
        'description': 'Advertise with UUID. Can be discovered by friends. Relay messages.',
      },
      {
        'level': PrivacyLevel.open,
        'name': 'Open',
        'description': 'Advertise with name. Can be found by strangers nearby.',
      },
      {
        'level': PrivacyLevel.social,
        'name': 'Social',
        'description': 'Share friend list for introductions. Enable social discovery.',
      },
    ];
  }
}
