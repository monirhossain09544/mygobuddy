import 'package:flutter/material.dart';

class Booking {
  final String id;
  final String buddyId;
  final String clientId;
  final String buddyName;
  final String? buddyAvatarUrl;
  final String status;
  final DateTime date;
  final TimeOfDay time;
  final int duration;
  final double? amount;
  final String service;

  Booking({
    required this.id,
    required this.buddyId,
    required this.clientId,
    required this.buddyName,
    this.buddyAvatarUrl,
    required this.status,
    required this.date,
    required this.time,
    required this.duration,
    this.amount,
    required this.service,
  });

  factory Booking.fromMap(Map<String, dynamic> map) {
    final buddyProfile = map['profiles'] as Map<String, dynamic>?;
    final timeParts = (map['time'] as String).split(':');
    return Booking(
      id: map['id'],
      buddyId: map['buddy_id'],
      clientId: map['client_id'],
      buddyName: buddyProfile?['name'] ?? 'Unknown Buddy',
      buddyAvatarUrl: buddyProfile?['profile_picture'],
      status: map['status'],
      date: DateTime.parse(map['date']),
      time: TimeOfDay(
          hour: int.parse(timeParts[0]), minute: int.parse(timeParts[1])),
      duration: map['duration'],
      amount: (map['amount'] as num?)?.toDouble(),
      service: map['service'] ?? 'Service',
    );
  }
}
