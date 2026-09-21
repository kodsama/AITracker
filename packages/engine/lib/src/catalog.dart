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
    this.company,
  });

  /// Project name, e.g. `Sigma - Axis Camera`.
  final String name;

  /// Whether WorkingHours has it archived.
  final bool hidden;

  /// Colour the ledger draws it in, `#AARRGGBB`.
  final String? color;

  /// Tag attached to the project, which is how the ledger records who the work
  /// is for. Null when no tag is linked.
  final String? company;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'name': name,
    'hidden': hidden,
    if (color != null) 'color': color,
    if (company != null) 'company': company,
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
    this.companies = const [],
  });

  /// WorkingHours projects.
  final List<LedgerProject> projects;

  /// WorkingHours tags.
  final List<LedgerTag> tags;

  /// Tags WorkingHours has attached to a project, which in this ledger is what
  /// a company is: `Sigma`, `Additude`, `RiACT`.
  final List<String> companies;

  /// JSON form, as the MCP tool reports it.
  Map<String, Object?> toJson() => {
    'projects': [for (final project in projects) project.toJson()],
    'tags': [for (final tag in tags) tag.toJson()],
    'companies': companies,
  };

  /// Reads the ledger. A store that is absent or unreadable yields empty lists
  /// rather than an error: a catalog is a convenience, never a precondition.
  ///
  /// Reading is safe while WorkingHours is running; only writing is not.
  static Catalog read(AiTrackerConfig config) => _readWorkingHours(
    AiTrackerConfig.resolveHome(config.workingHours.databasePath),
  );

  static Catalog _readWorkingHours(String path) {
    if (!File(path).existsSync()) return const Catalog();
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      final companies = <String>{};
      final links = <String, String>{};
      for (final row in db.select(
        'select p.Name as project, t.Value as tag from ProjectTags pt '
        'join Projects p on p.ProjectId = pt.ProjectId '
        'join Tags t on t.TagId = pt.TagId',
      )) {
        final tag = '${row['tag']}';
        companies.add(tag);
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
              company: links['${row['Name']}'],
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
        companies: companies.toList()..sort(),
      );
    } on SqliteException {
      return const Catalog();
    } finally {
      db?.close();
    }
  }

}
