import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바 전용 앱이라 창이 없다. App 프로토콜이 Scene을 요구해서 빈 Settings를 둔다.
        Settings {
            EmptyView()
        }
    }
}
