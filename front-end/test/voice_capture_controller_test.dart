import 'package:expense_tracker/features/expense/data/datasources/pending_voice_expense_dao.dart';
import 'package:expense_tracker/features/expense/data/datasources/voice_datasource.dart';
import 'package:expense_tracker/features/expense/data/datasources/voice_diagnostic_log_dao.dart';
import 'package:expense_tracker/features/expense/presentation/voice/voice_capture_controller.dart';
import 'package:expense_tracker/services/auto_categorization_service.dart';
import 'package:expense_tracker/services/expense_nlp_parser_service.dart';
import 'package:expense_tracker/services/voice_audio_feedback_service.dart';
import 'package:expense_tracker/services/voice_expense_sync_service.dart';
import 'package:expense_tracker/services/wake_word_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart' show MicrophoneAccessDeniedException;

class MockWakeWordService extends Mock implements WakeWordService {}

class MockVoiceDatasource extends Mock implements VoiceDatasource {}

class MockExpenseNlpParserService extends Mock implements ExpenseNlpParserService {}

class MockAutoCategorizationService extends Mock implements AutoCategorizationService {}

class MockPendingVoiceExpenseDao extends Mock implements PendingVoiceExpenseDao {}

class MockVoiceExpenseSyncService extends Mock implements VoiceExpenseSyncService {}

class MockVoiceAudioFeedbackService extends Mock implements VoiceAudioFeedbackService {}

class MockVoiceDiagnosticLogDao extends Mock implements VoiceDiagnosticLogDao {}

