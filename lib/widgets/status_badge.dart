import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (start, end, fg) = _colors(status.toLowerCase());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [start, end]),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.16), width: 0.8),
      ),
      child: Text(
        status,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  static (Color, Color, Color) _colors(String s) {
    switch (s) {
      case 'draft':
        return (
          const Color(0xFFF1F5F9),
          const Color(0xFFF8FAFC),
          const Color(0xFF475569),
        );
      case 'pending':
      case 'open':
        return (
          const Color(0xFFFFF1D6),
          const Color(0xFFFFFAEE),
          const Color(0xFF9A6A00),
        );
      case 'approved':
      case 'confirmed':
      case 'paid':
      case 'completed':
      case 'available':
        return (
          const Color(0xFFDDF6E9),
          const Color(0xFFEDFDF3),
          const Color(0xFF0F7B45),
        );
      case 'sent':
      case 'assigned':
      case 'quotation sent':
      case 'pi sent':
        return (
          const Color(0xFFE3F0FF),
          const Color(0xFFF1F7FF),
          const Color(0xFF2667B2),
        );
      case 'converted':
        return (
          const Color(0xFFEDE8FF),
          const Color(0xFFF6F3FF),
          const Color(0xFF6D4EC6),
        );
      case 'rejected':
      case 'cancelled':
      case 'canceled':
      case 'maintenance':
      case 'overdue':
        return (
          const Color(0xFFFFE3E5),
          const Color(0xFFFFF1F2),
          const Color(0xFFB42318),
        );
      case 'partial':
      case 'on lease':
        return (
          const Color(0xFFFFEAD5),
          const Color(0xFFFFF5EA),
          const Color(0xFFC26B00),
        );
      default:
        return (
          const Color(0xFFF1F5F9),
          const Color(0xFFF8FAFC),
          const Color(0xFF64748B),
        );
    }
  }
}
