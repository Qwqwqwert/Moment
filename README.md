# Moment

Moment 是一个本地优先的笔记与待办应用，支持 Markdown 笔记、标签管理、媒体附件、待办提醒和 AI 辅助功能。

## 主要功能

- 笔记创建、编辑、搜索、收藏和回收站
- Markdown 内容和代码高亮
- 图片、视频、音频附件
- 待办事项、优先级、重复规则和提醒
- 标签管理与成就统计
- AI 标签生成和自然语言搜索
- 支持 Android、Windows、Linux 和 Web

## 数据存储

应用采用本地优先设计：

- SQLite 保存笔记、待办、标签和成就数据
- 本地文件系统保存图片、视频和音频附件
- 不依赖远程服务器即可使用核心功能

## 运行环境

### Android

- Android 5.0（API 21）及以上
- 图片、录音和通知功能需要相应系统权限
- AI 功能需要网络连接

### Linux

- 64 位 x86_64 Linux 桌面环境
- GTK 3、X11 或 Wayland
- 录音功能需要安装：

  ```bash
  sudo apt install ffmpeg pulseaudio-utils
  ```

- GNOME Keyring 或 KWallet 可用于安全保存 AI API Key

Linux 当前主要面向 x86_64；ARM64 设备需要重新构建 ARM64 版本。

## 项目结构

```text
lib/models/       数据模型
lib/data/         SQLite 仓储和附件存储
lib/screens/      页面和业务界面
lib/services/     AI、提醒和平台服务
lib/state/        全局状态管理
lib/widgets/      可复用组件
android/          Android 平台工程
linux/            Linux 平台工程
windows/          Windows 平台工程
web/              Web 平台工程
test/             自动化测试
```

## 构建示例

```bash
flutter pub get
flutter build apk --release
flutter build linux --release
flutter build windows --release
```

核心业务数据默认保存在本地，使用前请根据需要配置 AI 服务地址、模型名称和 API Key。
