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

/// State machine for FR4.4 hands-free voice expense logging — ties together
/// wake-word detection, transcription handoff, on-device NLP parsing,
/// category suggestion and offline-first persistence. See the class-level
/// docs on each collaborator for what it individually owns; this class only
/// sequences them:
///
/// listeningForWake --(wake word)--> transcribing --(transcript)--> parsed
///   --(confirm)--> back to listeningForWake
///
/// A confirmation UI (VoiceConfirmationSheet) should observe this
/// controller (it's a ChangeNotifier) and present [lastParsed] /
/// [lastCategorySuggestion] once [status] becomes [VoiceCaptureStatus.parsed],
/// then call [confirmSave] or [cancelPending].
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

  /// Starts continuous hands-free wake-word listening. Android only — see
  /// WakeWordService's platform-scope doc comment; on other platforms this
  /// resolves to [VoiceCaptureStatus.unsupportedPlatform] instead of
  /// throwing, so callers (e.g. MainShell's mic toggle) should check
  /// [status] afterwards rather than assuming success.
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
    // The only feedback a "hands-free" feature can give someone not looking
    // at the screen — haptic for a bag/pocket, a chime for anyone in
    // earshot. Fired together, immediately, so there's no ambiguity about
    // whether "Ok App" actually registered before they start talking.
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_audioFeedback.playWake());
    // Every detection is logged before we even know the outcome — this is
    // what lets the "Wake accuracy" summary (Profile > Support) measure how
    // often "Ok App" triggers without ever producing a saved expense
    // (background chatter, TV, etc.), instead of guessing at a false-positive rate.
    unawaited(_diagnostics.log('wake_detected'));

    // WakeWordService (Vosk, always-on grammar-restricted listening) and
    // _transcriptionService (VoiceDatasource/speech_to_text — Android's own
    // SpeechRecognizer, chosen over Vosk's open-vocabulary mode here for
    // accuracy; see VoiceDatasource's doc comment) are two independent
    // microphone consumers — only one may hold it at a time.
    // WakeWordService.stop() already pads this handoff to dodge a real
    // native crash in vosk_flutter_2 (see its doc comment); the try/catch
    // below is defense-in-depth for whatever that padding doesn't cover —
    // an exception here would otherwise propagate out of this callback
    // uncaught (it's invoked from inside WakeWordService's own stream
    // listener), so this is the difference between "didn't catch that, try
    // again" and the whole app going down.
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

  /// Called after the confirmation UI accepts the parsed/edited fields.
  /// Writes straight to the offline outbox (so the save always succeeds
  /// locally, even offline) and opportunistically tries to sync it, then
  /// resumes hands-free listening.
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
      // Don't retry a setup failure (permission denied / unsupported
      // platform / error) on every confirm-save — only an explicit
      // re-tap of the mic toggle should attempt that again.
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
