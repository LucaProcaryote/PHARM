import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/cabinet_service.dart';

/// The dispensing dialog: run the checks, open the drawer, hand the dose over.
///
/// The order matters and is the lesson. The safety checks run *before* the
/// drawer will open, not after — a cabinet that lets you take the drug and then
/// tells you the patient is allergic to it has not prevented anything.
Future<void> showDispenseDialog({
  required BuildContext context,
  required Patient patient,
  required Prescription prescription,
  required Cabinet cabinet,
  required Dispense request,
}) async {
  // `showDialog` builds on the root navigator, which sits above the provider
  // that PharmHome installs - so the dialog cannot see CabinetService unless it
  // is handed down explicitly. Re-providing the same instance keeps the drawer
  // state shared with the screen behind the dialog.
  final service = context.read<CabinetService>();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ChangeNotifierProvider<CabinetService>.value(
      value: service,
      child: _DispenseDialog(
        patient: patient,
        prescription: prescription,
        cabinet: cabinet,
        request: request,
      ),
    ),
  );
}

class _DispenseDialog extends StatefulWidget {
  const _DispenseDialog({
    required this.patient,
    required this.prescription,
    required this.cabinet,
    required this.request,
  });

  final Patient patient;
  final Prescription prescription;
  final Cabinet cabinet;
  final Dispense request;

  @override
  State<_DispenseDialog> createState() => _DispenseDialogState();
}

class _DispenseDialogState extends State<_DispenseDialog> {
  final _witnessController = TextEditingController();

  List<SafetyAlert>? _alerts;
  bool _acknowledged = false;
  bool _busy = false;
  StockItem? _slot;

  bool get _needsWitness => widget.prescription.medication.isControlled;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  @override
  void dispose() {
    _witnessController.dispose();
    super.dispose();
  }

  Future<void> _runChecks() async {
    final service = context.read<CabinetService>();
    final repository = context.read<HospitalRepository>();

    final alerts = await service.preflight(
      patient: widget.patient,
      prescription: widget.prescription,
      cabinet: widget.cabinet,
      quantity: widget.request.quantity,
    );
    final stock = await repository.listStock(cabinetId: widget.cabinet.id);
    StockItem? slot;
    for (final item in stock) {
      if (item.medication.code == widget.prescription.medication.code) {
        slot = item;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _slot = slot;
    });
  }

  bool get _canDispense {
    final alerts = _alerts;
    if (alerts == null || _busy) return false;
    if (alerts.any((a) => a.isBlocking)) return false;
    if (_needsWitness && _witnessController.text.trim().isEmpty) return false;
    if (alerts.any((a) => a.severity == SafetySeverity.warning) &&
        !_acknowledged) {
      return false;
    }
    return true;
  }

  Future<void> _dispense() async {
    final service = context.read<CabinetService>();
    final user = context.read<AuthService>().currentUser;
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _busy = true);

    // Open the drawer only once everything has passed.
    final slot = _slot;
    if (slot != null) service.openDrawer(widget.cabinet, slot);

    final outcome = await service.dispense(
      patient: widget.patient,
      prescription: widget.prescription,
      cabinet: widget.cabinet,
      request: widget.request,
      dispensedBy: user?.displayName ?? 'Unknown',
      witness: _needsWitness ? _witnessController.text.trim() : null,
      acknowledgedWarnings: _acknowledged,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (!outcome.succeeded) {
      setState(() => _alerts = outcome.alerts);
      return;
    }

    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          l10n.pharmDispenseSuccess(
            widget.prescription.medication.name.forLanguage(language),
            widget.patient.fullName,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final alerts = _alerts;
    final medication = widget.prescription.medication;

    return AlertDialog(
      title: Text(l10n.pharmDispense),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PatientIdentityBar(patient: widget.patient, dense: true),
              Gap.h16,
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${medication.name.forLanguage(language)} '
                        '${medication.strength}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(widget.prescription.dosageText(language)),
                      Gap.h8,
                      Wrap(
                        spacing: Gap.md,
                        runSpacing: Gap.sm,
                        children: <Widget>[
                          LabeledValue(
                            label: l10n.pharmCabinet,
                            value: widget.cabinet.code,
                          ),
                          LabeledValue(
                            label: l10n.pharmSlot,
                            value: _slot?.slot ?? '—',
                            monospace: true,
                          ),
                          LabeledValue(
                            label: l10n.labelQuantity,
                            value:
                                '${widget.request.quantity.toStringAsFixed(0)} '
                                '${widget.prescription.doseUnit}',
                          ),
                          LabeledValue(
                            label: l10n.pharmLot,
                            value: _slot?.lotNumber ?? '—',
                            monospace: true,
                          ),
                          LabeledValue(
                            label: l10n.pharmExpiry,
                            value: _slot == null
                                ? '—'
                                : Formats.shortDate(context, _slot!.expiryDate),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Gap.h16,
              Text(l10n.safetyChecks, style: theme.textTheme.labelLarge),
              Gap.h8,
              if (alerts == null)
                const Center(child: CircularProgressIndicator())
              else if (alerts.isEmpty)
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: HospitalTheme.successOf(context),
                    ),
                    Gap.w8,
                    Text(l10n.safetyNoIssues),
                  ],
                )
              else
                for (final alert in alerts)
                  _AlertBox(alert: alert, language: language),

              if (alerts != null &&
                  alerts.any((a) => a.isBlocking)) ...<Widget>[
                Gap.h8,
                Text(
                  l10n.safetyBlocked,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: HospitalTheme.criticalOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else if (alerts != null &&
                  alerts.any((a) => a.severity == SafetySeverity.warning))
                CheckboxListTile(
                  value: _acknowledged,
                  onChanged: (value) =>
                      setState(() => _acknowledged = value ?? false),
                  title: Text(
                    l10n.safetyAcknowledge,
                    style: theme.textTheme.bodySmall,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),

              if (_needsWitness) ...<Widget>[
                Gap.h8,
                Text(
                  l10n.pharmWitnessRequired,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: HospitalTheme.warningOf(context),
                  ),
                ),
                Gap.h8,
                TextField(
                  controller: _witnessController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.pharmWitnessName,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton.icon(
          onPressed: _canDispense ? _dispense : null,
          icon: const Icon(Icons.lock_open, size: 16),
          label: Text('${l10n.pharmOpenDrawer} & ${l10n.pharmDispense}'),
        ),
      ],
    );
  }
}

class _AlertBox extends StatelessWidget {
  const _AlertBox({required this.alert, required this.language});

  final SafetyAlert alert;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HospitalLocalizations.of(context);
    final color = switch (alert.severity) {
      SafetySeverity.blocking => HospitalTheme.criticalOf(context),
      SafetySeverity.warning => HospitalTheme.warningOf(context),
      SafetySeverity.advisory => HospitalTheme.infoOf(context),
    };
    final severityLabel = switch (alert.severity) {
      SafetySeverity.blocking => l10n.safetySeverityBlocking,
      SafetySeverity.warning => l10n.safetySeverityWarning,
      SafetySeverity.advisory => l10n.safetySeverityAdvisory,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            alert.isBlocking ? Icons.block : Icons.warning_amber_rounded,
            size: 18,
            color: color,
          ),
          Gap.w8,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        alert.title.forLanguage(language),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      severityLabel,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ],
                ),
                Text(
                  alert.detail.forLanguage(language),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
