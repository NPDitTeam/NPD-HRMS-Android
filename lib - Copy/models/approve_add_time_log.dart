import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Assuming User class is in main.dart or a shared model file
// import 'main.dart' show User; // If you need it here

class ApproveAddTimeLog {
  final int id;
  final int userId;
  final String? username;
  final String? requesterFirstname; // Added for requester's name
  final String? requesterLastname; // Added for requester's name
  final DateTime workDate;
  final TimeOfDay checkinTime;
  final TimeOfDay checkoutTime;
  final String department;
  final String position;
  final String state;
  final DateTime? createdAt;
  final String? reason;
  final String? userNote; // <<< เพิ่มส่วนนี้
  final DateTime? approvedAt;
  final int? approvedBy;
  final String? approverFirstname;
  final String? approverLastname;
  final String? reasonType;
  final String? filePath;

  ApproveAddTimeLog({
    required this.id,
    required this.userId,
    this.username,
    this.requesterFirstname,
    this.requesterLastname,
    required this.workDate,
    required this.checkinTime,
    required this.checkoutTime,
    required this.department,
    required this.position,
    required this.state,
    this.createdAt,
    this.reason,
    this.userNote, // <<< เพิ่มใน constructor ด้วย
    this.approvedAt,
    this.approvedBy,
    this.approverFirstname,
    this.approverLastname,
    this.reasonType,
    this.filePath,
  });

  factory ApproveAddTimeLog.fromJson(Map<String, dynamic> json) {
    TimeOfDay parseTime(String timeStr) {
      final format = DateFormat('HH:mm');
      return TimeOfDay.fromDateTime(format.parse(timeStr));
    }

    return ApproveAddTimeLog(
      id: int.parse(json['id'].toString()),
      userId: int.parse(json['user_id'].toString()),
      username: json['username'],
      requesterFirstname: json['requester_firstname'] == 'NULL' ||
              json['requester_firstname'] == null
          ? null
          : json['requester_firstname'],
      requesterLastname: json['requester_lastname'] == 'NULL' ||
              json['requester_lastname'] == null
          ? null
          : json['requester_lastname'],
      workDate: DateTime.parse(json['work_date']),
      checkinTime: parseTime(json['checkin_time']),
      checkoutTime: parseTime(json['checkout_time']),
      department: json['department'] ?? '', // Assume not null, or make nullable
      position: json['position'] ?? '', // Assume not null, or make nullable
      state: json['state'],
      createdAt: json['created_at'] != null &&
              json['created_at'] != '0000-00-00 00:00:00'
          ? DateTime.parse(json['created_at'])
          : null,
      reason: json['reason'] == 'NULL' || json['reason'] == null
          ? null
          : json['reason'],

      reasonType: json['reason_type'] == 'NULL' || json['reason_type'] == null
          ? null
          : json['reason_type'],

      userNote: json['user_note'] == 'NULL' ||
              json['user_note'] == null // <<< เพิ่มการ mapping จาก JSON
          ? null
          : json['user_note'],
      approvedAt: json['approved_at'] != null &&
              json['approved_at'] != '0000-00-00 00:00:00'
          ? DateTime.parse(json['approved_at'])
          : null,
      approvedBy: json['approved_by'] != null
          ? int.parse(json['approved_by'].toString())
          : null,
      approverFirstname: json['approver_firstname'] == 'NULL' ||
              json['approver_firstname'] == null
          ? null
          : json['approver_firstname'],
      approverLastname: json['approver_lastname'] == 'NULL' ||
              json['approver_lastname'] == null
          ? null
          : json['approver_lastname'],
      filePath: json['file_path'] == 'NULL' || json['file_path'] == null
          ? null
          : json['file_path'],
    );
  }

  Map<String, dynamic> toJson() {
    String formatTimeOfDay(TimeOfDay tod) {
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
      final format = DateFormat.Hm();
      return format.format(dt);
    }

    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'requester_firstname': requesterFirstname,
      'requester_lastname': requesterLastname,
      'work_date': DateFormat('yyyy-MM-dd').format(workDate),
      'checkin_time': formatTimeOfDay(checkinTime),
      'checkout_time': formatTimeOfDay(checkoutTime),
      'department': department,
      'position': position,
      'state': state,
      'created_at': createdAt?.toIso8601String(),
      'reason': reason,
      'user_note': userNote, // <<< เพิ่มการแปลง JSON
      'reason_type': reasonType,
      'approved_at': approvedAt?.toIso8601String(),
      'approved_by': approvedBy,
      'approver_firstname': approverFirstname,
      'approver_lastname': approverLastname,
      'file_path': filePath,
    };
  }
}
