import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/cabinet_service.dart';

/// Adds units to a slot. A restock always brings a new lot with it, because
/// mixing a fresh lot into a drawer that still holds an expired one is exactly
/// what an automated cabinet exists to prevent.
Future<void> showRestockDialog(BuildContext context, StockItem item) async {
  final service = context.read<CabinetService>();
  final l10n = HospitalLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final language = Localizations.localeOf(context).languageCode;

  final controller = TextEditingController(
    text: '${(item.parLevel * 2 - item.quantityOnHand).clamp(1, 999)}',
  );

  final quantity = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.pharmRestock),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${item.medication.name.forLanguage(language)} '
            '${item.medication.strength}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${l10n.pharmSlot} ${item.slot} · '
            '${l10n.pharmOnHand} ${item.quantityOnHand} · '
            '${l10n.pharmParLevel} ${item.parLevel}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Gap.h16,
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.pharmRestockAmount),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(controller.text)),
          child: Text(l10n.pharmRestock),
        ),
      ],
    ),
  );

  controller.dispose();
  if (quantity == null || quantity <= 0) return;

  await service.restock(item, quantity);
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.pharmRestocked(item.slot))),
  );
}
