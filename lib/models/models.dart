import 'package:flutter/material.dart';

class Semester {
  String id;
  String name;
  DateTime startDate;
  int totalWeeks;

  Semester({required this.id, required this.name, required this.startDate, required this.totalWeeks});

  // JSON 序列化（用于 HomeWidget 等场景）
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startDate': startDate.toIso8601String(),
    'totalWeeks': totalWeeks,
  };

  factory Semester.fromJson(Map<String, dynamic> json) => Semester(
    id: json['id'],
    name: json['name'],
    startDate: DateTime.parse(json['startDate']),
    totalWeeks: json['totalWeeks'],
  );

  // SQLite 序列化
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'start_date': startDate.toIso8601String(),
    'total_weeks': totalWeeks,
  };

  factory Semester.fromMap(Map<String, dynamic> map) => Semester(
    id: map['id'] as String,
    name: map['name'] as String,
    startDate: DateTime.parse(map['start_date'] as String),
    totalWeeks: map['total_weeks'] as int,
  );
}

class TimeSlot {
  int slotIndex;
  String name;
  String startTime;
  String endTime;

  TimeSlot({required this.slotIndex, required this.name, required this.startTime, required this.endTime});

  Map<String, dynamic> toJson() => {
    'slotIndex': slotIndex,
    'name': name,
    'startTime': startTime,
    'endTime': endTime,
  };

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
    slotIndex: json['slotIndex'],
    name: json['name'],
    startTime: json['startTime'],
    endTime: json['endTime'],
  );

  // SQLite 序列化
  Map<String, dynamic> toMap() => {
    'slot_index': slotIndex,
    'name': name,
    'start_time': startTime,
    'end_time': endTime,
  };

  factory TimeSlot.fromMap(Map<String, dynamic> map) => TimeSlot(
    slotIndex: map['slot_index'] as int,
    name: map['name'] as String,
    startTime: map['start_time'] as String,
    endTime: map['end_time'] as String,
  );
}

class Course {
  String id;
  String semesterId;
  String name;
  String room;
  String teacher;
  Color color;
  int dayOfWeek;
  int startSlot;
  int endSlot;
  List<int> weeks;

  Course({
    required this.id, required this.semesterId, required this.name, required this.room,
    required this.teacher, required this.color, required this.dayOfWeek,
    required this.startSlot, required this.endSlot, required this.weeks,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'semesterId': semesterId,
    'name': name,
    'room': room,
    'teacher': teacher,
    'color': color.value,
    'dayOfWeek': dayOfWeek,
    'startSlot': startSlot,
    'endSlot': endSlot,
    'weeks': weeks,
  };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
    id: json['id'],
    semesterId: json['semesterId'],
    name: json['name'],
    room: json['room'],
    teacher: json['teacher'],
    color: Color(json['color']),
    dayOfWeek: json['dayOfWeek'],
    startSlot: json['startSlot'],
    endSlot: json['endSlot'],
    weeks: List<int>.from(json['weeks']),
  );

  // SQLite 序列化：weeks 存为逗号分隔字符串
  Map<String, dynamic> toMap() => {
    'id': id,
    'semester_id': semesterId,
    'name': name,
    'room': room,
    'teacher': teacher,
    'color': color.value,
    'day_of_week': dayOfWeek,
    'start_slot': startSlot,
    'end_slot': endSlot,
    'weeks': weeks.join(','),
  };

  factory Course.fromMap(Map<String, dynamic> map) => Course(
    id: map['id'] as String,
    semesterId: map['semester_id'] as String,
    name: map['name'] as String,
    room: map['room'] as String,
    teacher: map['teacher'] as String,
    color: Color(map['color'] as int),
    dayOfWeek: map['day_of_week'] as int,
    startSlot: map['start_slot'] as int,
    endSlot: map['end_slot'] as int,
    weeks: (map['weeks'] as String).isEmpty
        ? <int>[]
        : (map['weeks'] as String).split(',').map((e) => int.parse(e)).toList(),
  );
}
