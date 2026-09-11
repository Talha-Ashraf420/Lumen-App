import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/epg.dart';
import 'package:lumen_tv/screens/epg_guide_screen.dart';

void main() {
  EpgProgramme programme(
    String title,
    int startMinute,
    int stopMinute,
  ) => EpgProgramme(
    channelKey: 'channel',
    startUtc: DateTime.utc(2026, 9, 12, 10).add(Duration(minutes: startMinute)),
    stopUtc: DateTime.utc(2026, 9, 12, 10).add(Duration(minutes: stopMinute)),
    title: title,
  );

  test('vertical guide movement selects temporal overlap', () {
    final programmes = [
      programme('Early', 0, 25),
      programme('Overlapping', 25, 80),
      programme('Late', 80, 120),
    ];

    expect(
      closestProgrammeIndexByTime(
        programmes,
        DateTime.utc(2026, 9, 12, 10, 45),
      ),
      1,
    );
  });

  test('vertical guide movement falls back to nearest midpoint', () {
    final programmes = [programme('Early', 0, 20), programme('Late', 70, 90)];

    expect(
      closestProgrammeIndexByTime(
        programmes,
        DateTime.utc(2026, 9, 12, 10, 55),
      ),
      1,
    );
    expect(closestProgrammeIndexByTime(const [], DateTime.utc(2026)), -1);
  });
}
