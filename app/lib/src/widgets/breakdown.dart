import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Time and tokens side by side, grouped however you want to read them.
class Breakdown extends StatefulWidget {
  /// Creates the table.
  const Breakdown({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  State<Breakdown> createState() => _BreakdownState();
}

/// What the table is ordered by.
enum _By { name, time, tokens, perHour, sessions }

class _BreakdownState extends State<Breakdown> {
  Grouping _by = Grouping.project;
  _By _sort = _By.time;
  bool _descending = true;

  List<SummaryRow> get _rows {
    final rows = summarise(widget.state.blocks, _by);
    if (_sort == _By.name && !_descending) return rows;
    final sorted = [...rows];
    sorted.sort((a, b) {
      final order = switch (_sort) {
        _By.name => a.label.compareTo(b.label),
        _By.time => a.time.compareTo(b.time),
        _By.tokens => a.tokens.total.compareTo(b.tokens.total),
        _By.perHour => a.tokensPerHour.compareTo(b.tokensPerHour),
        _By.sessions => a.sessions.compareTo(b.sessions),
      };
      return _descending ? -order : order;
    });
    return sorted;
  }

  void _order(_By by) => setState(() {
    if (_sort == by) {
      _descending = !_descending;
    } else {
      _sort = by;
      _descending = by != _By.name;
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    final longest = rows.isEmpty
        ? Duration.zero
        : rows.map((r) => r.time).reduce((a, b) => a > b ? a : b);
    final calendar =
        _by == Grouping.day || _by == Grouping.week || _by == Grouping.month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<Grouping>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final grouping in Grouping.values)
                ButtonSegment(value: grouping, label: Text(grouping.label)),
            ],
            selected: {_by},
            onSelectionChanged: (chosen) => setState(() {
              _by = chosen.first;
              // A calendar grouping reads in its own order until asked
              // otherwise; the rest read heaviest first.
              _sort = chosen.first == Grouping.day ||
                      chosen.first == Grouping.week ||
                      chosen.first == Grouping.month
                  ? _By.name
                  : _By.time;
              _descending = _sort == _By.time;
            }),
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Text(
            'Nothing in this window.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          _Head(
            by: _by,
            sort: _sort,
            descending: _descending,
            onOrder: _order,
            calendar: calendar,
          ),
          const Divider(height: 12),
          for (final row in rows)
            _Row(
              row: row,
              share: longest.inSeconds == 0
                  ? 0
                  : row.time.inSeconds / longest.inSeconds,
              colour: _by == Grouping.project
                  ? widget.state.colorFor(row.label, theme.brightness)
                  : null,
            ),
        ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({
    required this.by,
    required this.sort,
    required this.descending,
    required this.onOrder,
    required this.calendar,
  });

  final Grouping by;
  final _By sort;
  final bool descending;
  final ValueChanged<_By> onOrder;
  final bool calendar;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 4,
        child: _Header(
          label: calendar ? by.label : by.label,
          by: _By.name,
          sort: sort,
          descending: descending,
          onOrder: onOrder,
        ),
      ),
      const Spacer(flex: 3),
      SizedBox(
        width: 92,
        child: _Header(
          label: 'Time',
          by: _By.time,
          sort: sort,
          descending: descending,
          onOrder: onOrder,
          alignRight: true,
        ),
      ),
      SizedBox(
        width: 92,
        child: _Header(
          label: 'Tokens',
          by: _By.tokens,
          sort: sort,
          descending: descending,
          onOrder: onOrder,
          alignRight: true,
        ),
      ),
      SizedBox(
        width: 96,
        child: _Header(
          label: 'Per hour',
          by: _By.perHour,
          sort: sort,
          descending: descending,
          onOrder: onOrder,
          alignRight: true,
        ),
      ),
      SizedBox(
        width: 96,
        child: _Header(
          label: 'Sessions',
          by: _By.sessions,
          sort: sort,
          descending: descending,
          onOrder: onOrder,
          alignRight: true,
        ),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.label,
    required this.by,
    required this.sort,
    required this.descending,
    required this.onOrder,
    this.alignRight = false,
  });

  final String label;
  final _By by;
  final _By sort;
  final bool descending;
  final ValueChanged<_By> onOrder;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = sort == by;
    return InkWell(
      onTap: () => onOrder(by),
      child: Row(
        mainAxisAlignment: alignRight
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (active)
            Icon(
              descending ? Icons.arrow_drop_down : Icons.arrow_drop_up,
              size: 16,
              color: theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.share, this.colour});

  final SummaryRow row;
  final double share;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                if (colour != null) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(row.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 8,
                  color: colour ?? theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              formatDuration(row.time),
              textAlign: TextAlign.right,
              style: number,
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              compactCount(row.tokens.total),
              textAlign: TextAlign.right,
              style: number,
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              compactCount(row.tokensPerHour.round()),
              textAlign: TextAlign.right,
              style: number,
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              '${row.sessions}',
              textAlign: TextAlign.right,
              style: number,
            ),
          ),
        ],
      ),
    );
  }
}

/// `1.2M`, because a token count in full is unreadable at a glance.
String compactCount(int count) {
  if (count >= 1000000000) return '${(count / 1000000000).toStringAsFixed(1)}B';
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
  return '$count';
}
