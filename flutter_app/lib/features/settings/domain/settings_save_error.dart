import 'package:flutter_riverpod/legacy.dart';

/// Transient holder for a settings-save failure. The notifiers set it when a
/// PUT fails (after rolling the optimistic toggle back); the settings screens
/// listen and show a snackbar, then clear it. Lets us give clear "couldn't
/// save" feedback without wrapping every individual tile.
final settingsSaveErrorProvider = StateProvider<Object?>((_) => null);
