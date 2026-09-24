import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

/// ตัวช่วยจัดการไฟล์แนบ (ใช้ร่วมกันในหน้าประวัติทั้งหมด)
///
/// หมายเหตุเรื่อง path ที่เก็บใน DB:
/// - ใบขอเพิ่มเวลา: เก็บเป็น 'uploads/manual_time_logs/xxx.jpg' อิงจากโฟลเดอร์ /api/
/// - ใบลา: เก็บเป็น 'uploads/xxx.jpg' หรือ '../uploads/xxx.jpg' อิงจาก root ของโดเมน
const String kAttachmentDomain = 'https://npdhrms.com/';

/// สีปุ่ม "ดูไฟล์แนบ" — ตายตัว ไม่ผูกกับธีมที่ผู้ใช้เลือก
/// เพราะปุ่มวางอยู่บนพื้นขาวของการ์ด ถ้าใช้สีจากธีมจะมองไม่เห็นเมื่อเปลี่ยนสีแอป
const Color kAttachmentButtonColor = Color(0xFF1A1A1A);

/// ตัด prefix แบบ relative (../ , ./ , / ) ออกให้เหลือ path สะอาด
String _cleanRelativePath(String filePath) {
  String cleaned = filePath.trim().replaceAll('\\', '/');
  while (cleaned.startsWith('../') || cleaned.startsWith('./')) {
    cleaned = cleaned.substring(cleaned.startsWith('../') ? 3 : 2);
  }
  if (cleaned.startsWith('/')) cleaned = cleaned.substring(1);
  return cleaned;
}

/// encode ทีละ segment — ชื่อไฟล์ภาษาไทย/มีเว้นวรรคจะได้ไม่ทำให้ URL พัง
String _encodePath(String path) =>
    path.split('/').map(Uri.encodeComponent).join('/');

/// URL ไฟล์แนบของใบขอเพิ่มเวลา → https://npdhrms.com/api/uploads/manual_time_logs/...
String buildAddTimeAttachmentUrl(String filePath) {
  if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
    return Uri.encodeFull(filePath);
  }
  String cleaned = _cleanRelativePath(filePath);
  if (cleaned.startsWith('api/')) cleaned = cleaned.substring(4);
  return '${kAttachmentDomain}api/${_encodePath(cleaned)}';
}

/// URL ไฟล์แนบของใบลา → https://npdhrms.com/uploads/...
String buildLeaveAttachmentUrl(String filePath) {
  if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
    return Uri.encodeFull(filePath);
  }
  String cleaned = _cleanRelativePath(filePath);
  if (cleaned.startsWith('uploads/')) cleaned = cleaned.substring('uploads/'.length);
  return '${kAttachmentDomain}uploads/${_encodePath(cleaned)}';
}

/// อ่านนามสกุลไฟล์แบบไม่สนตัวพิมพ์เล็ก/ใหญ่ (.JPG จากกล้องมือถือต้องใช้ได้)
String attachmentExtension(String filePath) {
  final String name = filePath.split('/').last.split('?').first;
  if (!name.contains('.')) return '';
  return name.split('.').last.toLowerCase();
}

bool isImageExtension(String ext) =>
    ext == 'jpg' ||
    ext == 'jpeg' ||
    ext == 'png' ||
    ext == 'gif' ||
    ext == 'webp';

/// เปิดไฟล์แนบ: รูปภาพ → popup ซูมได้ในแอป, ไฟล์อื่น (PDF) → เปิดด้วยแอปภายนอก
Future<void> openAttachmentUrl(
  BuildContext context,
  String url, {
  required String extension,
}) async {
  if (isImageExtension(extension)) {
    showAttachmentImageDialog(context, url);
    return;
  }

  try {
    final Uri uri = Uri.parse(url);
    bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    ok = ok || await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ไม่สามารถเปิดไฟล์แนบได้ (.$extension)',
            style: GoogleFonts.ibmPlexSansThai()),
        backgroundColor: Colors.red,
      ));
    }
  } catch (e) {
    debugPrint('❌ เปิดไฟล์แนบไม่สำเร็จ: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ไม่สามารถเปิดไฟล์แนบได้: $e',
            style: GoogleFonts.ibmPlexSansThai()),
        backgroundColor: Colors.red,
      ));
    }
  }
}

void showAttachmentImageDialog(BuildContext context, String imageUrl) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: PhotoView(
                imageProvider: NetworkImage(imageUrl),
                backgroundDecoration: const BoxDecoration(color: Colors.white),
                minScale: PhotoViewComputedScale.contained * 0.8,
                maxScale: PhotoViewComputedScale.covered * 2,
                loadingBuilder: (context, event) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('PhotoView Error: $error ($imageUrl)');
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 8),
                        Text('โหลดไฟล์แนบไม่สำเร็จ',
                            style:
                                GoogleFonts.ibmPlexSansThai(color: Colors.red)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// ปุ่ม "ดูไฟล์แนบ" มาตรฐาน — คืน SizedBox.shrink() ถ้าไม่มีไฟล์
Widget buildAttachmentButton({
  required BuildContext context,
  required String? filePath,
  required String Function(String) urlBuilder,
  Alignment alignment = Alignment.centerRight,
}) {
  if (filePath == null || filePath.trim().isEmpty) {
    return const SizedBox.shrink();
  }
  return Align(
    alignment: alignment,
    child: TextButton.icon(
      // ระบุสีตรงๆ ไม่พึ่ง theme — ปุ่มนี้อยู่บนพื้นขาวเสมอ
      // ถ้าปล่อยให้รับสีจากธีม เวลาผู้ใช้เปลี่ยนสีแอปจะกลายเป็นขาวบนขาว มองไม่เห็น
      style: TextButton.styleFrom(foregroundColor: kAttachmentButtonColor),
      onPressed: () => openAttachmentUrl(
        context,
        urlBuilder(filePath),
        extension: attachmentExtension(filePath),
      ),
      icon: const Icon(Icons.attach_file, size: 18),
      label: Text('ดูไฟล์แนบ', style: GoogleFonts.ibmPlexSansThai()),
    ),
  );
}
