import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// Enum to represent the type of transaction for icon purposes
enum TransactionType { sent, received }
// Enum to represent the status of the transaction for text/color purposes
enum TransactionStatus { successful, pending, refund }

class TransactionHistoryScreen extends StatelessWidget {
  const TransactionHistoryScreen({super.key});

  // Dummy data for the transaction history, updated to match the new design
  final List<Map<String, dynamic>> _transactions = const [
    {
      'bookingNumber': '12345',
      'buddyName': 'Leo',
      'date': '2025-07-12 11:58:16',
      'amount': 50.00,
      'type': TransactionType.sent,
      'status': TransactionStatus.successful,
    },
    {
      'bookingNumber': '12345',
      'buddyName': 'Ethan',
      'date': '2025-07-11 08:33:16',
      'amount': 120.00,
      'type': TransactionType.sent,
      'status': TransactionStatus.successful,
    },
    {
      'bookingNumber': '12345',
      'buddyName': 'Olivia',
      'date': '2025-07-11 06:13:16',
      'amount': 100.00,
      'type': TransactionType.received,
      'status': TransactionStatus.refund,
    },
    {
      'bookingNumber': '12345',
      'buddyName': 'Liam',
      'date': '2025-07-11 06:00:16',
      'amount': 130.00,
      'type': TransactionType.sent,
      'status': TransactionStatus.pending,
    },
  ];

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9FAFB);
    const Color primaryTextColor = Color(0xFF111827);

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
            'Transaction History',
            style: GoogleFonts.poppins(
              color: primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          itemCount: _transactions.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16), // Reduced space between cards
          itemBuilder: (context, index) {
            final transaction = _transactions[index];
            return _TransactionHistoryItem(
              bookingNumber: transaction['bookingNumber'],
              buddyName: transaction['buddyName'],
              date: DateTime.parse(transaction['date']),
              amount: transaction['amount'],
              type: transaction['type'],
              status: transaction['status'],
            );
          },
        ),
      ),
    );
  }
}

class _TransactionHistoryItem extends StatelessWidget {
  final String bookingNumber;
  final String buddyName;
  final DateTime date;
  final double amount;
  final TransactionType type;
  final TransactionStatus status;

  const _TransactionHistoryItem({
    required this.bookingNumber,
    required this.buddyName,
    required this.date,
    required this.amount,
    required this.type,
    required this.status,
  });

  // Returns icon and colors for the left-side avatar
  Map<String, dynamic> _getTypeInfo(TransactionType type) {
    switch (type) {
      case TransactionType.sent:
        return {
          'icon': Icons.arrow_upward,
          'color': const Color(0xFFF04438),
          'bgColor': const Color(0xFFFEF3F2),
        };
      case TransactionType.received:
        return {
          'icon': Icons.arrow_downward,
          'color': const Color(0xFF12B76A),
          'bgColor': const Color(0xFFECFDF3),
        };
    }
  }

  // Returns text and color for the status on the right
  Map<String, dynamic> _getStatusInfo(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.successful:
        return {
          'text': 'Successful',
          'color': const Color(0xFF027A48),
        };
      case TransactionStatus.refund:
        return {
          'text': 'Refund',
          'color': const Color(0xFF027A48),
        };
      case TransactionStatus.pending:
        return {
          'text': 'Pending',
          'color': const Color(0xFFF79009),
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeInfo = _getTypeInfo(type);
    final statusInfo = _getStatusInfo(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Reduced vertical padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.07),
            spreadRadius: 1,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: typeInfo['bgColor'],
            child: Icon(
              typeInfo['icon'],
              color: typeInfo['color'],
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Booking #$bookingNumber',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Buddy: $buddyName',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMMM dd, yyyy. hh:mm:ssa').format(date),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${amount.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusInfo['text'],
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: statusInfo['color'],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
