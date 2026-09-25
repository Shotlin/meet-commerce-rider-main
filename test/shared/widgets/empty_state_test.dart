import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/shared/widgets/empty_state.dart';

void main() {
  Future<void> pumpEmpty(
    WidgetTester tester, {
    required String title,
    String? body,
    Widget? action,
    IconData icon = Icons.inbox_outlined,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: icon,
            title: title,
            body: body,
            action: action,
          ),
        ),
      ),
    );
  }

  testWidgets('renders title and body when both supplied', (
    WidgetTester tester,
  ) async {
    await pumpEmpty(
      tester,
      title: 'No offers right now',
      body: 'You are online. Waiting for orders near your store',
    );

    expect(find.text('No offers right now'), findsOneWidget);
    expect(
      find.text('You are online. Waiting for orders near your store'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });

  testWidgets('omits body when null', (WidgetTester tester) async {
    await pumpEmpty(tester, title: 'Nothing here yet');

    expect(find.text('Nothing here yet'), findsOneWidget);
    // The only Text widget should be the title.
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('renders an action when supplied', (WidgetTester tester) async {
    int taps = 0;
    await pumpEmpty(
      tester,
      title: 'Empty',
      action: ElevatedButton(
        key: const ValueKey<String>('cta'),
        onPressed: () => taps++,
        child: const Text('Refresh'),
      ),
    );

    expect(find.byKey(const ValueKey<String>('cta')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('cta')));
    expect(taps, 1);
  });

  testWidgets('omits action when null', (WidgetTester tester) async {
    await pumpEmpty(tester, title: 'Empty');

    expect(find.byType(ElevatedButton), findsNothing);
  });
}
