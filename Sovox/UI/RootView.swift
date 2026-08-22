import SwiftUI

struct RootView: View {
    @Binding var tab: AppTab
    @Environment(RecorderController.self) private var recorder
    @Environment(AppSettings.self) private var settings
    @State private var showFirstRun = true

    var body: some View {
        TabView(selection: $tab) {
            Tab("Record", systemImage: "record.circle", value: AppTab.record) {
                RecordView()
            }
            Tab("History", systemImage: "list.bullet", value: AppTab.history) {
                HistoryView()
            }
            Tab("Ask", systemImage: "bubble.left.and.text.bubble.right", value: AppTab.ask) {
                AskView()
            }
            Tab("To-dos", systemImage: "checklist", value: AppTab.todos) {
                TodosView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // Presented from inside the hierarchy rather than alongside the
        // environment modifiers in the scene. Attached at the WindowGroup level
        // the sheet body could evaluate before AppSettings was in scope, which
        // crashed on a first launch with "No Observable object of type
        // AppSettings found".
        .sheet(isPresented: Binding(get: { !settings.setupCompleted && showFirstRun },
                                    set: { if !$0 { showFirstRun = false } })) {
            SetupWizardView()
        }
    }
}
