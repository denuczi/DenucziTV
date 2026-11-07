import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

import '../domain/media_models.dart';

/// An explicit selection result distinguishes "All" (null) from cancellation.
class CategorySelection {
  const CategorySelection(this.id);

  final String? id;
}

/// Desktop-friendly category navigation with visible scroll controls.
/// The picker route is created only on demand and disposes its search state.
class CategoryFilterBar extends StatefulWidget {
  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<MediaCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  State<CategoryFilterBar> createState() => _CategoryFilterBarState();
}

class _CategoryFilterBarState extends State<CategoryFilterBar> {
  final ScrollController _controller = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void didUpdateWidget(covariant CategoryFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.categories, widget.categories)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
    }
  }

  void _updateArrows() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    final back = position.pixels > position.minScrollExtent + 1;
    final forward = position.pixels < position.maxScrollExtent - 1;
    if (back != _canScrollBack || forward != _canScrollForward) {
      setState(() {
        _canScrollBack = back;
        _canScrollForward = forward;
      });
    }
  }

  Future<void> _scrollBy(double direction) async {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    final target =
        (_controller.offset + direction * position.viewportDimension * 0.7)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openPicker() async {
    final selection = await showDialog<CategorySelection>(
      context: context,
      builder: (_) => CategoryPickerDialog(
        categories: widget.categories,
        selectedId: widget.selectedId,
      ),
    );
    if (!mounted || selection == null) {
      return;
    }
    widget.onSelected(selection.id);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrows);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showArrows = constraints.maxWidth >= 240;
        final compact = constraints.maxWidth < 420;
        return Row(
          children: [
            if (showArrows)
              IconButton(
                key: const Key('categoryScrollBack'),
                tooltip: context.l10n.previousCategories,
                visualDensity: VisualDensity.compact,
                onPressed: _canScrollBack ? () => _scrollBy(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            Expanded(
              child: ListView.builder(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                itemCount: widget.categories.length + 1,
                itemBuilder: (context, index) {
                  final category = index == 0
                      ? null
                      : widget.categories[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          category?.name ?? context.l10n.all,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      selected: widget.selectedId == category?.id,
                      onSelected: (_) => widget.onSelected(category?.id),
                      showCheckmark: false,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 7),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                },
              ),
            ),
            if (showArrows)
              IconButton(
                key: const Key('categoryScrollForward'),
                tooltip: context.l10n.nextCategories,
                visualDensity: VisualDensity.compact,
                onPressed: _canScrollForward ? () => _scrollBy(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            if (!compact) ...[
              const SizedBox(width: 6),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              const SizedBox(width: 8),
            ],
            if (compact)
              IconButton(
                key: const Key('openCategoryPicker'),
                tooltip: context.l10n.browseAllCategories,
                onPressed: _openPicker,
                icon: Icon(
                  Icons.grid_view_rounded,
                  color: widget.selectedId == null ? null : scheme.primary,
                ),
              )
            else
              OutlinedButton.icon(
                key: const Key('openCategoryPicker'),
                onPressed: _openPicker,
                icon: const Icon(Icons.grid_view_rounded, size: 17),
                label: Text(
                  widget.selectedId == null
                      ? context.l10n.categories
                      : context.l10n.filteredCategories,
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Searchable, lazy category list. No category widgets survive closing it.
class CategoryPickerDialog extends StatefulWidget {
  const CategoryPickerDialog({
    super.key,
    required this.categories,
    required this.selectedId,
  });

  final List<MediaCategory> categories;
  final String? selectedId;

  @override
  State<CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<CategoryPickerDialog> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;
    final matches = _query.isEmpty
        ? widget.categories
        : widget.categories
              .where((category) => category.name.toLowerCase().contains(_query))
              .toList(growable: false);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: math.min(520.0, math.max(0.0, size.width - 32.0)),
        height: math.min(620.0, math.max(0.0, size.height - 32.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
              child: Row(
                children: [
                  const Icon(Icons.category_outlined, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.chooseCategory,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.closeCategoryPicker,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: TextField(
                key: const Key('categorySearch'),
                controller: _search,
                autofocus: false,
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: context.l10n.searchCategories,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.l10n.clearCategorySearch,
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
              child: Text(
                context.l10n.categoriesFound(matches.length),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('categoryAll'),
              leading: const Icon(Icons.apps_rounded),
              title: Text(context.l10n.allCategories),
              selected: widget.selectedId == null,
              trailing: widget.selectedId == null
                  ? Icon(Icons.check, color: colors.primary)
                  : null,
              onTap: () =>
                  Navigator.pop(context, const CategorySelection(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.l10n.categoryNotFound,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('categoryResults'),
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final category = matches[index];
                        final selected = widget.selectedId == category.id;
                        return ListTile(
                          key: ValueKey('category-${category.id}'),
                          title: Text(
                            category.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: selected,
                          trailing: selected
                              ? Icon(Icons.check, color: colors.primary)
                              : null,
                          onTap: () => Navigator.pop(
                            context,
                            CategorySelection(category.id),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.cancel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
