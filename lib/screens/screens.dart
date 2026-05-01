import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:home_widget/home_widget.dart';
import '../services/ai_import_service.dart';
// 引入你的数据模型和状态管理
import '../models/models.dart';
import '../providers/app_state.dart';

// ==========================================
// 1. 主课表界面 Main Schedule Screen
// ==========================================

class MainScheduleScreen extends StatefulWidget {
  const MainScheduleScreen({super.key});

  @override
  State<MainScheduleScreen> createState() => _MainScheduleScreenState();
}

class _MainScheduleScreenState extends State<MainScheduleScreen> {
  final List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  final double timeColumnWidth = 45.0;
  final double slotHeight = 65.0;
  final double breakHeight = 20.0;

  bool _isImporting = false;

  // 记录当前被选中的空白格子 (day, slot)，用于两次点击逻辑
  int? _selectedDay;
  int? _selectedSlot;

  @override
  void initState() {
    super.initState();
    _initWidgetListener();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppState().loadDataFromLocal();
    });
  }

  void _initWidgetListener() {
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetLaunch);
    HomeWidget.widgetClicked.listen(_handleWidgetLaunch);
  }

  void _handleWidgetLaunch(Uri? uri) {
    if (uri != null && uri.scheme == 'scheduleapp' && uri.host == 'main_schedule') {
      debugPrint('从桌面小组件成功唤醒了 App!');

      final state = AppState();
      if (!state.isDataLoaded) return;
      final sem = state.currentSemester;

      if (sem != null) {
        DateTime now = DateTime.now();
        DateTime today = DateTime(now.year, now.month, now.day);
        DateTime start = DateTime(sem.startDate.year, sem.startDate.month, sem.startDate.day);

        int daysDiff = today.difference(start).inDays;
        int calculatedWeek = (daysDiff ~/ 7) + 1;

        if (calculatedWeek < 1) calculatedWeek = 1;
        if (calculatedWeek > sem.totalWeeks) calculatedWeek = sem.totalWeeks;

        state.setCurrentWeek(calculatedWeek);
      }
    }
  }

  void _handleSwipe(DragEndDetails details, AppState state, Semester currentSem) {
    double velocity = details.primaryVelocity ?? 0;
    if (velocity < -300) {
      if (state.currentWeek < currentSem.totalWeeks) {
        state.setCurrentWeek(state.currentWeek + 1);
      }
    } else if (velocity > 300) {
      if (state.currentWeek > 1) {
        state.setCurrentWeek(state.currentWeek - 1);
      }
    }
  }

  // ===== 新增：深度克隆课程（防止修改原数据） =====
  Future<void> _showServerUrlDialog(BuildContext context, AppState state) async {
    final controller = TextEditingController(text: state.aiServerUrl);

    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('设置服务器地址'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '例如 192.168.1.10 或 http://192.168.1.10:8000/api/parse_schedule',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );

      if (result == null) return;

      final normalized = AiImportService.normalizeServerUrl(result);
      await state.setAiServerUrl(normalized);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('服务器地址已保存: $normalized')),
      );
    } finally {
      controller.dispose();
    }
  }

  Course _cloneCourse(Course c) {
    return Course(
      id: c.id, semesterId: c.semesterId, name: c.name, room: c.room,
      teacher: c.teacher, color: c.color, dayOfWeek: c.dayOfWeek,
      startSlot: c.startSlot, endSlot: c.endSlot, weeks: List.from(c.weeks),
    );
  }

  // ===== 新增：合并相邻相同课程 =====
  List<Course> _mergeCourses(List<Course> dayCourses, AppState state) {
    if (dayCourses.isEmpty) return [];
    List<Course> merged = [];

    // 按照"名称_教室_教师_是否是本周"进行分组，防止不同周次的课被意外合并
    Map<String, List<Course>> courseGroups = {};
    for (var c in dayCourses) {
      bool isThisWeek = c.weeks.contains(state.currentWeek);
      String key = '${c.name}_${c.room}_${c.teacher}_$isThisWeek';
      courseGroups.putIfAbsent(key, () => []).add(c);
    }

    for (var group in courseGroups.values) {
      // 组内按开始节次排序
      group.sort((a, b) => a.startSlot.compareTo(b.startSlot));
      Course? currentMerged;

      for (var c in group) {
        if (currentMerged == null) {
          currentMerged = _cloneCourse(c);
        } else {
          // 检查是否跨越午休或晚休
          bool crossesLunch = currentMerged.endSlot == state.lunchBreakAfterSlot;
          bool crossesDinner = currentMerged.endSlot == state.dinnerBreakAfterSlot;
          bool crossesBreak = crossesLunch || crossesDinner;

          // 如果首尾相连，且不跨越休息时间，则合并
          if (currentMerged.endSlot == c.startSlot - 1 && !crossesBreak) {
            currentMerged.endSlot = c.endSlot;
          } else {
            merged.add(currentMerged);
            currentMerged = _cloneCourse(c);
          }
        }
      }
      if (currentMerged != null) {
        merged.add(currentMerged);
      }
    }

    // 最后再次按照开始时间排序返回，供冲突检测逻辑使用
    merged.sort((a, b) => a.startSlot.compareTo(b.startSlot));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState(),
      builder: (context, child) {
        final state = AppState();

        if (!state.isDataLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final currentSem = state.currentSemester;

        return Scaffold(
          appBar: AppBar(
            title: _buildWeekSelector(state, currentSem),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            elevation: 0,
            actions: [
              if (currentSem != null)
                IconButton(
                  icon: const Icon(Icons.add_box_outlined),
                  tooltip: '手动添加课程',
                  onPressed: () => _openCourseEditor(context, null),
                ),
            ],
          ),
          drawer: _buildDrawer(context, state),
          body: currentSem == null
              ? const Center(child: Text("请先创建或选择学期"))
              : SafeArea(
                  child: GestureDetector(
                    onHorizontalDragEnd: (details) => _handleSwipe(details, state, currentSem),
                    child: Container(
                      color: Colors.white,
                      child: Column(
                        children: [
                          _buildHeaderRow(state, currentSem),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTimeColumn(state),
                                  Expanded(
                                    child: _buildCourseGrid(state),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          // 取消了 currentSem == null 时的按钮隐藏，这样即使用户未创建学期，也能通过 AI 导入顺便新建
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _isImporting ? null : () async {
              // ========== 第1步：选择导入的目标学期 ==========
              var semResult = await showDialog(
                context: context,
                builder: (ctx) {
                  return AlertDialog(
                    title: const Text('选择导入目标学期'),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ...state.semesters.map((sem) => ListTile(
                                title: Text(sem.name),
                                subtitle: Text(sem.id == state.currentSemester?.id ? '(当前学期)' : ''),
                                trailing: const Icon(Icons.check_circle_outline),
                                onTap: () => Navigator.pop(ctx, sem),
                              )),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.add_circle, color: Colors.blue),
                            title: const Text('新建学期', style: TextStyle(color: Colors.blue)),
                            onTap: () => Navigator.pop(ctx, 'CREATE'),
                          ),
                        ],
                      ),
                    ),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
                  );
                },
              );

              if (semResult == 'CREATE') {
                // 跳转去新建学期，建完后用户可以在界面再次点击导入
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const SemesterEditScreen()));
                return;
              }

              if (semResult == null || semResult is! Semester) return; // 用户取消了选择
              Semester targetSemester = semResult;

              setState(() { _isImporting = true; });

              try {
                // ========== 第2步：调用 AI 解析（仅拿数据，不修改数据库） ==========
                final aiData = await AiImportService.importFromImage(context);

                if (aiData != null) {
                  // ========== 第3步：将解析数据转为预览用的 Course 列表 ==========
                  List<Course> previewCourses = AiImportService.parsePreviewCourses(aiData, targetSemester.id, state);

                  if (previewCourses.isEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未识别到任何课程信息')));
                    }
                    return;
                  }

                  // ========== 第4步：弹出用户确认/预览/撤销对话框 ==========
                  if (context.mounted) {
                    bool? confirm = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => AlertDialog(
                        title: const Text('AI 识别成功'),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('准备合并到：【${targetSemester.name}】', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                              const SizedBox(height: 12),
                              Text('共识别出 ${previewCourses.length} 门课程：'),
                              const SizedBox(height: 8),
                              Flexible(
                                child: Container(
                                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: previewCourses.length,
                                    separatorBuilder: (c, i) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final c = previewCourses[index];
                                      return ListTile(
                                        dense: true,
                                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        subtitle: Text('周${c.dayOfWeek} 第${c.startSlot}-${c.endSlot}节 | ${c.room}'),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 8.0),
                                child: Text('提示: 点击确认后将与该学期现有课表进行合并显示。', style: TextStyle(fontSize: 12, color: Colors.black54)),
                              )
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('撤销修改', style: TextStyle(color: Colors.red))),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认并合并课表')),
                        ],
                      )
                    );

                    // ========== 第5步：根据用户选择执行操作 ==========
                    if (confirm == true) {
                      // 将临时生成的预览课程永久写入状态库
                      await state.addCourses(previewCourses);
                      await AiImportService.applyTimeSlots(aiData, state);

                      // 如果用户选的目标学期不是当前主界面正在展示的学期，自动切过去
                      if (state.currentSemester?.id != targetSemester.id) {
                        await state.switchSemester(targetSemester);
                      }

                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 课表合并成功！')));
                    } else {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已撤销导入操作')));
                    }
                  }
                }
              } finally {
                if (mounted) setState(() { _isImporting = false; });
              }
            },
            icon: _isImporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
                : const Icon(Icons.auto_awesome),
            label: Text(_isImporting ? '处理中...' : 'AI 导入'),
          ),
        );
      },
    );
  }

  Widget _buildWeekSelector(AppState state, Semester? sem) {
    if (sem == null) return const Text('智能课表');
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: state.currentWeek,
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black87),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        items: List.generate(sem.totalWeeks, (index) {
          int w = index + 1;
          return DropdownMenuItem(
            value: w,
            child: Text('第 $w 周'),
          );
        }),
        onChanged: (val) {
          if (val != null) state.setCurrentWeek(val);
        },
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AppState state) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.school, size: 50, color: Colors.white),
                SizedBox(height: 10),
                Text('智能课表', style: TextStyle(color: Colors.white, fontSize: 24)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text('学期管理'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SemesterManageScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('时间设置'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TimeSlotScreen()));
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility),
            title: const Text('显示非本周课程'),
            value: state.showNonThisWeekCourses,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) {
              state.toggleShowNonThisWeekCourses(val);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('导出课表备份'),
            onTap: () async {
              Navigator.pop(context);
              await state.exportData();
            },
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('另存为本地文件'),
            onTap: () async {
              Navigator.pop(context);
              bool success = await state.saveBackupToFile();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? '文件已成功保存！' : '已取消保存')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('从文件导入课表'),
            onTap: () async {
              Navigator.pop(context);
              bool success = await state.importData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? '导入成功！' : '导入取消或失败')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('服务器地址设置'),
            subtitle: Text(
              state.aiServerUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () async {
              Navigator.pop(context);
              await _showServerUrlDialog(context, state);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
          const Divider(),
          if (state.semesters.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('切换学期', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
          ...state.semesters.map((sem) => RadioListTile<String>(
                title: Text(sem.name),
                value: sem.id,
                groupValue: state.currentSemester?.id,
                onChanged: (val) async {
                  await state.switchSemester(sem);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
              )),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(AppState state, Semester sem) {
    DateTime weekStart = sem.startDate.add(Duration(days: (state.currentWeek - 1) * 7));

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          SizedBox(width: timeColumnWidth, child: Center(child: Text('${weekStart.month}月', style: const TextStyle(fontSize: 12)))),
          ...List.generate(7, (index) {
            DateTime dayDate = weekStart.add(Duration(days: index));
            bool isToday = _isSameDay(dayDate, DateTime.now());
            return Expanded(
              child: Column(
                children: [
                  Text('周${weekdays[index]}', style: TextStyle(fontSize: 12, color: isToday ? Theme.of(context).colorScheme.primary : Colors.black87, fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      color: isToday ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('${dayDate.day}', style: TextStyle(fontSize: 12, color: isToday ? Colors.white : Colors.black54, fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildTimeColumn(AppState state) {
    List<Widget> children = [];
    for (int i = 0; i < state.timeSlots.length; i++) {
      final slot = state.timeSlots[i];
      children.add(Container(
        height: slotHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
            right: BorderSide(color: Colors.grey.shade200, width: 0.5),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${slot.slotIndex}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            // ===== 修改：分别显示上课与下课时间，并调整字号以防溢出 =====
            Text(slot.startTime, style: const TextStyle(fontSize: 9, color: Colors.black54, height: 1.0)),
            Text(slot.endTime, style: const TextStyle(fontSize: 9, color: Colors.black54, height: 1.0)),
          ],
        ),
      ));

      if (state.showLunchBreak && i == state.lunchBreakAfterSlot - 1) {
        children.add(Container(
          height: breakHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
              right: BorderSide(color: Colors.grey.shade200, width: 0.5),
            ),
          ),
          child: const Text('午休', style: TextStyle(fontSize: 10, color: Colors.black45)),
        ));
      }
      if (state.showDinnerBreak && i == state.dinnerBreakAfterSlot - 1) {
        children.add(Container(
          height: breakHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
              right: BorderSide(color: Colors.grey.shade200, width: 0.5),
            ),
          ),
          child: const Text('晚休', style: TextStyle(fontSize: 10, color: Colors.black45)),
        ));
      }
    }

    return SizedBox(
      width: timeColumnWidth,
      child: Column(children: children),
    );
  }

  Widget _buildCourseGrid(AppState state) {
    return LayoutBuilder(builder: (context, constraints) {
      double colWidth = constraints.maxWidth / 7;
      int maxSlots = state.timeSlots.length;

      // ===== 修改：根据开关决定拉取本周课程还是整学期课程 =====
      List<Course> targetCourses = state.showNonThisWeekCourses
          ? state.getSemesterCourses()
          : state.getCurrentWeekCourses();

      List<List<Course>> conflictGroups = [];
      for (int day = 1; day <= 7; day++) {
        List<Course> dayCoursesRaw = targetCourses.where((c) => c.dayOfWeek == day).toList();

        // ===== 修改：在此处拦截并合并相邻相同的课程 =====
        List<Course> dayCourses = _mergeCourses(dayCoursesRaw, state);

        // 以下冲突检测逻辑保持不变
        List<Course> currentGroup = [];
        int currentGroupEnd = -1;

        for (var course in dayCourses) {
          if (currentGroup.isEmpty) {
            currentGroup.add(course);
            currentGroupEnd = course.endSlot;
          } else {
            if (course.startSlot <= currentGroupEnd) {
              currentGroup.add(course);
              if (course.endSlot > currentGroupEnd) {
                currentGroupEnd = course.endSlot;
              }
            } else {
              conflictGroups.add(currentGroup);
              currentGroup = [course];
              currentGroupEnd = course.endSlot;
            }
          }
        }
        if (currentGroup.isNotEmpty) {
          conflictGroups.add(currentGroup);
        }
      }

      int breakCount = (state.showLunchBreak ? 1 : 0) + (state.showDinnerBreak ? 1 : 0);

      double getSlotTopY(int slot) {
        double y = (slot - 1) * slotHeight;
        if (state.showLunchBreak && slot > state.lunchBreakAfterSlot) y += breakHeight;
        if (state.showDinnerBreak && slot > state.dinnerBreakAfterSlot) y += breakHeight;
        return y;
      }

      double getSlotBottomY(int slot) {
        double y = slot * slotHeight;
        if (state.showLunchBreak && slot > state.lunchBreakAfterSlot) y += breakHeight;
        if (state.showDinnerBreak && slot > state.dinnerBreakAfterSlot) y += breakHeight;
        return y;
      }

      return SizedBox(
        height: maxSlots * slotHeight + breakHeight * breakCount,
        child: Stack(
          children: [
            Column(
              children: List.generate(maxSlots, (rowIndex) {
                Widget rowWidget = Row(
                  children: List.generate(7, (colIndex) {
                    final int cellDay = colIndex + 1;
                    final int cellSlot = rowIndex + 1;
                    final bool isSelected = _selectedDay == cellDay && _selectedSlot == cellSlot;
                    return GestureDetector(
                      onTap: () {
                        if (isSelected) {
                          // 第二次点击同一格子：打开课程编辑器
                          setState(() { _selectedDay = null; _selectedSlot = null; });
                          _openCourseEditor(context, null, initialDay: cellDay, initialStartSlot: cellSlot);
                        } else {
                          // 第一次点击：高亮显示加号
                          setState(() { _selectedDay = cellDay; _selectedSlot = cellSlot; });
                        }
                      },
                      child: Container(
                        width: colWidth,
                        height: slotHeight,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.indigo.withOpacity(0.06) : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
                            right: BorderSide(color: Colors.grey.shade200, width: 0.5),
                          ),
                        ),
                        child: isSelected
                            ? Center(
                                child: Icon(Icons.add, size: 22, color: Colors.indigo.withOpacity(0.35)),
                              )
                            : null,
                      ),
                    );
                  }),
                );

                List<Widget> colChildren = [rowWidget];

                if (state.showLunchBreak && rowIndex == state.lunchBreakAfterSlot - 1) {
                  colChildren.add(
                    Container(
                      height: breakHeight,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                      ),
                      alignment: Alignment.center,
                      child: const Text('午 休 时 间', style: TextStyle(color: Colors.black26, fontSize: 10, letterSpacing: 10)),
                    )
                  );
                }

                if (state.showDinnerBreak && rowIndex == state.dinnerBreakAfterSlot - 1) {
                  colChildren.add(
                    Container(
                      height: breakHeight,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                      ),
                      alignment: Alignment.center,
                      child: const Text('晚 休 时 间', style: TextStyle(color: Colors.black26, fontSize: 10, letterSpacing: 10)),
                    )
                  );
                }

                if (colChildren.length > 1) {
                  return Column(children: colChildren);
                }
                return rowWidget;
              }),
            ),

            ...conflictGroups.map((group) {
              int groupStartSlot = group.map((c) => c.startSlot).reduce(math.min);
              int groupEndSlot = group.map((c) => c.endSlot).reduce(math.max);
              int dayOfWeek = group.first.dayOfWeek;

              double topOffset = getSlotTopY(groupStartSlot);
              double bottomOffset = getSlotBottomY(groupEndSlot);
              double leftOffset = (dayOfWeek - 1) * colWidth;
              double height = bottomOffset - topOffset;

              return Positioned(
                top: topOffset,
                left: leftOffset,
                width: colWidth,
                height: height,
                child: GestureDetector(
                  onTap: () {
                    // 点击课程卡片时清除空白格选中状态
                    if (_selectedDay != null || _selectedSlot != null) {
                      setState(() { _selectedDay = null; _selectedSlot = null; });
                    }
                    _handleCourseTap(context, group, state);
                  },
                  child: _buildCourseCard(group, state),
                ),
              );
            }),
          ],
        ),
      );
    });
  }

  // ===== 修改：增加非本周课程置灰处理 =====
  Widget _buildCourseCard(List<Course> group, AppState state) {
    // 对冲突组进行排序：优先显示“本周课程”
    List<Course> sortedGroup = List.from(group);
    sortedGroup.sort((a, b) {
      bool aThisWeek = a.weeks.contains(state.currentWeek);
      bool bThisWeek = b.weeks.contains(state.currentWeek);
      if (aThisWeek && !bThisWeek) return -1;
      if (!aThisWeek && bThisWeek) return 1;
      return 0;
    });

    final course = sortedGroup.first;
    final isThisWeek = course.weeks.contains(state.currentWeek);
    final hasConflict = sortedGroup.length > 1;

    // 非本周课程设置为浅灰色
    Color bgColor = isThisWeek ? course.color.withOpacity(0.9) : Colors.grey.shade400.withOpacity(0.85);

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          margin: const EdgeInsets.all(1.5),
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6.0),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(course.name, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold), maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Flexible(child: Text(course.room, style: const TextStyle(fontSize: 10, color: Colors.white70), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Flexible(child: Text(course.teacher, style: const TextStyle(fontSize: 10, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        if (hasConflict)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                // 冲突角标的颜色也根据是否本周调整一下
                color: isThisWeek ? Colors.redAccent : Colors.grey.shade500,
                borderRadius: const BorderRadius.only(topRight: Radius.circular(6), bottomLeft: Radius.circular(6)),
              ),
              child: Text('${sortedGroup.length}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  // ===== 新增：将周次列表格式化为紧凑字符串 (例如 1-4, 6-8周) =====
  String _formatWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '无';
    List<int> sortedWeeks = List.from(weeks)..sort();

    List<String> parts = [];
    int start = sortedWeeks.first;
    int end = sortedWeeks.first;

    for (int i = 1; i < sortedWeeks.length; i++) {
      if (sortedWeeks[i] == end + 1) {
        end = sortedWeeks[i];
      } else {
        parts.add(start == end ? '$start' : '$start-$end');
        start = sortedWeeks[i];
        end = sortedWeeks[i];
      }
    }
    parts.add(start == end ? '$start' : '$start-$end');
    return '${parts.join(',')}周';
  }

  void _handleCourseTap(BuildContext context, List<Course> group, AppState state) {
    if (group.length == 1) {
      _openCourseEditor(context, group.first);
    } else {
      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('发现冲突课程，请选择'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: group.length,
                itemBuilder: (context, index) {
                  final course = group[index];
                  final isThisWeek = course.weeks.contains(state.currentWeek);

                  // 调用刚刚新增的格式化方法
                  final weeksText = _formatWeeks(course.weeks);

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isThisWeek ? course.color : Colors.grey,
                      child: const Icon(Icons.book, color: Colors.white, size: 20)
                    ),
                    title: Text(course.name),
                    // ===== 修改：改为使用 Column 来展示多行详细信息 =====
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('教师: ${course.teacher.isEmpty ? "未知" : course.teacher} | 教室: ${course.room}'),
                          Text(
                            '时间: 第${course.startSlot}-${course.endSlot}节 | $weeksText${isThisWeek ? "" : " (非本周)"}',
                            style: TextStyle(color: isThisWeek ? Colors.black54 : Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.edit, size: 16),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openCourseEditor(context, course);
                    },
                  );
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
          );
        }
      );
    }
  }

  void _openCourseEditor(BuildContext context, Course? course, {int? initialDay, int? initialStartSlot}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CourseEditScreen(course: course, initialDay: initialDay, initialStartSlot: initialStartSlot)));
  }
}

// ==========================================
// 2. 课程编辑/添加界面 Course Editor Screen
// ==========================================

class CourseEditScreen extends StatefulWidget {
  final Course? course;
  final int? initialDay;
  final int? initialStartSlot;

  const CourseEditScreen({super.key, this.course, this.initialDay, this.initialStartSlot});

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  final _formKey = GlobalKey<FormState>();

  String _name = '';
  String _room = '';
  String _teacher = '';
  int _dayOfWeek = 1;
  int _startSlot = 1;
  int _endSlot = 2;
  List<int> _selectedWeeks = [];
  Color _color = Colors.indigo;

  bool _isDragSelecting = true;
  int _lastDraggedIndex = -1;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    final state = AppState();

    _name = c?.name ?? '';
    _room = c?.room ?? '';
    _teacher = c?.teacher ?? '';
    _dayOfWeek = c?.dayOfWeek ?? widget.initialDay ?? 1;
    _startSlot = c?.startSlot ?? widget.initialStartSlot ?? 1;
    _endSlot = c?.endSlot ?? (_startSlot < 12 ? _startSlot + 1 : 12);

    Semester? courseSem = state.semesters.cast<Semester?>().firstWhere(
        (s) => s?.id == (c?.semesterId ?? state.currentSemester?.id),
        orElse: () => state.currentSemester
    );
    int totalWeeks = courseSem?.totalWeeks ?? 20;

    if (c?.weeks != null) {
      _selectedWeeks = c!.weeks.where((w) => w <= totalWeeks).toList();
    } else {
      _selectedWeeks = List.generate(totalWeeks, (i) => i + 1);
    }

    _color = c?.color ?? AppState().courseColors[DateTime.now().millisecond % AppState().courseColors.length];
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      if (_endSlot < _startSlot) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('结束节次不能早于开始节次')));
        return;
      }
      if (_selectedWeeks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少选择一个上课周次')));
        return;
      }

      final state = AppState();
      final newCourse = Course(
        id: widget.course?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        semesterId: widget.course?.semesterId ?? state.currentSemester!.id,
        name: _name,
        room: _room,
        teacher: _teacher,
        color: _color,
        dayOfWeek: _dayOfWeek,
        startSlot: _startSlot,
        endSlot: _endSlot,
        weeks: _selectedWeeks,
      );

      if (widget.course == null) {
        await state.addCourse(newCourse);
      } else {
        await state.updateCourse(newCourse);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? '添加课程' : '编辑课程'),
        actions: [
          if (widget.course != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () async {
                await AppState().deleteCourse(widget.course!.id);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              _save();
            },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(labelText: '课程名称', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? '请输入课程名称' : null,
              onSaved: (v) => _name = v!,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextFormField(initialValue: _room, decoration: const InputDecoration(labelText: '教室', border: OutlineInputBorder()), onSaved: (v) => _room = v ?? '')),
                const SizedBox(width: 16),
                Expanded(child: TextFormField(initialValue: _teacher, decoration: const InputDecoration(labelText: '教师', border: OutlineInputBorder()), onSaved: (v) => _teacher = v ?? '')),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '星期几', border: OutlineInputBorder()),
              value: _dayOfWeek,
              items: const [
                DropdownMenuItem(value: 1, child: Text('星期一')),
                DropdownMenuItem(value: 2, child: Text('星期二')),
                DropdownMenuItem(value: 3, child: Text('星期三')),
                DropdownMenuItem(value: 4, child: Text('星期四')),
                DropdownMenuItem(value: 5, child: Text('星期五')),
                DropdownMenuItem(value: 6, child: Text('星期六')),
                DropdownMenuItem(value: 7, child: Text('星期日')),
              ],
              onChanged: (v) => setState(() => _dayOfWeek = v!),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: '开始节次', border: OutlineInputBorder()),
                    value: _startSlot,
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('第${i + 1}节'))),
                    onChanged: (v) => setState(() => _startSlot = v!),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 10.0), child: Text('至')),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: '结束节次', border: OutlineInputBorder()),
                    value: _endSlot,
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('第${i + 1}节'))),
                    onChanged: (v) => setState(() => _endSlot = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('选择课程颜色:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12.0,
              runSpacing: 12.0,
              children: AppState().courseColors.map((color) {
                bool isSelected = _color.value == color.value;
                return GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Colors.black54, width: 2) : null,
                      boxShadow: [if (isSelected) const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Text('选择上课周次 (支持滑动多选):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 6;
                double spacing = 8.0;
                double itemWidth = (constraints.maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;

                Semester? courseSem = AppState().semesters.cast<Semester?>().firstWhere(
                    (s) => s?.id == (widget.course?.semesterId ?? AppState().currentSemester?.id),
                    orElse: () => AppState().currentSemester
                );
                int totalWeeks = courseSem?.totalWeeks ?? 20;

                void handlePointer(Offset pos, {bool isTapDown = false}) {
                  int col = (pos.dx / (itemWidth + spacing)).floor();
                  int row = (pos.dy / (itemWidth + spacing)).floor();
                  if (col < 0 || col >= crossAxisCount || row < 0) return;

                  int index = row * crossAxisCount + col;
                  int week = index + 1;

                  if (week >= 1 && week <= totalWeeks) {
                    if (isTapDown) {
                      _isDragSelecting = !_selectedWeeks.contains(week);
                      _lastDraggedIndex = -1;
                    }
                    if (_lastDraggedIndex != index) {
                      setState(() {
                        if (_isDragSelecting) {
                          if (!_selectedWeeks.contains(week)) _selectedWeeks.add(week);
                        } else {
                          _selectedWeeks.remove(week);
                        }
                        _lastDraggedIndex = index;
                      });
                    }
                  }
                }

  // ===== 修改：将 GestureDetector 替换为 Listener =====
                return Listener(
                  // 使用 onPointerDown 替代 onTapDown / onPanStart
                  onPointerDown: (event) => handlePointer(event.localPosition, isTapDown: true),
                  // 使用 onPointerMove 替代 onPanUpdate
                  onPointerMove: (event) => handlePointer(event.localPosition),
                  // 确保点击到组件的空白处也能触发
                  behavior: HitTestBehavior.opaque,
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: totalWeeks,
                    itemBuilder: (context, index) {
                      int week = index + 1;
                      bool isSelected = _selectedWeeks.contains(week);
                      return Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$week', style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. 学期管理界面 Semester Manage Screens
// ==========================================

class SemesterManageScreen extends StatelessWidget {
  const SemesterManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学期管理')),
      body: AnimatedBuilder(
        animation: AppState(),
        builder: (context, child) {
          final state = AppState();
          return ListView.builder(
            itemCount: state.semesters.length,
            itemBuilder: (context, index) {
              final sem = state.semesters[index];
              return ListTile(
                title: Text(sem.name),
                subtitle: Text('共 ${sem.totalWeeks} 周 | 开学: ${sem.startDate.toString().substring(0, 10)}'),
                trailing: const Icon(Icons.edit),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SemesterEditScreen(semester: sem))),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SemesterEditScreen())),
      ),
    );
  }
}

class SemesterEditScreen extends StatefulWidget {
  final Semester? semester;
  const SemesterEditScreen({super.key, this.semester});

  @override
  State<SemesterEditScreen> createState() => _SemesterEditScreenState();
}

class _SemesterEditScreenState extends State<SemesterEditScreen> {
  final _formKey = GlobalKey<FormState>();

  String _name = '';
  int _totalWeeks = 20;
  // 改为 late 初始化
  late DateTime _startDate;

  @override
  void initState() {
    super.initState();
    _name = widget.semester?.name ?? '';
    _totalWeeks = widget.semester?.totalWeeks ?? 20;

    if (widget.semester != null) {
      _startDate = widget.semester!.startDate;
    } else {
      // 修复：默认新建时，立刻把 DateTime.now() 对齐到本周一，并去除时分秒避免跨天误差
      DateTime now = DateTime.now();
      DateTime monday = now.subtract(Duration(days: now.weekday - 1));
      _startDate = DateTime(monday.year, monday.month, monday.day);
    }
  }

  void _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      int daysToSubtract = picked.weekday - 1;
      DateTime aligned = picked.subtract(Duration(days: daysToSubtract));
      setState(() {
        // 修复：同样去除时分秒，保证纯净的日期
        _startDate = DateTime(aligned.year, aligned.month, aligned.day);
      });
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final newSem = Semester(
        id: widget.semester?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _name,
        startDate: _startDate,
        totalWeeks: _totalWeeks,
      );

      if (widget.semester == null) {
        await AppState().addSemester(newSem);
        await AppState().switchSemester(newSem);
      } else {
        await AppState().updateSemester(newSem);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.semester == null ? '添加学期' : '编辑学期'),
        actions: [
          if (widget.semester != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除学期'),
                    content: const Text('确定要删除这个学期吗？\n警告：这将会同时清空该学期下的所有课程，且不可恢复！'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      TextButton(
                        onPressed: () async {
                          await AppState().deleteSemester(widget.semester!.id);
                          if (!context.mounted) return;
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        child: const Text('彻底删除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              _save();
            },
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: '学期名称 (如 2024秋季学期)', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? '必填' : null,
                onSaved: (v) => _name = v!,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _totalWeeks.toString(),
                decoration: const InputDecoration(labelText: '总周数', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) => int.tryParse(v ?? '') == null ? '请输入有效数字' : null,
                onSaved: (v) => _totalWeeks = int.parse(v!),
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                title: const Text('开学日期 (将自动对齐到周一)'),
                subtitle: Text(_startDate.toString().substring(0, 10)),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 4. 时间段设置界面 Time Slots Screen
// ==========================================

class TimeSlotScreen extends StatelessWidget {
  const TimeSlotScreen({super.key});

  Future<void> _editTimeSlot(BuildContext context, AppState state, int index, TimeSlot slot) async {
    List<String> startParts = slot.startTime.split(':');
    List<String> endParts = slot.endTime.split(':');
    TimeOfDay currentStart = TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1]));
    TimeOfDay currentEnd = TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1]));

    TimeOfDay? pickedStart = await showTimePicker(
      context: context,
      initialTime: currentStart,
      helpText: '选择 [${slot.name}] 开始时间',
    );

    if (pickedStart == null || !context.mounted) return;

    TimeOfDay? pickedEnd = await showTimePicker(
      context: context,
      initialTime: currentEnd,
      helpText: '选择 [${slot.name}] 结束时间',
    );

    if (pickedEnd == null) return;

    String formatTime(TimeOfDay time) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }

    await state.updateTimeSlot(index, formatTime(pickedStart), formatTime(pickedEnd));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('时间与休息设置')),
      body: AnimatedBuilder(
        animation: AppState(),
        builder: (context, child) {
          final state = AppState();
          int maxDropdown = state.timeSlots.length - 1;
          return Column(
            children: [
              // ===== 节数设置 =====
              Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: ListTile(
                  leading: const Icon(Icons.grid_view_rounded),
                  title: const Text('每天课程节数', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('当前 ${state.timeSlots.length} 节 (范围 4-16)'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: state.timeSlots.length > 4
                            ? () {
                                state.setTotalSlots(state.timeSlots.length - 1);
                              }
                            : null,
                      ),
                      Text('${state.timeSlots.length}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: state.timeSlots.length < 16
                            ? () {
                                state.setTotalSlots(state.timeSlots.length + 1);
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              // ===== 休息时间设置 =====
              Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text('休息时间设置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.wb_sunny_outlined),
                        title: const Text('显示午休'),
                        subtitle: state.showLunchBreak
                            ? Text('在第 ${state.lunchBreakAfterSlot} 节后插入')
                            : const Text('已关闭'),
                        value: state.showLunchBreak,
                        onChanged: (v) {
                          state.toggleLunchBreak(v);
                        },
                      ),
                      if (state.showLunchBreak)
                        Padding(
                          padding: const EdgeInsets.only(left: 56.0, right: 16.0, bottom: 8.0),
                          child: Row(
                            children: [
                              const Text('午休位置：'),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: state.lunchBreakAfterSlot.clamp(1, maxDropdown),
                                items: List.generate(maxDropdown, (i) => DropdownMenuItem(value: i + 1, child: Text('第${i + 1}节后'))),
                                onChanged: (v) {
                                  if (v != null) {
                                    state.setBreaks(v, state.dinnerBreakAfterSlot);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      SwitchListTile(
                        secondary: const Icon(Icons.nights_stay_outlined),
                        title: const Text('显示晚休'),
                        subtitle: state.showDinnerBreak
                            ? Text('在第 ${state.dinnerBreakAfterSlot} 节后插入')
                            : const Text('已关闭'),
                        value: state.showDinnerBreak,
                        onChanged: (v) {
                          state.toggleDinnerBreak(v);
                        },
                      ),
                      if (state.showDinnerBreak)
                        Padding(
                          padding: const EdgeInsets.only(left: 56.0, right: 16.0, bottom: 8.0),
                          child: Row(
                            children: [
                              const Text('晚休位置：'),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: state.dinnerBreakAfterSlot.clamp(1, maxDropdown),
                                items: List.generate(maxDropdown, (i) => DropdownMenuItem(value: i + 1, child: Text('第${i + 1}节后'))),
                                onChanged: (v) {
                                  if (v != null) {
                                    state.setBreaks(state.lunchBreakAfterSlot, v);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // ===== 时间段列表 =====
              const Padding(
                padding: EdgeInsets.only(left: 16.0, top: 8.0, bottom: 4.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('课表时间段 (点击可编辑)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: state.timeSlots.length,
                  itemBuilder: (context, index) {
                    final slot = state.timeSlots[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${slot.slotIndex}')),
                      title: Text(slot.name),
                      subtitle: Text('${slot.startTime} - ${slot.endTime}'),
                      trailing: const Icon(Icons.edit, color: Colors.grey),
                      onTap: () => _editTimeSlot(context, state, index, slot),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
// ==========================================
// 5. 关于界面 About Screen
// ==========================================

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 60,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'AI 智能课表',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '版本 1.0.0',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              const Card(
                elevation: 0,
                color: Color(0xFFF3F4F6),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      Text('作者', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text(
                        'Supersheep（使用AI协助开发）',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Powered by Kimi AI',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
