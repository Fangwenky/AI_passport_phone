import AppKit
import SwiftUI

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255)
    }
}

private enum Palette {
    static let paper = Color(rgb: 0xEAF7FF)
    static let cream = Color(rgb: 0xF7FCFF)
    static let cocoa = Color(rgb: 0x08233F)
    static let muted = Color(rgb: 0x527895)
    static let apple = Color(rgb: 0x1677FF)
    static let line = Color(rgb: 0xA9DDF5)
}

private struct PassportColors: Codable {
    var backgroundStart = "#061B3A"
    var backgroundEnd = "#0B4D80"
    var surface = "#EAF7FF"
    var ink = "#08233F"
    var muted = "#527895"
    var accent = "#1677FF"
    var line = "#A9DDF5"
}

private struct PassportAppearance: Codable {
    var theme = "ocean"
    var character = "default"
    var colors = PassportColors()
    var revision: Int64 = 0
}

private struct PassportProfile: Codable {
    var name = ""
    var headline = ""
    var bio = ""
    var website = ""
    var email = ""
    var contact = ""
}

private struct PassportModules: Codable {
    var enabled = ["codex", "profile"]
    var profile = PassportProfile()
}

private struct BridgeStatus: Decodable {
    let pairingCode: String
    let connected: Bool
    let bluetoothReady: Bool
    let theme: String
    let appearance: PassportAppearance
    let modules: PassportModules
    let taskCount: Int
    let codexConnected: Bool
    let host: String
}

@MainActor private final class ManagerModel: ObservableObject {
    @Published var running = false
    @Published var phoneConnected = false
    @Published var bluetoothReady = false
    @Published var codexConnected = false
    @Published var pairingCode = "------"
    @Published var theme = "ocean"
    @Published var appearance = PassportAppearance()
    @Published var modules = PassportModules()
    @Published var taskCount = 0
    @Published var host = ""
    @Published var transport = "USB"
    @Published var message = "正在检查桥接程序…"
    private var bridge: Process?
    private var timer: Timer?
    private var modulesLoaded = false
    private var appearanceLoaded = false

    private let project = Bundle.main.resourceURL!.appendingPathComponent("bridge", isDirectory: true)
    private let dataDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AI Passport", isDirectory: true)

    init() {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let file = dataDir.appendingPathComponent("appearance.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode(PassportAppearance.self, from: data) {
            appearance = saved; theme = saved.theme; appearanceLoaded = true
        }
        if let data = try? Data(contentsOf: dataDir.appendingPathComponent("modules.json")),
           let saved = try? JSONDecoder().decode(PassportModules.self, from: data) {
            modules = saved
            modulesLoaded = true
        }
    }

