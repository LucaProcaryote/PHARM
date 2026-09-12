import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

import '../widgets/restock_dialog.dart';

/// Stock across all cabinets, with the problems collected at the top.
///
/// The alert list is the working screen for a pharmacist: everything empty,
/// expired, expiring or below par, in one place, rather than something you find
/// by scrolling a cabinet.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _alertsOnly = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);

    return RepositoryBuilder<
      ({List<StockItem> stock, Map<String, Cabinet> cabinets})
    >(
      query: (repository) async => (
        stock: await repository.listStock(query: _query),
        cabinets: <String, Cabinet>{
          for (final cabinet in await repository.listCabinets())
            cabinet.id: cabinet,
        },
      ),
      builder: (context, data) {
        final flagged = data.stock
            .where((s) => s.isEmpty || s.isExpired || s.isLow || s.isNearExpiry)
            .toList();
        final shown = _alertsOnly ? flagged : data.stock;

        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: l10n.formularySearchHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                  Gap.h8,
                  Row(
                    children: <Widget>[
                      FilterChip(
                        selected: _alertsOnly,
                        label: Text('${l10n.pharmAlerts} (${flagged.length})'),
                        onSelected: (value) =>
                            setState(() => _alertsOnly = value),
                      ),
                      Gap.w8,
                      Text(
                        '${data.stock.length} ${l10n.pharmSlot.toLowerCase()}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty
                  ? EmptyView(
                      message: _alertsOnly
                          ? l10n.pharmNoAlerts
                          : l10n.labelNoResults,
                      icon: Icons.check_circle_outline,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Gap.md),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = shown[index];
                        final cabinet = data.cabinets[item.cabinetId];
                        final flags = <(String, Color)>[
                          if (item.isEmpty)
                            (
                              l10n.pharmOutOfStock,
                              HospitalTheme.criticalOf(context),
                            ),
                          if (item.isExpired)
                            (
                              l10n.pharmExpiredLot,
                              HospitalTheme.criticalOf(context),
                            ),
                          if (item.isLow && !item.isEmpty)
                            (
                              l10n.pharmLowStock,
                              HospitalTheme.warningOf(context),
                            ),
                          if (item.isNearExpiry)
                            (
                              l10n.pharmNearExpiry,
                              HospitalTheme.warningOf(context),
                            ),
                        ];

                        return ListTile(
                          title: Text(
                            '${item.medication.name.forLanguage(language)} '
                            '${item.medication.strength}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${cabinet?.code ?? item.cabinetId} · '
                            '${l10n.pharmSlot} ${item.slot} · '
                            '${l10n.pharmOnHand} ${item.quantityOnHand}'
                            '/${item.parLevel} · '
                            '${l10n.pharmLot} ${item.lotNumber} · '
                            '${Formats.shortDate(context, item.expiryDate)}',
                            style: theme.textTheme.labelSmall,
                          ),
                          trailing: Wrap(
                            spacing: Gap.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              for (final (label, color) in flags)
                                StatusChip(
                                  label: label,
                                  color: color,
                                  dense: true,
                                ),
                              IconButton(
                                tooltip: l10n.pharmRestock,
                                icon: const Icon(
                                  Icons.add_box_outlined,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    showRestockDialog(context, item),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
