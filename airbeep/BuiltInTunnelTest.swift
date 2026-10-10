import SwiftUI
import NetworkExtension
import Combine

@MainActor final class BuiltInTunnelTest: ObservableObject {
    @Published var status = "尚未检查"
    @Published var busy = false
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var identifier: String { (Bundle.main.bundleIdentifier ?? "com.shaoyou11.airbeep.tunneltest") + ".tunnel" }
    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private func updateStatus() {
        switch manager?.connection.status ?? .invalid {
        case .connected: status = "内置隧道已连接"
        case .connecting: status = "连接中…"
        case .disconnecting: status = "正在断开…"
        case .disconnected: status = "隧道已断开"
        case .reasserting: status = "正在恢复连接…"
        default: status = "尚未创建 VPN 配置"
        }
    }
    func connect() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let existing = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = existing.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == identifier } ?? NETunnelProviderManager()
            let p = NETunnelProviderProtocol(); p.providerBundleIdentifier = identifier
            p.serverAddress = "本机设备隧道"; p.providerConfiguration = ["localAddress":"10.7.0.2/30"]
            m.protocolConfiguration = p; m.localizedDescription = "AirBeep 隧道测试"; m.isEnabled = true
            try await m.saveToPreferences(); try await m.loadFromPreferences(); manager = m
            try m.connection.startVPNTunnel(); updateStatus()
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 500_000_000)
                if m.connection.status == .connected { updateStatus(); return }
            }
            if m.connection.status != .connected {
                status = "未能连接，请检查扩展签名或 VPN 状态"
                m.connection.fetchLastDisconnectError { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in self?.status = "隧道失败：\(error.localizedDescription)" }
                }
            }
        } catch { let e = error as NSError; status = "\(e.domain) (\(e.code))：\(e.localizedDescription)" }
    }
    func stop() { manager?.connection.stopVPNTunnel(); updateStatus() }
}
struct TunnelTestPanel: View {
    @StateObject private var tunnel = BuiltInTunnelTest()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("内置隧道验证").font(.headline)
            Text(tunnel.status).font(.caption).textSelection(.enabled)
            HStack {
                Button("连接内置隧道") { Task { await tunnel.connect() } }.disabled(tunnel.busy)
                Spacer()
                Button("断开") { tunnel.stop() }.disabled(tunnel.busy)
            }.buttonStyle(.bordered)
            Text("先验证连接；不会自动修改录音提示音。连接可能切换当前 VPN。").font(.caption2).foregroundStyle(.secondary)
        }.padding().background(.regularMaterial)
    }
}
