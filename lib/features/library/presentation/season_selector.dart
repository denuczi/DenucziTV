import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

/// A compact, keyboard-accessible season switcher for desktop windows.
///
/// The horizontal list has explicit navigation controls because mouse-wheel
/// scrolling is not guaranteed to move horizontal lists on every desktop.
/// The full picker is only mounted while its dialog is open.
class SeasonSelector extends StatefulWidget {
  const SeasonSelector({
    super.key,
    required this.seasons,
    required this.selectedSeason,
    required this.episodeCountForSeason,
    required this.onSelected,
  });

  final List<int> seasons;
  final int selectedSeason;
  final int Function(int season) episodeCountForSeason;
  final ValueChanged<int> onSelected;

  @override
  State<SeasonSelector> createState() => _SeasonSelectorState();
}

class _SeasonSelectorState extends State<SeasonSelector> {
  final ScrollController _scroll = ScrollController();
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateControls);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateControls());
  }

  @override
  void didUpdateWidget(covariant SeasonSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seasons.length != widget.seasons.length ||
        oldWidget.selectedSeason != widget.selectedSeason) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateControls());
    }
  }

  void _updateControls() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final back = position.pixels > position.minScrollExtent + 1;
    final forward = position.pixels < position.maxScrollExtent - 1;
    if (back != _canGoBack || forward != _canGoForward) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  Future<void> _move(int direction) async {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final target =
        (_scroll.offset + position.viewportDimension * direction * 0.75)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showAllSeasons() async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _SeasonPickerDialog(
        seasons: widget.seasons,
        selectedSeason: widget.selectedSeason,
        episodeCountForSeason: widget.episodeCountForSeason,
      ),
    );
    if (mounted && chosen != null) {
      widget.onSelected(chosen);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_updateControls);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.seasons.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          IconButton(
            key: const Key('previousSeasonChips'),
            tooltip: context.l10n.previousSeasons,
            onPressed: _canGoBack ? () => _move(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemCount: widget.seasons.length,
              itemBuilder: (context, index) {
                final season = widget.seasons[index];
                final count = widget.episodeCountForSeason(season);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('seasonChip-$season'),
                    selected: widget.selectedSeason == season,
                    showCheckmark: false,
                    tooltip: context.l10n.seasonEpisodeLabel(season, count),
                    label: Text(context.l10n.seasonEpisodeLabel(season, count)),
                    onSelected: (_) => widget.onSelected(season),
                  ),
                );
              },
            ),
          ),
          IconButton(
            key: const Key('nextSeasonChips'),
            tooltip: context.l10n.nextSeasons,
            onPressed: _canGoForward ? () => _move(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(width: 6),
          if (constraints.maxWidth < 420)
            IconButton(
              key: const Key('browseAllSeasons'),
              tooltip: context.l10n.browseAllSeasons,
              onPressed: _showAllSeasons,
              icon: const Icon(Icons.view_list_rounded),
            )
          else
            OutlinedButton.icon(
              key: const Key('browseAllSeasons'),
              onPressed: _showAllSeasons,
              icon: const Icon(Icons.view_list_rounded, size: 18),
              label: Text(context.l10n.seasonsHeading),
            ),
        ],
      ),
    );
  }
}

class _SeasonPickerDialog extends StatelessWidget {
  const _SeasonPickerDialog({
    required this.seasons,
    required this.selectedSeason,
    required this.episodeCountForSeason,
  });

  final List<int> seasons;
  final int selectedSeason;
  final int Function(int season) episodeCountForSeason;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: math.min(440.0, math.max(0.0, size.width - 32.0)),
        height: math.min(550.0, math.max(0.0, size.height - 32.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.chooseSeason,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          context.l10n.seasonsAvailable(seasons.length),
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.closeSeasonPicker,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                key: const Key('allSeasonsList'),
                itemCount: seasons.length,
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  final count = episodeCountForSeason(season);
                  return ListTile(
                    key: Key('seasonPicker-$season'),
                    title: Text(context.l10n.seasonOne(season)),
                    subtitle: Text(context.l10n.episodeCount(count)),
                    selected: selectedSeason == season,
                    trailing: selectedSeason == season
                        ? Icon(Icons.check_rounded, color: colors.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(season),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
