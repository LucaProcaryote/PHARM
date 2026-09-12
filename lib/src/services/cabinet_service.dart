import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:uuid/uuid.dart';

/// The outcome of asking the cabinet for a dose.
class DispenseOutcome {
  const DispenseOutcome({
    required this.alerts,
    this.dispense,
    this.stock,
  });

  /// Everything the safety checks found. Empty means a clean release.
  final List<SafetyAlert> alerts;

  /// Set when the dose actually left the cabinet.
  final Dispense? dispense;

  /// The slot after the quantity was deducted.
  final StockItem? stock;

  bool get succeeded => dispense != null;
  bool get isBlocked => alerts.any((a) => a.isBlocking);

  List<SafetyAlert> get blocking =>
      alerts.where((a) => a.isBlocking).toList(growable: false);
}

/// Drives the simulated automated dispensing cabinet.
///
/// The physical behaviour is modelled deliberately, because it is what makes
/// the exercise more than a stock table: the cabinet is locked until somebody
/// authenticates, a drawer opens for one slot at a time, and it closes itself
/// after a few seconds whether or not the nurse remembered to.
class CabinetService extends ChangeNotifier {
  CabinetService({required this.repository, Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final HospitalRepository repository;
  final Uuid _uuid;

  /// How long a drawer stays open before the cabinet closes it.
  static const Duration drawerTimeout = Duration(seconds: 8);

  /// Slot id whose drawer is currently open, or null. Only one at a time -
  /// that is the whole point of a controlled cabinet.
  String? _openSlotId;
  String? get openSlotId => _openSlotId;

  Timer? _closeTimer;

  /// Whether the cabinet auto-closed the drawer rather than the user closing
  /// it, so the interface can say what happened.
  bool _closedAutomatically = false;
  bool get closedAutomatically => _closedAutomatically;

  Future<Cabinet> unlock(Cabinet cabinet) async {
    final updated = await repository.saveCabinet(
      cabinet.copyWith(isLocked: false),
    );
    notifyListeners();
    return updated;
  }

  Future<Cabinet> lock(Cabinet cabinet) async {
    closeDrawer();
    final updated = await repository.saveCabinet(
      cabinet.copyWith(isLocked: true),
    );
    notifyListeners();
    return updated;
  }

  /// Opens one drawer. A locked cabinet refuses.
  bool openDrawer(Cabinet cabinet, StockItem slot) {
    if (cabinet.isLocked) return false;
    _closeTimer?.cancel();
    _openSlotId = slot.id;
    _closedAutomatically = false;
    _closeTimer = Timer(drawerTimeout, () {
      _openSlotId = null;
      _closedAutomatically = true;
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  void closeDrawer() {
    _closeTimer?.cancel();
    _closeTimer = null;
    if (_openSlotId == null) return;
    _openSlotId = null;
    _closedAutomatically = false;
    notifyListeners();
  }

  /// Runs every safety check without changing anything, so the interface can
  /// show the user what will happen before they commit.
  Future<List<SafetyAlert>> preflight({
    required Patient patient,
    required Prescription prescription,
    required Cabinet cabinet,
    required double quantity,
  }) async {
    final stock = await _findSlot(cabinet.id, prescription.medication.code);
    return SafetyChecks.dispenseBlockers(
      patient: patient,
      prescription: prescription,
      cabinet: cabinet,
      stock: stock,
      quantity: quantity,
    );
  }

  /// Hands over a dose, deducting the stock and closing the dispense record.
  ///
  /// Refuses outright if any check is blocking. Warnings (a low-risk allergy,
  /// a controlled substance) must be acknowledged by the caller passing
  /// [acknowledgedWarnings]; the cabinet does not decide that on its own.
  Future<DispenseOutcome> dispense({
    required Patient patient,
    required Prescription prescription,
    required Cabinet cabinet,
    required Dispense request,
    required String dispensedBy,
    String? witness,
    bool acknowledgedWarnings = false,
    DateTime? at,
  }) async {
    final stock = await _findSlot(cabinet.id, prescription.medication.code);
    final alerts = SafetyChecks.dispenseBlockers(
      patient: patient,
      prescription: prescription,
      cabinet: cabinet,
      stock: stock,
      quantity: request.quantity,
    );

    if (alerts.any((a) => a.isBlocking)) {
      return DispenseOutcome(alerts: alerts, stock: stock);
    }
    final needsWitness = prescription.medication.isControlled;
    if (needsWitness && (witness == null || witness.trim().isEmpty)) {
      return DispenseOutcome(alerts: alerts, stock: stock);
    }
    if (alerts.any((a) => a.severity == SafetySeverity.warning) &&
        !acknowledgedWarnings) {
      return DispenseOutcome(alerts: alerts, stock: stock);
    }

    final now = at ?? DateTime.now();

    // Deduct first, then record the handover: a failure between the two leaves
    // stock that is short rather than a dose recorded as given that is still
    // sitting in the drawer.
    final updatedStock = stock == null
        ? null
        : await repository.saveStockItem(stock.copyWith(
            quantityOnHand:
                (stock.quantityOnHand - request.quantity).round().clamp(0, 1 << 30),
          ));

    final completed = await repository.saveDispense(request.copyWith(
      status: DispenseStatus.dispensed,
      dispensedAt: now,
      dispensedBy: witness == null ? dispensedBy : '$dispensedBy / $witness',
      lotNumber: stock?.lotNumber,
    ));

    closeDrawer();
    return DispenseOutcome(
      alerts: alerts,
      dispense: completed,
      stock: updatedStock,
    );
  }

  /// Records that a dose was not given, and why.
  Future<Dispense> refuse({
    required Dispense request,
    required String reason,
    required String refusedBy,
    DateTime? at,
  }) =>
      repository.saveDispense(request.copyWith(
        status: DispenseStatus.refused,
        dispensedAt: at ?? DateTime.now(),
        dispensedBy: refusedBy,
        refusalReason: reason,
      ));

  /// Adds units to a slot and gives it a fresh lot number and expiry.
  Future<StockItem> restock(
    StockItem item,
    int quantity, {
    DateTime? expiry,
  }) =>
      repository.saveStockItem(StockItem(
        id: item.id,
        cabinetId: item.cabinetId,
        slot: item.slot,
        medication: item.medication,
        quantityOnHand: item.quantityOnHand + quantity,
        parLevel: item.parLevel,
        // A restock replaces the lot: mixing an expired lot with a fresh one in
        // the same drawer is exactly what a cabinet is meant to prevent.
        expiryDate: expiry ?? DateTime.now().add(const Duration(days: 540)),
        lotNumber: 'LOT${_uuid.v4().substring(0, 6).toUpperCase()}',
      ));

  Future<StockItem?> _findSlot(String cabinetId, String medicationCode) async {
    final items = await repository.listStock(cabinetId: cabinetId);
    for (final item in items) {
      if (item.medication.code == medicationCode) return item;
    }
    return null;
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }
}
