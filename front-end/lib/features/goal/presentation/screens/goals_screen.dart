import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/utils/validators.dart';
import '../../../../services/goal_service.dart';

/// Savings Goals: proactive, cumulative targets the user sets up themselves
/// (goal-gradient effect — name it, give it a number and a deadline, watch
/// the bar fill as contributions come in). Reached from Settings, distinct
/// from Wishlist which is reactive/nudge-triggered.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _goalService = GoalService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _goalService.fetchGoals();
  }

  void _refresh() {
    setState(() {
      _future = _goalService.fetchGoals();
    });
  }

  Future<void> _openCreateDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const GoalFormDialog(),
    );
    if (saved == true) _refresh();
  }

  Future<void> _openEditDialog(Map<String, dynamic> goal) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => GoalFormDialog(
        goalId: goal['goal_id'] as String,
        initialName: goal['goal_name'] as String,
        initialTarget: (goal['target_amount'] as num).toDouble(),
        initialDeadline: goal['deadline_date'] != null
            ? DateTime.parse(goal['deadline_date'] as String)
            : null,
        initialNotes: goal['notes'] as String?,
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _openContributeDialog(Map<String, dynamic> goal) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ContributeDialog(
        goalId: goal['goal_id'] as String,
        goalName: goal['goal_name'] as String,
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _confirmDelete(Map<String, dynamic> goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${goal['goal_name']}"?'),
        content: const Text(
          'This removes the goal and its contribution history.',
        ),
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
      await _goalService.deleteGoal(goal['goal_id'] as String);
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
        title: const Text('Savings Goals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New goal',
            onPressed: _openCreateDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
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

            final goals = snapshot.data ?? [];
            if (goals.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No savings goals yet. Tap + to set your first target.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: goals.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final goal = goals[index] as Map<String, dynamic>;
                return _GoalTile(
                  goal: goal,
                  onTap: () => _openEditDialog(goal),
                  onContribute: () => _openContributeDialog(goal),
                  onDelete: () => _confirmDelete(goal),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  final Map<String, dynamic> goal;
  final VoidCallback onTap;
  final VoidCallback onContribute;
  final VoidCallback onDelete;

  const _GoalTile({
    required this.goal,
    required this.onTap,
    required this.onContribute,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = goal['goal_name'] as String;
    final target = (goal['target_amount'] as num).toDouble();
    final saved = (goal['current_saved'] as num).toDouble();
    final status = goal['status'] as String;
    final deadline = goal['deadline_date'] as String?;
    final pct = target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;
    final isCompleted = status == 'completed';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isCompleted ? Icons.check_circle : Icons.savings_outlined,
                    color: isCompleted
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isCompleted)
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: AppColors.primary,
                      ),
                      tooltip: 'Add contribution',
                      onPressed: onContribute,
                    ),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      color: AppColors.textSecondary,
                    ),
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: AppColors.surface,
                  valueColor: AlwaysStoppedAnimation(
                    isCompleted ? AppColors.primary : AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RM ${saved.toStringAsFixed(2)} of RM ${target.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (deadline != null)
                    Text(
                      'by ${deadline.substring(0, 10)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Handles both creating a new goal and editing an existing one's name,
/// target, deadline or notes — status/current_saved are managed elsewhere
/// (contributions, or the auto-complete-at-target rule on the backend).
class GoalFormDialog extends StatefulWidget {
  final String? goalId;
  final String? initialName;
  final double? initialTarget;
  final DateTime? initialDeadline;
  final String? initialNotes;

  const GoalFormDialog({
    super.key,
    this.goalId,
    this.initialName,
    this.initialTarget,
    this.initialDeadline,
    this.initialNotes,
  });

  @override
  State<GoalFormDialog> createState() => _GoalFormDialogState();
}

class _GoalFormDialogState extends State<GoalFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _targetController;
  late final TextEditingController _notesController;
  final _goalService = GoalService();

  DateTime? _deadline;
  bool _isSaving = false;

  bool get _isEditing => widget.goalId != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _targetController = TextEditingController(
      text: widget.initialTarget != null
          ? widget.initialTarget!.toStringAsFixed(2)
          : '',
    );
    _notesController = TextEditingController(text: widget.initialNotes ?? '');
    _deadline = widget.initialDeadline;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final target = double.parse(_targetController.text);
      if (_isEditing) {
        await _goalService.updateGoal(
          widget.goalId!,
          goalName: _nameController.text.trim(),
          targetAmount: target,
          deadlineDate: _deadline,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await _goalService.createGoal(
          goalName: _nameController.text.trim(),
          targetAmount: target,
          deadlineDate: _deadline,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }
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
      title: Text(_isEditing ? 'Edit Goal' : 'New Savings Goal'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: !_isEditing,
                decoration: const InputDecoration(
                  labelText: 'Goal name (e.g. Japan Trip)',
                ),
                validator: (v) =>
                    Validators.validateRequired(v, fieldName: 'Goal name'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetController,
                decoration: const InputDecoration(
                  labelText: 'Target amount (RM)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: Validators.validateAmount,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDeadline,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Deadline (optional)',
                  ),
                  child: Text(
                    _deadline != null
                        ? '${_deadline!.year}-${_deadline!.month.toString().padLeft(2, '0')}-${_deadline!.day.toString().padLeft(2, '0')}'
                        : 'No deadline set',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
                maxLines: 2,
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
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Logs a contribution toward a goal — the moment the progress bar actually
/// moves. Kept separate from GoalFormDialog since it's a different action
/// (adding money) from editing the goal's own details.
class ContributeDialog extends StatefulWidget {
  final String goalId;
  final String goalName;

  const ContributeDialog({
    super.key,
    required this.goalId,
    required this.goalName,
  });

  @override
  State<ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends State<ContributeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _goalService = GoalService();
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await _goalService.contribute(
        widget.goalId,
        amount: double.parse(_amountController.text),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      // Reuses the expense-change bus as a general "financial data changed"
      // signal — same pattern income_history_screen.dart already relies on
      // — so the Guide dashboard's "Available to spend" / goal-commitment
      // line don't go stale after a contribution.
      notifyExpenseDataChanged();
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
      title: Text('Add to "${widget.goalName}"'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amountController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount (RM)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.validateAmount,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
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
              : const Text('Add'),
        ),
      ],
    );
  }
}