    func begin() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let token = try String(contentsOf: dataDir.appendingPathComponent("bridge-token"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3220\(path)")!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw NSError(domain: "AI Passport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "桥接程序没有接受这次操作"])
        }
        return data
    }

    func refresh() async {
        do {
            let status = try JSONDecoder().decode(BridgeStatus.self, from: await request("/status"))
            running = true
            phoneConnected = status.connected
            bluetoothReady = status.bluetoothReady
            codexConnected = status.codexConnected
            pairingCode = status.pairingCode.isEmpty ? "准备中" : status.pairingCode
            theme = status.theme
            if !appearanceLoaded { appearance = status.appearance; appearanceLoaded = true }
            if !modulesLoaded {
                modules = status.modules
                modulesLoaded = true
            }
            taskCount = status.taskCount
            host = status.host
            transport = status.host == "127.0.0.1" ? "USB" : "Wi-Fi"
            message = status.connected ? "手机已连接，任务流正在同步" :
                (transport == "USB" ? "桥接已启动，等待手机通过 USB 配对" :
                    (status.bluetoothReady ? "桥接已启动，等待手机配对" : "蓝牙广播未就绪，请检查 Mac 蓝牙权限"))
        } catch {
            running = false
            phoneConnected = false
            bluetoothReady = false
            codexConnected = false
            taskCount = 0
            pairingCode = "------"
            message = "桥接未运行。点击启动后，在手机里输入这里显示的配对码。"
        }
    }

    func start() {
        guard !running else { return }
        do {
            if transport == "USB" {
                let adb = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Android/sdk/platform-tools/adb")
                guard FileManager.default.isExecutableFile(atPath: adb.path) else {
                    message = "找不到 ADB。请先安装 Android Platform Tools。"; return
                }
                let reverse = Process()
                reverse.executableURL = adb
                reverse.arguments = ["reverse", "tcp:3219", "tcp:3219"]
                try reverse.run(); reverse.waitUntilExit()
                let pairingReverse = Process()
                pairingReverse.executableURL = adb
                pairingReverse.arguments = ["reverse", "tcp:3221", "tcp:3221"]
                try pairingReverse.run(); pairingReverse.waitUntilExit()
                guard reverse.terminationStatus == 0 && pairingReverse.terminationStatus == 0 else {
                    message = "USB 未连接或调试未授权，请检查手机后重试。"; return
                }
            }
            let log = dataDir.appendingPathComponent("manager-bridge.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log)
            try output.seekToEnd()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", "mac/bridge.js"]
            process.currentDirectoryURL = project
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            env["PASSPORT_BLE_BIN"] = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/Passport Bluetooth.app/Contents/MacOS/PassportBluetooth").path
            env["PASSPORT_DATA_DIR"] = dataDir.path
            if transport == "USB" { env["PASSPORT_HOST"] = "127.0.0.1" }
            else { env.removeValue(forKey: "PASSPORT_HOST") }
            process.environment = env
            process.standardOutput = output
            process.standardError = output
            try process.run()
            bridge = process
            message = "正在启动桥接程序…"
            Task { try? await Task.sleep(for: .seconds(1)); await refresh() }
        } catch { message = "启动失败：\(error.localizedDescription)" }
    }

    func stop() {
        Task {
            do {
                _ = try await request("/stop", method: "POST")
                message = "桥接程序正在停止…"
                try? await Task.sleep(for: .seconds(1))
                await refresh()
            } catch { message = "停止失败：\(error.localizedDescription)" }
        }
    }

    func shutdown() {
        timer?.invalidate()
        if bridge?.isRunning == true { bridge?.interrupt() }
    }

    func chooseTheme(_ value: String) {
        guard value == "ocean" || value == "midnight" else { return }
        appearance.theme = value
        appearance.character = "default"
        appearance.colors = value == "midnight"
            ? PassportColors(backgroundStart: "#171925", backgroundEnd: "#403042", surface: "#282536",
                             ink: "#FFEDE5", muted: "#CCB3B3", accent: "#E9A895", line: "#64505F")
            : PassportColors()
        saveAppearance()
    }

    func chooseCharacter() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png]
        picker.allowsMultipleSelection = false
        picker.message = "选择带透明背景的 PNG 角色图"
        guard picker.runModal() == .OK, let url = picker.url, let data = try? Data(contentsOf: url), data.count <= 8 * 1024 * 1024 else {
            message = "请选择小于 8 MB 的 PNG 图片"; return
        }
        appearance.theme = "custom"; appearance.character = "custom"; appearance.revision = Int64(Date().timeIntervalSince1970 * 1000)
        saveAppearance(image: data)
    }

    func saveAppearance(image: Data? = nil) {
        let values = Mirror(reflecting: appearance.colors).children.compactMap { $0.value as? String }
        guard values.allSatisfy({ $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }) else {
            message = "颜色必须使用 #RRGGBB 格式"; return
        }
        appearance.theme = appearance.theme == "custom" ? "custom" : appearance.theme
        Task {
            do {
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance)) as! [String: Any]
                if let image { object["imageBase64"] = image.base64EncodedString() }
                let body = try JSONSerialization.data(withJSONObject: object)
                if running { _ = try await request("/appearance", method: "POST", body: body) }
                else {
                    try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
                    try JSONEncoder().encode(appearance).write(to: dataDir.appendingPathComponent("appearance.json"), options: .atomic)
                    if let image { try image.write(to: dataDir.appendingPathComponent("custom-character.png"), options: .atomic) }
                }
                theme = appearance.theme
                appearanceLoaded = true
                message = phoneConnected ? "皮肤已同步到手机" : "皮肤已保存，手机连接后会自动同步"
            } catch { message = "保存皮肤失败：\(error.localizedDescription)" }
        }
    }

    func setModule(_ id: String, enabled: Bool) {
        if enabled && !modules.enabled.contains(id) { modules.enabled.append(id) }
        if !enabled { modules.enabled.removeAll { $0 == id } }
    }

    func saveModules() {
        let fields = [(modules.profile.name, 80), (modules.profile.headline, 120),
                      (modules.profile.bio, 4000), (modules.profile.website, 200),
                      (modules.profile.email, 160), (modules.profile.contact, 200)]
        guard fields.allSatisfy({ $0.0.utf16.count <= $0.1 }) else {
            message = "名片内容过长，请精简后再保存。"; return
        }
        Task {
            do {
                let data = try JSONEncoder().encode(modules)
                if running {
                    _ = try await request("/modules", method: "POST", body: data)
                    message = phoneConnected ? "功能与名片已同步到手机" : "设置已保存，手机连接后会同步"
                } else {
                    let file = dataDir.appendingPathComponent("modules.json")
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try data.write(to: file, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    message = "功能与名片已保存，启动桥接后会同步"
                }
                modulesLoaded = true
            } catch { message = "保存失败：\(error.localizedDescription)" }
        }
    }
}

