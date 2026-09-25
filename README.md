# AI Passport Phone

把一台闲置 Android 手机变成 Codex 桌面外设：待机时是带动画的角色壁纸，滑动后进入工作流监看、语音命令和个人名片等模块。Mac 与 Windows 管理端负责连接、模块选择、角色图片和整套配色。

![默认蓝鲸皮肤](previews/default-ocean-landscape.png)

## 功能

- 横屏左滑、竖屏上滑打开模块；反向滑动收回壁纸。
- Codex 任务以流式时间线显示。运行中的任务只读，空闲任务可接收确认后的语音命令。
- 手机录音在电脑本地通过 whisper.cpp 转写，手机预览并确认后才发送。
- 模块化功能列表：目前包含 Codex 监看和个人名片，桌面端可选择是否显示。
- 个人名片全屏展示姓名、自介、网站、邮箱和其他联系方式。
- 背景方案库以预览卡片展示内置和自定义方案，点击即可切换并同步到手机。
- 点击“添加背景方案”进入可视化编辑器，可实时预览角色、渐变背景和 7 个主题色；保存后自动生成新的方案卡片。
- 切换方案时，Mac 和 Windows 管理端的侧栏、画布、卡片、文字与按钮也会同步使用该方案配色。
- 内置“蓝鲸航线”和“午夜莓果”方案，支持为每个自定义方案单独保存透明 PNG 角色。
- USB 优先配对，同一局域网可通过蓝牙交换加密连接信息。数据通道使用证书指纹固定的 WSS。
- Android 沉浸式全屏、常亮、横竖屏响应布局和断线过期提示。

默认蓝色鲸鱼少女是为本项目生成的原创角色，没有使用 DeepSeek 商标或第三方同人图。用户上传的角色、配色、个人资料、令牌和证书只保存在本机应用数据目录。

## 安装

在 [Releases](../../releases) 下载：

- `AI-Passport-Android-v0.3.1.apk`
- `AI-Passport-macOS-v0.3.1.zip`
- `AI-Passport-Windows-v0.3.1-x64.zip`

Android 端需要开启开发者选项和 USB 调试。桌面端点击“启动桥接”，再在手机输入六位配对码并点击“连接 / 配对”。USB 连接会自动配置 ADB 端口转发；Windows 包已包含 Android Platform Tools。局域网模式要求手机与电脑可以互相访问。

macOS 包使用临时签名，没有 Apple 公证。首次启动若被 Gatekeeper 拦截，请在 Finder 中右键应用并选择“打开”。Windows 包未做商业代码签名，SmartScreen 可能显示提示。

## 运行依赖

桌面端的状态监看需要已登录的 `codex` CLI。语音转写另需：

- `ffmpeg`
- `whisper-cli`（whisper.cpp）
- `ggml-base.bin`，放入应用数据目录

应用数据位置：

- macOS：`~/Library/Application Support/AI Passport/`
- Windows：`%APPDATA%/AI Passport/data/`

## 从源码构建

需要 Node.js 20+、JDK 17、Android SDK；构建 macOS 管理端还需要 Xcode Command Line Tools。

```sh
npm install --allow-git=all
npm test

# Android
cd android
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew assembleDebug

# macOS
cd ..
./mac/build-app.sh

# Windows x64（可在 macOS 交叉打包）
./scripts/download-windows-platform-tools.sh
npm run windows:build
```

Android APK 位于 `android/app/build/outputs/apk/debug/`，macOS 应用位于 `dist/`，Windows ZIP 位于 `release/windows/`。

## 工作方式

桥接程序合并 Codex App Server 的任务名称与本机 Codex JSONL 会话日志，向手机推送公开的进度和结果消息。它不发送内部推理或工具输出。独立 App Server 对桌面端活动任务的可见性有限，所以当前任务状态属于本机日志驱动的尽力同步。

电脑端本地控制 API 仅监听 `127.0.0.1` 并使用随机令牌。手机端 HTTPS/WSS 连接固定首次配对得到的证书指纹。六位配对码是短期配对门槛，请仅在可信网络中使用局域网模式。

## Root

核心功能不需要 Root。若要把 Redmi Note 9 5G 做成长期自启动设备，可参考 [ROOT.md](ROOT.md)。刷机前必须核实精确型号、固件与 bootloader 状态；解锁会清空数据。

## License

MIT。Android Platform Tools 不属于本项目，Windows 发布包中附带其原始 `NOTICE.txt`。
