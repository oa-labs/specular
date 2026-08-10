import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/voice/voice_service.dart';

void main() {
  test('voice session manifest preserves recoverable segment state', () {
    final session = VoiceSession(
      id: 'session-1',
      createdAt: DateTime.utc(2026, 8, 10),
      noteId: 'note-1',
      state: VoiceSessionState.pending,
      transcript: 'Raw transcript',
      segments: [
        VoiceSegment(
          path: '/recordings/0000.wav',
          startedAt: DateTime.utc(2026, 8, 10),
          durationMs: 300000,
          transcribed: true,
        ),
      ],
    );

    final restored = VoiceSession.fromJson(session.toJson());

    expect(restored.id, session.id);
    expect(restored.noteId, 'note-1');
    expect(restored.state, VoiceSessionState.pending);
    expect(restored.segments.single.path, '/recordings/0000.wav');
    expect(restored.segments.single.transcribed, isTrue);
  });
}
