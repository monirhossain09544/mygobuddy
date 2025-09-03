import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/providers/language_provider.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';

class LanguageScreen extends StatefulWidget {
  final bool isInitialSetup;
  const LanguageScreen({super.key, this.isInitialSetup = false});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selectedLanguageCode = 'en';

  @override
  void initState() {
    super.initState();
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    _selectedLanguageCode = languageProvider.appLocale?.languageCode ?? 'en';
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color accentColor = Color(0xFF19638D);
    const Color accentColorLight = Color(0xFFE8F0F8);
    final localizations = AppLocalizations.of(context)!;

    // Define the languages with their translation keys
    final List<Map<String, String>> languageData = [
      {'key': 'language_name_en', 'fallback': 'English', 'flag': '🇬🇧', 'code': 'en'},
      {'key': 'language_name_es', 'fallback': 'Spanish', 'flag': '🇪🇸', 'code': 'es'},
    ];

    // Build the list of languages with translated names
    final List<Map<String, String>> languages = languageData.map((lang) {
      return {
        'name': localizations.translate(lang['key']!, fallback: lang['fallback']),
        'flag': lang['flag']!,
        'code': lang['code']!,
      };
    }).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          surfaceTintColor: backgroundColor,
          elevation: 0,
          leading: widget.isInitialSetup
              ? null
              : IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            localizations.language,
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          automaticallyImplyLeading: !widget.isInitialSetup,
        ),
        body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          itemCount: languages.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final language = languages[index];
            final isSelected = language['code'] == _selectedLanguageCode;
            return _buildLanguageOption(
              name: language['name']!,
              flag: language['flag']!,
              isSelected: isSelected,
              accentColor: accentColor,
              accentColorLight: accentColorLight,
              groupValue: languages.firstWhere((lang) => lang['code'] == _selectedLanguageCode)['name']!,
              onTap: () {
                setState(() {
                  _selectedLanguageCode = language['code']!;
                });
              },
            );
          },
        ),
        bottomNavigationBar: _buildSaveChangesButton(context, accentColor),
      ),
    );
  }

  Widget _buildLanguageOption({
    required String name,
    required String flag,
    required bool isSelected,
    required Color accentColor,
    required Color accentColorLight,
    required String groupValue,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentColorLight : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(
              flag,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
            Radio<String>(
              value: name,
              groupValue: groupValue,
              onChanged: (value) {
                onTap();
              },
              activeColor: accentColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveChangesButton(BuildContext context, Color accentColor) {
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(24.0, 10.0, 24.0, 20.0),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
              final newLocale = Locale(_selectedLanguageCode);
              languageProvider.changeLanguage(newLocale);

              if (!widget.isInitialSetup) {
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            child: Text(
              AppLocalizations.of(context)!.saveChanges,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
