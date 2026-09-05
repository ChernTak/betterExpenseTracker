import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/category_presets.dart';
import '../../../../core/events/category_events.dart';
import '../../../../services/category_service.dart';

/// Self-serve category management (add/rename/delete/reorder) — users start with 13 seeded defaults, fully editable.
class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  final _categoryService = CategoryService();
  late Future<List<CategoryItem>> _future;
  List<CategoryItem> _categories = [];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CategoryItem>> _load() async {
    final list = await _categoryService.fetchCategories();
    if (mounted) setState(() => _categories = list);
    return list;
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openAddDialog() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const _CategoryFormDialog());
    if (saved == true) {
      _refresh();
      notifyCategoriesChanged();
    }
  }

  Future<void> _openEditDialog(CategoryItem category) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryFormDialog(category: category),
    );
    if (saved == true) {
      _refresh();
      notifyCategoriesChanged();
    }
  }

  Future<void> _confirmDelete(CategoryItem category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${category.label}"?'),
        content: const Text(
          'Expenses using this category will be moved to Other. Any budget set for it will be removed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _categoryService.deleteCategory(category.id);
      _refresh();
      notifyCategoriesChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, item);
    });
    try {
      await _categoryService.reorderCategories(_categories.map((c) => c.id).toList());
      notifyCategoriesChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add category', onPressed: _openAddDialog),
        ],
      ),
      body: FutureBuilder<List<CategoryItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _categories.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && _categories.isEmpty) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (_categories.isEmpty) {
            return const Center(child: Text('No categories yet.'));
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _categories.length,
            onReorder: _handleReorder,
            itemBuilder: (context, index) {
              final category = _categories[index];
              return Container(
                key: ValueKey(category.id),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surface),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: CircleAvatar(
                    backgroundColor: category.color.withValues(alpha: 0.15),
                    child: Icon(category.icon, color: category.color),
                  ),
                  title: Text(category.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'Edit',
                        onPressed: () => _openEditDialog(category),
                      ),
                      if (!category.isProtected)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.expense),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(category),
                        ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.drag_handle, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Creates or edits a category's label/icon/color/keywords — mirrors _BudgetFormDialog's structure.
class _CategoryFormDialog extends StatefulWidget {
  final CategoryItem? category;

  const _CategoryFormDialog({this.category});

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _categoryService = CategoryService();
  late final TextEditingController _labelController;
  late final TextEditingController _keywordsController;
  late String _iconKey;
  late String _colorHex;
  bool _isSaving = false;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _labelController = TextEditingController(text: category?.label ?? '');
    _keywordsController = TextEditingController(text: category?.keywords ?? '');
    _iconKey = category != null
        ? kCategoryIconPresets.entries
              .firstWhere((e) => e.value == category.icon, orElse: () => kCategoryIconPresets.entries.first)
              .key
        : kCategoryIconPresets.keys.first;
    _colorHex = category != null ? colorToHex(category.color) : kCategoryColorPresets.first;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await _categoryService.updateCategory(
          widget.category!.id,
          label: _labelController.text.trim(),
          icon: _iconKey,
          color: _colorHex,
          keywords: _keywordsController.text,
        );
      } else {
        await _categoryService.createCategory(
          label: _labelController.text.trim(),
          icon: _iconKey,
          color: _colorHex,
          keywords: _keywordsController.text,
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
      title: Text(_isEditing ? 'Edit Category' : 'New Category'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _keywordsController,
                decoration: const InputDecoration(
                  labelText: 'Merchant keywords (optional)',
                  hintText: 'e.g. vet, petsmart, pet food',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Icon', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                width: 300,
                child: GridView.count(
                  crossAxisCount: 6,
                  children: kCategoryIconPresets.entries.map((entry) {
                    final selected = entry.key == _iconKey;
                    return InkWell(
                      onTap: () => setState(() => _iconKey = entry.key),
                      borderRadius: BorderRadius.circular(20),
                      child: CircleAvatar(
                        backgroundColor: selected ? hexToColor(_colorHex) : AppColors.surface,
                        child: Icon(
                          entry.value,
                          color: selected ? Colors.white : AppColors.textSecondary,
                          size: 18,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Color', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kCategoryColorPresets.map((hex) {
                  final selected = hex == _colorHex;
                  return InkWell(
                    onTap: () => setState(() => _colorHex = hex),
                    borderRadius: BorderRadius.circular(16),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: hexToColor(hex),
                      child: selected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                  );
                }).toList(),
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
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
