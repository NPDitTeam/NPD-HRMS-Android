import 'package:flutter/material.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onItemTapped;
  final Color selectedItemColor;
  final bool isApprover; // สถานะว่าเป็นผู้อนุมัติหรือไม่
  final bool isConsultant; // Add this new parameter

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onItemTapped,
    required this.selectedItemColor,
    required this.isApprover,
    this.isConsultant = false, // Initialize with a default value
  });

  @override
  Widget build(BuildContext context) {
    List<BottomNavigationBarItem> navItems = [];

    if (isConsultant) {
      // If the user is a consultant, only show Home and Payslip, plus approver menus if they are also an approver
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.home_rounded),
          label: 'หน้าแรก',
        ),
      );
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.receipt_long_outlined),
          label: 'สลิปเงินเดือน',
        ),
      );
    } else {
      // Regular user: Show all standard menus
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.home_rounded),
          label: 'หน้าแรก',
        ),
      );
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.check_circle_rounded),
          label: 'ลงเวลา',
        ),
      );
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.calendar_month_rounded),
          label: 'การลา',
        ),
      );
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.add_alarm_rounded),
          label: 'เพิ่มเวลา',
        ),
      );
    }

    // If the user is an approver (and it applies to their current view)
    // The previous logic for adding approver items is preserved here
    if (isApprover) {
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.verified_user_rounded),
          label: 'อนุมัติลา', // เมนูสำหรับอนุมัติการลา
        ),
      );
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.watch_later_outlined),
          label: 'อนุมัติเวลา', // เมนูสำหรับอนุมัติเพิ่มเวลา
        ),
      );
    }

    // ✅ ใช้สีจาก Theme — เปลี่ยนตาม ThemeController อัตโนมัติ
    final scheme = Theme.of(context).colorScheme;
    final Color bgColor = scheme.primary;
    final Color onBg = scheme.onPrimary;

    return BottomNavigationBar(
      items: navItems,
      currentIndex: currentIndex,
      selectedItemColor: onBg, // ตัวอักษรบนพื้น primary
      unselectedItemColor: onBg.withOpacity(0.6),
      backgroundColor: bgColor,
      onTap: onItemTapped,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    );
  }
}
