import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuk_kasir/laundry_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'local logo persists per store and can be removed independently',
    () async {
      SharedPreferences.setMockInitialValues({});
      final bytes = Uint8List.fromList([1, 2, 3]);
      await LaundryLogo.save('a', bytes);
      await LaundryLogo.save('b', Uint8List.fromList([4]));
      expect(await LaundryLogo.load('a'), bytes);
      expect(await LaundryLogo.load('b'), [4]);
      await LaundryLogo.save('a', null);
      expect(await LaundryLogo.load('a'), isNull);
      expect(await LaundryLogo.load('b'), [4]);
    },
  );
}
