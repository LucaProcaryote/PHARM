import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

import 'src/pharm_home.dart';

/// Entry point of the pharmacy cabinet.
///
/// ```
/// flutter run -d chrome                                  # demo data
/// flutter run -d chrome --dart-define=BACKEND=restApi    # local API + Postgres
/// ```
void main() {
  runApp(
    MiniHospitalApp(
      config: AppConfig.fromEnvironment(HospitalApp.pharm),
      title: (l10n) => l10n.appTitlePharm,
      subtitle: (l10n) => l10n.hospitalName,
      homeBuilder: (context) => const PharmHome(),
    ),
  );
}
