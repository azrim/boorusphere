import 'package:boorusphere/data/repository/web_clearance/web_clearance_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../utils/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveContainer = HiveTestContainer();
  tearDownAll(hiveContainer.dispose);

  group('WebClearance', () {
    test('round-trips through the stored form', () {
      const clearance = WebClearance(
        userAgent: 'Mozilla/5.0 (Linux; Android 14)',
        cookies: 'cf_clearance=abc; __cf_bm=def',
      );

      expect(WebClearance.tryParse(clearance.encode()), clearance);
    });

    test('refuses what an older or hand-written entry could hold', () {
      expect(WebClearance.tryParse(null), isNull);
      expect(WebClearance.tryParse('not json'), isNull);
      expect(WebClearance.tryParse('{"ua": "x"}'), isNull);
      expect(WebClearance.tryParse('{"ua": "", "cookie": "a=1"}'), isNull);
      expect(WebClearance.tryParse('{"ua": "x", "cookie": ""}'), isNull);
    });
  });

  group('WebClearanceRepo', () {
    test('answers for the host that solved it and its subdomains', () async {
      final repo = WebClearanceRepo(null);
      await repo.save(
        host: 'danbooru.donmai.us',
        userAgent: 'agent',
        cookies: 'cf_clearance=abc',
      );

      expect(repo.forHost('danbooru.donmai.us')?.cookies, 'cf_clearance=abc');
      expect(repo.forHost('DANBOORU.donmai.us')?.cookies, 'cf_clearance=abc');
      expect(repo.forHost('safebooru.donmai.us'), isNull);
      expect(repo.forHost('example.com'), isNull);
    });

    test('prefers the most specific entry', () async {
      final repo = WebClearanceRepo(null);
      await repo.save(
        host: 'donmai.us',
        userAgent: 'site agent',
        cookies: 'site=1',
      );
      await repo.save(
        host: 'cdn.donmai.us',
        userAgent: 'cdn agent',
        cookies: 'cdn=1',
      );

      expect(repo.forHost('cdn.donmai.us')?.cookies, 'cdn=1');
      expect(repo.forHost('danbooru.donmai.us')?.cookies, 'site=1');
    });

    test('a host prefix does not count as a parent', () async {
      final repo = WebClearanceRepo(null);
      await repo.save(
        host: 'donmai.us',
        userAgent: 'agent',
        cookies: 'cf_clearance=abc',
      );

      expect(repo.forHost('notdonmai.us'), isNull);
    });

    test(
      'refuses an empty answer, which would clear a working session',
      () async {
        final repo = WebClearanceRepo(null);
        await repo.save(host: 'a.test', userAgent: 'agent', cookies: 'a=1');
        await repo.save(host: 'a.test', userAgent: '', cookies: 'b=2');
        await repo.save(host: 'a.test', userAgent: 'agent', cookies: '');

        expect(repo.forHost('a.test')?.cookies, 'a=1');
      },
    );

    test('persists to the box it was given', () async {
      final box = await Hive.openBox<String>(WebClearanceRepo.key);
      addTearDown(() async {
        await Hive.deleteBoxFromDisk(WebClearanceRepo.key);
      });

      final repo = WebClearanceRepo(box);
      await repo.save(
        host: 'danbooru.donmai.us',
        userAgent: 'agent',
        cookies: 'cf_clearance=abc',
      );

      final reopened = WebClearanceRepo(box);
      expect(reopened.forHost('danbooru.donmai.us')?.userAgent, 'agent');
      expect(
        reopened.forHost('danbooru.donmai.us')?.cookies,
        'cf_clearance=abc',
      );
    });
  });
}
