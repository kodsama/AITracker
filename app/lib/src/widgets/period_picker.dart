import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// The window every screen reads: a row of named ranges, plus a pair of dates
/// when none of them is the right shape.
class PeriodPicker extends StatelessWidget {
  /// Creates the picker.
  const PeriodPicker({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final kind in PeriodKind.values)
          if (kind != PeriodKind.custom)
            ChoiceChip(
              label: Text(kind.label),
              selected: state.periodKind == kind,
              onSelected: (_) => state.setPeriod(kind),
            ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(
            state.periodKind == PeriodKind.custom
                ? '${_day(state.period.start)} to ${_day(state.period.end.subtract(const Duration(days: 1)))}'
                : 'Pick dates',
          ),
          backgroundColor: state.periodKind == PeriodKind.custom
              ? theme.colorScheme.secondaryContainer
              : null,
          onPressed: () => _pick(context),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: state.period.start,
        end: state.period.end.subtract(const Duration(days: 1)),
      ),
    );
    if (picked == null) return;
    await state.setPeriod(
      PeriodKind.custom,
      start: picked.start,
      end: picked.end,
    );
  }

  static String _day(DateTime date) =>
      '${date.day}/${date.month}/${date.year % 100}';
}
