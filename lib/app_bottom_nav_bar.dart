import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ui/app_theme.dart';

/// ปุ่มหนึ่งปุ่มบนแถบเมนูล่าง
class _NavItemData {
  const _NavItemData({
    required this.icon,
    required this.label,
    IconData? selectedIcon,
    this.badge = 0,
  }) : selectedIcon = selectedIcon ?? icon;

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
}

/// แถบเมนูล่าง — พื้นสีธีมไล่เฉด เว้าเป็นวงกลมตรงเมนูที่เปิดอยู่
///
/// ไอคอนของหน้าที่อยู่ลอยขึ้นมาในวงกลมสีขาว ส่วนชื่อเมนูยังอยู่ครบทุกปุ่ม
/// เพื่อให้คนที่ไม่คุ้นไอคอนยังอ่านออกว่าปุ่มไหนคืออะไร
///
/// ไม่เกิน 5 ปุ่มเสมอ: เดิมผู้อนุมัติมี 6 ปุ่ม (แยก "อนุมัติลา" กับ "อนุมัติเวลา")
/// ตัวหนังสือจึงเล็กและกดพลาดง่าย ตอนนี้รวมเป็นปุ่ม "อนุมัติ" แล้วแยกเป็นแท็บข้างใน
///
/// ลำดับปุ่มต้องตรงกับลำดับหน้าใน `_initializePages` ของ main.dart
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onItemTapped,
    required this.isApprover,
    this.isConsultant = false,
    this.pendingApprovals = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onItemTapped;
  final bool isApprover;
  final bool isConsultant;

  /// คำขอที่รออนุมัติทั้งหมด (ลา + เพิ่มเวลา) — แสดงเป็นตัวเลขบนปุ่ม "อนุมัติ"
  final int pendingApprovals;

  /// วงกลมของปุ่มที่เลือก
  static const double _bubble = 52;

  /// ขอบบนของแถบ วัดจากบนสุดของวิดเจ็ต — วงกลมโผล่พ้นแถบขึ้นไปเท่านี้
  static const double _barTop = 26;

  /// ความสูงส่วนเนื้อหา (ไม่รวมพื้นที่ปลอดภัยด้านล่างของเครื่อง)
  static const double _contentHeight = 78;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color onAccent = AppColors.onAccent(accent);

    final items = <_NavItemData>[
      const _NavItemData(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: 'หน้าแรก',
      ),
      if (isConsultant)
        const _NavItemData(
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          label: 'สลิปเงินเดือน',
        )
      else ...const [
        _NavItemData(icon: Icons.fingerprint_rounded, label: 'ลงเวลา'),
        _NavItemData(
          icon: Icons.event_note_outlined,
          selectedIcon: Icons.event_note_rounded,
          label: 'การลา',
        ),
        _NavItemData(
          icon: Icons.more_time_outlined,
          selectedIcon: Icons.more_time_rounded,
          label: 'เพิ่มเวลา',
        ),
      ],
      if (isApprover)
        _NavItemData(
          icon: Icons.fact_check_outlined,
          selectedIcon: Icons.fact_check_rounded,
          label: 'อนุมัติ',
          badge: pendingApprovals,
        ),
    ];

    final int index = currentIndex.clamp(0, items.length - 1);
    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return SizedBox(
      height: _contentHeight + bottomInset,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double itemWidth = constraints.maxWidth / items.length;

          // เลื่อนรอยเว้ากับวงกลมตามปุ่มที่กด แทนการกระโดดทันที
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: index.toDouble(), end: index.toDouble()),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, position, _) {
              final double centerX = itemWidth * (position + 0.5);

              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _barTop,
                    bottom: 0,
                    child: CustomPaint(
                      painter: _NotchedBarPainter(
                        centerX: centerX,
                        notchRadius: _bubble / 2 + 6,
                        accent: accent,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: _contentHeight,
                    child: Row(
                      children: [
                        for (int i = 0; i < items.length; i++)
                          Expanded(
                            child: _NavItem(
                              data: items[i],
                              selected: i == index,
                              onAccent: onAccent,
                              onTap: () => onItemTapped(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // วงกลมของปุ่มที่เลือก — กดทะลุไปที่ปุ่มข้างล่างได้
                  Positioned(
                    left: centerX - _bubble / 2,
                    top: 0,
                    child: IgnorePointer(
                      child: _SelectedBubble(
                        data: items[index],
                        accent: accent,
                        size: _bubble,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.selected,
    required this.onAccent,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final Color onAccent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color faded = onAccent.withValues(alpha: 0.75);
    final Widget icon = Icon(data.icon, size: 24, color: faded);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 30),
          SizedBox(
            height: 24,
            // ไอคอนของปุ่มที่เลือกไปอยู่ในวงกลมด้านบนแล้ว ตรงนี้จึงเว้นที่ไว้เฉย ๆ
            child: selected
                ? null
                : (data.badge > 0
                    ? Badge.count(
                        count: data.badge,
                        backgroundColor: AppColors.danger,
                        child: icon,
                      )
                    : icon),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSansThai(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? onAccent : faded,
            ),
          ),
        ],
      ),
    );
  }
}

/// วงกลมสีขาวที่ลอยอยู่ตรงรอยเว้าของแถบ
class _SelectedBubble extends StatelessWidget {
  const _SelectedBubble({
    required this.data,
    required this.accent,
    required this.size,
  });

  final _NavItemData data;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget icon = Icon(
      data.selectedIcon,
      key: ValueKey<IconData>(data.selectedIcon),
      size: 24,
      // วงกลมเป็นพื้นขาว ไอคอนจึงต้องเป็นสีเข้ม ไม่ใช่สีบนพื้นธีม
      color: AppColors.ink(accent),
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: data.badge > 0
              ? Badge.count(
                  count: data.badge,
                  backgroundColor: AppColors.danger,
                  child: icon,
                )
              : icon,
        ),
      ),
    );
  }
}

/// แถบพื้นสีธีมที่เว้าเป็นวงกลมตรงปุ่มที่เลือก
class _NotchedBarPainter extends CustomPainter {
  const _NotchedBarPainter({
    required this.centerX,
    required this.notchRadius,
    required this.accent,
  });

  final double centerX;
  final double notchRadius;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect host = Offset.zero & size;

    // ใช้ตัวคิดรูปทรงชุดเดียวกับ BottomAppBar ของ Flutter แล้วตัดด้วยสี่เหลี่ยม
    // มุมบนมน เพื่อให้ได้ทั้งรอยเว้าและมุมโค้งในรูปเดียว
    final Path notched = const CircularNotchedRectangle().getOuterPath(
      host,
      Rect.fromCircle(center: Offset(centerX, 0), radius: notchRadius),
    );
    final Path rounded = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          host,
          topLeft: const Radius.circular(24),
          topRight: const Radius.circular(24),
        ),
      );
    final Path shape = Path.combine(PathOperation.intersect, notched, rounded);

    canvas.drawShadow(shape, Colors.black.withValues(alpha: 0.3), 6, false);
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, AppColors.darken(accent)],
        ).createShader(host),
    );
  }

  @override
  bool shouldRepaint(_NotchedBarPainter old) =>
      old.centerX != centerX ||
      old.notchRadius != notchRadius ||
      old.accent != accent;
}
