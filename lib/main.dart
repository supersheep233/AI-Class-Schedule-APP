import 'package:flutter/material.dart';
// 引入页面统一管理文件
import 'screens/screens.dart';

/// 应用入口函数
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClassScheduleApp());
}

/// 课表应用的主组件，配置应用的全局状态和主题
class ClassScheduleApp extends StatelessWidget {
  const ClassScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 应用在后台任务管理器中显示的名称
      title: 'AI 智能课表',
      
      // 全局主题配置
      theme: ThemeData(
        // 以靛蓝色为种子色生成配色方案
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        // 启用 Material 3 设计规范
        useMaterial3: true,
        // 应用栏 (AppBar) 的统一配置
        appBarTheme: const AppBarTheme(
          centerTitle: true, // 标题居中显示
        ),
      ),
      
      // 设置应用的首页为课表主界面
      home: const MainScheduleScreen(),
      
      // 隐藏调试模式下的右上角红色横幅
      debugShowCheckedModeBanner: false,
    );
  }
}
