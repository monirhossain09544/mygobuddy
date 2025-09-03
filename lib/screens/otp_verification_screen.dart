import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/screens/reset_password_screen.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  const OtpVerificationScreen({super.key, required this.email});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  int _resendTimer = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        if (mounted) setState(() => _resendTimer--);
      } else {
        _timer?.cancel();
      }
    });
  }

  Future<void> _resendCode() async {
    if (_resendTimer > 0) return;
    setState(() => _isLoading = true);
    final localizations = AppLocalizations.of(context)!;
    try {
      await supabase.auth.resetPasswordForEmail(widget.email);
      if (mounted) {
        context.showSnackBar(localizations.translate('otp_resend_success_snackbar'));
        setState(() => _resendTimer = 60);
        startTimer();
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(localizations.translate('otp_resend_error_snackbar'), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    final localizations = AppLocalizations.of(context)!;
    if (_pinController.text.length != 6) {
      context.showSnackBar(localizations.translate('otp_invalid_length_snackbar'), isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await supabase.auth.verifyOTP(
        token: _pinController.text,
        type: OtpType.recovery,
        email: widget.email,
      );

      if (response.session != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ResetPasswordScreen()),
        );
      } else {
        if (mounted) context.showSnackBar(localizations.translate('otp_invalid_otp_snackbar'), isError: true);
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(localizations.translate('error_unexpected'), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF19638D);
    const Color accentColor = Color(0xFFF15808);
    const Color backgroundColor = Color(0xFFF8F8F8);
    final localizations = AppLocalizations.of(context)!;

    final defaultPinTheme = PinTheme(
      width: 48,
      height: 52,
      textStyle: GoogleFonts.poppins(fontSize: 20, color: primaryColor, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1D1D6)),
      ),
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Text(
                localizations.translate('otp_verify_email_title'),
                style: GoogleFonts.poppins(
                  color: primaryColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                localizations.translate('otp_prompt').replaceAll('{email}', widget.email),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),
              Pinput(
                controller: _pinController,
                length: 6,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: defaultPinTheme.copyWith(
                  decoration: defaultPinTheme.decoration!.copyWith(
                    border: Border.all(color: primaryColor, width: 1.5),
                  ),
                ),
                onCompleted: (pin) => _verifyOtp(),
              ),
              const SizedBox(height: 30),
              Center(
                child: SizedBox(
                  width: 260,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                      localizations.translate('otp_verify_button'),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _resendTimer > 0 ? null : _resendCode,
                child: Text(
                  _resendTimer > 0
                      ? localizations.translate('otp_resend_timer').replaceAll('{seconds}', _resendTimer.toString().padLeft(2, '0'))
                      : localizations.translate('otp_resend_button'),
                  style: GoogleFonts.poppins(
                    color: _resendTimer > 0 ? Colors.grey : accentColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
