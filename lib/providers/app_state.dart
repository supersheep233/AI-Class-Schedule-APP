import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:home_widget/home_widget.dart';

import '../models/models.dart';
import '../services/database_helper.dart';

class AppState extends ChangeNotifier {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;

  AppState._internal() {
    _initDefaultData();
  }

  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool showNonThisWeekCourses = false;
  String aiServerUrl = 'http://127.0.0.1:8000/api/parse_schedule';

  List<Semester> semesters = [];
  Semester? currentSemester;
  int currentWeek = 1;

  int lunchBreakAfterSlot = 4;
  int dinnerBreakAfterSlot = 8;
  bool showLunchBreak = true;
  bool showDinnerBreak = true;

  List<Course> allCourses = [];
  List<TimeSlot> timeSlots = [];

  final List<Color> courseColors = [
    Colors.red.shade400,
    Colors.pink.shade400,
    Colors.purple.shade400,
    Colors.deepPurple.shade400,
    Colors.indigo.shade400,
    Colors.blue.shade400,
    Colors.lightBlue.shade500,
    Colors.cyan.shade600,
    Colors.teal.shade500,
    Colors.green.shade500,
    Colors.lightGreen.shade600,
    Colors.lime.shade700,
    Colors.amber.shade600,
    Colors.orange.shade500,
    Colors.deepOrange.shade400,
    Colors.brown.shade400,
  ];

  bool isDataLoaded = false;
  bool _isLoadingData = false;

  List<TimeSlot> _buildDefaultTimeSlots() {
    return List.generate(12, (index) {
      final s = index + 1;
      return TimeSlot(
        slotIndex: s,
        name: '第$s节',
        startTime: '${8 + index}:00',
        endTime: '${8 + index}:45',
      );
    });
  }

  int _calculateWeekForSemester(Semester semester, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final start = DateTime(
      semester.startDate.year,
      semester.startDate.month,
      semester.startDate.day,
    );

    int week = (today.difference(start).inDays ~/ 7) + 1;
    if (week < 1) week = 1;
    if (week > semester.totalWeeks) week = semester.totalWeeks;
    return week;
  }

  void _recalculateCurrentWeek() {
    if (currentSemester == null) {
      currentWeek = 1;
      return;
    }
    currentWeek = _calculateWeekForSemester(currentSemester!);
  }

