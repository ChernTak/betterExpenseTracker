import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../route.dart';
import '../../../../services/admin_service.dart';
import '../../../../services/auth_service.dart';
import 'admin_audit_log_screen.dart';
import 'admin_data_retention_screen.dart';
import 'admin_user_detail_screen.dart';

/// FR1.7 / use case "Manage User Account" — the System Administrator's only
/// screen. Deliberately outside MainShell: an admin account has no expenses,
/// budgets or goals of its own, so the four user-facing tabs don't apply.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _adminService = AdminService();
  final _authService = AuthService();

  late Future<List<AdminUser>> _usersFuture;
  String? _currentAdminId;

  @override
  void initState() {
    super.initState();
    _usersFuture = _adminService.fetchUsers();
    _authService.getUserId().then((id) => setState(() => _currentAdminId = id));
  }

  void _refresh() {
    // Must be a block body, not `setState(() => _usersFuture = ...)` — an
    // assignment expression evaluates to the assigned value, so an arrow
    // closure there returns the Future itself, and setState() throws at
    // runtime ("setState() callback argument returned a Future") because it
    // rejects any callback whose return value is a Future.
    setState(() {
      _usersFuture = _adminService.fetchUsers();
    });
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _toggleActive(AdminUser user) async {
    try {
      if (user.isActive) {
        await _adminService.deactivateUser(user.userId);
      } else {
        await _adminService.reactivateUser(user.userId);
      }
      _refresh();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _confirmDelete(AdminUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Request deletion for "${user.username}"?'),
        content: const Text(
          'This deactivates the account and starts a grace period before the account and all of its '
          'expenses, budgets, goals and history are permanently deleted (PDPA data-deletion). '
          'The request can be cancelled at any point before the account is purged.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Request Deletion', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _adminService.deleteUser(user.userId);
      _refresh();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _cancelDeletion(AdminUser user) async {
    try {
      await _adminService.cancelDeletion(user.userId);
      _refresh();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _confirmPurge(AdminUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Permanently purge "${user.username}"?'),
        content: const Text(
          'This immediately and permanently deletes the account and all of its data. '
          'This cannot be undone, even if the grace period has not yet elapsed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Purge Now', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _adminService.purgeUser(user.userId, force: true);
      _refresh();
    } catch (e) {
      _showError(e);
    }
  }

  void _openUserDetail(AdminUser user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminUserDetailScreen(userId: user.userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Accounts'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminAuditLogScreen()),
            ),
            icon: const Icon(Icons.history),
            tooltip: 'Audit Log',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminDataRetentionScreen()),
            ),
            icon: const Icon(Icons.auto_delete_outlined),
            tooltip: 'Data Retention',
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Log out'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminUser>>(
          future: _usersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(error: snapshot.error!, onRetry: _refresh);
            }

            final users = snapshot.data!;
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _UserTile(
                user: users[index],
                isSelf: users[index].userId == _currentAdminId,
                onTap: () => _openUserDetail(users[index]),
                onToggleActive: () => _toggleActive(users[index]),
                onDelete: () => _confirmDelete(users[index]),
                onCancelDeletion: () => _cancelDeletion(users[index]),
                onPurge: () => _confirmPurge(users[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AdminUser user;
  final bool isSelf;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;
  final VoidCallback onCancelDeletion;
  final VoidCallback onPurge;

  const _UserTile({
    required this.user,
    required this.isSelf,
    required this.onTap,
    required this.onToggleActive,
    required this.onDelete,
    required this.onCancelDeletion,
    required this.onPurge,
  });

  @override
  Widget build(BuildContext context) {
    final pendingDeletion = user.deletionRequestedAt != null;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.username, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        Text(user.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  _StatusChip(user: user),
                ],
              ),
              if (pendingDeletion) ...[
                const SizedBox(height: 6),
                Text(
                  'Deletion requested ${_daysAgo(user.deletionRequestedAt!)}',
                  style: const TextStyle(color: AppColors.expense, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // FR1.7 — an admin cannot deactivate/delete their own account
                  // (also enforced server-side by admin.service.js).
                  if (!isSelf) ...[
                    if (pendingDeletion) ...[
                      TextButton.icon(
                        onPressed: onCancelDeletion,
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('Cancel'),
                      ),
                      TextButton.icon(
                        onPressed: onPurge,
                        icon: const Icon(Icons.delete_forever, size: 18, color: AppColors.expense),
                        label: const Text('Purge Now', style: TextStyle(color: AppColors.expense)),
                      ),
                    ] else ...[
                      TextButton.icon(
                        onPressed: onToggleActive,
                        icon: Icon(user.isActive ? Icons.block : Icons.check_circle_outline, size: 18),
                        label: Text(user.isActive ? 'Deactivate' : 'Reactivate'),
                      ),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.expense),
                        label: const Text('Delete', style: TextStyle(color: AppColors.expense)),
                      ),
                    ],
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('This is your account', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _daysAgo(DateTime dt) {
    final days = DateTime.now().difference(dt).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }
}

class _StatusChip extends StatelessWidget {
  final AdminUser user;
  const _StatusChip({required this.user});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (!user.isActive) {
      label = 'Deactivated';
      color = AppColors.expense;
    } else if (user.isLocked) {
      label = 'Locked';
      color = AppColors.warning;
    } else if (user.role == 'admin') {
      label = 'Admin';
      color = AppColors.primary;
    } else {
      label = user.isGuest ? 'Guest' : 'Active';
      color = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
