  import SwiftUI

@main
struct DiskCheckApp: App {
    @NSApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate
    @State private var store = DiskScanStore()
    @State private var trashStore = TrashStore()

    var body: some Scene {
        WindowGroup {
            MainView(store: store, trashStore: trashStore)
                .frame(minWidth: 900, minHeight: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            ScanMenuBarView(store: store)
        } label: {
            ScanMenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
