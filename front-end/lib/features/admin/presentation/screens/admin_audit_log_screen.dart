import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../services/admin_service.dart';

/// PDPA accountability — read-only view of admin_audit_log: who did what to
/// which user's data, and when. Mirrors AdminUsersScreen's structure.
class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  final _adminService = AdminService();
  late Future<List<AdminAuditEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _adminService.fetchAuditLog();
  }

  void _refresh() {
    setState(() {
      _entriesFuture = _adminService.fetchAuditLog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Audit Log')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminAuditEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      snapshot.error.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }

            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No admin actions logged yet.'))),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _AuditTile(entry: entries[index]),
            );
          },
        ),
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  final AdminAuditEntry entry;
  const _AuditTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.action.replaceAll('_', ' '),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                Text(
                  _formatTimestamp(entry.createdAt),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            if (entry.targetEmail != null) ...[
              const SizedBox(height: 4),
              Text('Target: ${entry.targetEmail}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
            if (entry.details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                entry.details.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
