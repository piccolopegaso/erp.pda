import 'package:flutter_test/flutter_test.dart';
import 'package:mic_pda/core/scanner.dart';
import 'package:mic_pda/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ScannerService s;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    s = ScannerService(await AppSettings.load());
  });

  test('delivers to the top-most handler only', () {
    final a = <String>[], b = <String>[];
    s.register(a.add);
    final tb = s.register(b.add);
    s.dispatch('X1');
    expect(a, isEmpty);
    expect(b, ['X1']);
    s.unregister(tb);
    s.dispatch('X2');
    expect(a, ['X2']);
  });

  test('inactive top screen swallows scans instead of leaking them below', () {
    final a = <String>[], b = <String>[];
    s.register(a.add);
    s.register(b.add, isActive: () => false);
    s.dispatch('Y');
    expect(a, isEmpty);
    expect(b, isEmpty);
  });

  test('bounce: same code within dedup window is ignored, manual entry is not', () {
    final a = <String>[];
    s.register(a.add);
    s.dispatch('Z');
    s.dispatch('Z');
    s.dispatch('Z', manual: true);
    expect(a, ['Z', 'Z']);
  });

  test('control characters and whitespace are stripped', () {
    final a = <String>[];
    s.register(a.add);
    s.dispatch(' \u001dABC123\r\n');
    expect(a, ['ABC123']);
  });
}
