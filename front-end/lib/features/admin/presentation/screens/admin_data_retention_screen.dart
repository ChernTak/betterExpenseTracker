import 'package:flutter/material.dart';

import '../../../../services/admin_service.dart';

/// PDPA storage-limitation: admin-triggered retention purges, since this app has no job scheduler to run them automatically.
class AdminDataRetentionScreen extends StatelessWidget {
  const AdminDataRetentionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final adminService = AdminService();

    return Scaffold(
      appBar: AppBar(title: const Text('Data Retention')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RetentionSection(
            description:
                'Food-recommendation logs store the raw GPS coordinates used for each search. '
                'They have no automatic expiry — purge entries older than the chosen threshold below.',
            defaultDays: 90,
            purgeButtonLabel: 'Purge Old Location Logs',
            confirmTitle: 'Purge old location logs?',
            confirmBody: (days) =>
                'This permanently deletes food-recommendation logs (including raw GPS coordinates) '
                'generated more than $days day(s) ago. This cannot be undone.',
            successMessage: (count, days) => 'Purged $count recommendation log(s) older than $days day(s).',
            purge: adminService.purgeRecommendationLogs,
          ),
          const SizedBox(height: 32),
          _RetentionSection(
            description:
                '"Continue as Guest" creates a new throwaway account on every use, with no way to resume '
                'it later. Accounts with no activity (expenses, budgets, etc.) since the threshold below are '
                'no longer serving any purpose and can be purged.',
            defaultDays: 30,
            purgeButtonLabel: 'Purge Stale Guest Accounts',
            confirmTitle: 'Purge stale guest accounts?',
            confirmBody: (days) =>
                'This permanently deletes guest accounts (and all of their expenses, budgets and history) '
                'with no activity in the last $days day(s). This cannot be undone.',
            successMessage: (count, days) => 'Purged $count guest account(s) inactive for $days+ day(s).',
            purge: adminService.purgeStaleGuests,
          ),
        ],
      ),
    );
  }
}

class _RetentionSection extends StatefulWidget {
  final String description;
  final int defaultDays;
  final String purgeButtonLabel;
  final String confirmTitle;
  final String Function(int days) confirmBody;
  final String Function(int count, int days) successMessage;
  final Future<int> Function(int days) purge;

  const _RetentionSection({
    required this.description,
    required this.defaultDays,
    required this.purgeButtonLabel,
    required this.confirmTitle,
    required this.confirmBody,
    required this.successMessage,
    required this.purge,
  });

  @override
  State<_RetentionSection> createState() => _RetentionSectionState();
}

class _RetentionSectionState extends State<_RetentionSection> {
  late final _daysController = TextEditingController(text: widget.defaultDays.toString());
  bool _purging = false;

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _purge() async {
    final days = int.tryParse(_daysController.text.trim());
    if (days == null || days < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a non-negative number of days')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(widget.confirmTitle),
        content: Text(widget.confirmBody(days)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Purge')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _purging = true);
    try {
      final deletedCount = await widget.purge(days);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.successMessage(deletedCount, days))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.description),
        const SizedBox(height: 20),
        TextField(
          controller: _daysController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Older than (days)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _purging ? null : _purge,
          child: _purging
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.purgeButtonLabel),
        ),
      ],
    );
  }
}