void main() {
  // _onWakeWordDetected calls HapticFeedback.mediumImpact(), which needs a
  // live platform-channel binding even though the call is fire-and-forget.
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockWakeWordService wakeWordService;
  late MockVoiceDatasource transcriptionService;
  late MockExpenseNlpParserService parser;
  late MockAutoCategorizationService autoCategorizationService;
  late MockPendingVoiceExpenseDao outbox;
  late MockVoiceExpenseSyncService syncService;
  late MockVoiceAudioFeedbackService audioFeedback;
  late MockVoiceDiagnosticLogDao diagnostics;
  late VoiceCaptureController controller;

  // Captured from WakeWordService.start(callback) so tests can simulate a
  // wake-word detection by invoking it directly, the same way the real
  // WakeWordService would once Vosk's grammar matches "ok app".
  Function()? capturedWakeCallback;

  Future<void> triggerWakeWord() async {
    await (capturedWakeCallback!() as Future);
  }

  const suggestion = CategorySuggestion(
    category: 'food_dining',
    confidence: 0.9,
    needsReview: false,
    source: 'keyword',
  );

  setUpAll(() {
    registerFallbackValue(() {});
  });

  setUp(() {
    wakeWordService = MockWakeWordService();
    transcriptionService = MockVoiceDatasource();
    parser = MockExpenseNlpParserService();
    autoCategorizationService = MockAutoCategorizationService();
    outbox = MockPendingVoiceExpenseDao();
    syncService = MockVoiceExpenseSyncService();
    audioFeedback = MockVoiceAudioFeedbackService();
    diagnostics = MockVoiceDiagnosticLogDao();
    capturedWakeCallback = null;

    when(() => wakeWordService.start(any())).thenAnswer((invocation) async {
      capturedWakeCallback = invocation.positionalArguments[0] as Function();
    });
    when(() => wakeWordService.stop()).thenAnswer((_) async {});
    when(() => wakeWordService.dispose()).thenAnswer((_) async {});
    when(() => transcriptionService.dispose()).thenAnswer((_) async {});
    when(() => audioFeedback.playWake()).thenAnswer((_) async {});
    when(() => audioFeedback.playSuccess()).thenAnswer((_) async {});
    when(() => audioFeedback.playError()).thenAnswer((_) async {});
    when(() => diagnostics.log(any(), detail: any(named: 'detail'))).thenAnswer((_) async {});
    when(
      () => autoCategorizationService.categorize(any(), source: any(named: 'source')),
    ).thenAnswer((_) async => suggestion);
    when(
      () => outbox.insert(
        amount: any(named: 'amount'),
        category: any(named: 'category'),
        merchantName: any(named: 'merchantName'),
        transactionDate: any(named: 'transactionDate'),
        rawTranscript: any(named: 'rawTranscript'),
      ),
    ).thenAnswer((_) async => 1);
    when(() => syncService.flushPending()).thenAnswer((_) async {});

    controller = VoiceCaptureController(
      wakeWordService: wakeWordService,
      transcriptionService: transcriptionService,
      parser: parser,
      autoCategorizationService: autoCategorizationService,
      outbox: outbox,
      syncService: syncService,
      audioFeedback: audioFeedback,
      diagnostics: diagnostics,
    );
  });

  group('startHandsFree', () {
    test('success transitions to listeningForWake', () async {
      await controller.startHandsFree();
      expect(controller.status, VoiceCaptureStatus.listeningForWake);
      expect(controller.isHandsFreeActive, isTrue);
    });

    test('WakeWordUnsupportedPlatformException -> unsupportedPlatform', () async {
      when(() => wakeWordService.start(any())).thenThrow(WakeWordUnsupportedPlatformException());

      await controller.startHandsFree();

      expect(controller.status, VoiceCaptureStatus.unsupportedPlatform);
      expect(controller.isHandsFreeActive, isFalse);
      expect(controller.errorMessage, isNotNull);
    });

    test('MicrophoneAccessDeniedException -> permissionDenied', () async {
      when(() => wakeWordService.start(any())).thenThrow(MicrophoneAccessDeniedException());

      await controller.startHandsFree();

      expect(controller.status, VoiceCaptureStatus.permissionDenied);
    });

    test('unexpected error -> error status, not a crash', () async {
      when(() => wakeWordService.start(any())).thenThrow(StateError('model missing'));

      await controller.startHandsFree();

      expect(controller.status, VoiceCaptureStatus.error);
      expect(controller.errorMessage, contains('model missing'));
    });
  });

  group('wake word -> transcription outcomes', () {
    // Regression test for a real crash found via on-device logcat
    // (2026-08-28): the wake-word-to-transcription handoff can race Vosk's
    // native teardown and throw. Before this fix, an exception here
    // propagated straight out of _onWakeWordDetected — which is invoked
    // from inside WakeWordService's own stream listener, so it never even
    // reached a caller's try/catch. This confirms it now degrades to a
    // normal noSpeechDetected-style failure instead of crashing.
    test('listenOnce throwing degrades gracefully instead of propagating', () async {
      when(() => transcriptionService.listenOnce()).thenThrow(Exception('error reading audio buffer'));

      await controller.startHandsFree();
      await triggerWakeWord(); // must not throw

      expect(controller.status, VoiceCaptureStatus.listeningForWake);
      verify(() => audioFeedback.playError()).called(1);
      verify(
        () => diagnostics.log('transcription_error', detail: any(named: 'detail')),
      ).called(1);
      verify(() => wakeWordService.start(any())).called(2);
    });

    test('no speech detected: feedback fires, then auto-resumes listening', () async {
      when(() => transcriptionService.listenOnce()).thenAnswer((_) async => null);

      await controller.startHandsFree();
      await triggerWakeWord();

      // noSpeechDetected is a transient status _resumeListeningIfActive()
      // immediately moves past — by the time triggerWakeWord() settles, a
      // successful resume has already landed the controller back in
      // listeningForWake. The diagnostics/audio calls below are what
      // actually prove the no-speech branch ran.
      expect(controller.status, VoiceCaptureStatus.listeningForWake);
      verify(() => audioFeedback.playWake()).called(1);
      verify(() => audioFeedback.playError()).called(1);
      verify(() => diagnostics.log('wake_detected')).called(1);
      verify(() => diagnostics.log('no_speech_detected')).called(1);
      // Resumed listening after the failed attempt — start() called once
      // for the initial startHandsFree, once more to resume.
      verify(() => wakeWordService.start(any())).called(2);
    });

    test('noSpeechDetected is actually emitted mid-flow, not skipped', () async {
      // MainShell's snackbar ("Didn't catch that...") only fires because
      // notifyListeners() runs while status == noSpeechDetected, even
      // though the controller moves past it a moment later — this is what
      // the previous test's final-status assertion can't see.
      when(() => transcriptionService.listenOnce()).thenAnswer((_) async => null);
      final seenStatuses = <VoiceCaptureStatus>[];
      controller.addListener(() => seenStatuses.add(controller.status));

      await controller.startHandsFree();
      await triggerWakeWord();

      expect(seenStatuses, contains(VoiceCaptureStatus.noSpeechDetected));
      expect(seenStatuses.last, VoiceCaptureStatus.listeningForWake);
    });

    test('parsed with amount: status parsed, no error feedback fired', () async {
      when(() => transcriptionService.listenOnce()).thenAnswer(
        (_) async => "spent twelve dollars on lunch at mcdonald's today",
      );
      const parsed = ParsedVoiceExpense(
        amount: 12.0,
        merchantName: "Mcdonald's",
        transactionDate: null,
        rawTranscript: "spent twelve dollars on lunch at mcdonald's today",
      );
      when(() => parser.parse(any())).thenReturn(parsed);

      await controller.startHandsFree();
      await triggerWakeWord();

      expect(controller.status, VoiceCaptureStatus.parsed);
      expect(controller.lastParsed, parsed);
      expect(controller.lastCategorySuggestion, suggestion);
      verify(() => audioFeedback.playWake()).called(1);
      verifyNever(() => audioFeedback.playError());
      verify(() => diagnostics.log('wake_detected')).called(1);
      verifyNever(() => diagnostics.log('parse_failed', detail: any(named: 'detail')));
    });

    test('parsed without amount: status parseFailed, error feedback fired', () async {
      when(() => transcriptionService.listenOnce()).thenAnswer((_) async => 'lunch at mcdonalds today');
      const parsed = ParsedVoiceExpense(
        amount: null,
        merchantName: 'Mcdonalds',
        transactionDate: null,
        rawTranscript: 'lunch at mcdonalds today',
      );
      when(() => parser.parse(any())).thenReturn(parsed);

      await controller.startHandsFree();
      await triggerWakeWord();

      expect(controller.status, VoiceCaptureStatus.parseFailed);
      verify(() => audioFeedback.playError()).called(1);
      verify(() => diagnostics.log('parse_failed', detail: parsed.rawTranscript)).called(1);
    });

    test('categorization uses merchant when present, else falls back to transcript', () async {
      const transcript = 'spent ten dollars today';
      when(() => transcriptionService.listenOnce()).thenAnswer((_) async => transcript);
      const parsed = ParsedVoiceExpense(
        amount: 10.0,
        merchantName: null,
        transactionDate: null,
        rawTranscript: transcript,
      );
      when(() => parser.parse(any())).thenReturn(parsed);

      await controller.startHandsFree();
      await triggerWakeWord();

      verify(() => autoCategorizationService.categorize(transcript, source: 'voice')).called(1);
    });
  });

  group('confirmSave', () {
    test('writes to the outbox, plays success, resumes listening', () async {
      when(() => transcriptionService.listenOnce()).thenAnswer((_) async => 'spent rm10 at ikea');
      const parsed = ParsedVoiceExpense(
        amount: 10.0,
        merchantName: 'Ikea',
        transactionDate: null,
        rawTranscript: 'spent rm10 at ikea',
      );
      when(() => parser.parse(any())).thenReturn(parsed);

      await controller.startHandsFree();
      await triggerWakeWord();
      await controller.confirmSave(amount: 10.0, category: 'shopping', merchantName: 'Ikea');

      verify(
        () => outbox.insert(
          amount: 10.0,
          category: 'shopping',
          merchantName: 'Ikea',
          transactionDate: null,
          rawTranscript: 'spent rm10 at ikea',
        ),
      ).called(1);
      verify(() => syncService.flushPending()).called(1);
      verify(() => audioFeedback.playSuccess()).called(1);
      verify(() => diagnostics.log('saved', detail: 'spent rm10 at ikea')).called(1);
      expect(controller.lastParsed, isNull);
      expect(controller.lastCategorySuggestion, isNull);
      expect(controller.status, VoiceCaptureStatus.listeningForWake);
    });

    test('does not retry listening after a setup failure status', () async {
      when(() => wakeWordService.start(any())).thenThrow(MicrophoneAccessDeniedException());
      await controller.startHandsFree();
      expect(controller.status, VoiceCaptureStatus.permissionDenied);

      clearInteractions(wakeWordService);
      await controller.cancelPending();

      verifyNever(() => wakeWordService.start(any()));
    });
  });

  group('cancelPending', () {
    test('logs discarded with the last transcript and resumes listening', () async {
      when(() => transcriptionService.listenOnce()).thenAnswer((_) async => 'spent rm5 at starbucks');
      const parsed = ParsedVoiceExpense(
        amount: 5.0,
        merchantName: 'Starbucks',
        transactionDate: null,
        rawTranscript: 'spent rm5 at starbucks',
      );
      when(() => parser.parse(any())).thenReturn(parsed);

      await controller.startHandsFree();
      await triggerWakeWord();
      await controller.cancelPending();

      verify(() => diagnostics.log('discarded', detail: 'spent rm5 at starbucks')).called(1);
      expect(controller.lastParsed, isNull);
      expect(controller.status, VoiceCaptureStatus.listeningForWake);
    });
  });

  test('dispose() releases the wake word service and voice datasource', () {
    controller.dispose();
    verify(() => wakeWordService.dispose()).called(1);
    verify(() => transcriptionService.dispose()).called(1);
  });
}
