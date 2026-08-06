import 'package:expense_tracker/services/expense_nlp_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = ExpenseNlpParserService();

  test('parses the FYP example phrase', () {
    final result = parser.parse(
      "spent twelve dollars on lunch at mcdonald's today",
    );
    expect(result.amount, 12.0);
    expect(result.merchantName, "Mcdonald's");
    expect(result.transactionDate, _today());
  });

  test('parses a digit amount with RM prefix and no date phrase', () {
    final result = parser.parse('spent rm45.50 at starbucks');
    expect(result.amount, 45.5);
    expect(result.merchantName, 'Starbucks');
    expect(result.transactionDate, isNull); // left for backend's CURRENT_DATE default
  });

  test('resolves "yesterday" to one day before today', () {
    final result = parser.parse('spent five dollars on coffee yesterday');
    expect(result.amount, 5.0);
    expect(result.transactionDate, _today().subtract(const Duration(days: 1)));
  });

  test('parses compound number words', () {
    final result = parser.parse('spent twenty five dollars at ikea');
    expect(result.amount, 25.0);
    expect(result.merchantName, 'Ikea');
  });

  test('returns null amount when nothing numeric was said', () {
    final result = parser.parse('lunch at mcdonald\'s today');
    expect(result.amount, isNull);
    expect(result.hasAmount, isFalse);
  });

  test('returns null merchant when no preposition phrase is present', () {
    final result = parser.parse('spent ten dollars today');
    expect(result.amount, 10.0);
    expect(result.merchantName, isNull);
  });
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}
