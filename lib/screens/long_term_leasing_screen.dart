import 'package:flutter/material.dart';

class LongTermLeasingScreen extends StatelessWidget {
  const LongTermLeasingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Long-term leasing form can be connected once the backend fields are confirmed.',
              ),
            ),
          );
        },
        backgroundColor: const Color(0xFFB88910),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Lease',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF6E5), Color(0xFFFFFFFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF0DFC0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Color(0xFFFFE8B5),
                        child: Icon(
                          Icons.key_outlined,
                          color: Color(0xFFB88910),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Long Term Leasing',
                          style: TextStyle(
                            color: Color(0xFF16233B),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Manage long-term vehicle lease contracts, track active customers, monitor renewal dates, and keep contract billing visible in one place.',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: const [
                  _LeaseStatCard(
                    label: 'Active Leases',
                    value: '0',
                    icon: Icons.assignment_turned_in_outlined,
                    iconBg: Color(0xFFEAF7F0),
                    iconColor: Color(0xFF1F8F5F),
                  ),
                  SizedBox(width: 10),
                  _LeaseStatCard(
                    label: 'Expiring Soon',
                    value: '0',
                    icon: Icons.schedule_outlined,
                    iconBg: Color(0xFFFFF5E2),
                    iconColor: Color(0xFFB88910),
                  ),
                  SizedBox(width: 10),
                  _LeaseStatCard(
                    label: 'Vehicles on Lease',
                    value: '0',
                    icon: Icons.directions_car_outlined,
                    iconBg: Color(0xFFEFF6FF),
                    iconColor: Color(0xFF2563EB),
                  ),
                  SizedBox(width: 10),
                  _LeaseStatCard(
                    label: 'Overdue Billing',
                    value: '0',
                    icon: Icons.warning_amber_rounded,
                    iconBg: Color(0xFFFFF1F2),
                    iconColor: Color(0xFFE11D48),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE6EAF0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: const [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 54,
                    color: Color(0xFFCBD5E1),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No lease records yet',
                    style: TextStyle(
                      color: Color(0xFF16233B),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'This module has been added to navigation below Invoices. Once the lease fields or endpoint are confirmed, it can be expanded into a full create, renew, and billing workflow.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaseStatCard extends StatelessWidget {
  const _LeaseStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF16233B),
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
