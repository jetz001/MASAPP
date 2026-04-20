import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_repository.dart';

class AppSettingsState {
  final Map<String, String> data;

  AppSettingsState({this.data = const {}});

  String get(String key, {String defaultValue = ''}) => data[key] ?? defaultValue;

  AppSettingsState copyWith({Map<String, String>? data}) {
    return AppSettingsState(data: data ?? this.data);
  }
}

class AppSettingsNotifier extends AsyncNotifier<AppSettingsState> {
  @override
  FutureOr<AppSettingsState> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    final data = await repo.getAllSettings();
    return AppSettingsState(data: data);
  }

  Future<void> updateSetting(String key, String value) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.saveSetting(key, value);
    
    // Optimistic update or just refetch
    final currentData = state.valueOrNull?.data ?? {};
    state = AsyncData(AppSettingsState(data: {
      ...currentData,
      key: value,
    }));
  }
}

final appSettingsProvider = AsyncNotifierProvider<AppSettingsNotifier, AppSettingsState>(() {
  return AppSettingsNotifier();
});

// Common keys for easier access
class AppSettingKeys {
  static const orgName = 'org_name';
  static const orgLogo = 'org_logo';
  static const orgAddress = 'org_address';
  static const orgPhone = 'org_phone';
  static const orgTaxId = 'org_tax_id';
  static const docIntakeRef = 'doc_intake_ref';
}
