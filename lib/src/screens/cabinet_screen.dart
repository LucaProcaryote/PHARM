import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/cabinet_service.dart';
import '../widgets/restock_dialog.dart';

/// The cabinet itself: a wall of drawers you can lock, unlock and open.
///
/// This is the screen that makes the pharmacy feel physical. The cabinet
/// refuses everything while locked, only one drawer opens at a time, and the
/// drawer closes itself after a few seconds whether or not anybody remembered.
class CabinetScreen extends StatefulWidget {
  const CabinetScreen({super.key});

  @override
  State<CabinetScreen> createState() => _CabinetScreenState();
}

class _CabinetScreenState extends State<CabinetScreen> {
  String? _cabinetId;
  bool _announcedAutoClose = false;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final service = context.watch<CabinetService>();
    final canDispense =
        context.watch<AuthService>().currentUser?.role.canDispense ?? false;

    // Tell the user when the cabinet shut the drawer on its own.
    if (service.closedAutomatically && !_announcedAutoClose) {
      _announcedAutoClose = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pharmDrawerClosedAutomatically)),
        );
      });
    } else if (!service.closedAutomatically) {
      _announcedAutoClose = false;
    }

    return RepositoryBuilder<({List<Cabinet> cabinets, List<StockItem> stock})>(
      query: (repository) async {
        final cabinets = await repository.listCabinets();
        final id = _cabinetId ?? (cabinets.isEmpty ? null : cabinets.first.id);
        return (
          cabinets: cabinets,
          stock: id == null
              ? const <StockItem>[]
              : await repository.listStock(cabinetId: id),
        );
      },
      builder: (context, data) {
        if (data.cabinets.isEmpty) {
          return EmptyView(
            message: l10n.labelNoResults,
            icon: Icons.inventory_2_outlined,
          );
        }
        final cabinet = data.cabinets.firstWhere(
          (c) => c.id == (_cabinetId ?? data.cabinets.first.id),
          orElse: () => data.cabinets.first,
        );

        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: cabinet.id,
                      decoration:
                          InputDecoration(labelText: l10n.pharmCabinet),
                      items: <DropdownMenuItem<String>>[
                        for (final option in data.cabinets)
                          DropdownMenuItem<String>(
                            value: option.id,
                            child: Text(
                              '${option.code} — '
                              '${option.name.forLanguage(language)}',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        context.read<CabinetService>().closeDrawer();
                        setState(() => _cabinetId = value);
                      },
                    ),
                  ),
                  Gap.w16,
                  _LockButton(cabinet: cabinet, enabled: canDispense),
                ],
              ),
            ),
            if (cabinet.temperatureCelsius != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(
                    label: '${cabinet.temperatureCelsius!.toStringAsFixed(1)} °C',
                    color: HospitalTheme.infoOf(context),
                    icon: Icons.thermostat,
                    dense: true,
                  ),
                ),
              ),
            const Divider(height: Gap.md),
            Expanded(
              child: data.stock.isEmpty
                  ? EmptyView(
                      message: l10n.labelNoResults,
                      icon: Icons.inventory_2_outlined,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Wrap(
                        spacing: Gap.sm,
                        runSpacing: Gap.sm,
                        children: <Widget>[
                          for (final item in data.stock)
                            _DrawerTile(
                              item: item,
                              cabinet: cabinet,
                              isOpen: service.openSlotId == item.id,
                              canOperate: canDispense,
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LockButton extends StatelessWidget {
  const _LockButton({required this.cabinet, required this.enabled});

  final Cabinet cabinet;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final service = context.read<CabinetService>();
    final locked = cabinet.isLocked;

    return FilledButton.tonalIcon(
      onPressed: !enabled
          ? null
          : () => locked ? service.unlock(cabinet) : service.lock(cabinet),
      icon: Icon(locked ? Icons.lock : Icons.lock_open, size: 18),
      label: Text(locked ? l10n.pharmUnlock : l10n.pharmLock),
      style: FilledButton.styleFrom(
        backgroundColor: locked
            ? HospitalTheme.criticalOf(context).withValues(alpha: 0.15)
            : HospitalTheme.successOf(context).withValues(alpha: 0.15),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.item,
    required this.cabinet,
    required this.isOpen,
    required this.canOperate,
  });

  final StockItem item;
  final Cabinet cabinet;
  final bool isOpen;
  final bool canOperate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final service = context.read<CabinetService>();

    // The most serious condition decides the colour; the label says which.
    final (Color color, String? flag) = item.isExpired
        ? (HospitalTheme.criticalOf(context), l10n.pharmExpiredLot)
        : item.isEmpty
            ? (HospitalTheme.criticalOf(context), l10n.pharmOutOfStock)
            : item.isLow
                ? (HospitalTheme.warningOf(context), l10n.pharmLowStock)
                : item.isNearExpiry
                    ? (HospitalTheme.warningOf(context), l10n.pharmNearExpiry)
                    : (HospitalTheme.successOf(context), null);

    return SizedBox(
      width: 230,
      child: Container(
        padding: const EdgeInsets.all(Gap.sm + 2),
        decoration: BoxDecoration(
          color: isOpen
              ? theme.colorScheme.primaryContainer
              : color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isOpen ? theme.colorScheme.primary : color.withValues(alpha: 0.4),
            width: isOpen ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.slot,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (item.medication.isControlled)
                  Tooltip(
                    message: l10n.medicationControlled,
                    child: Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: HospitalTheme.warningOf(context),
                    ),
                  ),
              ],
            ),
            Gap.h4,
            Text(
              item.medication.name.forLanguage(language),
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${item.medication.strength} · '
              '${item.medication.form.forLanguage(language)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Gap.h8,
            Row(
              children: <Widget>[
                Text(
                  '${item.quantityOnHand}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Gap.w4,
                Text(
                  '/ ${item.parLevel}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  Formats.shortDate(context, item.expiryDate),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: item.isExpired || item.isNearExpiry
                        ? color
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (flag != null) ...<Widget>[
              Gap.h4,
              // Always written out, never colour alone.
              StatusChip(label: flag, color: color, dense: true),
            ],
            Gap.h8,
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: !canOperate
                        ? null
                        : () {
                            if (isOpen) {
                              service.closeDrawer();
                              return;
                            }
                            final opened = service.openDrawer(cabinet, item);
                            if (!opened) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.pharmBlockedLocked),
                                ),
                              );
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                    ),
                    child: Text(
                      isOpen ? l10n.pharmCloseDrawer : l10n.pharmOpenDrawer,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
                Gap.w4,
                IconButton(
                  tooltip: l10n.pharmRestock,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  onPressed:
                      canOperate ? () => showRestockDialog(context, item) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
