import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider with ChangeNotifier {
  Locale? _appLocale;
  bool _isLoading = true;

  Locale? get appLocale => _appLocale;
  bool get isLoading => _isLoading;

  LanguageProvider() {
    loadLocale(); // Call on initialization
  }

// Renamed from fetchLocale to loadLocale for clarity and to fix the error.
  Future<void> loadLocale() async {
    _isLoading = true;
    // No need to notify here, the initial state is loading.

    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('language_code');

    if (languageCode != null && languageCode.isNotEmpty) {
      _appLocale = Locale(languageCode);
    } else {
      _appLocale = null; // This indicates that no language has been set yet.
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> changeLanguage(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (_appLocale == locale) {
      return;
    }
    _appLocale = locale;
    await prefs.setString('language_code', locale.languageCode);
    notifyListeners();
  }
}
