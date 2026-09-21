import 'catalog.dart';
import 'config.dart';

/// What colour a project has on each side.
class ColourDifference {
  /// Creates the comparison.
  const ColourDifference({
    required this.project,
    required this.ledgerProject,
    this.here,
    this.there,
  });

  /// Project name as this tool knows it.
  final String project;

  /// Project name in WorkingHours.
  final String ledgerProject;

  /// Colour in the mapping, null when it has none yet.
  final String? here;

  /// Colour in the ledger, null when the ledger has no such project.
  final String? there;

  /// Whether the two sides disagree.
  bool get differs => (here ?? '').toUpperCase() != (there ?? '').toUpperCase();

  /// Whether the ledger holds this project at all. Nothing can be pushed to or
  /// pulled from a project that is not there yet.
  bool get inLedger => there != null;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'project': project,
    'working_hours': ledgerProject,
    if (here != null) 'here': here,
    if (there != null) 'there': there,
    'differs': differs,
  };
}

/// Compares every mapped project's colour with the ledger's.
///
/// Both directions read from this: pushing writes [ColourDifference.here] into
/// the ledger, pulling copies [ColourDifference.there] into the mapping, and
/// the list itself is what a preview shows.
List<ColourDifference> compareColors(AiTrackerConfig config, Catalog catalog) {
  final ledger = {
    for (final project in catalog.projects) project.name: project.color,
  };
  final names = <String>{
    for (final rule in config.rules) rule.project,
    for (final link in config.links) link.name,
  }.toList()..sort();

  return [
    for (final name in names)
      ColourDifference(
        project: name,
        ledgerProject: config.linkFor(name)?.workingHoursProject ?? name,
        here: config.linkFor(name)?.color,
        there: ledger[config.linkFor(name)?.workingHoursProject ?? name],
      ),
  ];
}

/// The configuration with the ledger's colours copied into the mapping.
///
/// [only] limits it to those projects; null takes every difference. A project
/// the ledger does not hold is left alone, since there is nothing to copy.
AiTrackerConfig pullColors(
  AiTrackerConfig config,
  List<ColourDifference> differences, {
  Set<String>? only,
}) {
  final wanted = [
    for (final difference in differences)
      if (difference.differs &&
          difference.inLedger &&
          (only == null || only.contains(difference.project)))
        difference,
  ];
  if (wanted.isEmpty) return config;

  final links = [...config.links];
  for (final difference in wanted) {
    final index = links.indexWhere((link) => link.name == difference.project);
    if (index < 0) {
      links.add(ProjectLink(name: difference.project, color: difference.there));
    } else {
      links[index] = links[index].copyWith(color: difference.there);
    }
  }
  return config.copyWith(links: links);
}
