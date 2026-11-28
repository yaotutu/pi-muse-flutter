import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'src/app/pi_muse_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const PiMuseApp());
}
