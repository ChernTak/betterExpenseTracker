import 'package:expense_tracker/features/expense/presentation/voice/voice_capture_controller.dart';
import 'package:expense_tracker/features/expense/presentation/voice/voice_confirmation_sheet.dart';
import 'package:expense_tracker/services/auto_categorization_service.dart';
import 'package:expense_tracker/services/expense_nlp_parser_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockVoiceCaptureController extends Mock implements VoiceCaptureController {}

void main() {
  late MockVoiceCaptureController controller;

  const parsed = ParsedVoiceExpense(
    amount: 12.0,
    merchantName: "Mcdonald's",
    transactionDate: null,
    rawTranscript: "spent twelve dollars on lunch at mcdonald's today",
  );
  const suggestion = CategorySuggestion(
    category: 'food_dining',
    confidence: 0.9,
    needsReview: false,
    source: 'keyword',
  );

  setUp(() {
    controller = MockVoiceCaptureController();
    when(() => controller.lastParsed).thenReturn(parsed);
    when(() => controller.lastCategorySuggestion).thenReturn(suggestion);
    when(
      () => controller.confirmSave(
        amount: any(named: 'amount'),
        category: any(named: 'category'),
        merchantName: any(named: 'merchantName'),
        transactionDate: any(named: 'transactionDate'),
      ),
    ).thenAnswer((_) async {});
    when(() => controller.cancelPending()).thenAnswer((_) async {});
  });

  Future<void> pumpWithSheetOpen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => VoiceConfirmationSheet.show(context, controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceConfirmationSheet), findsOneWidget);
  }

  testWidgets('Save calls confirmSave with the edited fields and closes', (tester) async {
    await pumpWithSheetOpen(tester);

    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();

    final captured = verify(
      () => controller.confirmSave(
        amount: captureAny(named: 'amount'),
        category: captureAny(named: 'category'),
        merchantName: captureAny(named: 'merchantName'),
        transactionDate: captureAny(named: 'transactionDate'),
      ),
    ).captured;
    expect(captured[0], 12.0);
    expect(captured[1], 'food_dining');
    verifyNever(() => controller.cancelPending());
    expect(find.byType(VoiceConfirmationSheet), findsNothing);
  });

  testWidgets('Discard calls cancelPending exactly once and closes', (tester) async {
    await pumpWithSheetOpen(tester);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    verify(() => controller.cancelPending()).called(1);
    verifyNever(
      () => controller.confirmSave(
        amount: any(named: 'amount'),
        category: any(named: 'category'),
        merchantName: any(named: 'merchantName'),
        transactionDate: any(named: 'transactionDate'),
      ),
    );
    expect(find.byType(VoiceConfirmationSheet), findsNothing);
  });

  // The actual fix under test: before this, the sheet was
  // isDismissible: false / enableDrag: false, so a wake word firing
  // mid-task on another screen could only be gotten rid of via its own
  // Save/Discard buttons. Now it's dismissible — but a dismissal that
  // bypasses both buttons still has to resolve the controller (see
  // _VoiceConfirmationSheetState.dispose's _resolved fallback), or
  // hands-free listening would never resume.
  testWidgets('swiping the sheet away calls cancelPending exactly once', (tester) async {
    await pumpWithSheetOpen(tester);

    await tester.drag(find.byType(VoiceConfirmationSheet), const Offset(0, 600));
    await tester.pumpAndSettle();

    verify(() => controller.cancelPending()).called(1);
    expect(find.byType(VoiceConfirmationSheet), findsNothing);
  });

  testWidgets('tapping the backdrop calls cancelPending exactly once', (tester) async {
    await pumpWithSheetOpen(tester);

    // Top-left corner of the screen is outside the bottom sheet's content.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    verify(() => controller.cancelPending()).called(1);
    expect(find.byType(VoiceConfirmationSheet), findsNothing);
  });

  testWidgets('amount field is prefilled and editable before saving', (tester) async {
    await pumpWithSheetOpen(tester);

    expect(find.text('12.00'), findsOneWidget);

    await tester.enterText(find.text('12.00'), '25.00');
    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();

    final captured = verify(
      () => controller.confirmSave(
        amount: captureAny(named: 'amount'),
        category: any(named: 'category'),
        merchantName: any(named: 'merchantName'),
        transactionDate: any(named: 'transactionDate'),
      ),
    ).captured;
    expect(captured.single, 25.0);
  });
}
