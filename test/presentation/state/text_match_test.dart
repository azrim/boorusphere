import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/utils/text_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchRank', () {
    test('ranks the match position, closest first', () {
      expect(matchRank('blue_eyes', 'blue_eyes'), 0);
      expect(matchRank('blue_eyes', 'blue'), 1);
      expect(matchRank('long_hair', 'hair'), 2);
      expect(matchRank('ahoge', 'hoge'), 3);
    });

    test('treats a space as a word boundary too', () {
      expect(matchRank('long hair', 'hair'), 2);
    });

    test('ignores case', () {
      expect(matchRank('Blue_Eyes', 'BLUE'), 1);
      expect(matchRank('Blue_Eyes', 'eyes'), 2);
    });

    test('flags a tag that does not contain the text', () {
      expect(matchRank('animal_ears', 'zzz'), kNoMatch);
    });
  });

  group('compareSuggestions', () {
    test('puts the tag being spelled above popular substring matches', () {
      final list = [
        const Suggestion('long_hair', 9000),
        const Suggestion('hair', 4000),
        const Suggestion('hair_ornament', 100),
        const Suggestion('animal_ears', 9999),
      ];

      list.sort((a, b) => compareSuggestions(a, b, 'hair'));

      expect(list.map((it) => it.name), [
        'hair',
        'hair_ornament',
        'long_hair',
        'animal_ears',
      ]);
    });

    test('breaks a tie inside one rank by post count', () {
      final list = [
        const Suggestion('blue_sky', 10),
        const Suggestion('blue_eyes', 900),
      ];

      list.sort((a, b) => compareSuggestions(a, b, 'blue'));

      expect(list.first.name, 'blue_eyes');
    });
  });
}
