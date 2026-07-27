import SwiftUI

struct SeparationControlsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: AppStyle.spacing) {
            if appViewModel.canStartSeparation {
                Button(action: { appViewModel.startSeparation() }) {
                    Label("Start Separation", systemImage: "wand.and.stars")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.glass(color: .appAccent))
                .disabled(!appViewModel.canStartSeparation)
            }
            
            if appViewModel.separationState.isActive {
                Button(action: { appViewModel.cancelSeparation() }) {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.glass(color: .appTextSecondary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}