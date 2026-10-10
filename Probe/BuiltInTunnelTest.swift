import SwiftUI
import NetworkExtension
import Combine

@MainActor final class BuiltInTunnelTest: ObservableObject {
    @Published private(set) var status = "正在读取隧道配置…"
    @Published private(set) var busy = false
    @Published private(set) var connectionStatus: NEVPNStatus = .invalid
    @Published private(set) var errorText: String?
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var attempt = UUID()
    private var identifier: String { (Bundle.main.bundleIdentifier ?? "com.shaoyou11.airbeep.tunneltest") + ".tunnel" }
    var canStop: Bool { [.connected, .connecting, .reasserting].contains(connectionStatus) }
    var report: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "AirBeep 隧道测试 · 构建 \(build)\n\(status)\n\(errorText ?? "无错误记录")\n系统：\(UIDevice.current.systemVersion)"
    }
    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] notification in
            let connection = notification.object as? NEVPNConnection
            Task { @MainActor [weak self] in
                guard let self, connection === self.manager?.connection else { return }
                self.updateStatus()
            }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private func updateStatus() {
        connectionStatus = manager?.connection.status ?? .invalid
        switch connectionStatus {
        case .connected: status = "内置隧道已连接"
        case .connecting: status = "正在连接…"
        case .disconnecting: status = "正在断开…"
        case .disconnected: status = "隧道已断开"
        case .reasserting: status = "正在恢复连接…"
        default: status = "尚未创建 VPN 配置"
        }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let existing = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = existing.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == identifier }
            updateStatus()
        } catch { record(error) }
    }
    private func record(_ error: Error) {
        let e = error as NSError
        errorText = "\(e.localizedDescription)\n\(e.domain) · \(e.code)"
    }
    func connect() async {
        guard !busy, !canStop, connectionStatus != .disconnecting else { return }
        busy = true; errorText = nil
        let current = UUID(); attempt = current
        defer { if attempt == current { busy = false } }
        do {
            let existing = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = existing.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == identifier } ?? NETunnelProviderManager()
            let p = NETunnelProviderProtocol(); p.providerBundleIdentifier = identifier
            p.serverAddress = "本机设备隧道"; p.providerConfiguration = ["localAddress":"10.7.0.2/30"]
            m.protocolConfiguration = p; m.localizedDescription = "AirBeep 隧道测试"; m.isEnabled = true
            try await m.saveToPreferences(); try await m.loadFromPreferences(); manager = m
            guard attempt == current else { return }
            try m.connection.startVPNTunnel(); updateStatus()
            for _ in 0..<40 {
                try await Task.sleep(for: .milliseconds(500))
                guard attempt == current else { return }
                updateStatus()
                if connectionStatus == .connected { return }
                if connectionStatus == .disconnected || connectionStatus == .invalid { break }
            }
            errorText = "连接未完成。请检查 VPN 配置、扩展签名和系统兼容性，可重试并分享诊断。"
            m.connection.fetchLastDisconnectError { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.attempt == current, let error else { return }
                    self.record(error)
                }
            }
            m.connection.stopVPNTunnel(); updateStatus()
        } catch { updateStatus(); record(error) }
    }
    func stop() {
        attempt = UUID(); busy = false
        manager?.connection.stopVPNTunnel(); updateStatus()
    }
}
struct TunnelTestPanel: View {
    @StateObject private var tunnel = BuiltInTunnelTest()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tunnel.status, systemImage: tunnel.connectionStatus == .connected ? "checkmark.shield.fill" : "network")
                .font(.headline).foregroundStyle(tunnel.connectionStatus == .connected ? .green : .primary)
            if tunnel.busy { ProgressView("正在处理…").font(.caption) }
            if let error = tunnel.errorText {
                Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button("连接") { Task { await tunnel.connect() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(tunnel.busy || tunnel.canStop || tunnel.connectionStatus == .disconnecting)
                Button("断开") { tunnel.stop() }.buttonStyle(.bordered).disabled(!tunnel.canStop)
                Spacer()
                Button { Task { await tunnel.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新隧道状态").disabled(tunnel.busy)
            }.controlSize(.large)
            ShareLink(item: tunnel.report) { Label("分享诊断", systemImage: "square.and.arrow.up") }.font(.subheadline)
            Text("连接可能切换当前 VPN。已连接仅代表扩展启动，不代表配对或其他功能已经通过验证。")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .task { await tunnel.refresh() }
            .onChange(of: scenePhase) { _, value in if value == .active { Task { await tunnel.refresh() } } }
    }
}
