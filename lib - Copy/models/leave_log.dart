import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LeaveLog {
  final int id;
  final int userId;
  final String?
      username; // Made nullable to avoid 'Null is not a subtype of String' error
  final DateTime leaveStartDate;
  final TimeOfDay leaveStartTime;
  final DateTime leaveEndDate;
  final TimeOfDay leaveEndTime;
  final String leaveType;
  final String? note;
  final String? filePath;
  final String state;
  final String? reason;
  final int? approvedBy;
  final String? approverFirstname;
  final String? approverLastname;
  final DateTime? approvedAt;
  final DateTime? createdAt;
  final String? department;
  final String? position;

  // These fields are for the requestor's first and last name, as returned by the API
  final String? requesterFirstname;
  final String? requesterLastname;

  LeaveLog({
    required this.id,
    required this.userId,
    this.username, // Removed 'required' as it's now nullable
    required this.leaveStartDate,
    required this.leaveStartTime,
    required this.leaveEndDate,
    required this.leaveEndTime,
    required this.leaveType,
    this.note,
    this.filePath,
    required this.state,
    this.reason,
    this.approvedBy,
    this.approverFirstname,
    this.approverLastname,
    this.approvedAt,
    this.createdAt,
    this.department,
    this.position,
    this.requesterFirstname,
    this.requesterLastname,
  });

  factory LeaveLog.fromJson(Map<String, dynamic> json) {
    TimeOfDay parseTime(String timeStr) {
      final format = DateFormat('HH:mm');
      return TimeOfDay.fromDateTime(format.parse(timeStr));
    }

    return LeaveLog(
      id: int.parse(json['id'].toString()),
      userId: int.parse(json['user_id'].toString()),
      username: json['username'], // Now accepts null
      leaveStartDate: DateTime.parse(json['leave_start_date']),
      leaveStartTime: parseTime(json['leave_statr_time']),
      leaveEndDate: DateTime.parse(json['leave_end_date']),
      leaveEndTime: parseTime(json['leave_end_time']),
      leaveType: json['leave_type'],
      note:
          json['note'] == 'NULL' || json['note'] == null ? null : json['note'],
      filePath: json['file_path'] == 'NULL' || json['file_path'] == null
          ? null
          : json['file_path'],
      state: json['state'],
      reason: json['reason'] == 'NULL' || json['reason'] == null
          ? null
          : json['reason'],
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
      approvedAt: json['approved_at'] != null &&
              json['approved_at'] != '0000-00-00 00:00:00'
          ? DateTime.parse(json['approved_at'])
          : null,
      createdAt: json['created_at'] != null &&
              json['created_at'] != '0000-00-00 00:00:00'
          ? DateTime.parse(json['created_at'])
          : null,
      department: json['department'] == 'NULL' || json['department'] == null
          ? null
          : json['department'],
      position: json['position'] == 'NULL' || json['position'] == null
          ? null
          : json['position'],
      requesterFirstname:
          json['firstname'] == 'NULL' || json['firstname'] == null
              ? null
              : json['firstname'],
      requesterLastname: json['lastname'] == 'NULL' || json['lastname'] == null
          ? null
          : json['lastname'],
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
      'leave_start_date': DateFormat('yyyy-MM-dd').format(leaveStartDate),
      'leave_statr_time': formatTimeOfDay(leaveStartTime),
      'leave_end_date': DateFormat('yyyy-MM-dd').format(leaveEndDate),
      'leave_end_time': formatTimeOfDay(leaveEndTime),
      'leave_type': leaveType,
      'note': note,
      'file_path': filePath,
      'state': state,
      'reason': reason,
      'approved_by': approvedBy,
      'approver_firstname': approverFirstname,
      'approver_lastname': approverLastname,
      'approved_at': approvedAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'department': department,
      'position': position,
      'firstname': requesterFirstname,
      'lastname': requesterLastname,
    };
  }
}
