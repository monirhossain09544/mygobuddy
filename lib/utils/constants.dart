import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase client instance
final supabase = Supabase.instance.client;

/// App Color Constants
const Color primaryColor = Color(0xFF19638D);
const Color primaryTextColor = Color(0xFF111827);
const Color secondaryTextColor = Color(0xFF6B7280);

/// Simple pre-filled snackbar to show message
extension ShowSnackBar on BuildContext {
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }
}