private enum Page: String, CaseIterable {
    case home = "总览"
    case appearance = "外观"
    case modules = "手机功能"
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .appearance: return "paintpalette.fill"
        case .modules: return "square.stack.3d.up.fill"
        }
    }
}

private struct ManagerView: View {
    @StateObject private var model = ManagerModel()
    @State private var page: Page = .home
    private let character = NSImage(contentsOfFile: Bundle.main.path(forResource: "companion", ofType: "png") ?? "")

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(page == .home ? "桌面工作台" : page == .appearance ? "外观皮肤" : "手机功能")
                                .font(.system(size: 32, weight: .bold, design: .serif))
                            Text(page == .home ? "连接、配对和运行状态都在这里。" :
                                 page == .appearance ? "选好皮肤，手机会立即换上。" : "决定手机里出现哪些功能，并编辑个人名片。")
                                .font(.system(size: 13)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        statusPill
                    }
                    if page == .home { overview }
                    else if page == .appearance { appearance }
                    else { modulesPage }
                    Text(model.message).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(32)
            }
            .foregroundStyle(Palette.cocoa)
            .background(Palette.paper)
        }
        .frame(minWidth: 920, minHeight: 630)
        .onAppear { model.begin() }
        .onDisappear { model.shutdown() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("✦  AI PASSPORT").font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(2).padding(.bottom, 6)
            Text("WORK COMPANION").font(.system(size: 10, weight: .medium))
                .tracking(3).foregroundStyle(Color.white.opacity(0.55))
            Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1).padding(.vertical, 28)
            ForEach(Page.allCases, id: \.self) { item in
                Button { page = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 15, weight: page == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .background(page == item ? Color.white.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).padding(.bottom, 5)
            }
            Spacer()
            Text("REDMI  /  DESK EDITION").font(.system(size: 10, weight: .bold))
                .tracking(2).foregroundStyle(Color.white.opacity(0.52))
        }
        .foregroundStyle(Color.white)
        .padding(22).frame(width: 220)
        .background(Palette.cocoa)
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle().fill(model.phoneConnected ? Color(rgb: 0x60A783) : Palette.apple)
                .frame(width: 8, height: 8)
            Text(model.phoneConnected ? "手机已连接" : model.running ? "等待手机" : "未启动")
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(Palette.cream, in: Capsule())
        .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }

    private var overview: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [Color(rgb: 0xFFF7E9), Color(rgb: 0xF2D7CE)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if let character {
                    Image(nsImage: character).resizable().scaledToFit()
                        .frame(width: 330, height: 330).offset(x: 320, y: 47)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("PAIRING CODE  /  配对码")
                        .font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(Palette.apple)
                    Text(model.pairingCode)
                        .font(.system(size: 58, weight: .bold, design: .serif)).tracking(5)
                        .monospacedDigit().foregroundStyle(Palette.cocoa)
                    Text("在手机 AI Passport 中输入这六位数字，\n点击「连接 / 配对」。USB 会被优先使用。")
                        .font(.system(size: 14)).foregroundStyle(Palette.cocoa.opacity(0.8))
                        .lineSpacing(5)
                }
                .padding(32)
            }
            .frame(height: 245).clipped().overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line))

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("桥接程序", caption: "MAC → REDMI")
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.running ? "正在运行" : "尚未启动").font(.system(size: 17, weight: .semibold))
                            Text(model.running ? "电脑正在同步 Codex 工作内容" : "点击启动，自动准备 USB 数据连接")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button(model.running ? "停止桥接" : "启动桥接") {
                            model.running ? model.stop() : model.start()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.apple)
                    }
                    Picker("连接方式", selection: $model.transport) {
                        Text("USB").tag("USB")
                        Text("同一 Wi-Fi").tag("Wi-Fi")
                    }
                    .pickerStyle(.segmented).tint(Palette.apple).disabled(model.running)
                    Text(model.transport == "USB"
                         ? "当前网络隔离时选 USB。启动时会自动设置 ADB 转发。"
                         : "手机和 Mac 需要处于可互访的同一局域网。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))

                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("实时状态", caption: "LIVE STATUS")
                    statusRow("手机连接", model.phoneConnected ? "已连接" : "等待配对")
                    statusRow("配对通道", model.transport == "USB" ? "USB 本地连接" : (model.bluetoothReady ? "蓝牙可配对" : "未就绪"))
                    statusRow("Codex 接口", model.codexConnected ? "已连接" : "未连接")
                    statusRow("可见任务", "\(model.taskCount) 个")
                    statusRow("数据地址", model.running ? model.host : "—")
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("选择预设，或上传透明 PNG 并用十六进制颜色设计自己的桌面伙伴。")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
            HStack(alignment: .top, spacing: 18) {
                themeCard("ocean", name: "蓝鲸航线", note: "深海蓝 · 发光青", dark: false)
                themeCard("midnight", name: "午夜莓果", note: "柔和夜色 · 暖金星点", dark: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("自定义角色与风格", caption: "CUSTOM SKIN")
                HStack {
                    Button("选择角色 PNG") { model.chooseCharacter() }
                        .buttonStyle(.borderedProminent).tint(Palette.apple)
                    Text(model.appearance.character == "custom" ? "已使用本地角色" : "当前使用默认蓝鲸角色")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    colorField("背景起点", text: $model.appearance.colors.backgroundStart)
                    colorField("背景终点", text: $model.appearance.colors.backgroundEnd)
                    colorField("卡片表面", text: $model.appearance.colors.surface)
                    colorField("正文", text: $model.appearance.colors.ink)
                    colorField("辅助文字", text: $model.appearance.colors.muted)
                    colorField("强调色", text: $model.appearance.colors.accent)
                    colorField("描边", text: $model.appearance.colors.line)
                }
                HStack { Spacer(); Button("保存自定义风格") {
                    model.appearance.theme = "custom"; model.saveAppearance()
                }.buttonStyle(.borderedProminent).tint(Palette.apple) }
            }
            .padding(22).background(Palette.cream, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
        }
    }

    private var modulesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("显示在手机上", caption: "MODULES")
                    Text("打开手机功能页时，只显示已启用的入口。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    moduleToggle("Codex 监看", detail: "实时进度 · 语音命令", id: "codex", symbol: "waveform.path")
                    moduleToggle("个人名片", detail: "自我介绍 · 网站 · 联系方式", id: "profile", symbol: "person.crop.rectangle")
                    Text("收起后再次展开，会回到手机上次打开的功能。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                .padding(22).frame(width: 275, alignment: .leading)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))

                VStack(alignment: .leading, spacing: 15) {
                    sectionTitle("个人名片", caption: "ABOUT ME")
                    Text("填写的内容会显示在已配对的手机上；留空的项目不会出现。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    profileField("姓名", hint: "你希望展示的名字", text: $model.modules.profile.name)
                    profileField("一句话介绍", hint: "例如：设计与代码的实践者", text: $model.modules.profile.headline)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("自我介绍").font(.system(size: 12, weight: .semibold))
                        TextEditor(text: $model.modules.profile.bio)
                            .font(.system(size: 13)).scrollContentBackground(.hidden)
                            .padding(7).frame(height: 140)
                            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
                    }
                    profileField("个人网站", hint: "https://example.com", text: $model.modules.profile.website)
                    profileField("邮箱", hint: "name@example.com", text: $model.modules.profile.email)
                    profileField("其他联系方式", hint: "微信、电话或其他方式", text: $model.modules.profile.contact)
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
            }
            HStack {
                Spacer()
                Button("保存并同步到手机") { model.saveModules() }
                    .buttonStyle(.borderedProminent).tint(Palette.apple)
            }
        }
    }

    private func moduleToggle(_ title: String, detail: String, id: String, symbol: String) -> some View {
        let enabled = model.modules.enabled.contains(id)
        return Button { model.setModule(id, enabled: !enabled) } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Palette.apple)
                    .frame(width: 27)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21)).foregroundStyle(enabled ? Palette.apple : Palette.muted)
            }
        }
        .buttonStyle(.plain).accessibilityValue(enabled ? "已启用" : "已关闭")
        .padding(12)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
    }

    private func profileField(_ title: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold))
            TextField(hint, text: text).textFieldStyle(.plain)
                .environment(\.colorScheme, .light)
                .font(.system(size: 13)).foregroundStyle(Palette.cocoa)
                .padding(.horizontal, 11).frame(height: 35)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        }
    }

    private func colorField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold))
            TextField("#RRGGBB", text: text).textFieldStyle(.plain).environment(\.colorScheme, .light)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.cocoa)
                .padding(.horizontal, 10).frame(height: 34)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line))
        }
    }

    private func themeCard(_ id: String, name: String, note: String, dark: Bool) -> some View {
        Button { model.chooseTheme(id) } label: {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(dark ? Color(rgb: 0x252333) : Color(rgb: 0x0B4D80))
                    if let character {
                        Image(nsImage: character).resizable().scaledToFit()
                            .frame(width: 245, height: 245).offset(x: 70, y: 57)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("12:48").font(.system(size: 42, weight: .bold, design: .serif))
                        Text("9 月 20 日 · 星期日").font(.system(size: 11))
                        Text("● 已连接").font(.system(size: 11, weight: .semibold)).padding(7)
                            .background(dark ? Color(rgb: 0x383344) : .white, in: Capsule())
                    }
                    .foregroundStyle(Color.white)
                    .padding(20)
                }
                .frame(height: 250).clipped()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.system(size: 20, weight: .bold, design: .serif))
                        Text(note).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: model.theme == id ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundStyle(Palette.apple)
                }
            }
            .padding(14)
            .background(Palette.cream, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .stroke(model.theme == id ? Palette.apple : Palette.line, lineWidth: model.theme == id ? 2 : 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ title: String, caption: String) -> some View {
        HStack {
            Text(title).font(.system(size: 19, weight: .bold, design: .serif))
            Spacer()
            Text(caption).font(.system(size: 9, weight: .bold)).tracking(1.5)
                .foregroundStyle(Palette.muted)
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.muted)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.system(size: 12))
    }
}

@main private struct PassportManagerApp: App {
    var body: some Scene {
        WindowGroup("AI Passport") { ManagerView() }
            .windowStyle(.hiddenTitleBar)
    }
}
