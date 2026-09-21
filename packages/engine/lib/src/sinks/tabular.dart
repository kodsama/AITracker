import 'dart:io';

import 'package:excel/excel.dart';

import '../config.dart';
import '../tracking.dart';
import 'report.dart';

/// Writes the blocks to a CSV file and an Excel workbook.
///
/// Unlike the app sinks this one owns its files outright: each run rewrites
/// them from the transcripts, so there is nothing to deduplicate and no store
/// to guard.
class TabularSink {
  /// Creates the sink.
  const TabularSink({required this.config});

  /// Output paths.
  final TabularSinkConfig config;

  /// Column order, shared by both formats.
  static const List<String> columns = [
    'Date',
    'Start',
    'End',
    'Hours',
    'Duration',
    'Company',
    'Project',
    'Description',
    'Repository',
    'Sessions',
  ];

  /// Writes both files, or reports what they would hold.
  ///
  /// Unmapped blocks are included with an empty project column: a spreadsheet
  /// is where you go to see what the rules missed.
  SyncReport sync(List<TrackedBlock> blocks, {bool dryRun = true}) {
    final rows = blocks.where((b) => !b.excluded).toList()
      ..sort((a, b) => a.block.start.compareTo(b.block.start));
    if (dryRun) {
      return SyncReport(
        sink: 'tabular',
        applied: false,
        written: rows,
        notes: [
          'would write ${rows.length} rows to ${AiTrackingConfig.resolveHome(config.csvPath)}',
          'would write ${rows.length} rows to ${AiTrackingConfig.resolveHome(config.xlsxPath)}',
        ],
      );
    }

    final outputs = <String>[
      _writeCsv(rows),
      _writeXlsx(rows),
    ];
    return SyncReport(
      sink: 'tabular',
      applied: true,
      written: rows,
      outputs: outputs,
    );
  }

  String _writeCsv(List<TrackedBlock> rows) {
    final path = AiTrackingConfig.resolveHome(config.csvPath);
    final buffer = StringBuffer()..writeln(columns.join(','));
    for (final row in rows) {
      buffer.writeln(_cells(row).map(_escape).join(','));
    }
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsStringSync(buffer.toString());
    return path;
  }

  String _writeXlsx(List<TrackedBlock> rows) {
    final path = AiTrackingConfig.resolveHome(config.xlsxPath);
    final book = Excel.createExcel();
    final sheet = book['AI hours'];
    book.setDefaultSheet('AI hours');
    book.delete('Sheet1');
    sheet.appendRow([for (final column in columns) TextCellValue(column)]);
    for (final row in rows) {
      final cells = _cells(row);
      sheet.appendRow([
        TextCellValue(cells[0]),
        TextCellValue(cells[1]),
        TextCellValue(cells[2]),
        DoubleCellValue(double.parse(cells[3])),
        TextCellValue(cells[4]),
        TextCellValue(cells[5]),
        TextCellValue(cells[6]),
        TextCellValue(cells[7]),
        TextCellValue(cells[8]),
        IntCellValue(int.parse(cells[9])),
      ]);
    }
    final bytes = book.encode();
    if (bytes == null) throw const FileSystemException('could not encode the workbook');
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return path;
  }

  List<String> _cells(TrackedBlock row) => [
    row.day.toIso8601String().substring(0, 10),
    _clock(row.block.start),
    _clock(row.block.end),
    (row.block.duration.inMinutes / 60).toStringAsFixed(2),
    formatDuration(row.block.duration),
    row.company ?? '',
    row.project ?? '',
    row.description,
    row.repo,
    '${row.block.sessions}',
  ];

  static String _clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  static String _escape(String value) =>
      value.contains(RegExp('[",\n]')) ? '"${value.replaceAll('"', '""')}"' : value;
}
