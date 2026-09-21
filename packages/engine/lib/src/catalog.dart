import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'config.dart';

/// A project as the WorkingHours ledger holds it.
class LedgerProject {
  /// Creates the entry.
  const LedgerProject({
    required this.name,
    required this.hidden,
    this.color,
    this.customer,
  });

  /// Project name, e.g. `Sigma - Axis Camera`.
  final String name;

  /// Whether WorkingHours has it archived.
  final bool hidden;

  /// Colour the ledger draws it in, `#AARRGGBB`.
  final String? color;

  /// Tag attached to the project, which is how the ledger records who the work
  /// is for. Null when no tag is linked.
  final String? customer;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'name': name,
    'hidden': hidden,
    if (color != null) 'color': color,
    if (customer != null) 'customer': customer,
  };
}

/// A tag as one of the apps holds it.
class LedgerTag {
  /// Creates the entry.
  const LedgerTag({required this.value, this.hidden = false});

  /// Tag text.
  final String value;

  /// Whether the app has it archived.
  final bool hidden;

  /// JSON form.
  Map<String, Object?> toJson() => {'value': value, 'hidden': hidden};
}

/// Everything the two apps already know, so a mapping can point at real things
/// instead of inventing names.
class Catalog {
  /// Creates a catalog.
  const Catalog({
    this.projects = const [],
    this.tags = const [],
    this.customers = const [],
    this.diariumTags = const [],
  });

  /// WorkingHours projects.
  final List<LedgerProject> projects;

  /// WorkingHours tags.
  final List<LedgerTag> tags;

  /// Tags WorkingHours has attached to a project, which in this ledger is what
  /// a customer is: `Sigma`, `Additude`, `RiACT`.
  final List<String> customers;

  /// Diarium tags.
  final List<LedgerTag> diariumTags;

  /// JSON form, as the MCP tool reports it.
  Map<String, Object?> toJson() => {
    'projects': [for (final project in projects) project.toJson()],
    'tags': [for (final tag in tags) tag.toJson()],
    'customers': customers,
    'diarium_tags': [for (final tag in diariumTags) tag.toJson()],
  };

  /// Reads both stores. Either being absent or unreadable yields empty lists
  /// rather than an error: a catalog is a convenience, never a precondition.
  ///
  /// Reading is safe while the apps are running; only writing is not.
  static Catalog read(AiTrackerConfig config) {
    final ledger = _readWorkingHours(
      AiTrackerConfig.resolveHome(config.workingHours.databasePath),
    );
    return Catalog(
      projects: ledger.projects,
      tags: ledger.tags,
      customers: ledger.customers,
      diariumTags: _readDiariumTags(
        AiTrackerConfig.resolveHome(config.diarium.databasePath),
      ),
    );
  }

  static Catalog _readWorkingHours(String path) {
    if (!File(path).existsSync()) return const Catalog();
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      final customers = <String>{};
      final links = <String, String>{};
      for (final row in db.select(
        'select p.Name as project, t.Value as tag from ProjectTags pt '
        'join Projects p on p.ProjectId = pt.ProjectId '
        'join Tags t on t.TagId = pt.TagId',
      )) {
        final tag = '${row['tag']}';
        customers.add(tag);
        links['${row['project']}'] = tag;
      }
      return Catalog(
        projects: [
          for (final row in db.select(
            'select Name, Hidden, Color from Projects order by Name',
          ))
            LedgerProject(
              name: '${row['Name']}',
              hidden: (row['Hidden'] as int? ?? 0) != 0,
              color: row['Color'] as String?,
              customer: links['${row['Name']}'],
            ),
        ],
        tags: [
          for (final row in db.select(
            'select Value, Hidden from Tags order by Value',
          ))
            LedgerTag(
              value: '${row['Value']}',
              hidden: (row['Hidden'] as int? ?? 0) != 0,
            ),
        ],
        customers: customers.toList()..sort(),
      );
    } on SqliteException {
      return const Catalog();
    } finally {
      db?.close();
    }
  }

  static List<LedgerTag> _readDiariumTags(String path) {
    if (!File(path).existsSync()) return const [];
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      return [
        for (final row in db.select('select Value from Tags order by Value'))
          LedgerTag(value: '${row['Value']}'),
      ];
    } on SqliteException {
      return const [];
    } finally {
      db?.close();
    }
  }
}
