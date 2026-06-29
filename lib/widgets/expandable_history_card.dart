import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// การ์ดประวัติการลา/เพิ่มเวลา แบบพับเก็บ/ขยายได้
/// Header แสดง: ไอคอน | วันที่ + ประเภท | สถานะ badge
/// Body (expanded): รายละเอียด + ปุ่มต่างๆ
class ExpandableHistoryCard extends StatefulWidget {
  final IconData leadingIcon;
  final Color accentColor; // สีหลักของการ์ด (สีสถานะ)
  final String dateLabel; // "18 เม.ย. 2569" หรือ "18-20 เม.ย. 2569"
  final String typeLabel; // "ลาป่วย", "ค่าเบี้ยเลี้ยง"
  final String status; // "รออนุมัติ", "อนุมัติ", "ไม่อนุมัติ", "ยกเลิก"
  final Color statusColor;
  final String? subtitle; // optional เช่น ชื่อคนขอ สำหรับหน้าอนุมัติ
  final Widget details; // เนื้อหาภายในเมื่อขยาย
  final bool initiallyExpanded;

  const ExpandableHistoryCard({
    super.key,
    required this.leadingIcon,
    required this.accentColor,
    required this.dateLabel,
    required this.typeLabel,
    required this.status,
    required this.statusColor,
    required this.details,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  @override
  State<ExpandableHistoryCard> createState() => _ExpandableHistoryCardState();
}

class _ExpandableHistoryCardState extends State<ExpandableHistoryCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _controller;
  late Animation<double> _arrowAnim;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _arrowAnim = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (_expanded) _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.accentColor.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — always visible
          InkWell(
            onTap: _toggle,
            splashColor: widget.accentColor.withOpacity(0.08),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.leadingIcon,
                        color: widget.accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  // Date + type
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.dateLabel,
                          style: GoogleFonts.ibmPlexSansThai(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.typeLabel,
                          style: GoogleFonts.ibmPlexSansThai(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: GoogleFonts.ibmPlexSansThai(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.statusColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.status,
                      style: GoogleFonts.ibmPlexSansThai(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  RotationTransition(
                    turns: _arrowAnim,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey.shade500,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Details — smooth expand/collapse
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: widget.details,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
