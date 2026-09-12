import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/cabinet_service.dart';
import '../widgets/dispense_dialog.dart';

/// Everything waiting to be handed over.
///
/// The queue is built from the dispense records the prescriptions generate, so
/// it reflects what is actually due rather than a list somebody maintains by
/// hand. Overdue doses are called out, because "late" is the number that
/// matters on a drug round.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  String? _cabinetFilter;
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return RepositoryBuilder<_QueueData>(
      query: (repository) async {
        final dispenses = await repository.listDispenses(
          cabinetId: _cabinetFilter,
          status: _showHistory ? null : DispenseStatus.requested,
          limit: 300,
        );
        final prescriptions = <String, Prescription>{};
        final patients = <String, Patient>{};
        for (final dispense in dispenses) {
          if (!prescriptions.containsKey(dispense.prescriptionId)) {
            final prescription =
                await repository.findPrescription(dispense.prescriptionId);
            if (prescription != null) {
              prescriptions[prescription.id] = prescription;
            }
          }
          if (!patients.containsKey(dispense.patientId)) {
            final patient = await repository.findPatient(dispense.patientId);
            if (patient != null) patients[patient.id] = patient;
          }
        }
        return _QueueData(
          dispenses: dispenses,
          prescriptions: prescriptions,
          patients: patients,
          cabinets: await repository.listCabinets(),
        );
      },
      builder: (context, data) {
        final pending = data.dispenses
            .where((d) => d.status == DispenseStatus.requested)
            .length;

        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _cabinetFilter,
                      decoration:
                          InputDecoration(labelText: l10n.pharmCabinet),
                      items: <DropdownMenuItem<String?>>[
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n.labelAll),
                        ),
                        for (final cabinet in data.cabinets)
                          DropdownMenuItem<String?>(
                            value: cabinet.id,
                            child: Text(
                              '${cabinet.code} — '
                              '${cabinet.name.forLanguage(language)}',
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _cabinetFilter = value),
                    ),
                  ),
                  Gap.w16,
                  FilterChip(
                    selected: _showHistory,
                    label: Text(l10n.pharmHistory),
                    onSelected: (value) =>
                        setState(() => _showHistory = value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.pharmPendingCount(pending),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
            const Divider(height: Gap.md),
            Expanded(
              child: data.dispenses.isEmpty
                  ? EmptyView(
                      message: l10n.pharmQueueEmpty,
                      icon: Icons.check_circle_outline,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Gap.md),
                      itemCount: data.dispenses.length,
                      separatorBuilder: (_, __) => Gap.h8,
                      itemBuilder: (context, index) => _QueueCard(
                        dispense: data.dispenses[index],
                        data: data,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _QueueData {
  const _QueueData({
    required this.dispenses,
    required this.prescriptions,
    required this.patients,
    required this.cabinets,
  });

  final List<Dispense> dispenses;
  final Map<String, Prescription> prescriptions;
  final Map<String, Patient> patients;
  final List<Cabinet> cabinets;
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.dispense, required this.data});

  final Dispense dispense;
  final _QueueData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final canDispense =
        context.watch<AuthService>().currentUser?.role.canDispense ?? false;

    final prescription = data.prescriptions[dispense.prescriptionId];
    final patient = data.patients[dispense.patientId];
    if (prescription == null || patient == null) return const SizedBox.shrink();

    final cabinet = data.cabinets
        .where((c) => c.id == dispense.cabinetId)
        .firstOrNull;

    final isPending = dispense.status == DispenseStatus.requested;
    final isOverdue = isPending &&
        DateTime.now().difference(dispense.requestedAt) >
            const Duration(hours: 1);

    final statusColor = switch (dispense.status) {
      DispenseStatus.dispensed => HospitalTheme.successOf(context),
      DispenseStatus.refused => HospitalTheme.criticalOf(context),
      DispenseStatus.requested => isOverdue
          ? HospitalTheme.criticalOf(context)
          : HospitalTheme.infoOf(context),
      _ => theme.colorScheme.outline,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PatientAvatar(patient: patient, radius: 18),
                Gap.w16,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${prescription.medication.name.forLanguage(language)} '
                        '${prescription.medication.strength}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        prescription.dosageText(language),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        '${l10n.pharmForPatient(patient.fullName)} · '
                        '${patient.mrn}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    StatusChip(
                      label: isOverdue
                          ? l10n.pharmOverdue
                          : dispense.status.display.forLanguage(language),
                      color: statusColor,
                      icon: isOverdue ? Icons.schedule : null,
                      dense: true,
                    ),
                    Gap.h4,
                    Text(
                      l10n.pharmDue(
                        Formats.smart(context, dispense.requestedAt),
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (patient.hasHighRiskAllergy) ...<Widget>[
              Gap.h8,
              AllergyBanner(patient: patient),
            ],
            if (!isPending) ...<Widget>[
              Gap.h8,
              Text(
                dispense.status == DispenseStatus.refused
                    ? '${l10n.pharmRefusalReason}: ${dispense.refusalReason ?? '—'}'
                    : '${l10n.pharmDispensed} · '
                        '${dispense.dispensedBy ?? '—'} · '
                        '${dispense.dispensedAt == null ? '' : Formats.dateTime(context, dispense.dispensedAt!)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (isPending && canDispense) ...<Widget>[
              Gap.h8,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => _refuse(context),
                    icon: const Icon(Icons.block, size: 16),
                    label: Text(l10n.pharmRefuse),
                  ),
                  Gap.w8,
                  FilledButton.icon(
                    onPressed: cabinet == null
                        ? null
                        : () => showDispenseDialog(
                              context: context,
                              patient: patient,
                              prescription: prescription,
                              cabinet: cabinet,
                              request: dispense,
                            ),
                    icon: const Icon(Icons.medication_outlined, size: 16),
                    label: Text(l10n.pharmDispense),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refuse(BuildContext context) async {
    final l10n = HospitalLocalizations.of(context);
    final service = context.read<CabinetService>();
    final user = context.read<AuthService>().currentUser;
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.pharmRefuse),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.pharmRefusalReason),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.pharmRefuse),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;

    await service.refuse(
      request: dispense,
      reason: reason,
      refusedBy: user?.displayName ?? 'Unknown',
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
