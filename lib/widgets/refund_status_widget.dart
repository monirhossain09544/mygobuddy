import 'package:flutter/material.dart';
import '../utils/constants.dart';

class RefundStatusWidget extends StatefulWidget {
  final String? refundStatus;
  final double? refundAmount;
  final DateTime? refundInitiatedAt;
  final DateTime? refundCompletedAt;
  final String? errorMessage;

  const RefundStatusWidget({
    Key? key,
    this.refundStatus,
    this.refundAmount,
    this.refundInitiatedAt,
    this.refundCompletedAt,
    this.errorMessage,
  }) : super(key: key);

  @override
  State<RefundStatusWidget> createState() => _RefundStatusWidgetState();
}

class _RefundStatusWidgetState extends State<RefundStatusWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    // Start animations based on status
    if (widget.refundStatus == 'processing') {
      _pulseController.repeat(reverse: true);
    }

    _slideController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RefundStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update animations when status changes
    if (oldWidget.refundStatus != widget.refundStatus) {
      if (widget.refundStatus == 'processing') {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  Color _getStatusColor() {
    switch (widget.refundStatus) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return primaryColor;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return secondaryTextColor;
    }
  }

  IconData _getStatusIcon() {
    switch (widget.refundStatus) {
      case 'pending':
        return Icons.schedule;
      case 'processing':
        return Icons.sync;
      case 'completed':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  String _getStatusText() {
    switch (widget.refundStatus) {
      case 'pending':
        return 'Refund Initiated';
      case 'processing':
        return 'Processing Refund...';
      case 'completed':
        return 'Refund Completed';
      case 'failed':
        return 'Refund Failed';
      default:
        return 'No Refund Status';
    }
  }

  String _getStatusDescription() {
    switch (widget.refundStatus) {
      case 'pending':
        return 'Your refund request has been received and is being prepared.';
      case 'processing':
        return 'We are processing your refund. This may take a few moments.';
      case 'completed':
        return widget.refundAmount != null
            ? 'Refund of \$${widget.refundAmount!.toStringAsFixed(2)} has been processed successfully. It will appear in your account within 3-5 business days.'
            : 'Your refund has been processed successfully.';
      case 'failed':
        return widget.errorMessage ?? 'There was an issue processing your refund. Please contact support.';
      default:
        return '';
    }
  }

  Widget _buildStatusIcon() {
    final icon = _getStatusIcon();
    final color = _getStatusColor();

    if (widget.refundStatus == 'processing') {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
          );
        },
      );
    }

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(
        icon,
        color: color,
        size: 28,
      ),
    );
  }

  Widget _buildProgressBar() {
    if (widget.refundStatus != 'processing') return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          LinearProgressIndicator(
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we process your refund...',
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimestamp() {
    DateTime? timestamp;
    String label = '';

    switch (widget.refundStatus) {
      case 'pending':
      case 'processing':
        timestamp = widget.refundInitiatedAt;
        label = 'Initiated: ';
        break;
      case 'completed':
      case 'failed':
        timestamp = widget.refundCompletedAt ?? widget.refundInitiatedAt;
        label = widget.refundStatus == 'completed' ? 'Completed: ' : 'Failed: ';
        break;
    }

    if (timestamp == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '$label${_formatTimestamp(timestamp)}',
        style: TextStyle(
          color: secondaryTextColor,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hours ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year} at ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.refundStatus == null) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: _getStatusColor().withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getStatusText(),
                        style: TextStyle(
                          color: primaryTextColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStatusDescription(),
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      _buildTimestamp(),
                    ],
                  ),
                ),
              ],
            ),
            _buildProgressBar(),
          ],
        ),
      ),
    );
  }
}
