import SwiftUI
@main struct ProbeApp: App {
 var body: some Scene {
  WindowGroup {
   NavigationStack {
    ScrollView {
     VStack(alignment: .leading, spacing: 24) {
      Image(systemName: "network.badge.shield.half.filled").font(.system(size: 48)).foregroundStyle(.pink)
      Text("AirBeep 隧道验证").font(.largeTitle.bold())
      Text("这个测试包只验证现有签名材料能否运行内置隧道，不修改任何录音提示音。")
      TunnelTestPanel()
      Text("测试步骤").font(.headline)
      Text("1. 点击连接内置隧道，允许添加 VPN 配置。\n2. 等待状态显示已连接。\n3. 使用分享诊断保留结果，再点击断开。")
      Text("如果无法安装，或连接报错，请保留完整提示。签名成功不代表系统一定允许运行。").font(.footnote).foregroundStyle(.secondary)
     }.padding(24)
    }.navigationTitle("签名兼容性测试").navigationBarTitleDisplayMode(.inline)
   }
  }
 }
}
