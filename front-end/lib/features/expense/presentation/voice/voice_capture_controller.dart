import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:vosk_flutter_2/vosk_flutter_2.dart' show MicrophoneAccessDeniedException;

import '../../../../services/auto_categorization_service.dart';
import '../../../../services/expense_nlp_parser_service.dart';
import '../../../../services/voice_audio_feedback_service.dart';
import '../../../../services/voice_expense_sync_service.dart';
import '../../../../services/wake_word_service.dart';
import '../../data/datasources/pending_voice_expense_dao.dart';
import '../../data/datasources/voice_diagnostic_log_dao.dart';
import '../../data/datasources/voice_datasource.dart';

enum VoiceCaptureStatus {
  idle,
  listeningForWake,
  transcribing,
  parsed,
  noSpeechDetected,
  parseFailed,
  permissionDenied,
  unsupportedPlatform,
  error,
}

/// State machine for hands-free voice expense logging, sequencing wake-word detection, transcription, parsing, category suggestion and persistence: listeningForWake -> transcribing -> parsed -> (confirm) -> listeningForWake.
class VoiceCaptureController extends ChangeNotifier {
  final WakeWordService _wakeWordService;
  final VoiceDatasource _transcriptionService;
  final ExpenseNlpParserService _parser;
  final AutoCategorizationService _autoCategorizationService;
  final PendingVoiceExpenseDao _outbox;
  final VoiceExpenseSyncService _syncService;
  final VoiceAudioFeedbackService _audioFeedback;
  final VoiceDiagnosticLogDao _diagnostics;

  VoiceCaptureController({
    WakeWordService? wakeWordService,
    VoiceDatasource? transcriptionService,
    ExpenseNlpParserService? parser,
    AutoCategorizationService? autoCategorizationService,
    PendingVoiceExpenseDao? outbox,
    VoiceExpenseSyncService? syncService,
    VoiceAudioFeedbackService? audioFeedback,
    VoiceDiagnosticLogDao? diagnostics,
  }) : _wakeWordService = wakeWordService ?? WakeWordService(),
       _transcriptionService = transcriptionService ?? VoiceDatasource(),
       _parser = parser ?? ExpenseNlpParserService(),
       _autoCategorizationService =
           autoCategorizationService ?? AutoCategorizationService(),
       _outbox = outbox ?? PendingVoiceExpenseDao(),
       _syncService = syncService ?? VoiceExpenseSyncService(),
       _audioFeedback = audioFeedback ?? VoiceAudioFeedbackService(),
       _diagnostics = diagnostics ?? VoiceDiagnosticLogDao();

  VoiceCaptureStatus status = VoiceCaptureStatus.idle;
  ParsedVoiceExpense? lastParsed;
  CategorySuggestion? lastCategorySuggestion;
  String? errorMessage;

  static const _inactiveStatuses = {
    VoiceCaptureStatus.idle,
    VoiceCaptureStatus.permissionDenied,
    VoiceCaptureStatus.unsupportedPlatform,
    VoiceCaptureStatus.error,
  };

  bool get isHandsFreeActive => !_inactiveStatuses.contains(status);

  void _setStatus(VoiceCaptureStatus next) {
    status = next;
    notifyListeners();
  }

  /// Starts continuous hands-free wake-word listening. Android only; on other platforms resolves to [VoiceCaptureStatus.unsupportedPlatform] instead of throwing, so callers should check [status] afterward.
  Future<void> startHandsFree() async {
    try {
      await _wakeWordService.start(_onWakeWordDetected);
      _setStatus(VoiceCaptureStatus.listeningForWake);
    } on WakeWordUnsupportedPlatformException catch (e) {
      errorMessage = e.toString();
      _setStatus(VoiceCaptureStatus.unsupportedPlatform);
    } on MicrophoneAccessDeniedException {
      errorMessage = 'Microphone permission was denied.';
      _setStatus(VoiceCaptureStatus.permissionDenied);
    } catch (e) {
      // A missing/corrupt bundled model (VoiceModelProvisioner) or any
      // other setup failure not already handled above.
      errorMessage = e.toString();
      _setStatus(VoiceCaptureStatus.error);
    }
  }

  Future<void> stopHandsFree() async {
    await _wakeWordService.stop();
    _setStatus(VoiceCaptureStatus.idle);
  }

  Future<void> _onWakeWordDetected() async {
    // Haptic + chime fired together immediately, since that's the only feedback hands-free use can give without looking at the screen.
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_audioFeedback.playWake());
    // Logged before the outcome is known, so "Wake accuracy" (Profile > Support) can measure false-positive triggers instead of guessing.
    unawaited(_diagnostics.log('wake_detected'));

    // WakeWordService and _transcriptionService share one mic; stop() already pads the handoff against a native vosk_flutter_2 crash, and the try/catch below is defense-in-depth so an uncaught exception here doesn't take down the app.
    await _wakeWordService.stop();
    _setStatus(VoiceCaptureStatus.transcribing);

    String? transcript;
    try {
      transcript = await _transcriptionService.listenOnce();
    } catch (e) {
      unawaited(_audioFeedback.playError());
      unawaited(_diagnostics.log('transcription_error', detail: e.toString()));
      _setStatus(VoiceCaptureStatus.noSpeechDetected);
      await _resumeListeningIfActive();
      return;
    }
    if (transcript == null || transcript.trim().isEmpty) {
      unawaited(_audioFeedback.playError());
      unawaited(_diagnostics.log('no_speech_detected'));
      _setStatus(VoiceCaptureStatus.noSpeechDetected);
      await _resumeListeningIfActive();
      return;
    }

    final parsed = _parser.parse(transcript);
    final categorizationInput = parsed.merchantName ?? transcript;
    lastCategorySuggestion = await _autoCategorizationService.categorize(
      categorizationInput,
      source: 'voice',
    );
    lastParsed = parsed;

    if (!parsed.hasAmount) {
      unawaited(_audioFeedback.playError());
      unawaited(_diagnostics.log('parse_failed', detail: transcript));
    }
    _setStatus(
      parsed.hasAmount
          ? VoiceCaptureStatus.parsed
          : VoiceCaptureStatus.parseFailed,
    );
  }

  /// Called after the confirmation UI accepts the fields; writes to the offline outbox first so save always succeeds locally, then syncs and resumes listening.
  Future<void> confirmSave({
    required double amount,
    required String category,
    String? merchantName,
    DateTime? transactionDate,
  }) async {
    final transcript = lastParsed?.rawTranscript ?? '';
    await _outbox.insert(
      amount: amount,
      category: category,
      merchantName: merchantName,
      transactionDate: transactionDate?.toIso8601String().split('T').first,
      rawTranscript: transcript,
    );
    unawaited(_syncService.flushPending());
    unawaited(_audioFeedback.playSuccess());
    unawaited(_diagnostics.log('saved', detail: transcript));

    lastParsed = null;
    lastCategorySuggestion = null;
    await _resumeListeningIfActive();
  }

  Future<void> cancelPending() async {
    unawaited(_diagnostics.log('discarded', detail: lastParsed?.rawTranscript));
    lastParsed = null;
    lastCategorySuggestion = null;
    await _resumeListeningIfActive();
  }

  Future<void> _resumeListeningIfActive() async {
    if (_inactiveStatuses.contains(status) &&
        status != VoiceCaptureStatus.idle) {
      // Don't retry a setup failure automatically; only an explicit re-tap of the mic toggle should.
      return;
    }
    await startHandsFree();
  }

  @override
  void dispose() {
    _wakeWordService.dispose();
    _transcriptionService.dispose();
    super.dispose();
  }
}