  void _initDefaultData() {
    semesters.clear();
    allCourses.clear();
    timeSlots.clear();

    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));

    final defaultSemester = Semester(
      id: 'sem_1',
      name: '示例课表',
      startDate: DateTime(monday.year, monday.month, monday.day),
      totalWeeks: 20,
    );

    semesters.add(defaultSemester);
    currentSemester = defaultSemester;
    currentWeek = 1;

    timeSlots = _buildDefaultTimeSlots();

    final standardWeeks = List.generate(16, (i) => i + 1);

    allCourses.addAll([
      Course(
        id: 'c1',
        semesterId: 'sem_1',
        name: '高等数学',
        room: '101 教室',
        teacher: '张三',
        color: courseColors[9],
        dayOfWeek: 1,
        startSlot: 1,
        endSlot: 2,
        weeks: standardWeeks,
      ),
      Course(
        id: 'c2',
        semesterId: 'sem_1',
        name: '大学物理',
        room: '201 实验室',
        teacher: '李四',
        color: courseColors[5],
        dayOfWeek: 2,
        startSlot: 3,
        endSlot: 4,
        weeks: standardWeeks,
      ),
      Course(
        id: 'c3',
        semesterId: 'sem_1',
        name: '大学英语',
        room: '301 语音室',
        teacher: '王五',
        color: courseColors[13],
        dayOfWeek: 3,
        startSlot: 1,
        endSlot: 2,
        weeks: standardWeeks,
      ),
      Course(
        id: 'c4',
        semesterId: 'sem_1',
        name: 'C语言程序设计',
        room: '401 机房',
        teacher: '赵六',
        color: courseColors[2],
        dayOfWeek: 4,
        startSlot: 5,
        endSlot: 6,
        weeks: standardWeeks,
      ),
      Course(
        id: 'c5',
        semesterId: 'sem_1',
        name: '马克思主义基本原理',
        room: '阶梯教室 102',
        teacher: '孙七',
        color: courseColors[14],
        dayOfWeek: 5,
        startSlot: 3,
        endSlot: 4,
        weeks: standardWeeks,
      ),
      Course(
        id: 'c6',
        semesterId: 'sem_1',
        name: '嵌入式系统基础',
        room: '单片机实验室 501',
        teacher: '周八',
        color: courseColors[7],
        dayOfWeek: 2,
        startSlot: 7,
        endSlot: 8,
        weeks: List.generate(12, (i) => i + 1),
      ),
    ]);
  }

  List<Course> getCurrentWeekCourses() {
    if (currentSemester == null) return [];
    return allCourses
        .where((c) =>
            c.semesterId == currentSemester!.id && c.weeks.contains(currentWeek))
        .toList();
  }

  List<Course> getSemesterCourses() {
    if (currentSemester == null) return [];
    return allCourses.where((c) => c.semesterId == currentSemester!.id).toList();
  }

  Future<void> toggleShowNonThisWeekCourses(bool val) async {
    showNonThisWeekCourses = val;
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> setAiServerUrl(String url) async {
    aiServerUrl = url.trim().isEmpty
        ? 'http://127.0.0.1:8000/api/parse_schedule'
        : url.trim();
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> syncWidgetData() async {
    if (currentSemester == null) return;

    await HomeWidget.saveWidgetData(
      'semester_start_date',
      currentSemester!.startDate.toIso8601String(),
    );
    await HomeWidget.saveWidgetData(
      'semester_total_weeks',
      currentSemester!.totalWeeks,
    );

    final semCourses =
        allCourses.where((c) => c.semesterId == currentSemester!.id).toList();

    final jsonStr = jsonEncode(semCourses.map((c) {
      final sTime = timeSlots
          .firstWhere(
            (ts) => ts.slotIndex == c.startSlot,
            orElse: () => TimeSlot(
              slotIndex: 0,
              name: '',
              startTime: '00:00',
              endTime: '00:00',
            ),
          )
          .startTime;

      final eTime = timeSlots
          .firstWhere(
            (ts) => ts.slotIndex == c.endSlot,
            orElse: () => TimeSlot(
              slotIndex: 0,
              name: '',
              startTime: '23:59',
              endTime: '23:59',
            ),
          )
          .endTime;

      return {
        'name': c.name,
        'room': c.room,
        'teacher': c.teacher,
        'dayOfWeek': c.dayOfWeek,
        'weeks': c.weeks,
        'startSlot': c.startSlot,
        'endSlot': c.endSlot,
        'startTime': sTime,
        'endTime': eTime,
      };
    }).toList());

    await HomeWidget.saveWidgetData('all_courses', jsonStr);
    await HomeWidget.updateWidget(androidName: 'CourseWidgetProvider');
  }

  Future<void> _syncWidgetIfReady() async {
    if (isDataLoaded && !_isLoadingData) {
      await syncWidgetData();
    }
  }

  Future<void> setCurrentWeek(int week) async {
    if (currentSemester != null) {
      if (week < 1) week = 1;
      if (week > currentSemester!.totalWeeks) week = currentSemester!.totalWeeks;
    }

    currentWeek = week;
    if (!isDataLoaded || _isLoadingData) {
      notifyListeners();
      return;
    }

    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> setBreaks(int lunch, int dinner) async {
    lunchBreakAfterSlot = lunch;
    dinnerBreakAfterSlot = dinner;
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> toggleLunchBreak(bool val) async {
    showLunchBreak = val;
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> toggleDinnerBreak(bool val) async {
    showDinnerBreak = val;
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> setTotalSlots(int count) async {
    if (count < 4) count = 4;
    if (count > 16) count = 16;
    if (count == timeSlots.length) return;

    if (count > timeSlots.length) {
      for (int i = timeSlots.length; i < count; i++) {
        final s = i + 1;
        timeSlots.add(TimeSlot(
          slotIndex: s,
          name: '第$s节',
          startTime: '${8 + i}:00',
          endTime: '${8 + i}:45',
        ));
      }
    } else {
      timeSlots = timeSlots.sublist(0, count);
    }

    if (lunchBreakAfterSlot >= count) lunchBreakAfterSlot = count - 1;
    if (dinnerBreakAfterSlot >= count) dinnerBreakAfterSlot = count - 1;

    await _saveTimeSlotsToDb();
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> switchSemester(Semester semester) async {
    currentSemester = semester;
    _recalculateCurrentWeek();
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> addSemester(Semester semester) async {
    semesters.add(semester);
    await _dbHelper.insertSemester(semester);
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> updateSemester(Semester semester) async {
    final idx = semesters.indexWhere((s) => s.id == semester.id);
    if (idx != -1) {
      semesters[idx] = semester;
      if (currentSemester?.id == semester.id) {
        currentSemester = semester;
        _recalculateCurrentWeek();
      }
      await _dbHelper.updateSemester(semester);
      await _saveSettingsToDb();
      notifyListeners();
    }
  }

  Future<void> deleteSemester(String semesterId) async {
    semesters.removeWhere((s) => s.id == semesterId);
    allCourses.removeWhere((c) => c.semesterId == semesterId);

    if (currentSemester?.id == semesterId) {
      currentSemester = semesters.isNotEmpty ? semesters.first : null;
      _recalculateCurrentWeek();
    }

    await _dbHelper.deleteSemester(semesterId);
    await _saveSettingsToDb();
    notifyListeners();
  }

  Future<void> addCourse(Course course) async {
    allCourses.add(course);
    await _dbHelper.insertCourse(course);
    await _syncWidgetIfReady();
    notifyListeners();
  }

  Future<void> addCourses(List<Course> courses) async {
    allCourses.addAll(courses);
    await _dbHelper.insertCourses(courses);
    await _syncWidgetIfReady();
    notifyListeners();
  }

  Future<void> updateCourse(Course course) async {
    final idx = allCourses.indexWhere((c) => c.id == course.id);
    if (idx != -1) {
      allCourses[idx] = course;
      await _dbHelper.updateCourse(course);
      await _syncWidgetIfReady();
      notifyListeners();
    }
  }

  Future<void> deleteCourse(String courseId) async {
    allCourses.removeWhere((c) => c.id == courseId);
    await _dbHelper.deleteCourse(courseId);
    await _syncWidgetIfReady();
    notifyListeners();
  }

  Future<void> updateTimeSlot(int index, String startTime, String endTime) async {
    if (index >= 0 && index < timeSlots.length) {
      timeSlots[index].startTime = startTime;
      timeSlots[index].endTime = endTime;
      await _dbHelper.updateTimeSlot(timeSlots[index]);
      await _syncWidgetIfReady();
      notifyListeners();
    }
  }

  Future<void> _saveSettingsToDb() async {
    try {
      await _dbHelper.saveAllSettings(
        currentSemesterId: currentSemester?.id,
        currentWeek: currentWeek,
        lunchBreakAfterSlot: lunchBreakAfterSlot,
        dinnerBreakAfterSlot: dinnerBreakAfterSlot,
        showLunchBreak: showLunchBreak,
        showDinnerBreak: showDinnerBreak,
        showNonThisWeekCourses: showNonThisWeekCourses,
        aiServerUrl: aiServerUrl,
        initialized: true,
      );
      if (isDataLoaded && !_isLoadingData) {
        await syncWidgetData();
      }
    } catch (e) {
      debugPrint('保存设置失败: $e');
    }
  }

  Future<void> _saveTimeSlotsToDb() async {
    try {
      await _dbHelper.saveAllTimeSlots(timeSlots);
    } catch (e) {
      debugPrint('保存时间段失败: $e');
    }
  }

  Future<void> _saveAllDataToDb() async {
    try {
      for (final sem in semesters) {
        await _dbHelper.insertSemester(sem);
      }
      await _dbHelper.insertCourses(allCourses);
      await _dbHelper.saveAllTimeSlots(timeSlots);
      await _saveSettingsToDb();
    } catch (e) {
      debugPrint('保存全部数据到数据库失败: $e');
    }
  }

  Future<void> loadDataFromLocal() async {
    _isLoadingData = true;
    try {
      final dbSemesters = await _dbHelper.getAllSemesters();
      final initialized = await _dbHelper.getSetting('initialized');

      if (dbSemesters.isEmpty) {
        if (initialized == 'true') {
          // Avoid rewriting defaults when historical data may have load issues.
          semesters = [];
          currentSemester = null;
          currentWeek = 1;
          allCourses = [];
          timeSlots = await _dbHelper.getAllTimeSlots();
          if (timeSlots.isEmpty) {
            timeSlots = _buildDefaultTimeSlots();
          }
        } else {
          _initDefaultData();
          await _saveAllDataToDb();
        }
      } else {
        semesters = dbSemesters;
        allCourses = await _dbHelper.getAllCourses();
        timeSlots = await _dbHelper.getAllTimeSlots();

        if (timeSlots.isEmpty) {
          timeSlots = _buildDefaultTimeSlots();
          await _saveTimeSlotsToDb();
        }

        final currentSemId = await _dbHelper.getSetting('currentSemesterId');
        final lunchStr = await _dbHelper.getSetting('lunchBreakAfterSlot');
        final dinnerStr = await _dbHelper.getSetting('dinnerBreakAfterSlot');
        final showLunchStr = await _dbHelper.getSetting('showLunchBreak');
        final showDinnerStr = await _dbHelper.getSetting('showDinnerBreak');
        final showNonThisWeekStr =
            await _dbHelper.getSetting('showNonThisWeekCourses');
        final aiServerUrlStr = await _dbHelper.getSetting('aiServerUrl');

        lunchBreakAfterSlot = int.tryParse(lunchStr ?? '') ?? 4;
        dinnerBreakAfterSlot = int.tryParse(dinnerStr ?? '') ?? 8;
        showLunchBreak = showLunchStr == 'true';
        showDinnerBreak = showDinnerStr != 'false';
        showNonThisWeekCourses = showNonThisWeekStr == 'true';
        if (aiServerUrlStr != null && aiServerUrlStr.trim().isNotEmpty) {
          aiServerUrl = aiServerUrlStr.trim();
        }

        if (currentSemId != null && currentSemId.isNotEmpty) {
          currentSemester = semesters.firstWhere(
            (s) => s.id == currentSemId,
            orElse: () => semesters.first,
          );
        } else if (semesters.isNotEmpty) {
          currentSemester = semesters.first;
        }

        _recalculateCurrentWeek();
      }
    } catch (e) {
      debugPrint('加载数据失败: $e');
      // Keep in-memory state, but do not write defaults back to DB on failure.
    } finally {
      _isLoadingData = false;
    }

    isDataLoaded = true;
    await syncWidgetData();
    notifyListeners();
  }

  Future<void> exportData() async {
    try {
      final dbPath = await _dbHelper.getDatabasePath();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final xFile = XFile(dbFile.path, mimeType: 'application/x-sqlite3');
        await Share.shareXFiles([xFile], text: '这是我的课表备份数据库，请查收！');
      }
    } catch (e) {
      debugPrint('导出失败: $e');
    }
  }

  Future<bool> saveBackupToFile() async {
    try {
      final dbPath = await _dbHelper.getDatabasePath();
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) return false;

      final now = DateTime.now();
      final defaultFileName = 'schedule_backup_${now.month}月${now.day}日.db';

      final bytes = await dbFile.readAsBytes();

      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '选择课表备份保存位置',
        fileName: defaultFileName,
        type: FileType.any,
        bytes: bytes,
      );

      if (outputFile != null) {
        return true;
      }
    } catch (e) {
      debugPrint('另存为本地文件失败: $e');
    }
    return false;
  }

  Future<bool> importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final importFile = File(result.files.single.path!);

        if (!importFile.path.toLowerCase().endsWith('.db')) {
          debugPrint('导入失败：请选择 .db 格式的数据库文件');
          return false;
        }

        final isValid = await _dbHelper.isValidDatabaseFile(importFile.path);
        if (!isValid) {
          debugPrint('导入失败：数据库文件结构不完整');
          return false;
        }

        await _dbHelper.close();

        final dbPath = await _dbHelper.getDatabasePath();
        await importFile.copy(dbPath);

        await _dbHelper.reopen();

        isDataLoaded = false;
        await loadDataFromLocal();
        return true;
      }
    } catch (e) {
      debugPrint('导入失败: $e');
      try {
        await _dbHelper.reopen();
        await loadDataFromLocal();
      } catch (_) {}
    }
    return false;
  }
}
