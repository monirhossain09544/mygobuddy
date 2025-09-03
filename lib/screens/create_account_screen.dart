import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/screens/buddy_profile_setup_screen.dart';
import 'package:mygobuddy/screens/setup_profile_screen.dart';
import 'package:mygobuddy/screens/sign_in_screen.dart';
import 'package:mygobuddy/screens/terms_and_conditions_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:mygobuddy/widgets/custom_circular_checkbox.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateAccountScreen extends StatefulWidget {
  final bool isBuddy;
  const CreateAccountScreen({super.key, required this.isBuddy});
  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _referralCodeController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final localizations = AppLocalizations.of(context)!;
    if (!_agreedToTerms) {
      context.showSnackBar(localizations.translate('error_agree_terms'),
          isError: true);
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final referralCode = _referralCodeController.text.trim();
      String? referrerId;
      // Validate the referral code if one was entered
      if (referralCode.isNotEmpty) {
        try {
          final referrerData = await supabase
              .from('profiles')
              .select('id')
              .eq('id', referralCode)
              .maybeSingle();
          if (referrerData == null) {
            if (mounted) context.showSnackBar(localizations.translate('error_invalid_referral_code'), isError: true);
            setState(() { _isLoading = false; });
            return;
          }
          referrerId = referrerData['id'] as String;
        } catch (e) {
          if (mounted) context.showSnackBar(localizations.translate('error_validating_referral_code'), isError: true);
          setState(() { _isLoading = false; });
          return;
        }
      }
      final res = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (res.user != null && mounted) {
        final newUser = res.user!;
        // Step 1: Create the main profile record for all users.
        await supabase.from('profiles').insert({
          'id': newUser.id,
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'userType': widget.isBuddy ? 'buddy' : 'client',
          'is_buddy': widget.isBuddy,
          'role': widget.isBuddy ? 'buddy' : 'client',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'referrer_id': referrerId, // Add the referrer_id here
        });
        // Step 2: If the user is a buddy, create a corresponding record
        // in the 'buddies' table with the default rate.
        if (widget.isBuddy) {
          await supabase.from('buddies').insert({
            'id': newUser.id,
            'name': _nameController.text.trim(),
            'tier': 'standard', // Set default tier
          });
        }
        // Step 3: If a valid referrer ID exists, process the referral
        if (referrerId != null) {
          await supabase.rpc('handle_successful_referral', params: {
            'p_referred_user_id': newUser.id,
            'p_referrer_id': referrerId,
          });
        }
        // Step 4: Show the success dialog and navigate to the profile setup screen.
        _showSuccessDialog();
      }
    } on AuthException catch (e) {
      if (mounted) context.showSnackBar(e.message, isError: true);
    } on PostgrestException catch (e) {
      debugPrint('Database Error: ${e.message}');
      if (mounted) {
        context.showSnackBar('Database error: ${e.message}', isError: true);
      }
    } catch (e, stackTrace) {
      debugPrint('An unexpected error occurred: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        context.showSnackBar(localizations.translate('error_unexpected'),
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessDialog() {
    final localizations = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        Future.delayed(const Duration(seconds: 3), () {
          Navigator.of(context).pop(); // Close the dialog
          context.showSnackBar(
              localizations.translate('success_redirect_profile'));

          // CORRECTED: Always navigate to SetupProfileScreen first.
          // It will handle routing to BuddyProfileSetupScreen if needed.
          final Widget nextScreen = SetupProfileScreen(isBuddy: widget.isBuddy);

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => nextScreen,
            ),
          );
        });
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Container(
              padding:
              const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.shade700,
                    size: 60,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    localizations.translate('dialog_account_created'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    localizations.translate('dialog_redirecting_profile'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    const Color primaryColor = Color(0xFF19638D);
    const Color accentColor = Color(0xFFF15808);
    const Color backgroundColor = Color(0xFFF8F8F8);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: backgroundColor,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 50),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            localizations.translate('create_account_title'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: primaryColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            localizations.translate('create_account_subtitle'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.03,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildTextField(
                      controller: _nameController,
                      icon: Icons.person_outline,
                      label: localizations.translate('label_full_name'),
                      hint: localizations.translate('hint_enter_name'),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return localizations
                              .translate('validation_enter_full_name');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _emailController,
                      icon: Icons.email_outlined,
                      label: localizations.translate('label_email'),
                      hint: localizations.translate('hint_enter_email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null ||
                            value.isEmpty ||
                            !value.contains('@')) {
                          return localizations
                              .translate('validation_invalid_email');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _passwordController,
                      icon: Icons.lock_outline,
                      label: localizations.translate('label_password'),
                      hint: localizations.translate('hint_enter_password'),
                      isPassword: true,
                      obscureText: _obscurePassword,
                      onToggleVisibility: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return localizations
                              .translate('validation_password_length');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _confirmPasswordController,
                      icon: Icons.lock_outline,
                      label: localizations.translate('label_confirm_password'),
                      hint: localizations.translate('hint_confirm_password'),
                      isPassword: true,
                      obscureText: _obscureConfirmPassword,
                      onToggleVisibility: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return localizations
                              .translate('validation_passwords_no_match');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _referralCodeController,
                      icon: Icons.group_add_outlined,
                      label: localizations.translate('label_referral_code_optional'),
                      hint: localizations.translate('hint_enter_referral_code'),
                    ),
                    const SizedBox(height: 24),
                    CustomCircularCheckbox(
                      value: _agreedToTerms,
                      onChanged: (value) {
                        setState(() {
                          _agreedToTerms = value;
                        });
                      },
                      activeColor: primaryColor,
                      label: RichText(
                        text: TextSpan(
                          style: GoogleFonts.poppins(
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                                text: localizations.translate('text_agree_to')),
                            TextSpan(
                              text: localizations
                                  .translate('text_terms_and_conditions'),
                              style: const TextStyle(
                                color: primaryColor,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) =>
                                    const TermsAndConditionsScreen(),
                                  ));
                                },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: SizedBox(
                        width: 260,
                        child: ElevatedButton(
                          onPressed:
                          _isLoading || !_agreedToTerms ? null : _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3),
                          )
                              : Text(
                            localizations.translate('button_sign_up'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          localizations.translate('text_already_have_account'),
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (context) =>
                                      SignInScreen(isBuddy: widget.isBuddy)),
                            );
                          },
                          child: Text(
                            localizations.translate('button_sign_in'),
                            style: GoogleFonts.poppins(
                              color: accentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required IconData icon,
    required String label,
    required String hint,
    TextEditingController? controller,
    String? Function(String?)? validator,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: const Color(0xFF292D32),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.08,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(
            color: const Color(0xFF292D32),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.07,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              color: const Color(0xFF8E8E93),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.07,
            ),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: isPassword
                ? IconButton(
              icon: Icon(
                obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.grey[400],
              ),
              onPressed: onToggleVisibility,
            )
                : null,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(width: 0.50, color: Color(0xFFD1D1D6)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(width: 0.50, color: Color(0xFFD1D1D6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFF19638D), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
