import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../services/admin_service.dart';

/// PDPA Access / Notice & Choice — the single-user detail view. Fetching it
/// is audit-logged server-side as "view_profile" (this is deliberately the
/// only place mobile_number appears unmasked — see AdminUsersScreen's list,
/// which shows the masked version). Also surfaces consent history and a
/// DSAR export action for this user.
class AdminUserDetailScreen extends StatefulWidget {
  final String userId;
  const AdminUserDetailScreen({super.key, required this.userId});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  final _adminService = AdminService();
  late Future<AdminUser> _userFuture;
  late Future<List<ConsentLogEntry>> _consentFuture;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _userFuture = _adminService.fetchUser(widget.userId);
    _consentFuture = _adminService.fetchConsentHistory(widget.userId);
  }

  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final json = await _adminService.exportUser(widget.userId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Data Export (DSAR)'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                messenger.showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              },
              child: const Text('Copy to Clipboard'),
            ),
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Details')),
      body: FutureBuilder<AdminUser>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString().replaceFirst('Exception: ', '')),
              ),
            );
          }

          final user = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoRow(label: 'Username', value: user.username),
              _InfoRow(label: 'Email', value: user.email),
              _InfoRow(label: 'Mobile number', value: user.mobileNumber ?? '—'),
              _InfoRow(label: 'Role', value: user.role),
              _InfoRow(label: 'Account status', value: user.isActive ? 'Active' : 'Deactivated'),
              if (user.deletionRequestedAt != null)
                _InfoRow(
                  label: 'Deletion requested',
                  value: user.deletionRequestedAt!.toLocal().toString(),
                ),
              const SizedBox(height: 24),
              const Text('Consent History', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 8),
              FutureBuilder<List<ConsentLogEntry>>(
                future: _consentFuture,
                builder: (context, consentSnapshot) {
                  if (consentSnapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (consentSnapshot.hasError) {
                    return Text(
                      consentSnapshot.error.toString().replaceFirst('Exception: ', ''),
                      style: const TextStyle(color: AppColors.textSecondary),
                    );
                  }
                  final history = consentSnapshot.data!;
                  if (history.isEmpty) {
                    return const Text('No consent changes recorded.', style: TextStyle(color: AppColors.textSecondary));
                  }
                  return Column(
                    children: history
                        .map(
                          (entry) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              entry.granted ? Icons.check_circle_outline : Icons.remove_circle_outline,
                              color: entry.granted ? AppColors.primary : AppColors.expense,
                            ),
                            title: Text('${entry.consentType} consent ${entry.granted ? 'granted' : 'withdrawn'}'),
                            subtitle: Text(entry.changedAt.toLocal().toString()),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _exporting ? null : _exportData,
                icon: _exporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                label: const Text('Export Data (DSAR)'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
