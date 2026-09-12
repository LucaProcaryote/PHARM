import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import 'screens/cabinet_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/stock_screen.dart';
import 'services/cabinet_service.dart';

/// The pharmacy application's navigation, with the cabinet service provided
/// above every screen so the drawer state is shared.
class PharmHome extends StatelessWidget {
  const PharmHome({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final repository = context.read<HospitalRepository>();

    return ChangeNotifierProvider<CabinetService>(
      create: (_) => CabinetService(repository: repository),
      child: AppShell(
        title: l10n.appTitlePharm,
        destinations: <ShellDestination>[
          ShellDestination(
            label: (l10n) => l10n.pharmQueue,
            icon: Icons.pending_actions_outlined,
            selectedIcon: Icons.pending_actions,
            builder: (context) => const QueueScreen(),
          ),
          ShellDestination(
            label: (l10n) => l10n.pharmCabinet,
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            builder: (context) => const CabinetScreen(),
          ),
          ShellDestination(
            label: (l10n) => l10n.pharmStock,
            icon: Icons.warehouse_outlined,
            selectedIcon: Icons.warehouse,
            builder: (context) => const StockScreen(),
          ),
        ],
      ),
    );
  }
}
