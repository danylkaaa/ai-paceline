import AILimitsCore
import SwiftUI

struct PanelView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Limits").font(.headline)
            Text("Charts come in the next steps.").foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
    }
}
