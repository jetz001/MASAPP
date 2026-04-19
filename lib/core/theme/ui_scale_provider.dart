import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UiScaleNotifier extends Notifier<double> {
  final double initialScale;
  static const _key = 'ui_scale_factor';

  UiScaleNotifier([this.initialScale = 1.0]);

  @override
  double build() {
    return initialScale;
  }

  Future<void> setScale(double scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, scale);
  }
}

final uiScaleProvider = NotifierProvider<UiScaleNotifier, double>(() {
  return UiScaleNotifier();
});
