import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart' show MicrophoneAccessDeniedException;

import '../../../../services/auto_categorization_service.dart';
import '../../../../services/expense_nlp_parser_service.dart';
import '../../../../services/voice_expense_sync_service.dart';
import '../../../../services/wake_word_service.dart';
import '../../data/datasources/pending_voice_expense_dao.dart';
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
  final VoiceDatasource _voiceDatasource;
  final ExpenseNlpParserService _parser;
  final AutoCategorizationService _autoCategorizationService;
  final PendingVoiceExpenseDao _outbox;
  final VoiceExpenseSyncService _syncService;

  VoiceCaptureController({
    WakeWordService? wakeWordService,
    VoiceDatasource? voiceDatasource,
    ExpenseNlpParserService? parser,
    AutoCategorizationService? autoCategorizationService,
    PendingVoiceExpenseDao? outbox,
    VoiceExpenseSyncService? syncService,
  }) : _wakeWordService = wakeWordService ?? WakeWordService(),
       _voiceDatasource = voiceDatasource ?? VoiceDatasource(),
       _parser = parser ?? ExpenseNlpParserService(),
       _autoCategorizationService =
           autoCategorizationService ?? AutoCategorizationService(),
       _outbox = outbox ?? PendingVoiceExpenseDao(),
       _syncService = syncService ?? VoiceExpenseSyncService();

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
    // Both engines need exclusive mic access — release Vosk's stream before
    // speech_to_text tries to acquire it.
    await _wakeWordService.stop();
    _setStatus(VoiceCaptureStatus.transcribing);

    final transcript = await _voiceDatasource.listenOnce();
    if (transcript == null || transcript.trim().isEmpty) {
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

    lastParsed = null;
    lastCategorySuggestion = null;
    await _resumeListeningIfActive();
  }

  Future<void> cancelPending() async {
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
    _voiceDatasource.dispose();
    super.dispose();
  }
}
