import 'dart:math' as math;

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';

import '../measures.dart';

/// One measure per bucket, stacked by project.
///
/// One axis, one measure: bar height is hours or tokens, never both, and the
/// segments inside a bar are what went to each project. Empty buckets stay in
/// place so a quiet week reads as quiet rather than disappearing.
class StackedBars extends StatefulWidget {
  /// Creates the chart.
  const StackedBars({
    required this.buckets,
    required this.width,
    required this.series,
    required this.colorOf,
    required this.amount,
    super.key,
  });

  /// Bucket start to project to however much, oldest first.
  final Map<DateTime, Map<String, double>> buckets;

  /// What the height means, and how it reads.
  final Amount amount;

  /// How wide one bar is, which decides the x labels.
  final Bucket width;

  /// Projects in the order they stack, bottom first.
  final List<String> series;

  /// Colour for a project.
  final Color Function(String project) colorOf;

  @override
  State<StackedBars> createState() => _StackedBarsState();
}

class _StackedBarsState extends State<StackedBars> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = widget.buckets.keys.toList();
    if (keys.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _Geometry(constraints.maxWidth, 260, keys.length);
        return MouseRegion(
          onHover: (event) {
            final index = geometry.indexAt(event.localPosition.dx);
            if (index != _hovered) setState(() => _hovered = index);
          },
          onExit: (_) => setState(() => _hovered = null),
          child: SizedBox(
            height: 260,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BarsPainter(
                      buckets: widget.buckets,
                      series: widget.series,
                      colorOf: widget.colorOf,
                      bucket: widget.width,
                      amount: widget.amount,
                      hovered: _hovered,
                      surface: theme.colorScheme.surface,
                      grid: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.45,
                      ),
                      ink: theme.colorScheme.onSurfaceVariant,
                      textDirection: Directionality.of(context),
                    ),
                  ),
                ),
                if (_hovered != null && _hovered! < keys.length)
                  _Tooltip(
                    geometry: geometry,
                    index: _hovered!,
                    day: keys[_hovered!],
                    row: widget.buckets[keys[_hovered!]]!,
                    bucket: widget.width,
                    amount: widget.amount,
                    colorOf: widget.colorOf,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Where the plot sits inside the box, so hover and paint agree.
class _Geometry {
  _Geometry(this.width, this.height, this.count);

  final double width;
  final double height;
  final int count;

  static const double left = 52;
  static const double bottom = 26;
  static const double top = 14;

  double get plotWidth => math.max(width - left, 1);
  double get slot => plotWidth / math.max(count, 1);
  double get barWidth => math.min(slot * 0.68, 46);

  double centreOf(int index) => left + slot * (index + 0.5);

  int? indexAt(double x) {
    if (x < left) return null;
    final index = ((x - left) / slot).floor();
    return index < 0 || index >= count ? null : index;
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.buckets,
    required this.series,
    required this.colorOf,
    required this.bucket,
    required this.amount,
    required this.hovered,
    required this.surface,
    required this.grid,
    required this.ink,
    required this.textDirection,
  });

  final Map<DateTime, Map<String, double>> buckets;
  final List<String> series;
  final Color Function(String) colorOf;
  final Bucket bucket;
  final Amount amount;
  final int? hovered;
  final Color surface;
  final Color grid;
  final Color ink;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final keys = buckets.keys.toList();
    final geometry = _Geometry(size.width, size.height, keys.length);
    final plotHeight = size.height - _Geometry.bottom - _Geometry.top;
    final ceiling = amount.ceiling(
      buckets.values.fold<double>(0, (most, row) => math.max(most, rowTotal(row))),
    );

    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final value = ceiling * tick / 4;
      final y = _Geometry.top + plotHeight * (1 - tick / 4);
      canvas.drawLine(Offset(_Geometry.left, y), Offset(size.width, y), line);
      _label(
        canvas,
        amount.tick(value),
        Offset(_Geometry.left - 8, y),
        align: TextAlign.right,
        anchorRight: true,
      );
    }

    final step = math.max(1, (keys.length / 12).ceil());
    for (var i = 0; i < keys.length; i++) {
      final row = buckets[keys[i]]!;
      final centre = geometry.centreOf(i);
      var y = _Geometry.top + plotHeight;
      final isHovered = hovered == i;

      for (final project in series) {
        final value = row[project];
        if (value == null || value <= 0) continue;
        final height = plotHeight * value / ceiling;
        if (height <= 0) continue;
        final top = y - height;
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTRB(
            centre - geometry.barWidth / 2,
            top,
            centre + geometry.barWidth / 2,
            // A 2px surface gap between segments, so a stack reads as parts.
            y - 2,
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = isHovered
                ? colorOf(project)
                : colorOf(project).withValues(alpha: hovered == null ? 1 : 0.55),
        );
        y = top;
      }

      if (i % step == 0) {
        _label(
          canvas,
          _xLabel(keys[i]),
          Offset(centre, size.height - _Geometry.bottom + 6),
          align: TextAlign.center,
        );
      }
    }
  }

  String _xLabel(DateTime at) => switch (bucket) {
    Bucket.day => '${_weekday(at)} ${at.day}',
    Bucket.week => '${at.day} ${_month(at)}',
    Bucket.month => _month(at),
  };

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    required TextAlign align,
    bool anchorRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: ink, fontSize: 11),
      ),
      textDirection: textDirection,
      textAlign: align,
    )..layout();
    final dx = switch (align) {
      TextAlign.center => at.dx - painter.width / 2,
      TextAlign.right => at.dx - painter.width,
      _ => at.dx,
    };
    painter.paint(
      canvas,
      Offset(dx, anchorRight ? at.dy - painter.height / 2 : at.dy),
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.buckets != buckets ||
      old.hovered != hovered ||
      old.amount != amount ||
      old.ink != ink;
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.geometry,
    required this.index,
    required this.day,
    required this.row,
    required this.bucket,
    required this.amount,
    required this.colorOf,
  });

  final _Geometry geometry;
  final int index;
  final DateTime day;
  final Map<String, double> row;
  final Bucket bucket;
  final Amount amount;
  final Color Function(String) colorOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = row.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final left = clampDouble(
      geometry.centreOf(index) + 12,
      0,
      math.max(geometry.width - 220, 0),
    );

    return Positioned(
      left: left,
      top: 8,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_title(day, bucket), style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              if (entries.isEmpty)
                Text('Nothing', style: theme.textTheme.bodySmall)
              else
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorOf(entry.key),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190),
                          child: Text(
                            entry.key,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          amount.format(entry.value),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              if (entries.length > 1) ...[
                const SizedBox(height: 4),
                Text(
                  'Total ${amount.format(rowTotal(row))}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _title(DateTime at, Bucket bucket) => switch (bucket) {
    Bucket.day => '${_weekday(at)} ${at.day} ${_month(at)}',
    Bucket.week => 'Week of ${at.day} ${_month(at)}',
    Bucket.month => '${_month(at)} ${at.year}',
  };
}

String _weekday(DateTime at) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];

String _month(DateTime at) => const [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][at.month - 1];
