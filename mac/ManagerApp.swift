import AppKit
import SwiftUI

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255)
    }
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(rgb: value)
    }
    init(mixing first: String, with second: String, amount: Double) {
        let a = UInt32(first.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        let b = UInt32(second.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        let t = max(0, min(1, amount))
        func channel(_ shift: UInt32) -> Double {
            Double((a >> shift) & 255) * (1 - t) + Double((b >> shift) & 255) * t
        }
        self.init(red: channel(16) / 255, green: channel(8) / 255, blue: channel(0) / 255)
    }
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255),
                      Int(color.greenComponent * 255), Int(color.blueComponent * 255))
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
    var schemeId: String? = "ocean"
    var theme = "ocean"
    var character = "default"
    var colors = PassportColors()
    var revision: Int64 = 0
}

private struct PassportScheme: Codable, Identifiable {
    var id: String
    var name: String
    var note: String
    var builtIn: Bool? = false
    var appearance: PassportAppearance
}

private struct AppearanceLibrary: Codable {
    var activeId: String
    var schemes: [PassportScheme]
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

private struct PhoneModuleDefinition: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var shortName: String
    var category: String
    var summary: String
    var icon: String
    var phoneIcon: String
    var settings: String
    var features: [String]
}

private let defaultModuleCatalog = [
    PhoneModuleDefinition(id: "codex", name: "Codex 工作流", shortName: "Codex 监看", category: "工作",
        summary: "实时查看任务进度，并通过确认后的语音命令创建或继续任务。",
        icon: "waveform.path", phoneIcon: "◉", settings: "codex",
        features: ["实时任务流", "语音命令", "断线状态"]),
    PhoneModuleDefinition(id: "profile", name: "个人名片", shortName: "个人名片", category: "展示",
        summary: "在手机上展示自我介绍、个人网站和联系方式。",
        icon: "person.crop.rectangle", phoneIcon: "✦", settings: "profile",
        features: ["个人简介", "联系方式", "全屏展示"])
]

private struct BridgeStatus: Decodable {
    let pairingCode: String
    let connected: Bool
    let bluetoothReady: Bool
    let theme: String
    let appearance: PassportAppearance
    let appearanceSchemes: [PassportScheme]?
    let activeSchemeId: String?
    let modules: PassportModules
    let moduleCatalog: [PhoneModuleDefinition]?
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
    @Published var appearanceSchemes: [PassportScheme] = [
        PassportScheme(id: "ocean", name: "蓝鲸航线", note: "深海蓝 · 发光青", builtIn: true,
                       appearance: PassportAppearance()),
        PassportScheme(id: "midnight", name: "午夜莓果", note: "柔和夜色 · 暖金星点", builtIn: true,
                       appearance: PassportAppearance(schemeId: "midnight", theme: "midnight", character: "default",
                         colors: PassportColors(backgroundStart: "#171925", backgroundEnd: "#403042", surface: "#282536",
                           ink: "#FFEDE5", muted: "#CCB3B3", accent: "#E9A895", line: "#64505F"), revision: 0))
    ]
    @Published var activeSchemeId = "ocean"
    @Published var modules = PassportModules()
    @Published var moduleCatalog = defaultModuleCatalog
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
        if let data = try? Data(contentsOf: dataDir.appendingPathComponent("schemes.json")),
           let saved = try? JSONDecoder().decode(AppearanceLibrary.self, from: data) {
            appearanceSchemes = saved.schemes; activeSchemeId = saved.activeId
            if let selected = saved.schemes.first(where: { $0.id == saved.activeId }) {
                appearance = selected.appearance; theme = selected.appearance.theme
            }
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
            if let schemes = status.appearanceSchemes { appearanceSchemes = schemes }
            if let active = status.activeSchemeId { activeSchemeId = active }
            appearance = status.appearance; appearanceLoaded = true
            if let catalog = status.moduleCatalog, !catalog.isEmpty { moduleCatalog = catalog }
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

    func schemeImage(_ id: String) -> NSImage? {
        NSImage(contentsOf: dataDir.appendingPathComponent("characters/\(id).png"))
    }

    func chooseCharacterData() -> (Data, NSImage)? {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png]
        picker.allowsMultipleSelection = false
        picker.message = "选择带透明背景的 PNG 角色图"
        guard picker.runModal() == .OK, let url = picker.url,
              let data = try? Data(contentsOf: url), data.count <= 8 * 1024 * 1024,
              let image = NSImage(data: data) else {
            message = "请选择小于 8 MB 的有效 PNG 图片"; return nil
        }
        return (data, image)
    }

