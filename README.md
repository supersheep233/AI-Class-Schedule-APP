# Class Schedule

一款基于 Flutter 的跨平台课表管理应用，支持课程管理、学期切换、时间段自定义、本地数据库备份导入导出，以及通过图片识别课表的 AI 导入流程。项目同时包含一个 Python 后端，用于接入 Kimi / Moonshot AI 的课表解析接口。

项目由AI开发，主要是为了我自己使用，解决市面上课程表臃肿且导入繁琐的问题，同时也希望能帮助到其他需要的同学。

当前只开发了安卓系统，IOS没有适配

## 主要功能

- 课表查看与编辑
- 学期管理与周次切换
- 自定义每天节数与上课时间
- 午休、晚休分隔线显示控制
- SQLite 本地持久化存储
- 课表数据库备份、导出、导入
- Android 桌面小组件同步展示今日课程
- 通过上传课表图片进行 AI 识别导入

## APP使用

- 安卓设备；到Realese下载APK，安装即可
- 若不使用AI导入功能，可以正常作为课程表软件手动导入使用
- 若使用AI导入功能，需要创建服务器，可以使用局域网内设备运行server.py，填入API_KEY，在APP侧边输入服务器IP，即可使用

## 项目结构

```text
class_schedule/
├── lib/                # Flutter 主应用
├── android/            # Android 原生工程与小组件
├── ios/                # iOS 原生工程
├── web/                # Web 构建入口
├── windows/            # Windows 桌面工程
├── macos/              # macOS 桌面工程
├── linux/              # Linux 桌面工程
├── server/             # FastAPI + AI 解析后端
├── test/               # Flutter 测试
└── pubspec.yaml
```

## 环境要求

- Flutter 3.11 或更高版本
- Dart 3.x
- Python 3.10+
- 可用的 Moonshot / Kimi API Key

## 本地运行

### 1. 安装依赖

```bash
flutter pub get
```

### 2. 启动后端

进入 `server/` 目录并安装 Python 依赖：

```bash
cd server
python -m venv .venv
.venv\Scripts\activate
pip install fastapi uvicorn openai python-multipart
```

设置环境变量后启动服务：

```powershell
$env:MOONSHOT_API_KEY="你的_API_KEY"
python -m uvicorn server:app --host 0.0.0.0 --port 8000
```

如果你使用的是其他终端，请将 `MOONSHOT_API_KEY` 配置为同名环境变量即可。

### 3. 启动 Flutter 应用

回到项目根目录后运行：

```bash
flutter run
```

如果你要测试 AI 导入功能，请确保 Flutter 端的后端地址配置正确。当前项目已支持在应用内保存服务器地址，默认使用本地地址，你可以在侧边栏里改成自己的后端地址。

## AI 识别接口说明

后端提供的核心接口为：

```text
POST /api/parse_schedule
```

请求体为上传的课表图片，响应为 `application/x-ndjson` 流式数据。前端会实时接收：

- `progress`：进度提示
- `generating`：模型输出片段
- `success`：最终解析结果
- `error`：错误信息

## 数据存储

应用使用 SQLite 保存以下内容：

- 学期信息
- 课程信息
- 时间段信息
- 当前周次与显示设置

还支持将数据库导出为 `.db` 文件，方便备份与迁移。

## 运行测试

```bash
flutter test
```
