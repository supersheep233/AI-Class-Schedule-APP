import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../models/models.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  /// 获取数据库实例，延迟初始化
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 获取数据库文件路径
  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'class_schedule.db');
  }

  Future<Database> _initDatabase() async {
    final path = await getDatabasePath();
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE semesters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        total_weeks INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE courses (
        id TEXT PRIMARY KEY,
        semester_id TEXT NOT NULL,
        name TEXT NOT NULL,
        room TEXT NOT NULL DEFAULT '',
        teacher TEXT NOT NULL DEFAULT '',
        color INTEGER NOT NULL,
        day_of_week INTEGER NOT NULL,
        start_slot INTEGER NOT NULL,
        end_slot INTEGER NOT NULL,
        weeks TEXT NOT NULL,
        FOREIGN KEY (semester_id) REFERENCES semesters (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE time_slots (
        slot_index INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ==================== Settings ====================

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (result.isNotEmpty) {
      return result.first['value'] as String?;
    }
    return null;
  }

  // ==================== Semesters ====================

  Future<void> insertSemester(Semester semester) async {
    final db = await database;
    await db.insert('semesters', semester.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSemester(Semester semester) async {
    final db = await database;
    await db.update('semesters', semester.toMap(),
        where: 'id = ?', whereArgs: [semester.id]);
  }

  Future<void> deleteSemester(String semesterId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('courses', where: 'semester_id = ?', whereArgs: [semesterId]);
      await txn.delete('semesters', where: 'id = ?', whereArgs: [semesterId]);
    });
  }

  Future<List<Semester>> getAllSemesters() async {
    final db = await database;
    final result = await db.query('semesters');
    return result.map((map) => Semester.fromMap(map)).toList();
  }

  // ==================== Courses ====================

  Future<void> insertCourse(Course course) async {
    final db = await database;
    await db.insert('courses', course.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertCourses(List<Course> courses) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var course in courses) {
        await txn.insert('courses', course.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> updateCourse(Course course) async {
    final db = await database;
    await db.update('courses', course.toMap(),
        where: 'id = ?', whereArgs: [course.id]);
  }

  Future<void> deleteCourse(String courseId) async {
    final db = await database;
    await db.delete('courses', where: 'id = ?', whereArgs: [courseId]);
  }

  Future<List<Course>> getAllCourses() async {
    final db = await database;
    final result = await db.query('courses');
    return result.map((map) => Course.fromMap(map)).toList();
  }

  // ==================== TimeSlots ====================

  Future<void> insertTimeSlot(TimeSlot slot) async {
    final db = await database;
    await db.insert('time_slots', slot.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveAllTimeSlots(List<TimeSlot> slots) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('time_slots');
      for (var slot in slots) {
        await txn.insert('time_slots', slot.toMap());
      }
    });
  }

  Future<void> updateTimeSlot(TimeSlot slot) async {
    final db = await database;
    await db.update('time_slots', slot.toMap(),
        where: 'slot_index = ?', whereArgs: [slot.slotIndex]);
  }

  Future<List<TimeSlot>> getAllTimeSlots() async {
    final db = await database;
    final result = await db.query('time_slots', orderBy: 'slot_index ASC');
    return result.map((map) => TimeSlot.fromMap(map)).toList();
  }

  // ==================== 批量保存所有设置 ====================

  Future<void> saveAllSettings({
    required String? currentSemesterId,
    required int currentWeek,
    required int lunchBreakAfterSlot,
    required int dinnerBreakAfterSlot,
    required bool showLunchBreak,
    required bool showDinnerBreak,
    required bool showNonThisWeekCourses,
    required String aiServerUrl,
    required bool initialized,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      Future<void> set(String key, String value) async {
        await txn.insert('settings', {'key': key, 'value': value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await set('currentSemesterId', currentSemesterId ?? '');
      await set('currentWeek', currentWeek.toString());
      await set('lunchBreakAfterSlot', lunchBreakAfterSlot.toString());
      await set('dinnerBreakAfterSlot', dinnerBreakAfterSlot.toString());
      await set('showLunchBreak', showLunchBreak.toString());
      await set('showDinnerBreak', showDinnerBreak.toString());
      await set('showNonThisWeekCourses', showNonThisWeekCourses.toString());
      await set('aiServerUrl', aiServerUrl);
      await set('initialized', initialized.toString());
    });
  }

  Future<bool> isValidDatabaseFile(String filePath) async {
    if (!await File(filePath).exists()) return false;

    Database? tempDb;
    try {
      tempDb = await openDatabase(
        filePath,
        readOnly: true,
        singleInstance: false,
      );
      final rows = await tempDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final tableNames = rows
          .map((e) => (e['name'] as String?) ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();

      const required = {'semesters', 'courses', 'time_slots', 'settings'};
      return required.every(tableNames.contains);
    } catch (_) {
      return false;
    } finally {
      await tempDb?.close();
    }
  }

  // ==================== 关闭 & 重新打开数据库 ====================

  /// 关闭当前数据库连接（用于导入时替换文件前）
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// 重新打开数据库（用于导入后重新加载）
  Future<void> reopen() async {
    await close();
    _database = await _initDatabase();
  }
}
