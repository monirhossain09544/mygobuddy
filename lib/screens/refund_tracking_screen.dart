import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/constants.dart';
import '../utils/localizations.dart';

class RefundTrackingScreen extends StatefulWidget {
  final String bookingId;
  final String refundAmount;

  const RefundTrackingScreen({
    Key? key,
    required this.bookingId,
    required this.refundAmount,
  }) : super(key: key);

  @override
  State<RefundTrackingScreen> createState() => _RefundTrackingScreenState();
}

class _RefundTrackingScreenState extends State<RefundTrackingScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? refundData;
  List<Map<String, dynamic>>? allRefunds;
  bool isLoading = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fetchRefundData();
    _setupRealTimeUpdates();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchRefundData() async {
    try {
      if (widget.bookingId == 'all') {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId == null) {
          setState(() {
            isLoading = false;
          });
          return;
        }

        final response = await Supabase.instance.client
            .from('bookings')
            .select('*')
            .eq('client_id', userId)
            .eq('status', 'cancelled')
            .order('cancelled_at', ascending: false);

        setState(() {
          allRefunds = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
      } else {
        final response = await Supabase.instance.client
            .from('bookings')
            .select('*')
            .eq('id', widget.bookingId)
            .single();

        setState(() {
          refundData = response;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _setupRealTimeUpdates() {
    if (widget.bookingId == 'all') {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      Supabase.instance.client
          .from('bookings')
          .stream(primaryKey: ['id']).listen((data) {
        final filteredData = data.where((booking) =>
        booking['client_id'] == userId &&
            booking['status'] == 'cancelled'
        ).toList();

        if (mounted) {
          setState(() {
            allRefunds = List<Map<String, dynamic>>.from(filteredData);
          });
        }
      });
    } else {
      Supabase.instance.client
          .from('bookings')
          .stream(primaryKey: ['id']).listen((data) {
        final filteredData = data.where((booking) =>
        booking['id'] == widget.bookingId
        ).toList();

        if (filteredData.isNotEmpty && mounted) {
          setState(() {
            refundData = filteredData.first;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: primaryTextColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.bookingId == 'all' ? 'All Refunds' : 'Refund Status',
          style: const TextStyle(
            color: primaryTextColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : widget.bookingId == 'all'
          ? _buildAllRefundsView()
          : refundData == null
          ? _buildErrorState()
          : _buildRefundTrackingContent(),
    );
  }

  Widget _buildAllRefundsView() {
    if (allRefunds == null || allRefunds!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No refunds found',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You haven\'t cancelled any bookings yet',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: allRefunds!.length,
      itemBuilder: (context, index) {
        final refund = allRefunds![index];
        return _buildRefundListItem(refund);
      },
    );
  }

  Widget _buildRefundListItem(Map<String, dynamic> refund) {
    final refundStatus = refund['refund_status'] ?? 'pending';
    final refundAmount = refund['refund_amount']?.toString() ?? refund['amount']?.toString() ?? '0.00';
    final service = refund['service'] ?? 'Unknown Service';
    final cancelledAt = refund['cancelled_at'];

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (refundStatus.toLowerCase()) {
      case 'processing':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Processing';
        break;
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Completed';
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = 'Failed';
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
        statusText = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RefundTrackingScreen(
                bookingId: refund['id'],
                refundAmount: refundAmount,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cancelled ${_formatDateTime(cancelledAt ?? '')}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$$refundAmount',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(
                  'Tap to view details',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Unable to load refund information',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchRefundData,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundTrackingContent() {
    final refundStatus = refundData!['refund_status'] ?? 'pending';
    final refundAmount = refundData!['refund_amount']?.toString() ?? widget.refundAmount;
    final cancelledAt = refundData!['cancelled_at'];
    final refundInitiatedAt = refundData!['refund_initiated_at'];
    final refundCompletedAt = refundData!['refund_completed_at'];
    final refundTransactionId = refundData!['refund_transaction_id'];
    final refundErrorMessage = refundData!['refund_error_message'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRefundStatusCard(refundStatus, refundAmount),
          const SizedBox(height: 24),
          _buildProgressTimeline(refundStatus, cancelledAt, refundInitiatedAt, refundCompletedAt),
          const SizedBox(height: 24),
          _buildRefundDetails(refundAmount, refundTransactionId, refundErrorMessage),
          const SizedBox(height: 24),
          _buildExpectedTimeframe(refundStatus),
        ],
      ),
    );
  }

  Widget _buildRefundStatusCard(String status, String amount) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    Widget? statusWidget;

    switch (status.toLowerCase()) {
      case 'processing':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Processing Refund';
        statusWidget = AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Icon(statusIcon, color: statusColor, size: 32),
            );
          },
        );
        break;
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Refund Completed';
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = 'Refund Failed';
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
        statusText = 'Refund Pending';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          statusWidget ?? Icon(statusIcon, color: statusColor, size: 48),
          const SizedBox(height: 16),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '\$$amount',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Refund Amount',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressTimeline(String status, String? cancelledAt,
      String? refundInitiatedAt, String? refundCompletedAt) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Refund Timeline',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 20),
          _buildTimelineItem(
            'Booking Cancelled',
            cancelledAt != null ? _formatDateTime(cancelledAt) : 'Unknown',
            Icons.cancel,
            Colors.red,
            isCompleted: true,
          ),
          _buildTimelineItem(
            'Refund Initiated',
            refundInitiatedAt != null ? _formatDateTime(refundInitiatedAt) : 'Pending',
            Icons.play_arrow,
            Colors.blue,
            isCompleted: refundInitiatedAt != null,
            isActive: status == 'processing' && refundInitiatedAt != null,
          ),
          _buildTimelineItem(
            'Refund Completed',
            refundCompletedAt != null ? _formatDateTime(refundCompletedAt) : 'Pending',
            Icons.check_circle,
            Colors.green,
            isCompleted: refundCompletedAt != null,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(String title, String time, IconData icon, Color color,
      {bool isCompleted = false, bool isActive = false, bool isLast = false}) {
    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isCompleted ? color : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isCompleted ? Colors.white : Colors.grey[500],
                size: 18,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isCompleted ? color.withOpacity(0.3) : Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isCompleted ? primaryTextColor : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'In Progress',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRefundDetails(String amount, String? transactionId, String? errorMessage) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Refund Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Amount', '\$$amount'),
          if (transactionId != null) ...[
            const SizedBox(height: 12),
            _buildDetailRow('Transaction ID', transactionId),
          ],
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            _buildDetailRow('Error', errorMessage, isError: true),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isError = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: isError ? Colors.red : primaryTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpectedTimeframe(String status) {
    String timeframe;
    String description;
    Color color;

    switch (status.toLowerCase()) {
      case 'processing':
        timeframe = '1-3 business days';
        description = 'Your refund is being processed and should appear in your account soon.';
        color = Colors.orange;
        break;
      case 'completed':
        timeframe = 'Completed';
        description = 'Your refund has been successfully processed and should appear in your account.';
        color = Colors.green;
        break;
      case 'failed':
        timeframe = 'Failed';
        description = 'There was an issue processing your refund. Please contact support for assistance.';
        color = Colors.red;
        break;
      default:
        timeframe = '3-5 business days';
        description = 'Once initiated, refunds typically take 3-5 business days to appear in your account.';
        color = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                'Expected Timeframe',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            timeframe,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes} minutes ago';
        }
        return '${difference.inHours} hours ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return dateTimeString;
    }
  }
}
