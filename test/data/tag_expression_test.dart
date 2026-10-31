import 'package:boorusphere/data/repository/tags_blocker/tag_expression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool blocks(String expression, Iterable<String> tags) =>
      BlockedTagExpression.parse(expression).matches(tags);

  group('BlockedTagExpression', () {
    test('a single tag hides posts that carry it', () {
      expect(blocks('foo', ['foo']), isTrue);
      expect(blocks('foo', ['bar']), isFalse);
    });

    test('matching ignores case on both sides', () {
      expect(blocks('Foo', ['FOO']), isTrue);
      expect(blocks('foo', ['Foo', 'bar']), isTrue);
    });

    test('spaces are AND: every plain term has to be there', () {
      expect(blocks('foo bar', ['foo', 'bar']), isTrue);
      expect(blocks('foo bar', ['foo']), isFalse);
      expect(blocks('foo bar', ['bar']), isFalse);
      expect(blocks('foo bar', ['foo', 'bar', 'baz']), isTrue);
    });

    test('~ puts terms in an OR group', () {
      expect(blocks('~foo ~bar', ['foo']), isTrue);
      expect(blocks('~foo ~bar', ['bar']), isTrue);
      expect(blocks('~foo ~bar', ['baz']), isFalse);
    });

    test('plain terms outside the OR group still have to pass', () {
      expect(blocks('foo ~bar', ['foo', 'bar']), isTrue);
      expect(blocks('foo ~bar', ['foo', 'baz']), isFalse);
      expect(blocks('foo ~bar', ['bar']), isFalse);
    });

    test('- negates a term', () {
      expect(blocks('-foo', ['bar']), isTrue);
      expect(blocks('-foo', ['foo']), isFalse);
      expect(blocks('foo -bar', ['foo']), isTrue);
      expect(blocks('foo -bar', ['foo', 'bar']), isFalse);
    });

    test('empty expressions never match', () {
      expect(blocks('', ['foo']), isFalse);
      expect(blocks('   ', ['foo']), isFalse);
      expect(blocks('-', ['foo']), isFalse);
      expect(blocks('~', ['foo']), isFalse);
    });

    test('operator-looking text after the first operator stays in the tag', () {
      // Exactly one operator is read, so `~-foo` is not parsed as a double
      // negative; the tag it looks for is literally `-foo`.
      expect(blocks('~-foo', ['-foo']), isTrue);
      expect(blocks('--foo', ['-foo']), isFalse);
    });

    test('a single positive tag is exposed for single-tag consumers', () {
      expect(BlockedTagExpression.parse('foo').singlePositiveTag, 'foo');
      expect(BlockedTagExpression.parse('~foo').singlePositiveTag, 'foo');
      expect(BlockedTagExpression.parse('-foo').singlePositiveTag, isNull);
      expect(BlockedTagExpression.parse('foo bar').singlePositiveTag, isNull);
    });

    test('only a plain single tag can refuse a whole query', () {
      expect(BlockedTagExpression.parse('foo').singlePlainTag, 'foo');
      expect(BlockedTagExpression.parse('~foo').singlePlainTag, isNull);
      expect(BlockedTagExpression.parse('-foo').singlePlainTag, isNull);
      expect(BlockedTagExpression.parse('foo bar').singlePlainTag, isNull);
    });
  });

  group('parseBlockedTagExpressions', () {
    test('drops entries with no usable term', () {
      final expressions = parseBlockedTagExpressions(['foo', '', '-', 'bar']);

      expect(expressions, hasLength(2));
      expect(expressions.first.matches(['foo']), isTrue);
      expect(expressions.last.matches(['bar']), isTrue);
    });
  });

  group('matchesBlockedTagExpressions', () {
    test('any entry may hide the post', () {
      final expressions = parseBlockedTagExpressions(['foo bar', '~baz']);

      expect(matchesBlockedTagExpressions(expressions, ['foo', 'bar']), isTrue);
      expect(matchesBlockedTagExpressions(expressions, ['baz']), isTrue);
      expect(matchesBlockedTagExpressions(expressions, ['foo']), isFalse);
      expect(matchesBlockedTagExpressions(expressions, ['bar']), isFalse);
    });
  });
}
