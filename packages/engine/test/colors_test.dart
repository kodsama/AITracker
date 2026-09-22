import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

void main() {
  Log.enabled = false;

  const catalog = Catalog(
    projects: [
      LedgerProject(
        name: 'Byte Buddies - idbuddy',
        hidden: false,
        color: '#FF69BD0D',
      ),
      LedgerProject(name: 'BB - web', hidden: false, color: '#FF112233'),
    ],
  );

  const config = AiTrackerConfig(
    sources: [],
    rules: [
      ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy'),
      ProjectRule(match: 'web', project: 'Byte Buddies - WebWrapper'),
      ProjectRule(match: 'x', project: 'Never - filed'),
    ],
    links: [
      ProjectLink(name: 'Byte Buddies - idbuddy', color: '#FF6C4AB6'),
      ProjectLink(name: 'Byte Buddies - WebWrapper', workingHours: 'BB - web'),
    ],
  );

  group('compareColors', () {
    test('lines each project up with what the ledger draws it in', () {
      final differences = compareColors(config, catalog);

      expect(differences.map((d) => d.project), [
        'Byte Buddies - WebWrapper',
        'Byte Buddies - idbuddy',
        'Never - filed',
      ]);

      final idbuddy = differences.firstWhere(
        (d) => d.project == 'Byte Buddies - idbuddy',
      );
      expect(idbuddy.here, '#FF6C4AB6');
      expect(idbuddy.there, '#FF69BD0D');
      expect(idbuddy.differs, isTrue);
      expect(idbuddy.inLedger, isTrue);
    });

    test('follows the mapped ledger name, not the project name', () {
      final web = compareColors(config, catalog).firstWhere(
        (d) => d.project == 'Byte Buddies - WebWrapper',
      );

      expect(web.ledgerProject, 'BB - web');
      expect(web.there, '#FF112233');
      expect(web.here, isNull);
    });

    test('a project the ledger has never seen is not in it', () {
      final missing = compareColors(config, catalog).firstWhere(
        (d) => d.project == 'Never - filed',
      );

      expect(missing.inLedger, isFalse);
      expect(missing.differs, isFalse);
      expect(missing.toJson(), {
        'project': 'Never - filed',
        'working_hours': 'Never - filed',
        'differs': false,
      });
    });

    test('case does not make a difference a difference', () {
      final same = compareColors(
        const AiTrackerConfig(
          sources: [],
          links: [
            ProjectLink(name: 'Byte Buddies - idbuddy', color: '#ff69bd0d'),
          ],
        ),
        catalog,
      ).single;

      expect(same.differs, isFalse);
    });
  });

  group('pullColors', () {
    test('copies the ledger colours into the mapping', () {
      final pulled = pullColors(config, compareColors(config, catalog));

      expect(pulled.linkFor('Byte Buddies - idbuddy')?.color, '#FF69BD0D');
      // A project with no link yet gains one carrying the colour.
      expect(pulled.linkFor('Byte Buddies - WebWrapper')?.color, '#FF112233');
      expect(pulled.linkFor('Byte Buddies - WebWrapper')?.workingHours, 'BB - web');
    });

    test('takes only the projects it was asked for', () {
      final pulled = pullColors(
        config,
        compareColors(config, catalog),
        only: {'Byte Buddies - idbuddy'},
      );

      expect(pulled.linkFor('Byte Buddies - idbuddy')?.color, '#FF69BD0D');
      expect(pulled.linkFor('Byte Buddies - WebWrapper')?.color, isNull);
    });

    test('a project with no mapping at all gains one carrying the colour', () {
    const ledger = Catalog(
      projects: [
        LedgerProject(name: 'Never - filed', hidden: false, color: '#FF445566'),
      ],
    );

    final pulled = pullColors(config, compareColors(config, ledger));

    expect(pulled.linkFor('Never - filed')?.color, '#FF445566');
    expect(pulled.linkFor('Never - filed')?.workingHours, isNull);
  });

  test('nothing to take leaves the configuration alone', () {
      final pulled = pullColors(config, const []);

      expect(identical(pulled, config), isTrue);
    });
  });
}
