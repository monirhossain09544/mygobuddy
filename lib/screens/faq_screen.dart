import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/utils/localizations.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  // This will hold the original translated data
  List<Map<String, String>> _originalFaqData = [];
  // This will hold the list of FAQs to be displayed (can be filtered)
  late List<Map<String, String>> _filteredFaqs;
  final TextEditingController _searchController = TextEditingController();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Initialize with an empty list; it will be populated in didChangeDependencies
    _filteredFaqs = [];
    _searchController.addListener(_filterFaqs);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize only once
    if (!_isInitialized) {
      _initializeFaqs();
      _isInitialized = true;
    }
  }

  void _initializeFaqs() {
    final localizations = AppLocalizations.of(context);
    // The keys for our FAQ items
    final faqKeys = ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'];

    // Build the list of FAQs from the translation keys
    _originalFaqData = faqKeys.map((key) {
      return {
        'question': localizations.translate('faq_$key'),
        'answer': localizations.translate('faq_a$key'),
      };
    }).toList();

    // Set the initial state for the filtered list
    setState(() {
      _filteredFaqs = _originalFaqData;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterFaqs);
    _searchController.dispose();
    super.dispose();
  }

  void _filterFaqs() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      // Always filter from the original, complete list of FAQs
      _filteredFaqs = _originalFaqData.where((faq) {
        return faq['question']!.toLowerCase().contains(query) ||
            faq['answer']!.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color primaryColor = Color(0xFF19638D);

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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            localizations.translate('faq_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          children: [
            _buildSearchBar(localizations),
            const SizedBox(height: 24),
            ..._filteredFaqs.map((faq) {
              return _FaqExpansionTile(
                question: faq['question']!,
                answer: faq['answer']!,
                primaryColor: primaryColor,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(AppLocalizations localizations) {
    return TextField(
      controller: _searchController,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: localizations.translate('faq_search_hint'),
        hintStyle: GoogleFonts.poppins(color: Colors.grey.shade500),
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
        ),
      ),
    );
  }
}

class _FaqExpansionTile extends StatelessWidget {
  final String question;
  final String answer;
  final Color primaryColor;

  const _FaqExpansionTile({
    required this.question,
    required this.answer,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.07),
            spreadRadius: 1,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: primaryColor,
          collapsedIconColor: Colors.grey.shade700,
          title: Text(
            question,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF111827),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                answer,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
