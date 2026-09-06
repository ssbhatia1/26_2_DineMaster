import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';
import '../main.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'System Settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          FutureBuilder<SharedPreferences>(
            future: SharedPreferences.getInstance(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final username = snapshot.data!.getString('username') ?? 'User';
                final role = snapshot.data!.getString('role') ?? 'Role';
                return Card(
                  elevation: 0,
                  color: Colors.deepPurple.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple,
                      child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Role: $role'),
                    trailing: IconButton(
                      icon: const Icon(Icons.logout, color: Colors.red),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        context.go('/login');
                      },
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 16),
          _buildSettingsTile(
            context,
            Icons.restaurant_menu,
            'Menu Management',
            'Edit products, categories, and prices',
            () => context.go('/dashboard/products_manage'),
          ),
          _buildSettingsTile(
            context,
            Icons.people,
            'User Management',
            'Manage employees and permissions',
            () => context.go('/dashboard/user_management'),
          ),
          _buildSettingsTile(
            context,
            Icons.print,
            'Printer Settings',
            'Configure thermal printers and KOT routing',
            () => context.go('/dashboard/printer_settings'),
          ),
          _buildSettingsTile(
            context,
            Icons.palette,
            'Theme Settings',
            'Select light mode, dark mode, or system default',
            () => _showThemeSelectionDialog(context),
          ),
          _buildSettingsTile(
            context,
            Icons.percent,
            'GST Slabs Scale',
            'Configure the available GST percentage options',
            () => _showGstScaleDialog(context),
          ),
          _buildSettingsTile(
            context,
            Icons.sync,
            'Network & Synchronization',
            'Configure host server IP and multi-device sync',
            () => _showNetworkSettingsDialog(context),
          ),
          _buildSettingsTile(
            context,
            Icons.security,
            'Backup & Restore',
            'Manage database backups',
            () => _showBackupRestoreDialog(context),
          ),
          _buildSettingsTile(
            context,
            Icons.info,
            'About System',
            'Version 1.0.0',
            () => _showAboutDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      color: isDark ? Colors.grey.shade900 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.deepPurple.withAlpha(25),
          child: Icon(icon, color: Colors.deepPurple),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white60 : Colors.black45),
        onTap: onTap,
      ),
    );
  }

  void _showThemeSelectionDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString('theme_mode') ?? 'system';

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Theme Mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('System Default'),
              value: 'system',
              groupValue: current,
              onChanged: (val) async {
                if (val != null) {
                  await prefs.setString('theme_mode', val);
                  themeNotifier.value = ThemeMode.system;
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Light Theme'),
              value: 'light',
              groupValue: current,
              onChanged: (val) async {
                if (val != null) {
                  await prefs.setString('theme_mode', val);
                  themeNotifier.value = ThemeMode.light;
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Dark Theme'),
              value: 'dark',
              groupValue: current,
              onChanged: (val) async {
                if (val != null) {
                  await prefs.setString('theme_mode', val);
                  themeNotifier.value = ThemeMode.dark;
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showGstScaleDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final rawScale = prefs.getString('gst_scale') ?? '0.0,5.0,12.0,18.0,28.0';
    
    // Parse to list
    List<double> scale = rawScale
        .split(',')
        .map((s) => double.tryParse(s.trim()) ?? -1.0)
        .where((val) => val >= 0.0)
        .toList();
    scale.sort();

    final rateController = TextEditingController();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.percent, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Text('Edit GST Slabs Scale'),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Define the GST rate slabs that can be assigned to food products in Menu Management.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: rateController,
                            decoration: const InputDecoration(
                              labelText: 'New GST Rate (%)',
                              hintText: 'e.g. 18.0',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final val = double.tryParse(rateController.text.trim());
                            if (val != null && val >= 0.0 && val <= 100.0) {
                              if (!scale.contains(val)) {
                                setStateDialog(() {
                                  scale.add(val);
                                  scale.sort();
                                });
                              }
                              rateController.clear();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid rate between 0 and 100')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          ),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Active GST Slabs:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: scale.map((rate) {
                        return InputChip(
                          label: Text('$rate%'),
                          onDeleted: () {
                            setStateDialog(() {
                              scale.remove(rate);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (scale.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('GST scale cannot be empty. Add at least one slab.')),
                      );
                      return;
                    }
                    
                    final serialized = scale.join(',');
                    await prefs.setString('gst_scale', serialized);
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('GST Scale saved successfully!')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                  child: const Text('Save Slabs'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMockDialog(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('This feature is currently under development.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About System'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dine Master ERP & POS'),
            Text('Version: 1.0.0'),
            Text('Developed by: Antigravity'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showBackupRestoreDialog(BuildContext context) async {
    final String homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    final backupDir = Directory(join(homeDir, 'Downloads', 'NexodineBackups'));
    List<File> backups = [];

    if (await backupDir.exists()) {
      try {
        backups = backupDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.db'))
            .toList();
        // Sort newest first
        backups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      } catch (e) {
        print('Error reading backups directory: $e');
      }
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.backup, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Text('Database Backup & Restore'),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Save a copy of your database to Downloads/NexodineBackups, or restore from a previous session.'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final path = await DatabaseHelper.instance.backupDatabase();
                          // Reload files list
                          List<File> updatedBackups = [];
                          if (await backupDir.exists()) {
                            updatedBackups = backupDir
                                .listSync()
                                .whereType<File>()
                                .where((file) => file.path.endsWith('.db'))
                                .toList();
                            updatedBackups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
                          }
                          setStateDialog(() {
                            backups = updatedBackups;
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Backup created successfully: $path')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error creating backup: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Create New Backup Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Restore Point History:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    backups.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Text('No previous local backups found.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                          )
                        : SizedBox(
                            height: 180,
                            child: ListView.builder(
                              itemCount: backups.length,
                              itemBuilder: (context, index) {
                                final file = backups[index];
                                final name = basename(file.path);
                                final modified = file.lastModifiedSync();
                                final size = file.lengthSync();

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  child: ListTile(
                                    title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      '${DateFormat('yyyy-MM-dd hh:mm a').format(modified)} | ${(size / 1024).toStringAsFixed(1)} KB',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: ElevatedButton.icon(
                                      onPressed: () => _confirmRestore(context, file.path),
                                      icon: const Icon(Icons.restore, size: 14),
                                      label: const Text('Restore', style: TextStyle(fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange.shade800,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmRestore(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Restoration'),
        content: const Text(
          'WARNING: Restoring will overwrite all current tables, orders, KOTs, and settings with the selected backup data. This action cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close confirm
              Navigator.pop(context); // Close backup dialog
              try {
                await DatabaseHelper.instance.restoreDatabase(path);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Database successfully restored! Restarting app/DB context.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error restoring: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Overwrite & Restore'),
          ),
        ],
      ),
    );
  }

  void _showNetworkSettingsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    bool isServer = prefs.getBool('is_server') ?? true;
    final ipController = TextEditingController(text: prefs.getString('server_ip') ?? '');
    
    String localIp = 'Detecting...';
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        localIp = interfaces.first.addresses.first.address;
      } else {
        localIp = 'Not found';
      }
    } catch (_) {
      localIp = 'Error';
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.sync, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Text('Network & Sync Settings'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Run as Server / Host', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Only ONE machine (usually cashier PC) should run as Server.'),
                    value: isServer,
                    activeColor: Colors.deepPurple,
                    onChanged: (val) {
                      setStateDialog(() {
                        isServer = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (isServer) ...[
                    Card(
                      color: Colors.deepPurple.shade50,
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.deepPurple),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This device is the master host. Other devices (waiter/chef) can connect using IP: $localIp',
                                style: const TextStyle(color: Colors.deepPurple, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: ipController,
                      decoration: const InputDecoration(
                        labelText: 'Host Server IP Address',
                        hintText: 'e.g. 192.168.1.100',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.computer),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final ip = ipController.text.trim();
                        if (ip.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter an IP address')),
                          );
                          return;
                        }
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Testing connection...')),
                        );
                        
                        final client = HttpClient();
                        client.connectionTimeout = const Duration(seconds: 3);
                        try {
                          final request = await client.getUrl(Uri.parse('http://$ip:8082/'));
                          final response = await request.close();
                          if (response.statusCode == 200) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Connection SUCCESSFUL! Port 8082 is reachable.')),
                              );
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Connection failed. Server returned status ${response.statusCode}')),
                              );
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Connection failed: $e')),
                            );
                          }
                        } finally {
                          client.close();
                        }
                      },
                      icon: const Icon(Icons.network_check),
                      label: const Text('Test Connection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await prefs.setBool('is_server', isServer);
                    if (!isServer) {
                      await prefs.setString('server_ip', ipController.text.trim());
                    }
                    
                    // Reinitialize connection
                    await SyncService.instance.initConnection();
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Network settings saved successfully!')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                  child: const Text('Save & Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
