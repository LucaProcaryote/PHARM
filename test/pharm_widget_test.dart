import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:pharm_app/src/pharm_home.dart';

Future<void> pumpPharm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1300);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final repository = MemoryHospitalRepository(
    seed: HospitalSeed.build(now: DateTime.utc(2026, 9, 12, 10)),
  );
  final auth = DemoAuthService();
  await auth.initialize();
  await auth.signInAs(
    seedUsers.firstWhere((u) => u.role == UserRole.pharmacist),
  );

  await tester.pumpWidget(
    MiniHospitalApp(
      config: const AppConfig(
        app: HospitalApp.pharm,
        backendMode: BackendMode.memory,
        authMode: AuthMode.demo,
        apiBaseUrl: '',
        fhirBaseUrl: '',
        eaiBaseUrl: '',
      ),
      title: (l10n) => l10n.appTitlePharm,
      homeBuilder: (context) => const PharmHome(),
      repositoryOverride: repository,
      authOverride: auth,
      localeStore: InMemoryLocaleStore(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the queue opens with work waiting in it', (tester) async {
    await pumpPharm(tester);

    expect(find.text('Pharmacy Cabinet'), findsOneWidget);
    // The seed leaves the most recent dose of each prescription pending.
    expect(find.textContaining('doses pending'), findsOneWidget);
    expect(find.text('Dispense'), findsWidgets);
  });

  testWidgets('the cabinet starts locked and can be unlocked', (tester) async {
    await pumpPharm(tester);

    // Navigate via the rail: "Cabinet" is also the label of a dropdown on the
    // queue screen, so an unqualified finder would open that instead.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Cabinet'),
      ),
    );
    await tester.pumpAndSettle();

    // Locked cabinets offer "Unlock cabinet"; the state is written, not implied.
    expect(find.text('Unlock cabinet'), findsOneWidget);

    await tester.tap(find.text('Unlock cabinet'));
    await tester.pumpAndSettle();
    expect(find.text('Lock cabinet'), findsOneWidget);
  });

  testWidgets('stock alerts are named, not only coloured', (tester) async {
    await pumpPharm(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Stock'),
      ),
    );
    await tester.pumpAndSettle();

    // The seed deliberately contains empty, expired and below-par slots.
    expect(find.textContaining('Cabinet alerts'), findsOneWidget);
    final labels = <String>['Out of stock', 'Expired lot', 'Low stock'];
    final found = labels.where((l) => find.text(l).evaluate().isNotEmpty);
    expect(
      found,
      isNotEmpty,
      reason: 'the stock screen should surface at least one kind of alert',
    );
  });

  testWidgets('the dispensing dialog runs the checks before opening anything', (
    tester,
  ) async {
    await pumpPharm(tester);

    await tester.tap(find.text('Dispense').first);
    await tester.pumpAndSettle();

    expect(find.text('Safety checks'), findsOneWidget);
    // Every ward cabinet starts locked, so the release must be refused - and
    // the reason has to be stated, not merely implied by a disabled button.
    expect(find.text('Cabinet locked'), findsOneWidget);
    expect(find.text('Unlock the cabinet before dispensing.'), findsOneWidget);
    expect(
      find.text('This action is blocked and cannot be completed.'),
      findsOneWidget,
    );
    // Each alert states its severity in words as well as in colour.
    expect(find.text('Blocking'), findsWidgets);
  });

  testWidgets('everything translates', (tester) async {
    await pumpPharm(tester);

    await tester.tap(find.text('NL'));
    await tester.pumpAndSettle();
    expect(find.text('Apotheekkast'), findsOneWidget);

    await tester.tap(find.text('FR'));
    await tester.pumpAndSettle();
    expect(find.text('Armoire de pharmacie'), findsOneWidget);
  });
}
