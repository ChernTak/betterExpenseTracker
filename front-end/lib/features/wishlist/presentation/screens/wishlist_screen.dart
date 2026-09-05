import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/utils/validators.dart';
import '../../../../services/category_service.dart';
import '../../../../services/wishlist_service.dart';

/// Wishlist: purchases the user has deliberately delayed. Most items arrive from a spending alert, but the "+" here lets a user pre-empt a temptation on their own, using the same dialog with alertId omitted.
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

const _statuses = ['pending', 'purchased', 'dismissed'];
const _statusLabels = {
  'pending': 'Pending',
  'purchased': 'Purchased',
  'dismissed': 'Dismissed',
};

class _WishlistScreenState extends State<WishlistScreen> {
  final _wishlistService = WishlistService();
  int _tab = 0;
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() =>
      _wishlistService.fetchItems(status: _statuses[_tab]);

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  void _changeTab(int index) {
    setState(() {
      _tab = index;
      _future = _load();
    });
  }

  Future<void> _openAddDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const AddToWishlistDialog(),
    );
    if (added == true) _refresh();
  }

  Future<void> _resolve(Map<String, dynamic> item, String status) async {
    try {
      await _wishlistService.updateItem(
        item['wishlist_id'] as String,
        status: status,
      );
      // 'purchased' creates a real expense, so ping the expense-change bus to keep the Guide dashboard from going stale.
      if (status == 'purchased') notifyExpenseDataChanged();
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _convertToGoal(Map<String, dynamic> item) async {
    final result = await showDialog<_ConvertToGoalResult>(
      context: context,
      builder: (_) => _ConvertToGoalDialog(item: item),
    );
    if (result == null) return;

    try {
      await _wishlistService.convertToGoal(
        item['wishlist_id'] as String,
        targetAmount: result.targetAmount,
        deadlineDate: result.deadlineDate,
      );
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item['item_name']}" is now a saving goal')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${item['item_name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.expense),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _wishlistService.deleteItem(item['wishlist_id'] as String);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wishlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add item',
            onPressed: _openAddDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (var i = 0; i < _statuses.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(_statusLabels[_statuses[i]]!),
                      selected: _tab == i,
                      onSelected: (_) => _changeTab(i),
                      selectedColor: AppColors.primaryMuted,
                      labelStyle: TextStyle(
                        color: _tab == i
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: FutureBuilder<List<dynamic>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _tab == 0
                              ? "Nothing delayed right now — items you choose to put off after a spending nudge show up here."
                              : 'Nothing here yet.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }

                  // Expired-delay items surface first under their own heading — this reminder re-shows on every open since there's no push scheduler for it.
                  final today = DateTime.now();
                  final todayOnly = DateTime(today.year, today.month, today.day);
                  bool isExpired(Map<String, dynamic> item) {
                    if (item['status'] != 'pending') return false;
                    final delayUntil = item['delay_until_date'] as String?;
                    if (delayUntil == null) return false;
                    final parsed = DateTime.tryParse(delayUntil);
                    if (parsed == null) return false;
                    return !parsed.isAfter(todayOnly);
                  }

                  final readyItems = _tab == 0
                      ? items.where((i) => isExpired(i as Map<String, dynamic>)).toList()
                      : const <dynamic>[];
                  final waitingItems = _tab == 0
                      ? items.where((i) => !isExpired(i as Map<String, dynamic>)).toList()
                      : items;

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (readyItems.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(
                            'Ready to decide',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        for (final item in readyItems) ...[
                          _WishlistTile(
                            item: item as Map<String, dynamic>,
                            isExpired: true,
                            onMarkPurchased: () => _resolve(item, 'purchased'),
                            onDismiss: () => _resolve(item, 'dismissed'),
                            onConvertToGoal: () => _convertToGoal(item),
                            onRestore: () => _resolve(item, 'pending'),
                            onDelete: () => _confirmDelete(item),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 8),
                      ],
                      if (waitingItems.isNotEmpty && readyItems.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(
                            'Still waiting',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      for (final item in waitingItems) ...[
                        _WishlistTile(
                          item: item as Map<String, dynamic>,
                          isExpired: _tab == 0 ? isExpired(item) : true,
                          onMarkPurchased: () => _resolve(item, 'purchased'),
                          onDismiss: () => _resolve(item, 'dismissed'),
                          onConvertToGoal: () => _convertToGoal(item),
                          onRestore: () => _resolve(item, 'pending'),
                          onDelete: () => _confirmDelete(item),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WishlistTile extends StatelessWidget {
  final Map<String, dynamic> item;
  // Gates whether "Mark as bought" is selectable, mirroring the backend's hard 409 block so a tap can't round-trip into an error.
  final bool isExpired;
  final VoidCallback onMarkPurchased;
  final VoidCallback onDismiss;
  final VoidCallback onConvertToGoal;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _WishlistTile({
    required this.item,
    required this.isExpired,
    required this.onMarkPurchased,
    required this.onDismiss,
    required this.onConvertToGoal,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = item['item_name'] as String;
    final cost = (item['estimated_cost'] as num?)?.toDouble();
    final merchant = item['merchant_name'] as String?;
    final categoryKey = item['category'] as String?;
    final delayUntil = item['delay_until_date'] as String?;
    final status = item['status'] as String;
    final categoryItem = categoryKey != null
        ? CategoryService.lookup(categoryKey)
        : null;

    final monthlyLimit = (item['budget_monthly_limit'] as num?)?.toDouble();
    final currentSpend = (item['budget_current_spend'] as num?)?.toDouble();
    String? impactLine;
    if (status == 'pending' &&
        cost != null &&
        monthlyLimit != null &&
        monthlyLimit > 0 &&
        currentSpend != null) {
      final beforePct = (currentSpend / monthlyLimit * 100).clamp(0, 999);
      final afterPct = ((currentSpend + cost) / monthlyLimit * 100).clamp(0, 999);
      final categoryLabel = categoryItem?.label ?? 'this category\'s';
      impactLine =
          'Would push $categoryLabel budget to ${afterPct.toStringAsFixed(0)}% (from ${beforePct.toStringAsFixed(0)}%)';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: (categoryItem?.color ?? AppColors.textSecondary)
                .withValues(alpha: 0.15),
            child: Icon(
              categoryItem?.icon ?? Icons.shopping_bag_outlined,
              color: categoryItem?.color ?? AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (merchant != null && merchant.isNotEmpty) merchant,
                    if (cost != null) 'RM ${cost.toStringAsFixed(2)}',
                    if (status == 'pending' && delayUntil != null)
                      isExpired
                          ? 'ready since ${delayUntil.substring(0, 10)}'
                          : 'until ${delayUntil.substring(0, 10)}',
                  ].join(' · '),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (impactLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    impactLine,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (status == 'pending')
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
              onSelected: (value) {
                if (value == 'purchased' && isExpired) onMarkPurchased();
                if (value == 'dismissed') onDismiss();
                if (value == 'convert') onConvertToGoal();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'purchased',
                  enabled: isExpired,
                  child: Text(
                    isExpired ? 'Mark as bought' : 'Mark as bought (still delayed)',
                  ),
                ),
                const PopupMenuItem(
                  value: 'convert',
                  child: Text('Save toward this instead'),
                ),
                const PopupMenuItem(value: 'dismissed', child: Text('Dismiss')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          else if (status == 'dismissed')
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
              onSelected: (value) {
                if (value == 'restore') onRestore();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'restore', child: Text('Restore to pending')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          else
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: AppColors.expense,
              ),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// Adds a purchase to delay, opened from a real-time alert or manually; public so budgets_screen.dart and notification_handler.dart can invoke it.
class AddToWishlistDialog extends StatefulWidget {
  final String? alertId;
  final String? initialCategory;
  final String? initialMerchantName;

  const AddToWishlistDialog({
    super.key,
    this.alertId,
    this.initialCategory,
    this.initialMerchantName,
  });

  @override
  State<AddToWishlistDialog> createState() => _AddToWishlistDialogState();
}

class _AddToWishlistDialogState extends State<AddToWishlistDialog> {
  final _formKey = GlobalKey<FormState>();
  final _itemNameController = TextEditingController();
  final _costController = TextEditingController();
  late final TextEditingController _merchantController;
  final _delayDaysController = TextEditingController(text: '3');
  final _wishlistService = WishlistService();

  String? _category;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController(
      text: widget.initialMerchantName ?? '',
    );
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _costController.dispose();
    _merchantController.dispose();
    _delayDaysController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await _wishlistService.addItem(
        alertId: widget.alertId,
        itemName: _itemNameController.text.trim(),
        estimatedCost: _costController.text.isEmpty
            ? null
            : double.parse(_costController.text),
        merchantName: _merchantController.text.trim().isEmpty
            ? null
            : _merchantController.text.trim(),
        category: _category,
        delayDays: _delayDaysController.text.isEmpty
            ? null
            : int.parse(_delayDaysController.text),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delay this purchase'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _itemNameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'What are you tempted to buy?',
                ),
                validator: (v) =>
                    Validators.validateRequired(v, fieldName: 'Item name'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(
                  labelText: 'Estimated cost (RM, optional)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _merchantController,
                decoration: const InputDecoration(
                  labelText: 'Merchant (optional)',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ...CategoryService.cached.map(
                    (c) => DropdownMenuItem(
                      value: c.key,
                      child: Text(
                        c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _delayDaysController,
                decoration: const InputDecoration(
                  labelText: 'Delay for how many days?',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleSave,
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add to Wishlist'),
        ),
      ],
    );
  }
}

class _ConvertToGoalResult {
  final double targetAmount;
  final DateTime? deadlineDate;

  const _ConvertToGoalResult({required this.targetAmount, this.deadlineDate});
}

/// Confirms target amount/deadline before converting a pending item to a saving goal; target pre-fills from estimated_cost but stays editable/required since older items may lack it.
class _ConvertToGoalDialog extends StatefulWidget {
  final Map<String, dynamic> item;

  const _ConvertToGoalDialog({required this.item});

  @override
  State<_ConvertToGoalDialog> createState() => _ConvertToGoalDialogState();
}

class _ConvertToGoalDialogState extends State<_ConvertToGoalDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _targetController;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    final cost = (widget.item['estimated_cost'] as num?)?.toDouble();
    _targetController = TextEditingController(
      text: cost != null ? cost.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _ConvertToGoalResult(
        targetAmount: double.parse(_targetController.text),
        deadlineDate: _deadline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemName = widget.item['item_name'] as String;
    return AlertDialog(
      title: const Text('Save toward this instead'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"$itemName" will move out of Wishlist and become a saving goal you contribute to over time.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Target amount (RM)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDeadline,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Deadline (optional)'),
                  child: Text(
                    _deadline == null
                        ? 'No deadline'
                        : '${_deadline!.year}-${_deadline!.month.toString().padLeft(2, '0')}-${_deadline!.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _handleSave,
          child: const Text('Start Goal'),
        ),
      ],
    );
  }
}
