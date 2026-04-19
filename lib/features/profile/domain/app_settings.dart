class AppSettings {
  const AppSettings({
    required this.languageCode,
    this.darkMode = false,
    this.privateAccount = false,
    this.suggestAccount = true,
    this.syncContacts = false,
    this.locationServices = false,
    this.adsPersonalization = true,
    this.quickUpload = false,
  });

  final String languageCode;
  final bool darkMode;
  final bool privateAccount;
  final bool suggestAccount;
  final bool syncContacts;
  final bool locationServices;
  final bool adsPersonalization;
  final bool quickUpload;

  AppSettings copyWith({
    String? languageCode,
    bool? darkMode,
    bool? privateAccount,
    bool? suggestAccount,
    bool? syncContacts,
    bool? locationServices,
    bool? adsPersonalization,
    bool? quickUpload,
  }) {
    return AppSettings(
      languageCode: languageCode ?? this.languageCode,
      darkMode: darkMode ?? this.darkMode,
      privateAccount: privateAccount ?? this.privateAccount,
      suggestAccount: suggestAccount ?? this.suggestAccount,
      syncContacts: syncContacts ?? this.syncContacts,
      locationServices: locationServices ?? this.locationServices,
      adsPersonalization: adsPersonalization ?? this.adsPersonalization,
      quickUpload: quickUpload ?? this.quickUpload,
    );
  }

  factory AppSettings.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const <String, dynamic>{};
    return AppSettings(
      languageCode: (m['languageCode'] ?? 'en_US') as String,
      darkMode: (m['darkMode'] ?? false) as bool,
      privateAccount: (m['privateAccount'] ?? false) as bool,
      suggestAccount: (m['suggestAccount'] ?? true) as bool,
      syncContacts: (m['syncContacts'] ?? false) as bool,
      locationServices: (m['locationServices'] ?? false) as bool,
      adsPersonalization: (m['adsPersonalization'] ?? true) as bool,
      quickUpload: (m['quickUpload'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'languageCode': languageCode,
      'darkMode': darkMode,
      'privateAccount': privateAccount,
      'suggestAccount': suggestAccount,
      'syncContacts': syncContacts,
      'locationServices': locationServices,
      'adsPersonalization': adsPersonalization,
      'quickUpload': quickUpload,
    };
  }
}











