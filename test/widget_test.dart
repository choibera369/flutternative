import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutternative/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: HealthMonitorApp(),
      ),
    );

    // Verify that the app title is displayed
    expect(find.text('건강 측정'), findsOneWidget);
  });
}
