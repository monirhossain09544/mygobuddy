import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/providers/home_provider.dart';
import 'package:mygobuddy/providers/profile_provider.dart';
import 'package:mygobuddy/providers/trip_provider.dart';
import 'package:mygobuddy/screens/selection_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _validatePassword(String password) async {
    try {
      final user = supabase.auth.currentUser;
      if (user?.email == null) return false;

      // Attempt to sign in with current credentials to validate password
      final response = await supabase.auth.signInWithPassword(
        email: user!.email!,
        password: password,
      );

      return response.user != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> _deleteUserAccount() async {
    final localizations = AppLocalizations.of(context)!;
    final user = supabase.auth.currentUser;

    if (user == null) {
      context.showSnackBar(localizations.translate('error_user_not_found'), isError: true);
      return;
    }

    try {
      // Delete user data from all related tables using RPC function
      await supabase.rpc('delete_user_account', params: {
        'p_user_id': user.id,
      });

      // Clear all local providers
      if (mounted) {
        Provider.of<ProfileProvider>(context, listen: false).clearProfile();
        Provider.of<HomeProvider>(context, listen: false).clearData();
        Provider.of<TripProvider>(context, listen: false).clearTripState();
      }

      // Sign out the user
      await supabase.auth.signOut();

      if (mounted) {
        context.showSnackBar(localizations.translate('delete_account_success'));
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
          localizations.translate('delete_account_error', args: {'error': e.toString()}),
          isError: true,
        );
      }
      rethrow;
    }
  }

  void _showConfirmationDialog() {
    final localizations = AppLocalizations.of(context)!;

    if (_passwordController.text.trim().isEmpty) {
      context.showSnackBar(localizations.translate('delete_account_password_required'), isError: true);
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            localizations.translate('delete_account_dialog_title'),
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.translate('delete_account_dialog_content'),
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.translate('delete_account_warning_data_loss'),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• ${localizations.translate('delete_account_data_profile')}',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.red.shade600),
                    ),
                    Text(
                      '• ${localizations.translate('delete_account_data_bookings')}',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.red.shade600),
                    ),
                    Text(
                      '• ${localizations.translate('delete_account_data_messages')}',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.red.shade600),
                    ),
                    Text(
                      '• ${localizations.translate('delete_account_data_transactions')}',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.red.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                localizations.translate('delete_account_dialog_cancel'),
                style: GoogleFonts.poppins(color: Colors.grey.shade800),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            StatefulBuilder(
              builder: (context, setDialogState) {
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : Text(
                    localizations.translate('delete_account_dialog_confirm'),
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () async {
                    setDialogState(() {
                      _isLoading = true;
                    });

                    try {
                      final isValidPassword = await _validatePassword(_passwordController.text.trim());

                      if (!isValidPassword) {
                        if (mounted) {
                          context.showSnackBar(
                            localizations.translate('delete_account_invalid_password'),
                            isError: true,
                          );
                        }
                        return;
                      }

                      // Proceed with account deletion
                      await _deleteUserAccount();

                      // Navigate to selection screen
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const SelectionScreen()),
                              (Route<dynamic> route) => false,
                        );
                      }
                    } catch (e) {
                      // Error handling is done in _deleteUserAccount
                    } finally {
                      if (mounted) {
                        setDialogState(() {
                          _isLoading = false;
                        });
                      }
                    }
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    final Color destructiveColor = Colors.red.shade700;

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
            localizations.translate('delete_account_title'),
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: destructiveColor, size: 60),
              const SizedBox(height: 24),
              Text(
                localizations.translate('delete_account_warning_title'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                localizations.translate('delete_account_warning_message'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _buildPasswordField(
                label: localizations.translate('delete_account_confirm_password_label'),
                hint: localizations.translate('delete_account_confirm_password_hint'),
                obscureText: _obscurePassword,
                onToggleVisibility: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _showConfirmationDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: destructiveColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  child: Text(
                    localizations.translate('delete_account_button'),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required String hint,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: const Color(0xFF292D32),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passwordController,
          obscureText: obscureText,
          style: GoogleFonts.poppins(
            color: const Color(0xFF292D32),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.grey[400],
              ),
              onPressed: onToggleVisibility,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF19638D), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
