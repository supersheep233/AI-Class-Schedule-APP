import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../providers/app_state.dart';

class AiImportService {
  static const String defaultServerUrl = 'http://127.0.0.1:8000/api/parse_schedule';
  static const String defaultApiPath = '/api/parse_schedule';
  static const int defaultApiPort = 8000;

  static String normalizeServerUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return defaultServerUrl;

    var normalized = raw;
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) return defaultServerUrl;

    if (uri.path.isEmpty || uri.path == '/') {
      if (uri.hasAuthority && uri.port == 0) {
        return uri.replace(port: defaultApiPort, path: defaultApiPath).toString();
      }
      return uri.replace(path: defaultApiPath).toString();
    }

    return uri.toString();
  }

  // 1. 核心方法：使用流式读取，并实时在界面上更新状态
  static Future<Map<String, dynamic>?> importFromImage(
    BuildContext context, {
    String? serverUrl,
  }) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return null;

    // 状态控制器：用于在弹窗中实时刷新文本
    final progressNotifier = ValueNotifier<String>('正在准备上传图片...');
    final rawOutputNotifier = ValueNotifier<String>('');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                // 监听状态说明
                ValueListenableBuilder<String>(
                  valueListenable: progressNotifier,
                  builder: (context, value, child) {
                    return Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo));
                  },
                ),
                const SizedBox(height: 12),
                // 监听大模型的实时输出（代码黑框效果）
                Container(
                  height: 120,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(6)
                  ),
                  child: SingleChildScrollView(
                    reverse: true, // 始终滚动到底部
                    child: ValueListenableBuilder<String>(
                      valueListenable: rawOutputNotifier,
                      builder: (context, value, child) {
                        return Text(
                          value.isEmpty ? '等待接收数据流...' : value,
                          style: const TextStyle(fontSize: 11, color: Colors.greenAccent, fontFamily: 'monospace')
                        );
                      },
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );

    http.Client? client;

    try {
      // 强制直连开关（打包 release 版本时 kDebugMode 为 false，因此会自动变为系统默认行为，确保生产安全）
      const bool forceDirectConnection = kDebugMode;

      if (forceDirectConnection) {
        final innerClient = HttpClient();
        innerClient.findProxy = (uri) => 'DIRECT'; // 强制完全无视代理环境
        client = IOClient(innerClient);
      } else {
        client = http.Client();
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(normalizeServerUrl(serverUrl ?? AppState().aiServerUrl)),
      );
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      // 发送请求，获取流式响应
      var streamedResponse = await client.send(request);

      if (streamedResponse.statusCode == 200) {
        Map<String, dynamic>? finalResult;
        String errorMsg = '';

        // 核心逻辑：按行分割流数据并逐行解析
        await for (var chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (chunk.trim().isEmpty) continue;

          try {
            var data = jsonDecode(chunk);
            String status = data['status'];

            if (status == 'progress') {
              progressNotifier.value = data['message'];
            } else if (status == 'generating') {
              rawOutputNotifier.value += data['message'];
            } else if (status == 'success') {
              finalResult = data['data'];
            } else if (status == 'error') {
              errorMsg = data['message'];
            }
          } catch (e) {
            debugPrint("解析单行流数据失败: $e - Chunk: $chunk");
          }
        }

        // 跑完上面的 await for，代表网络连接结束
        Navigator.pop(context); // 关掉 Loading 弹窗

        if (errorMsg.isNotEmpty) {
          _showError(context, errorMsg);
          return null;
        }

        return finalResult;

      } else {
        Navigator.pop(context);
        _showError(context, '服务器错误: ${streamedResponse.statusCode}');
        return null;
      }
    } catch (e) {
      Navigator.pop(context);
      _showError(context, '网络请求失败，请检查服务: $e');
      return null;
    } finally {
      // 释放资源
      progressNotifier.dispose();
      rawOutputNotifier.dispose();
    }
  }

// 2. 解析方法：加入强校验机制，防止 AI 乱出数据格式
  static List<Course> parsePreviewCourses(Map<String, dynamic> data, String semesterId, AppState state) {
    List<Course> result = [];
    if (data['courses'] != null) {
      List<dynamic> coursesJson = data['courses'];

      Map<String, Color> courseColorMap = {};
      int colorIndex = 0;

      // 辅助方法：安全解析 int，哪怕 AI 返回了字符串 "1" 也能扛住
      int parseIntSafe(dynamic val, int defaultVal) {
        if (val == null) return defaultVal;
        if (val is int) return val;
        return int.tryParse(val.toString()) ?? defaultVal;
      }

      for (var courseMap in coursesJson) {
        String courseName = courseMap['name']?.toString() ?? '未知课程';

        if (!courseColorMap.containsKey(courseName)) {
          courseColorMap[courseName] = state.courseColors[colorIndex % state.courseColors.length];
          colorIndex++;
        }

        // 安全解析周次列表
        List<int> safeWeeks = [];
        if (courseMap['weeks'] is List) {
          for (var w in courseMap['weeks']) {
            if (w is int) {
              safeWeeks.add(w);
            } else {
              int? parsed = int.tryParse(w.toString());
              if (parsed != null) safeWeeks.add(parsed);
            }
          }
        }

        result.add(Course(
          id: DateTime.now().microsecondsSinceEpoch.toString() + '_' + result.length.toString(),
          semesterId: semesterId,
          name: courseName,
          room: courseMap['room']?.toString() ?? '',
          teacher: courseMap['teacher']?.toString() ?? '',
          color: courseColorMap[courseName]!,
          dayOfWeek: parseIntSafe(courseMap['dayOfWeek'], 1),
          startSlot: parseIntSafe(courseMap['startSlot'], 1),
          endSlot: parseIntSafe(courseMap['endSlot'], 2),
          weeks: safeWeeks,
        ));
      }
    }
    return result;
  }

  // 3. 辅助方法：修复由于 slotIndex 为 null 导致的奔溃问题
  static Future<void> applyTimeSlots(Map<String, dynamic> data, AppState state) async {
    if (data['timeSlots'] != null) {
      List<dynamic> slotsJson = data['timeSlots'];
      for (var slotMap in slotsJson) {
        // 1. 防御性检查：防止 AI 漏掉该字段
        var rawIndex = slotMap['slot'] ?? slotMap['slotIndex'];
        if (rawIndex == null) continue; // 如果为 null 直接跳过，不强行解析

        // 2. 防止 AI 将数字输出为字符串 "1"
        int? parsedIndex;
        if (rawIndex is int) {
          parsedIndex = rawIndex;
        } else {
          parsedIndex = int.tryParse(rawIndex.toString());
        }

        if (parsedIndex != null) {
          int index = parsedIndex - 1;
          // 3. 边界检查，防止越界
          if (index >= 0 && index < state.timeSlots.length) {
            String sTime = slotMap['startTime']?.toString() ?? state.timeSlots[index].startTime;
            String eTime = slotMap['endTime']?.toString() ?? state.timeSlots[index].endTime;
            await state.updateTimeSlot(index, sTime, eTime);
          }
        }
      }
    }
  }

  static void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }
}
