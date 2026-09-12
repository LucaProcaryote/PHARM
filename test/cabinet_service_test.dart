import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:pharm_app/src/services/cabinet_service.dart';

void main() {
  late MemoryHospitalRepository repository;
  late CabinetService service;

  final now = DateTime.utc(2026, 9, 12, 10);

  setUp(() async {
    repository = MemoryHospitalRepository(seed: HospitalSeed.build(now: now));
    await repository.initialize();
    service = CabinetService(repository: repository);
  });

  tearDown(() => service.dispose());

  /// A pending dose together with everything needed to hand it over.
  Future<({Dispense request, Prescription prescription, Patient patient, Cabinet cabinet})>
      pendingDose() async {
    final pending = await repository.listDispenses(
      status: DispenseStatus.requested,
    );
    for (final dispense in pending) {
      final prescription =
          await repository.findPrescription(dispense.prescriptionId);
      final patient = await repository.findPatient(dispense.patientId);
      final cabinet = dispense.cabinetId == null
          ? null
          : await repository.findCabinet(dispense.cabinetId!);
      if (prescription != null && patient != null && cabinet != null) {
        return (
          request: dispense,
          prescription: prescription,
          patient: patient,
          cabinet: cabinet,
        );
      }
    }
    fail('the seed should leave doses waiting in the queue');
  }

  Future<StockItem> slotFor(String cabinetId, String medicationCode) async {
    final stock = await repository.listStock(cabinetId: cabinetId);
    return stock.firstWhere((s) => s.medication.code == medicationCode);
  }

  group('the cabinet lock', () {
    test('a locked cabinet refuses to open a drawer', () async {
      final cabinet = (await repository.listCabinets())
          .firstWhere((c) => c.isLocked);
      final slot = (await repository.listStock(cabinetId: cabinet.id)).first;

      expect(service.openDrawer(cabinet, slot), isFalse);
      expect(service.openSlotId, isNull);
    });

    test('unlocking lets a drawer open, and only one at a time', () async {
      var cabinet = (await repository.listCabinets())
          .firstWhere((c) => c.isLocked);
      cabinet = await service.unlock(cabinet);
      expect(cabinet.isLocked, isFalse);

      final stock = await repository.listStock(cabinetId: cabinet.id);
      expect(service.openDrawer(cabinet, stock[0]), isTrue);
      expect(service.openSlotId, stock[0].id);

      // Opening a second drawer closes the first: that is the point of a
      // controlled cabinet.
      expect(service.openDrawer(cabinet, stock[1]), isTrue);
      expect(service.openSlotId, stock[1].id);
    });

    test('the drawer closes itself after the timeout', () async {
      // Everything asynchronous happens before the fake clock takes over, so
      // the only thing the fake clock has to drive is the auto-close timer.
      final cabinet = await service.unlock(
        (await repository.listCabinets()).first,
      );
      final slot = (await repository.listStock(cabinetId: cabinet.id)).first;

      FakeAsync().run((async) {
        service.openDrawer(cabinet, slot);
        expect(service.openSlotId, slot.id);
        expect(service.closedAutomatically, isFalse);

        // Still open a moment before the timeout.
        async.elapse(CabinetService.drawerTimeout - const Duration(seconds: 1));
        expect(service.openSlotId, slot.id);

        // And shut once it passes, flagged as an automatic close so the
        // interface can say what happened rather than silently changing.
        async.elapse(const Duration(seconds: 2));
        expect(service.openSlotId, isNull);
        expect(service.closedAutomatically, isTrue);
      });
    });

    test('locking the cabinet closes any open drawer', () async {
      var cabinet = (await repository.listCabinets()).first;
      cabinet = await service.unlock(cabinet);
      final slot = (await repository.listStock(cabinetId: cabinet.id)).first;
      service.openDrawer(cabinet, slot);
      expect(service.openSlotId, isNotNull);

      await service.lock(cabinet);
      expect(service.openSlotId, isNull);
    });
  });

  group('safety checks before anything opens', () {
    test('a locked cabinet blocks the dispense', () async {
      final dose = await pendingDose();
      final alerts = await service.preflight(
        patient: dose.patient,
        prescription: dose.prescription,
        cabinet: dose.cabinet,
        quantity: dose.request.quantity,
      );
      expect(
        alerts.where((a) => a.blocker == DispenseBlocker.cabinetLocked),
        isNotEmpty,
      );
    });

    test('a high-risk allergy blocks the dispense outright', () async {
      // Émile Van Damme is allergic to penicillin; give him amoxicillin.
      final patient =
          (await repository.findPatient('pat-001'))!;
      final amoxicillin = formularyByCode('MED-0103')!;
      final cabinet = await service.unlock(
        (await repository.findCabinet('cab-card'))!,
      );

      final prescription = Prescription(
        id: 'rx-test',
        patientId: patient.id,
        medication: amoxicillin,
        doseQuantity: 1,
        doseUnit: 'capsule',
        frequencyPerDay: 3,
        route: MedicationRoute.oral,
        startDate: now,
        prescriber: 'Tester',
        status: PrescriptionStatus.active,
      );

      final alerts = SafetyChecks.dispenseBlockers(
        patient: patient,
        prescription: prescription,
        cabinet: cabinet,
        stock: await slotFor('cab-card', 'MED-0103'),
        quantity: 1,
      );

      final allergy =
          alerts.where((a) => a.blocker == DispenseBlocker.allergyConflict);
      expect(allergy, isNotEmpty);
      expect(allergy.first.isBlocking, isTrue);
      // The reason is written in all three languages, ready for the interface.
      expect(allergy.first.title.fr, contains('Pénicilline'));
      expect(allergy.first.title.nl, contains('Penicilline'));
    });

    test('a beta-lactam cross-reacts with a penicillin allergy', () async {
      final patient = (await repository.findPatient('pat-001'))!;
      // Ceftriaxone is a cephalosporin - a different drug, same family.
      final ceftriaxone = formularyByCode('MED-0116')!;
      final alerts = SafetyChecks.allergyAlerts(
        patient: patient,
        medication: ceftriaxone,
      );
      expect(alerts, isNotEmpty);
      expect(alerts.first.detail.en, contains('beta-lactam'));
    });

    test('an unrelated drug raises nothing', () async {
      final patient = (await repository.findPatient('pat-001'))!;
      final paracetamol = formularyByCode('MED-0101')!;
      expect(
        SafetyChecks.allergyAlerts(patient: patient, medication: paracetamol),
        isEmpty,
      );
    });

    test('an expired lot blocks the dispense', () async {
      final expired = (await repository.listStock())
          .firstWhere((s) => s.isExpired);
      final cabinet = await service.unlock(
        (await repository.findCabinet(expired.cabinetId))!,
      );
      final patient = (await repository.findPatient('pat-003'))!;
      final prescription = Prescription(
        id: 'rx-x',
        patientId: patient.id,
        medication: expired.medication,
        doseQuantity: 1,
        doseUnit: 'unit',
        frequencyPerDay: 1,
        route: MedicationRoute.oral,
        startDate: now,
        prescriber: 'Tester',
        status: PrescriptionStatus.active,
      );

      final alerts = SafetyChecks.dispenseBlockers(
        patient: patient,
        prescription: prescription,
        cabinet: cabinet,
        stock: expired,
        quantity: 1,
      );
      expect(
        alerts.where((a) => a.blocker == DispenseBlocker.expiredLot),
        isNotEmpty,
      );
    });

    test('asking for more than the slot holds blocks the dispense', () async {
      final slot = (await repository.listStock())
          .firstWhere((s) => s.quantityOnHand > 0 && !s.isExpired);
      final cabinet = await service.unlock(
        (await repository.findCabinet(slot.cabinetId))!,
      );
      final patient = (await repository.findPatient('pat-003'))!;
      final prescription = Prescription(
        id: 'rx-y',
        patientId: patient.id,
        medication: slot.medication,
        doseQuantity: 1,
        doseUnit: 'unit',
        frequencyPerDay: 1,
        route: MedicationRoute.oral,
        startDate: now,
        prescriber: 'Tester',
        status: PrescriptionStatus.active,
      );

      final alerts = SafetyChecks.dispenseBlockers(
        patient: patient,
        prescription: prescription,
        cabinet: cabinet,
        stock: slot,
        quantity: slot.quantityOnHand + 10,
      );
      expect(
        alerts.where((a) => a.blocker == DispenseBlocker.outOfStock),
        isNotEmpty,
      );
    });
  });

  group('dispensing', () {
    test('deducts the stock and records the handover', () async {
      final dose = await pendingDose();
      final cabinet = await service.unlock(dose.cabinet);
      final before =
          await slotFor(cabinet.id, dose.prescription.medication.code);

      final outcome = await service.dispense(
        patient: dose.patient,
        prescription: dose.prescription,
        cabinet: cabinet,
        request: dose.request,
        dispensedBy: 'Paul Mertens',
        acknowledgedWarnings: true,
        witness: 'Marie Lambert',
        at: now,
      );

      expect(outcome.succeeded, isTrue);
      expect(outcome.dispense!.status, DispenseStatus.dispensed);
      expect(outcome.dispense!.dispensedAt, now);
      expect(outcome.dispense!.lotNumber, before.lotNumber);

      final after =
          await slotFor(cabinet.id, dose.prescription.medication.code);
      expect(
        after.quantityOnHand,
        before.quantityOnHand - dose.request.quantity.round(),
      );

      // The drawer must not be left hanging open afterwards.
      expect(service.openSlotId, isNull);
    });

    test('refuses while the cabinet is locked, and changes nothing', () async {
      final dose = await pendingDose();
      final before =
          await slotFor(dose.cabinet.id, dose.prescription.medication.code);

      final outcome = await service.dispense(
        patient: dose.patient,
        prescription: dose.prescription,
        cabinet: dose.cabinet,
        request: dose.request,
        dispensedBy: 'Paul Mertens',
      );

      expect(outcome.succeeded, isFalse);
      expect(outcome.isBlocked, isTrue);
      final after =
          await slotFor(dose.cabinet.id, dose.prescription.medication.code);
      expect(after.quantityOnHand, before.quantityOnHand);
    });

    test('a controlled substance will not go without a witness', () async {
      final morphine = formularyByCode('MED-0114')!;
      final cabinet = await service.unlock(
        (await repository.findCabinet('cab-icu'))!,
      );
      final patient = (await repository.findPatient('pat-003'))!;
      final prescription = Prescription(
        id: 'rx-morphine',
        patientId: patient.id,
        medication: morphine,
        doseQuantity: 1,
        doseUnit: 'mg',
        frequencyPerDay: 4,
        route: MedicationRoute.intravenous,
        startDate: now,
        prescriber: 'Tester',
        status: PrescriptionStatus.active,
      );
      await repository.savePrescription(prescription);
      final request = Dispense(
        id: 'disp-morphine',
        prescriptionId: prescription.id,
        patientId: patient.id,
        quantity: 1,
        status: DispenseStatus.requested,
        requestedAt: now,
        cabinetId: cabinet.id,
      );

      var outcome = await service.dispense(
        patient: patient,
        prescription: prescription,
        cabinet: cabinet,
        request: request,
        dispensedBy: 'Paul Mertens',
        acknowledgedWarnings: true,
      );
      expect(outcome.succeeded, isFalse,
          reason: 'no witness was given');

      outcome = await service.dispense(
        patient: patient,
        prescription: prescription,
        cabinet: cabinet,
        request: request,
        dispensedBy: 'Paul Mertens',
        witness: 'Sofie De Clercq',
        acknowledgedWarnings: true,
      );
      expect(outcome.succeeded, isTrue);
      // Both names are on the record.
      expect(outcome.dispense!.dispensedBy, contains('Paul Mertens'));
      expect(outcome.dispense!.dispensedBy, contains('Sofie De Clercq'));
    });

    test('an unacknowledged warning stops the dispense', () async {
      // pat-018 is allergic to morphine, recorded as low risk: a warning, not
      // a block, so it must be acknowledged rather than silently ignored.
      final patient = (await repository.findPatient('pat-018'))!;
      expect(
        patient.allergies.any((a) => a.substance.en.contains('Morphine')),
        isTrue,
      );
      final morphine = formularyByCode('MED-0114')!;
      final cabinet = await service.unlock(
        (await repository.findCabinet('cab-icu'))!,
      );
      final prescription = Prescription(
        id: 'rx-m2',
        patientId: patient.id,
        medication: morphine,
        doseQuantity: 1,
        doseUnit: 'mg',
        frequencyPerDay: 1,
        route: MedicationRoute.intravenous,
        startDate: now,
        prescriber: 'Tester',
        status: PrescriptionStatus.active,
      );
      final request = Dispense(
        id: 'disp-m2',
        prescriptionId: prescription.id,
        patientId: patient.id,
        quantity: 1,
        status: DispenseStatus.requested,
        requestedAt: now,
        cabinetId: cabinet.id,
      );

      final outcome = await service.dispense(
        patient: patient,
        prescription: prescription,
        cabinet: cabinet,
        request: request,
        dispensedBy: 'Paul Mertens',
        witness: 'Sofie De Clercq',
        acknowledgedWarnings: false,
      );
      expect(outcome.succeeded, isFalse);
      expect(
        outcome.alerts.any((a) => a.severity == SafetySeverity.warning),
        isTrue,
      );
    });

    test('refusing records the reason instead of the dose', () async {
      final dose = await pendingDose();
      final refused = await service.refuse(
        request: dose.request,
        reason: 'Patient off the ward',
        refusedBy: 'Paul Mertens',
        at: now,
      );
      expect(refused.status, DispenseStatus.refused);
      expect(refused.refusalReason, 'Patient off the ward');

      final stored = (await repository.listDispenses(
        prescriptionId: dose.prescription.id,
        status: DispenseStatus.refused,
      ));
      expect(stored.map((d) => d.id), contains(dose.request.id));
    });
  });

  group('restocking', () {
    test('adds units and replaces the lot', () async {
      final empty = (await repository.listStock())
          .firstWhere((s) => s.isEmpty);
      final restocked = await service.restock(empty, 40);

      expect(restocked.quantityOnHand, 40);
      expect(restocked.lotNumber, isNot(empty.lotNumber));
      expect(restocked.expiryDate.isAfter(DateTime.now()), isTrue);
      expect(restocked.isEmpty, isFalse);
    });

    test('clears an expired slot', () async {
      final expired = (await repository.listStock())
          .firstWhere((s) => s.isExpired);
      final restocked = await service.restock(expired, 25);
      expect(restocked.isExpired, isFalse);
    });
  });
}