    private func useLibrary(_ library: AppearanceLibrary) {
        appearanceSchemes = library.schemes
        activeSchemeId = library.activeId
        if let selected = library.schemes.first(where: { $0.id == library.activeId }) {
            appearance = selected.appearance; theme = selected.appearance.theme
        }
        appearanceLoaded = true
    }

    func activateScheme(_ id: String) {
        guard let selected = appearanceSchemes.first(where: { $0.id == id }) else { return }
        Task {
            do {
                if running {
                    let body = try JSONSerialization.data(withJSONObject: ["id": id])
                    useLibrary(try JSONDecoder().decode(AppearanceLibrary.self,
                        from: await request("/schemes/activate", method: "POST", body: body)))
                } else {
                    activeSchemeId = id; appearance = selected.appearance; theme = selected.appearance.theme
                    let library = AppearanceLibrary(activeId: id, schemes: appearanceSchemes)
                    try JSONEncoder().encode(library).write(to: dataDir.appendingPathComponent("schemes.json"), options: .atomic)
                    try JSONEncoder().encode(appearance).write(to: dataDir.appendingPathComponent("appearance.json"), options: .atomic)
                }
                message = phoneConnected ? "电脑界面与手机背景方案已同步切换" : "电脑界面背景方案已切换"
            } catch { message = "切换方案失败：\(error.localizedDescription)" }
        }
    }

