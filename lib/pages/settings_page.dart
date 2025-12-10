import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_coordinator.dart';
import '../protocol/constants.dart';

/// Settings page for configuring privacy level and other preferences
class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        children: [
          // Privacy Level Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy Level',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: 8),
                Text(
                  'Choose how you want to interact with others',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          // Privacy Level Options
          _PrivacyLevelOption(
            level: PrivacyLevel.silent,
            title: 'Silent',
            description:
                'No advertising. You can only connect to known friends. Does not relay messages for others.',
            icon: Icons.visibility_off,
            iconColor: Colors.grey,
          ),
          Divider(height: 1),

          _PrivacyLevelOption(
            level: PrivacyLevel.visible,
            title: 'Visible',
            description:
                'Advertise with your UUID. Friends can discover you. You will relay messages for friends and friends-of-friends.',
            icon: Icons.bluetooth,
            iconColor: Colors.blue,
          ),
          Divider(height: 1),

          _PrivacyLevelOption(
            level: PrivacyLevel.open,
            title: 'Open',
            description:
                'Advertise with your name. Anyone nearby can see you and send friend requests based on proximity.',
            icon: Icons.public,
            iconColor: Colors.orange,
          ),
          Divider(height: 1),

          _PrivacyLevelOption(
            level: PrivacyLevel.social,
            title: 'Social',
            description:
                'Share your friend list (as Bloom filter). Enables introductions through mutual friends.',
            icon: Icons.people,
            iconColor: Colors.green,
          ),

          // Info Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'Current Settings',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _InfoRow(
                      label: 'Privacy Level',
                      value: coordinator.privacyLevelName,
                    ),
                    _InfoRow(
                      label: 'Advertising',
                      value: coordinator.isAdvertising ? 'Active' : 'Inactive',
                    ),
                    _InfoRow(
                      label: 'Scanning',
                      value: coordinator.isScanning ? 'Active' : 'Inactive',
                    ),
                    _InfoRow(
                      label: 'Friends',
                      value: '${coordinator.friends.length}',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // User Identity Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Identity',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Editable Display Name
                        Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                'Display Name:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(coordinator.myDisplayName),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit, size: 20),
                              onPressed: () => _showEditNameDialog(context, coordinator),
                              tooltip: 'Edit display name',
                            ),
                          ],
                        ),
                        _InfoRow(
                          label: 'Public Key',
                          value: _formatPeerId(coordinator.myPublicKey),
                          monospace: true,
                        ),
                        _InfoRow(
                          label: 'Service UUID',
                          value: coordinator.myServiceUUID.isNotEmpty 
                              ? coordinator.myServiceUUID 
                              : 'Not generated',
                          monospace: true,
                        ),
                        SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _showRegenerateDialog(context, coordinator),
                            icon: Icon(Icons.refresh),
                            label: Text('Recreate Service UUID'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPeerId(List<int> peerId) {
    return peerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  void _showEditNameDialog(BuildContext context, AppCoordinator coordinator) {
    final controller = TextEditingController(text: coordinator.myDisplayName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Display Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter your name',
            border: OutlineInputBorder(),
          ),
          maxLength: 30,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              coordinator.setDisplayName(value);
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                coordinator.setDisplayName(controller.text);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Display name updated'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
  
  void _showRegenerateDialog(BuildContext context, AppCoordinator coordinator) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Regenerate Service UUID?'),
          ],
        ),
        content: Text(
          'This will generate a new identity for your device. '
          'Other devices will see you as a new peer.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await coordinator.regenerateIdentity();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Identity regenerated successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text('Regenerate'),
          ),
        ],
      ),
    );
  }
}

/// Widget for a single privacy level option
class _PrivacyLevelOption extends StatelessWidget {
  final int level;
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;

  const _PrivacyLevelOption({
    required this.level,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<AppCoordinator>();
    final isSelected = coordinator.privacyLevel == level;

    return InkWell(
      onTap: () {
        coordinator.setPrivacyLevel(level);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Privacy level changed to $title'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor),
            ),
            SizedBox(width: 16),

            // Title and Description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),

            // Radio indicator
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            else
              Icon(
                Icons.radio_button_unchecked,
                color: Colors.grey,
              ),
          ],
        ),
      ),
    );
  }
}

/// Widget for displaying an info row
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: monospace ? 'monospace' : null,
                fontSize: monospace ? 11 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
