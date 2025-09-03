import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'package:mygobuddy/models/dashboard_data.dart';
import 'package:mygobuddy/providers/dashboard_provider.dart';
import 'package:mygobuddy/screens/payout_settings_screen.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mygobuddy/utils/localizations.dart';

class BuddyDashboardScreen extends StatefulWidget {
  const BuddyDashboardScreen({super.key});

  @override
  State<BuddyDashboardScreen> createState() => _BuddyDashboardScreenState();
}

class _BuddyDashboardScreenState extends State<BuddyDashboardScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fetch data when the screen is first built
      context.read<DashboardProvider>().fetchDashboardData();
    });
  }

  void _showRequestPayoutDialog() {
    final provider = context.read<DashboardProvider>();
    final dashboardData = provider.dashboardData;

    if (dashboardData == null || dashboardData.payoutMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a payout method first.'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PayoutSettingsScreen()));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _RequestPayoutSheet(
          availableBalance: dashboardData.availableBalance,
          payoutMethod: dashboardData.payoutMethod!,
          onRequest: (amount) async {
            await _handleRequestPayout(amount);
          },
        );
      },
    );
  }

  Future<void> _handleRequestPayout(double amount) async {
    final provider = context.read<DashboardProvider>();

    try {
      final createResponse = await supabase.rpc('request_paypal_payout', params: {
        'p_amount': amount,
      });

      print('[v0] Create response: $createResponse');
      print('[v0] Response type: ${createResponse.runtimeType}');

      if (createResponse == null) {
        throw Exception('Failed to create payout request');
      }

      // Handle both direct response and nested response structures
      dynamic responseData = createResponse;
      if (createResponse is List && createResponse.isNotEmpty) {
        responseData = createResponse.first;
      }

      print('[v0] Response data: $responseData');

      // Check if the request was successful
      if (responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Failed to create payout request');
      }

      final payoutId = responseData['payout_id'];
      print('[v0] Extracted payout ID: $payoutId');

      if (payoutId == null) {
        throw Exception('No payout ID returned from database');
      }

      final response = await supabase.functions.invoke('process-paypal-payout', body: {
        'payoutId': payoutId,
        'amount': amount,
      });

      if (mounted) {
        if (response.data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PayPal payout requested successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh dashboard data to show updated balance
          await provider.fetchDashboardData(force: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payout failed: ${response.data['error'] ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('[v0] Error in _handleRequestPayout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing payout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);
    const Color accentColor = Color(0xFFF15808);
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
          localizations.dashboardTitle,
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
          if (provider.state == DashboardState.loading && provider.dashboardData == null) {
            return _buildLoadingShimmer();
          }
          if (provider.state == DashboardState.error) {
            return Center(child: Text(provider.errorMessage));
          }
          if (provider.dashboardData == null) {
            return const Center(child: Text('No data available. Pull to refresh.'));
          }

          final data = provider.dashboardData!;

          return RefreshIndicator(
            onRefresh: () => provider.fetchDashboardData(force: true),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              children: [
                _buildBalanceCard(data),
                const SizedBox(height: 32),
                _buildStatsGrid(data),
                const SizedBox(height: 32),
                _buildSectionHeader(localizations.dashboardWeeklyReport),
                const SizedBox(height: 16),
                _EarningsChart(weeklyEarnings: data.weeklyEarnings),
                const SizedBox(height: 32),
                _buildSectionHeader(localizations.dashboardEarningsSummary),
                const SizedBox(height: 16),
                _buildEarningsSummary(data),
                const SizedBox(height: 32),
                _buildSectionHeader(localizations.dashboardPayoutMethod),
                const SizedBox(height: 16),
                _buildPayoutMethodCard(data.payoutMethod),
                const SizedBox(height: 32),
                _buildSectionHeader(localizations.dashboardRecentPayouts), // New Section
                const SizedBox(height: 16),
                _buildRecentPayouts(data.recentPayouts), // New Widget
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: Consumer<DashboardProvider>(
        builder: (context, provider, child) {
          final bool canRequest = provider.dashboardData?.availableBalance != null &&
              provider.dashboardData!.availableBalance > 0;
          return _buildRequestPayoutButton(accentColor, canRequest);
        },
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        children: [
          Container(height: 180, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))),
          const SizedBox(height: 32),
          Row(
            children: List.generate(3, (_) => Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), height: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))))),
          ),
          const SizedBox(height: 32),
          Container(height: 240, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(BuddyDashboardData data) {
    const primaryColor = Color(0xFF19638D);
    final formatCurrency = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final localizations = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, const Color(0xFF2E86AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Positioned(right: -20, bottom: -20, child: Icon(Icons.waves, size: 120, color: Colors.white.withOpacity(0.1))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localizations.dashboardAvailableForPayout, style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.85), fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(formatCurrency.format(data.availableBalance), style: GoogleFonts.poppins(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text('Next payout on: Aug 10, 2025', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(BuddyDashboardData data) {
    final localizations = AppLocalizations.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _InfoCard(value: data.todaysBookingsCount.toString(), label: localizations.dashboardTodaysBookings, icon: Icons.calendar_today_outlined, color: Colors.blue.shade600),
        _InfoCard(value: data.completedBookingsCount.toString(), label: localizations.dashboardCompleted, icon: Icons.check_circle_outline, color: Colors.green.shade600),
        _InfoCard(value: data.ongoingBookingsCount.toString(), label: localizations.dashboardOngoing, icon: Icons.hourglass_top_outlined, color: Colors.orange.shade700),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF111827)));
  }

  Widget _buildEarningsSummary(BuddyDashboardData data) {
    const primaryColor = Color(0xFF19638D);
    final localizations = AppLocalizations.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: primaryColor, size: 32),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.dashboardThisMonthsEarnings, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
                  const SizedBox(height: 4),
                  Text(NumberFormat.currency(locale: 'en_US', symbol: '\$').format(data.monthlyEarnings), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
                  Text(localizations.dashboardIncludesBookingsTips, style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF10B981), fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // New Lifetime Earnings Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Icon(Icons.military_tech_outlined, color: Colors.green.shade700, size: 32),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.dashboardTotalLifetimeEarnings, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
                  const SizedBox(height: 4),
                  Text(NumberFormat.currency(locale: 'en_US', symbol: '\$').format(data.totalLifetimeEarnings), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
                  Text(localizations.dashboardIncludesBookingsTips, style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF10B981), fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildTipsBreakdown(),
      ],
    );
  }

  Widget _buildTipsBreakdown() {
    return Consumer<DashboardProvider>(
      builder: (context, provider, child) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _fetchTipsSummary(),
          builder: (context, snapshot) {
            final tipsData = snapshot.data ?? {};
            final totalTips = (tipsData['total_tips'] as num?)?.toDouble() ?? 0.0;
            final tipCount = tipsData['tip_count'] as int? ?? 0;
            final localizations = AppLocalizations.of(context);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.volunteer_activism,
                      color: Color(0xFF10B981),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.dashboardTipsReceived,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                        Text(
                          totalTips > 0
                              ? '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(totalTips)} from $tipCount ${tipCount == 1 ? 'client' : 'clients'}'
                              : localizations.dashboardNoTipsReceived,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: totalTips > 0 ? const Color(0xFF111827) : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchTipsSummary() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      print('[v0] Fetching tips for buddy_id: $userId');

      // First, check if any tips exist for this buddy at all
      final allTipsResponse = await supabase
          .from('tips')
          .select('*')
          .eq('buddy_id', userId);

      print('[v0] All tips for buddy: $allTipsResponse');

      // Then check specifically for completed tips
      final response = await supabase
          .from('tips')
          .select('amount, status, created_at')
          .eq('buddy_id', userId)
          .eq('status', 'completed');

      print('[v0] Completed tips response: $response');

      double totalTips = 0;
      int tipCount = 0;

      for (final tip in response) {
        totalTips += (tip['amount'] as num).toDouble();
        tipCount++;
      }

      print('[v0] Calculated tips - Total: $totalTips, Count: $tipCount');

      return {
        'total_tips': totalTips,
        'tip_count': tipCount,
        'average_tip': tipCount > 0 ? totalTips / tipCount : 0,
      };
    } catch (e) {
      print('[v0] Error fetching tips summary: $e');
      return {
        'total_tips': 0.0,
        'tip_count': 0,
        'average_tip': 0.0,
      };
    }
  }

  Widget _buildPayoutMethodCard(PayoutMethod? payoutMethod) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          if (payoutMethod?.isPayPal == true)
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
            const Icon(Icons.account_balance_outlined, color: Color(0xFF19638D), size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    payoutMethod?.displayName ?? 'No Payout Method',
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF111827))
                ),
                const SizedBox(height: 2),
                if (payoutMethod != null)
                  Text(
                      payoutMethod.displayDetails,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF6B7280),
                        letterSpacing: payoutMethod.isPayPal ? 0 : 1.5,
                      )
                  ),
                if (payoutMethod?.isPayPal == true) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        payoutMethod?.paypalVerified == true
                            ? Icons.verified
                            : Icons.warning_outlined,
                        size: 14,
                        color: payoutMethod?.paypalVerified == true
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        payoutMethod?.paypalVerified == true
                            ? 'Verified'
                            : 'Unverified',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: payoutMethod?.paypalVerified == true
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
          TextButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PayoutSettingsScreen()));
            },
            child: Text(payoutMethod != null ? 'Change' : 'Add', style: GoogleFonts.poppins(color: const Color(0xFFF15808), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // New widget to display the list of recent payouts
  Widget _buildRecentPayouts(List<Payout> payouts) {
    final localizations = AppLocalizations.of(context);

    if (payouts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Text(
            localizations.dashboardNoRecentPayouts,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: payouts.length,
        itemBuilder: (context, index) {
          final payout = payouts[index];
          return _PayoutListItem(payout: payout);
        },
        separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
      ),
    );
  }

  Widget _buildRequestPayoutButton(Color accentColor, bool canRequest) {
    final localizations = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      color: Colors.white,
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: canRequest ? _showRequestPayoutDialog : null,
            icon: const Icon(Icons.file_download_outlined, size: 22),
            label: Text(localizations.dashboardRequestPayout),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: accentColor.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

// New list item widget for a single payout
class _PayoutListItem extends StatelessWidget {
  final Payout payout;
  const _PayoutListItem({required this.payout});

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'pending':
        return Icons.hourglass_top_outlined;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final formatDate = DateFormat('MMM d, yyyy');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Icon(_getStatusIcon(payout.status), color: _getStatusColor(payout.status)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payout Request',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                Text(
                  formatDate.format(payout.requestedAt),
                  style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatCurrency.format(payout.amount),
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(payout.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  payout.status.toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: _getStatusColor(payout.status),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _InfoCard({required this.value, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(value, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
            const SizedBox(height: 2),
            Text(label, style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF6B7280), height: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _EarningsChart extends StatefulWidget {
  final List<WeeklyEarning> weeklyEarnings;
  const _EarningsChart({required this.weeklyEarnings});

  @override
  State<_EarningsChart> createState() => _EarningsChartState();
}

class _EarningsChartState extends State<_EarningsChart> with SingleTickerProviderStateMixin {
  int? _selectedIndex;
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap(BuildContext context, TapDownDetails details) {
    if (widget.weeklyEarnings.isEmpty) return;
    final box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(details.globalPosition);
    final chartWidth = box.size.width - 40;
    final barSlotWidth = chartWidth / widget.weeklyEarnings.length;
    final index = ((localPosition.dx - 40) / barSlotWidth).floor();

    if (index >= 0 && index < widget.weeklyEarnings.length) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => _onTap(context, details),
      onTapUp: (_) => setState(() => _selectedIndex = null),
      onHorizontalDragEnd: (_) => setState(() => _selectedIndex = null),
      onVerticalDragEnd: (_) => setState(() => _selectedIndex = null),
      child: Container(
        height: 240,
        padding: const EdgeInsets.only(top: 16, right: 16, bottom: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return CustomPaint(
              painter: _BarChartPainter(earningsData: widget.weeklyEarnings, selectedIndex: _selectedIndex, animationValue: _animation.value),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<WeeklyEarning> earningsData;
  final int? selectedIndex;
  final double animationValue;

  _BarChartPainter({required this.earningsData, this.selectedIndex, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (earningsData.isEmpty) return;
    const double leftPadding = 40.0;
    const double bottomPadding = 30.0;
    final double chartHeight = size.height - bottomPadding;
    final double chartWidth = size.width - leftPadding;
    final double barSlotWidth = chartWidth / earningsData.length;
    final double barWidth = barSlotWidth * 0.5;

    final maxEarning = earningsData.isNotEmpty ? earningsData.map((e) => e.earning).reduce(max) * 1.2 : 0;
    final scale = maxEarning > 0 ? chartHeight / maxEarning : 0;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1;
    const int gridLineCount = 5;
    for (int i = 0; i <= gridLineCount; i++) {
      final y = chartHeight - (chartHeight / gridLineCount * i);
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final labelValue = maxEarning > 0 ? maxEarning / gridLineCount * i : 0;
      final textPainter = TextPainter(
        text: TextSpan(text: '\$${labelValue.toInt()}', style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 10)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(leftPadding - textPainter.width - 8, y - textPainter.height / 2));
    }

    for (int i = 0; i < earningsData.length; i++) {
      final barHeight = earningsData[i].earning * scale * animationValue;
      final left = leftPadding + (i * barSlotWidth) + (barSlotWidth - barWidth) / 2;
      final top = chartHeight - barHeight;
      final right = left + barWidth;
      final bottom = chartHeight;
      final isSelected = i == selectedIndex;
      final barPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(left, top),
          Offset(left, bottom),
          isSelected ? [const Color(0xFFF15808), const Color(0xFFF9A825)] : [const Color(0xFF88BFE2), const Color(0xFF19638D)],
        );
      canvas.drawRRect(RRect.fromLTRBR(left, top, right, bottom, const Radius.circular(4)), barPaint);
      final textPainter = TextPainter(
        text: TextSpan(text: earningsData[i].day, style: GoogleFonts.poppins(color: isSelected ? const Color(0xFF111827) : Colors.grey.shade600, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(left + barWidth / 2 - textPainter.width / 2, size.height - 20));
    }

    if (selectedIndex != null && selectedIndex! < earningsData.length) {
      final value = NumberFormat.currency(locale: 'en_US', symbol: '\$').format(earningsData[selectedIndex!].earning);
      final tooltipTextPainter = TextPainter(
        text: TextSpan(text: value, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final tooltipWidth = tooltipTextPainter.width + 20;
      final tooltipHeight = tooltipTextPainter.height + 10;
      final barLeft = leftPadding + (selectedIndex! * barSlotWidth) + (barSlotWidth - barWidth) / 2;
      final barTop = chartHeight - (earningsData[selectedIndex!].earning * scale * animationValue);
      double tooltipX = barLeft + barWidth / 2 - tooltipWidth / 2;
      tooltipX = max(8, min(tooltipX, size.width - tooltipWidth - 8));
      final tooltipY = barTop - tooltipHeight - 8;
      final tooltipPath = Path()
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight), const Radius.circular(8)))
        ..moveTo(tooltipX + tooltipWidth / 2 - 6, tooltipY + tooltipHeight)
        ..lineTo(tooltipX + tooltipWidth / 2, tooltipY + tooltipHeight + 6)
        ..lineTo(tooltipX + tooltipWidth / 2 + 6, tooltipY + tooltipHeight)
        ..close();
      canvas.drawPath(tooltipPath, Paint()..color = const Color(0xFF1F2937));
      tooltipTextPainter.paint(canvas, Offset(tooltipX + 10, tooltipY + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex || oldDelegate.animationValue != animationValue || oldDelegate.earningsData != earningsData;
  }
}

// New Custom Bottom Sheet Widget
class _RequestPayoutSheet extends StatefulWidget {
  final double availableBalance;
  final PayoutMethod payoutMethod;
  final Future<void> Function(double amount) onRequest;

  const _RequestPayoutSheet({
    required this.availableBalance,
    required this.payoutMethod,
    required this.onRequest,
  });

  @override
  State<_RequestPayoutSheet> createState() => _RequestPayoutSheetState();
}

class _RequestPayoutSheetState extends State<_RequestPayoutSheet> {
  final TextEditingController _amountController = TextEditingController();
  bool _isLoading = false;
  bool _isButtonEnabled = false;
  double _amount = 0.0;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_validateInput);
  }

  @override
  void dispose() {
    _amountController.removeListener(_validateInput);
    _amountController.dispose();
    super.dispose();
  }

  void _validateInput() {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    setState(() {
      _amount = amount;
      _isButtonEnabled = amount > 0 && amount <= widget.availableBalance;
    });
  }

  void _onMaxPressed() {
    _amountController.text = widget.availableBalance.toStringAsFixed(2);
  }

  Future<void> _onConfirm() async {
    if (!_isButtonEnabled) return;

    setState(() => _isLoading = true);
    Navigator.of(context).pop(); // Close sheet immediately
    await widget.onRequest(_amount);
    // No need to set loading to false as the widget is disposed
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    const primaryColor = Color(0xFF19638D);
    const accentColor = Color(0xFFF15808);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF9FAFB),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Request Payout',
                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF111827)),
              ),
              const SizedBox(height: 8),
              Text(
                'Available for withdrawal: ${formatCurrency.format(widget.availableBalance)}',
                style: GoogleFonts.poppins(fontSize: 15, color: const Color(0xFF6B7280)),
              ),
              const SizedBox(height: 24),
              _buildAmountInput(accentColor),
              const SizedBox(height: 24),
              _buildPayoutDestination(),
              const SizedBox(height: 24),
              _buildSummary(),
              const SizedBox(height: 32),
              _buildConfirmButton(accentColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountInput(Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Amount', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
        const SizedBox(height: 8),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF111827)),
            hintText: '0.00',
            hintStyle: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accentColor, width: 2)),
            suffixIcon: TextButton(
              onPressed: _onMaxPressed,
              child: Text('Max', style: GoogleFonts.poppins(color: accentColor, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayoutDestination() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payout to', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              if (widget.payoutMethod.isPayPal)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Image.asset(
                    'assets/images/paypal_logo.png',
                    height: 20,
                  ),
                )
              else
                const Icon(Icons.account_balance_outlined, color: Color(0xFF19638D)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.payoutMethod.displayName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    Text(widget.payoutMethod.displayDetails, style: GoogleFonts.poppins(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final formatCurrency = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    const fee = 0.00; // Placeholder for future fee calculation
    final total = _amount - fee;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Amount Requested:', formatCurrency.format(_amount)),
          const SizedBox(height: 8),
          _buildSummaryRow('Processing Fee:', formatCurrency.format(fee)),
          const Divider(height: 24),
          _buildSummaryRow('You Will Receive:', formatCurrency.format(total), isTotal: true),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(color: isTotal ? const Color(0xFF111827) : const Color(0xFF6B7280), fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: GoogleFonts.poppins(color: const Color(0xFF111827), fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }

  Widget _buildConfirmButton(Color accentColor) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isButtonEnabled && !_isLoading ? _onConfirm : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accentColor.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        child: _isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : const Text('Confirm & Request'),
      ),
    );
  }
}