    func saveScheme(name: String, note: String, draft: PassportAppearance, image: Data?, completion: @escaping (Bool) -> Void) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { message = "请填写方案名称"; completion(false); return }
        let values = Mirror(reflecting: draft.colors).children.compactMap { $0.value as? String }
        guard values.allSatisfy({ $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }) else {
            message = "颜色必须使用 #RRGGBB 格式"; completion(false); return
        }
        let id = "custom-" + UUID().uuidString.lowercased()
        var next = draft
        next.schemeId = id; next.theme = "custom"; next.character = image == nil ? "default" : "custom"
        next.revision = Int64(Date().timeIntervalSince1970 * 1000)
        Task {
            do {
                var object: [String: Any] = ["id": id, "name": title, "note": String(note.prefix(80)),
                    "appearance": try JSONSerialization.jsonObject(with: JSONEncoder().encode(next))]
                if let image { object["imageBase64"] = image.base64EncodedString() }
                if running {
                    let body = try JSONSerialization.data(withJSONObject: object)
                    useLibrary(try JSONDecoder().decode(AppearanceLibrary.self,
                        from: await request("/schemes", method: "POST", body: body)))
                } else {
                    let scheme = PassportScheme(id: id, name: title, note: String(note.prefix(80)), appearance: next)
                    appearanceSchemes.append(scheme); activeSchemeId = id; appearance = next; theme = "custom"
                    let library = AppearanceLibrary(activeId: id, schemes: appearanceSchemes)
                    try JSONEncoder().encode(library).write(to: dataDir.appendingPathComponent("schemes.json"), options: .atomic)
                    try JSONEncoder().encode(next).write(to: dataDir.appendingPathComponent("appearance.json"), options: .atomic)
                    if let image {
                        let directory = dataDir.appendingPathComponent("characters", isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try image.write(to: directory.appendingPathComponent("\(id).png"), options: .atomic)
                    }
                }
                message = phoneConnected ? "新方案已保存并同步到手机" : "新方案已保存"
                completion(true)
            } catch { message = "保存方案失败：\(error.localizedDescription)"; completion(false) }
        }
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
    @State private var editingAppearance = false
    @State private var draftName = ""
    @State private var draftNote = ""
    @State private var draftAppearance = PassportAppearance(theme: "custom")
    @State private var draftImage: NSImage?
    @State private var draftImageData: Data?
    @State private var selectedModuleId: String?
    private let character = NSImage(contentsOfFile: Bundle.main.path(forResource: "companion", ofType: "png") ?? "")
    private var uiColors: PassportColors { model.appearance.colors }
    private var uiCanvas: Color { Color(mixing: uiColors.surface, with: uiColors.accent, amount: 0.075) }
    private var uiCard: Color { Color(hex: uiColors.surface) }
    private var uiInk: Color { Color(hex: uiColors.ink) }
    private var uiMuted: Color { Color(hex: uiColors.muted) }
    private var uiAccent: Color { Color(hex: uiColors.accent) }
    private var uiLine: Color { Color(hex: uiColors.line) }
    private var uiSidebar: Color { Color(hex: uiColors.backgroundStart) }
    private var uiSidebarText: Color {
        previewIsDark(uiColors.backgroundStart, uiColors.backgroundEnd) ? .white : .black.opacity(0.84)
    }
    private var uiWallpaperText: Color {
        previewIsDark(uiColors.backgroundStart, uiColors.backgroundEnd) ? .white : .black.opacity(0.82)
    }

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
                                 page == .appearance ? "选好皮肤，手机会立即换上。" : "管理手机功能入口，并进入每个模块的独立设置。")
                                .font(.system(size: 13)).foregroundStyle(uiMuted)
                        }
                        Spacer()
                        statusPill
                    }
                    if page == .home { overview }
                    else if page == .appearance { appearance }
                    else { modulesPage }
                    Text(model.message).font(.system(size: 12)).foregroundStyle(uiMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(32)
            }
            .foregroundStyle(uiInk)
            .background(uiCanvas)
        }
        .frame(minWidth: 920, minHeight: 630)
        .animation(.easeInOut(duration: 0.28), value: model.activeSchemeId)
        .onAppear { model.begin() }
        .onDisappear { model.shutdown() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("✦  AI PASSPORT").font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(2).padding(.bottom, 6)
            Text("WORK COMPANION").font(.system(size: 10, weight: .medium))
                .tracking(3).foregroundStyle(uiSidebarText.opacity(0.55))
            Rectangle().fill(uiSidebarText.opacity(0.16)).frame(height: 1).padding(.vertical, 28)
            ForEach(Page.allCases, id: \.self) { item in
                Button { page = item; if item != .modules { selectedModuleId = nil } } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 15, weight: page == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .background(page == item ? uiSidebarText.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).padding(.bottom, 5)
            }
            Spacer()
            Text("REDMI  /  DESK EDITION").font(.system(size: 10, weight: .bold))
                .tracking(2).foregroundStyle(uiSidebarText.opacity(0.52))
        }
        .foregroundStyle(uiSidebarText)
        .padding(22).frame(width: 220)
        .background(uiSidebar)
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle().fill(model.phoneConnected ? Color(rgb: 0x60A783) : uiAccent)
                .frame(width: 8, height: 8)
            Text(model.phoneConnected ? "手机已连接" : model.running ? "等待手机" : "未启动")
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(uiCard, in: Capsule())
        .overlay(Capsule().stroke(uiLine, lineWidth: 1))
    }

    private var overview: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [Color(hex: uiColors.backgroundStart), Color(hex: uiColors.backgroundEnd)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if let hero = model.schemeImage(model.activeSchemeId) ?? character {
                    Image(nsImage: hero).resizable().scaledToFit()
                        .frame(width: 330, height: 330).offset(x: 320, y: 47)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("PAIRING CODE  /  配对码")
                        .font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(uiWallpaperText)
                    Text(model.pairingCode)
                        .font(.system(size: 58, weight: .bold, design: .serif)).tracking(5)
                        .monospacedDigit().foregroundStyle(uiWallpaperText)
                    Text("在手机 AI Passport 中输入这六位数字，\n点击「连接 / 配对」。USB 会被优先使用。")
                        .font(.system(size: 14)).foregroundStyle(uiWallpaperText.opacity(0.82))
                        .lineSpacing(5)
                }
                .padding(32)
            }
            .frame(height: 245).clipped().overlay(RoundedRectangle(cornerRadius: 24).stroke(uiLine))

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("桥接程序", caption: "MAC → REDMI")
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.running ? "正在运行" : "尚未启动").font(.system(size: 17, weight: .semibold))
                            Text(model.running ? "电脑正在同步 Codex 工作内容" : "点击启动，自动准备 USB 数据连接")
                                .font(.system(size: 12)).foregroundStyle(uiMuted)
                        }
                        Spacer()
                        Button(model.running ? "停止桥接" : "启动桥接") {
                            model.running ? model.stop() : model.start()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(uiAccent)
                    }
                    Picker("连接方式", selection: $model.transport) {
                        Text("USB").tag("USB")
                        Text("同一 Wi-Fi").tag("Wi-Fi")
                    }
                    .pickerStyle(.segmented).tint(uiAccent).disabled(model.running)
                    Text(model.transport == "USB"
                         ? "当前网络隔离时选 USB。启动时会自动设置 ADB 转发。"
                         : "手机和 Mac 需要处于可互访的同一局域网。")
                        .font(.system(size: 11)).foregroundStyle(uiMuted)
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(uiCard, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))

                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("实时状态", caption: "LIVE STATUS")
                    statusRow("手机连接", model.phoneConnected ? "已连接" : "等待配对")
                    statusRow("配对通道", model.transport == "USB" ? "USB 本地连接" : (model.bluetoothReady ? "蓝牙可配对" : "未就绪"))
                    statusRow("Codex 接口", model.codexConnected ? "已连接" : "未连接")
                    statusRow("可见任务", "\(model.taskCount) 个")
                    statusRow("数据地址", model.running ? model.host : "—")
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(uiCard, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))
            }
        }
    }

    private var appearance: some View {
        Group {
            if editingAppearance { appearanceEditor }
            else { appearanceLibrary }
        }
    }

    private var appearanceLibrary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("选择背景方案会立即同步到手机。自定义方案保存在这台电脑上。")
                    .font(.system(size: 13)).foregroundStyle(uiMuted)
                Spacer()
                Button { beginAppearanceEditor() } label: {
                    Label("添加背景方案", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).tint(uiAccent)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                ForEach(model.appearanceSchemes) { scheme in
                    schemeCard(scheme)
                }
                Button { beginAppearanceEditor() } label: {
                    VStack(spacing: 11) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 34))
                        Text("添加背景方案").font(.system(size: 16, weight: .semibold))
                        Text("角色、颜色与实时预览").font(.system(size: 12)).foregroundStyle(uiMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 310)
                    .background(uiCard, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(uiLine,
                        style: StrokeStyle(lineWidth: 1.5, dash: [7])))
                }
                .buttonStyle(.plain).foregroundStyle(uiAccent)
            }
        }
    }

    private var appearanceEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button("‹ 返回方案库") { editingAppearance = false }.buttonStyle(.plain).foregroundStyle(uiAccent)
                Spacer()
                Text("可视化背景编辑器").font(.system(size: 13, weight: .semibold)).foregroundStyle(uiMuted)
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("实时预览", caption: "LIVE PREVIEW")
                    appearancePreview(draftAppearance, image: draftImage ?? character)
                        .frame(minHeight: 390)
                }
                .padding(18).frame(maxWidth: .infinity)
                .background(uiCard, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))

                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("方案设置", caption: "NEW SCHEME")
                    profileField("方案名称", hint: "例如：樱花午后", text: $draftName)
                    profileField("方案说明", hint: "例如：淡粉 · 柔光", text: $draftNote)
                    HStack {
                        Button("选择角色 PNG") {
                            if let selected = model.chooseCharacterData() {
                                draftImageData = selected.0; draftImage = selected.1
                            }
                        }.buttonStyle(.borderedProminent).tint(uiAccent)
                        if draftImage != nil {
                            Button("使用默认角色") { draftImage = nil; draftImageData = nil }.buttonStyle(.plain)
                        }
                    }
                    Divider()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                        visualColorField("背景起点", value: $draftAppearance.colors.backgroundStart)
                        visualColorField("背景终点", value: $draftAppearance.colors.backgroundEnd)
                        visualColorField("卡片表面", value: $draftAppearance.colors.surface)
                        visualColorField("正文", value: $draftAppearance.colors.ink)
                        visualColorField("辅助文字", value: $draftAppearance.colors.muted)
                        visualColorField("强调色", value: $draftAppearance.colors.accent)
                        visualColorField("描边", value: $draftAppearance.colors.line)
                    }
                    Spacer(minLength: 4)
                    HStack {
                        Button("取消") { editingAppearance = false }.buttonStyle(.plain)
                        Spacer()
                        Button("保存并启用") {
                            model.saveScheme(name: draftName, note: draftNote,
                                             draft: draftAppearance, image: draftImageData) { saved in
                                if saved { editingAppearance = false }
                            }
                        }.buttonStyle(.borderedProminent).tint(uiAccent)
                            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20).frame(width: 360).frame(minHeight: 430, alignment: .topLeading)
                .background(uiCard, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))
            }
        }
    }

    private func beginAppearanceEditor() {
        draftName = ""; draftNote = ""
        draftAppearance = PassportAppearance(schemeId: nil, theme: "custom", character: "default",
                                             colors: model.appearance.colors, revision: 0)
        draftImage = nil; draftImageData = nil; editingAppearance = true
    }

    private var modulesPage: some View {
        Group {
            if let id = selectedModuleId { moduleSettingsPage(id) }
            else { moduleLibrary }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedModuleId)
    }

    private var moduleLibrary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("模块中心", caption: "PHONE MODULES")
                    Text("选择模块进入设置；启用后才会出现在手机的功能抽屉中。")
                        .font(.system(size: 12)).foregroundStyle(uiMuted)
                }
                Spacer()
                Text("已启用 \(model.modules.enabled.count) / \(model.moduleCatalog.count)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(uiAccent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(uiCanvas, in: Capsule())
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(model.moduleCatalog) { module in moduleCard(module) }
            }
            Button { selectedModuleId = "__developer__" } label: {
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 20)).foregroundStyle(uiAccent).frame(width: 34, height: 34)
                        .background(uiCanvas, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("接入新模块").font(.system(size: 14, weight: .semibold))
                        Text("查看统一清单、设置适配器与手机渲染器的接入结构")
                            .font(.system(size: 11)).foregroundStyle(uiMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(uiAccent)
                }
                .padding(15).background(uiCard, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(uiLine, style: StrokeStyle(lineWidth: 1, dash: [5])))
            }
            .buttonStyle(.plain)
        }
    }

    private func moduleCard(_ module: PhoneModuleDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { selectedModuleId = module.id } label: {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Image(systemName: module.icon).font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(uiAccent).frame(width: 48, height: 48)
                            .background(uiCanvas, in: RoundedRectangle(cornerRadius: 14))
                        Spacer()
                        Text(module.category.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.5)
                            .foregroundStyle(uiMuted)
                    }
                    Text(module.name).font(.system(size: 20, weight: .bold, design: .serif))
                    Text(module.summary).font(.system(size: 12)).foregroundStyle(uiMuted)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(module.features.prefix(3), id: \.self) { feature in
                            Text(feature).font(.system(size: 9, weight: .medium)).foregroundStyle(uiAccent)
                                .padding(.horizontal, 7).padding(.vertical, 5)
                                .background(uiCanvas, in: Capsule())
                        }
                    }
                    HStack {
                        Text("打开设置").font(.system(size: 12, weight: .semibold))
                        Spacer(); Image(systemName: "arrow.right")
                    }.foregroundStyle(uiAccent)
                }
            }
            .buttonStyle(.plain)
            Divider().overlay(uiLine)
            Toggle("显示在手机上", isOn: moduleEnabled(module.id))
                .toggleStyle(.switch).tint(uiAccent).font(.system(size: 12, weight: .medium))
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 265, alignment: .topLeading)
        .background(uiCard, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))
    }

    @ViewBuilder private func moduleSettingsPage(_ id: String) -> some View {
        if id == "__developer__" { moduleDeveloperGuide }
        else if let module = model.moduleCatalog.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 18) {
                moduleSettingsHeader(module)
                if module.settings == "profile" { profileModuleSettings }
                else { codexModuleSettings }
            }
        } else { moduleLibrary }
    }

    private func moduleSettingsHeader(_ module: PhoneModuleDefinition) -> some View {
        HStack(spacing: 15) {
            Button { selectedModuleId = nil } label: { Label("返回模块中心", systemImage: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(uiAccent)
            Rectangle().fill(uiLine).frame(width: 1, height: 34)
            Image(systemName: module.icon).font(.system(size: 22)).foregroundStyle(uiAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.name).font(.system(size: 20, weight: .bold, design: .serif))
                Text(module.summary).font(.system(size: 11)).foregroundStyle(uiMuted)
            }
            Spacer()
            Toggle("在手机上显示", isOn: moduleEnabled(module.id)).toggleStyle(.switch).tint(uiAccent)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(18).background(uiCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(uiLine))
    }

    private var codexModuleSettings: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("运行状态", caption: "LIVE SOURCE")
                statusRow("Codex 接口", model.codexConnected ? "已连接" : "未连接")
                statusRow("可见任务", "\(model.taskCount) 个")
                statusRow("手机连接", model.phoneConnected ? "已连接" : "等待配对")
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(uiCard, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("手机上的行为", caption: "BEHAVIOR")
                moduleInfoRow("波形", "任务更新以流式时间线显示")
                moduleInfoRow("mic.fill", "录音交给电脑本地转写")
                moduleInfoRow("checkmark.shield.fill", "转写内容确认后才发送")
                Text("此模块不需要额外配置。运行中的桌面任务保持只读。")
                    .font(.system(size: 11)).foregroundStyle(uiMuted).padding(.top, 4)
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(uiCard, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))
        }
    }

    private var profileModuleSettings: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("名片内容", caption: "PROFILE SETTINGS")
            Text("留空的项目不会显示在手机上。")
                .font(.system(size: 12)).foregroundStyle(uiMuted)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 13) {
                    profileField("姓名", hint: "你希望展示的名字", text: $model.modules.profile.name)
                    profileField("一句话介绍", hint: "例如：设计与代码的实践者", text: $model.modules.profile.headline)
                    profileField("个人网站", hint: "https://example.com", text: $model.modules.profile.website)
                    profileField("邮箱", hint: "name@example.com", text: $model.modules.profile.email)
                    profileField("其他联系方式", hint: "微信、电话或其他方式", text: $model.modules.profile.contact)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("自我介绍").font(.system(size: 12, weight: .semibold))
                    TextEditor(text: $model.modules.profile.bio)
                        .font(.system(size: 13)).scrollContentBackground(.hidden)
                        .padding(9).frame(minHeight: 245)
                        .background(uiCanvas, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(uiLine))
                }.frame(maxWidth: .infinity)
            }
            HStack { Spacer(); Button("保存并同步到手机") { model.saveModules() }
                .buttonStyle(.borderedProminent).tint(uiAccent) }
        }
        .padding(22).background(uiCard, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))
    }

    private var moduleDeveloperGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { selectedModuleId = nil } label: { Label("返回模块中心", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(uiAccent)
                Spacer(); Text("MODULE SDK").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(uiMuted)
            }
            sectionTitle("接入新模块", caption: "ONE ID · THREE ADAPTERS")
            Text("每个功能由一个稳定 ID 串起清单、电脑设置页和手机显示页。桥接程序负责保存配置并把同一份模块清单同步给所有端。")
                .font(.system(size: 13)).foregroundStyle(uiMuted).lineSpacing(4)
            HStack(alignment: .top, spacing: 14) {
                developerStep("1", "注册清单", "在 mac/modules.js 添加名称、说明、分类、图标、设置类型与能力标签。")
                developerStep("2", "实现设置", "Mac 和 Windows 按 settings 字段打开对应设置页，统一写入 /modules。")
                developerStep("3", "实现手机页", "Android 使用同一个模块 ID 注册显示页面，并从 snapshot 读取配置。")
            }
            Text("完整字段、数据流和检查清单见仓库 docs/MODULES.md。")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(uiAccent)
                .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(uiCanvas, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(22).background(uiCard, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(uiLine))
    }

    private func developerStep(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(number).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(uiAccent)
                .frame(width: 38, height: 38).background(uiCanvas, in: Circle())
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(uiMuted).lineSpacing(4)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(uiCanvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
    }

    private func moduleInfoRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).foregroundStyle(uiAccent).frame(width: 24)
            Text(text).font(.system(size: 12))
        }
    }

    private func moduleEnabled(_ id: String) -> Binding<Bool> {
        Binding(get: { model.modules.enabled.contains(id) }, set: { enabled in
            model.setModule(id, enabled: enabled); model.saveModules()
        })
    }

    private func profileField(_ title: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold))
            TextField(hint, text: text).textFieldStyle(.plain)
                .environment(\.colorScheme, .light)
                .font(.system(size: 13)).foregroundStyle(uiInk)
                .padding(.horizontal, 11).frame(height: 35)
                .background(uiCanvas, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(uiLine))
        }
    }

    private func visualColorField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold))
            HStack(spacing: 7) {
                ColorPicker("", selection: Binding(get: { Color(hex: value.wrappedValue) },
                    set: { value.wrappedValue = $0.hexString }), supportsOpacity: false)
                    .labelsHidden().frame(width: 24)
                TextField("#RRGGBB", text: value).textFieldStyle(.plain).environment(\.colorScheme, .light)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(uiInk)
            }
            .padding(.horizontal, 8).frame(height: 34)
            .background(uiCanvas, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(uiLine))
        }
    }

    private func schemeCard(_ scheme: PassportScheme) -> some View {
        Button { model.activateScheme(scheme.id) } label: {
            VStack(alignment: .leading, spacing: 13) {
                appearancePreview(scheme.appearance, image: model.schemeImage(scheme.id) ?? character)
                    .frame(height: 225)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scheme.name).font(.system(size: 20, weight: .bold, design: .serif))
                        Text(scheme.note.isEmpty ? "自定义背景方案" : scheme.note)
                            .font(.system(size: 12)).foregroundStyle(uiMuted)
                    }
                    Spacer()
                    Image(systemName: model.activeSchemeId == scheme.id ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundStyle(uiAccent)
                }
            }
            .padding(14)
            .background(uiCard, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .stroke(model.activeSchemeId == scheme.id ? uiAccent : uiLine,
                        lineWidth: model.activeSchemeId == scheme.id ? 2 : 1))
        }
        .buttonStyle(.plain).frame(maxWidth: .infinity)
    }

    private func appearancePreview(_ appearance: PassportAppearance, image: NSImage?) -> some View {
        GeometryReader { proxy in
            let dark = previewIsDark(appearance.colors.backgroundStart, appearance.colors.backgroundEnd)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 17)
                    .fill(LinearGradient(colors: [Color(hex: appearance.colors.backgroundStart),
                                                  Color(hex: appearance.colors.backgroundEnd)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(Color(hex: appearance.colors.accent).opacity(0.18))
                    .frame(width: proxy.size.height * 1.15).offset(x: proxy.size.width * 0.62, y: -proxy.size.height * 0.34)
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: proxy.size.width * 0.62, height: proxy.size.height * 1.05)
                        .offset(x: proxy.size.width * 0.39, y: proxy.size.height * 0.02)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("AI PASSPORT  ✦").font(.system(size: 9, weight: .bold)).tracking(1.4)
                    Text("12:48").font(.system(size: min(43, proxy.size.height * 0.2), weight: .bold, design: .serif))
                    Text("9 月 25 日 · 星期五").font(.system(size: 10))
                    Text("● 已连接").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 6)
                        .background(Color(hex: appearance.colors.surface), in: Capsule())
                        .foregroundStyle(Color(hex: appearance.colors.accent))
                }
                .foregroundStyle(dark ? Color.white : Color.black.opacity(0.82)).padding(18)
            }
            .clipped()
        }
    }

    private func previewIsDark(_ first: String, _ second: String) -> Bool {
        func brightness(_ value: String) -> Double {
            let number = UInt32(value.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
            return (0.2126 * Double((number >> 16) & 255) + 0.7152 * Double((number >> 8) & 255) + 0.0722 * Double(number & 255)) / 255
        }
        return (brightness(first) + brightness(second)) / 2 < 0.53
    }

    private func sectionTitle(_ title: String, caption: String) -> some View {
        HStack {
            Text(title).font(.system(size: 19, weight: .bold, design: .serif))
            Spacer()
            Text(caption).font(.system(size: 9, weight: .bold)).tracking(1.5)
                .foregroundStyle(uiMuted)
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(uiMuted)
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
