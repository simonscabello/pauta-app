import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/domain/setlist_duration.dart';

EventSong song([int? seconds]) => EventSong(
      songId: 'musica',
      serviceId: 'culto',
      title: 'Digno é o Senhor',
      durationSeconds: seconds,
    );

void main() {
  test('formata minutos e segundos com dois dígitos nos segundos', () {
    expect(formatDuration(270), '4:30');
    expect(formatDuration(65), '1:05');
    expect(formatDuration(10), '0:10');
    expect(formatDuration(3600), '60:00');
  });

  test('omite o total quando nenhuma duração é conhecida', () {
    expect(setlistDurationLabel([]), isNull);
    expect(setlistDurationLabel([song(), song()]), isNull);
  });

  test('soma os segundos antes de arredondar os minutos para cima', () {
    expect(setlistDurationLabel([song(675), song(675)]), 'Cerca de 23 min');
    expect(setlistDurationLabel([song(30), song(30)]), 'Cerca de 1 min');
  });

  test('indica quantas músicas ficaram fora da soma', () {
    expect(
      setlistDurationLabel([song(), song(1350)]),
      'Cerca de 23 min (1 música sem duração)',
    );
    expect(
      setlistDurationLabel([song(1350), song(), song()]),
      'Cerca de 23 min (2 músicas sem duração)',
    );
  });
}
