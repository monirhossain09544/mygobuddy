import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mygobuddy/models/dashboard_data.dart';
import 'package:mygobuddy/providers/dashboard_provider.dart';
import 'package:mygobuddy/screens/add_paypal_account_screen.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';

class PayoutSettingsScreen extends StatelessWidget {
  const PayoutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryTextColor = Color(0xFF111827);
    const Color accentColor = Color(0xFFF15808);
    const Color backgroundColor = Color(0xFFF9FAFB);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          localizations.translate('payoutMethods'),
          style: GoogleFonts.poppins(
            color: primaryTextColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, provider, child) {
          final payoutMethod = provider.dashboardData?.payoutMethod;

          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                if (payoutMethod != null)
                  _buildPayoutMethodCard(payoutMethod, context, localizations)
                else
                  _buildEmptyState(context, localizations),
                const Spacer(),
                if (payoutMethod == null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Image.asset(
                        'assets/images/paypal_logo.png',
                        height: 20,
                      ),
                      label: Text(localizations.translate('connectPayPalAccount')),
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => const AddPayPalAccountScreen(),
                        ));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations localizations) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Image.asset(
              'assets/images/paypal_logo.png',
              height: 60,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.translate('noPayoutMethodAdded'),
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.translate('connectPayPalToReceiveEarnings'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutMethodCard(PayoutMethod payoutMethod, BuildContext context, AppLocalizations localizations) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          if (payoutMethod.isPayPal)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/images/paypal_logo.png',
                height: 24,
              ),
            )
          else
            const Icon(Icons.account_balance_outlined, color: Color(0xFF19638D), size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payoutMethod.displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  payoutMethod.displayDetails,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF6B7280),
                    letterSpacing: payoutMethod.isPayPal ? 0 : 1.5,
                  ),
                ),
                if (payoutMethod.isPayPal) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        payoutMethod.paypalVerified == true
                            ? Icons.verified
                            : Icons.warning_outlined,
                        size: 16,
                        color: payoutMethod.paypalVerified == true
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        payoutMethod.paypalVerified == true
                            ? localizations.translate('verified')
                            : localizations.translate('unverified'),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: payoutMethod.paypalVerified == true
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.grey),
            onPressed: () {
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (context) => const AddPayPalAccountScreen(),
              ));
            },
          ),
        ],
      ),
    );
  }
}
