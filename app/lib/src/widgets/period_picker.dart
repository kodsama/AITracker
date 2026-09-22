import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// The window every screen reads: step back and forward, choose a named one,
/// or pick two dates.
class PeriodPicker extends StatelessWidget {
  /// Creates the picker.
  const PeriodPicker({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final custom = state.periodKind == PeriodKind.custom;
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => state.stepPeriod(-1),
        ),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => state.stepPeriod(1),
        ),
        const SizedBox(width: 8),
        DropdownMenu<PeriodKind>(
          initialSelection: state.periodKind,
          width: 200,
          textStyle: theme.textTheme.bodyMedium,
          inputDecorationTheme: const InputDecorationTheme(isDense: true),
          onSelected: (kind) {
            if (kind == null) return;
            if (kind == PeriodKind.custom) {
              _pick(context);
            } else {
              state.setPeriod(kind);
            }
          },
          dropdownMenuEntries: [
            for (final kind in PeriodKind.values)
              DropdownMenuEntry(
                value: kind,
                label: kind == PeriodKind.custom ? 'Dates…' : kind.label,
              ),
          ],
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(custom ? _range(state.period) : 'Pick dates'),
        ),
        const SizedBox(width: 12),
        // What the window actually is, once it has been stepped away from the
        // name on the dropdown.
        if (state.periodStep != 0)
          Chip(
            label: Text(state.period.label),
            onDeleted: () => state.setPeriod(state.periodKind),
            deleteIcon: const Icon(Icons.close, size: 16),
            backgroundColor: theme.colorScheme.secondaryContainer,
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

  static String _range(Period period) =>
      '${_day(period.start)} to ${_day(period.end.subtract(const Duration(days: 1)))}';

  static String _day(DateTime date) =>
      '${date.day}/${date.month}/${date.year % 100}';
}
