import SwiftUI

struct SeparationProgressView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: AppStyle.smallSpacing) {
            HStack {
                Label("Progress", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Status text
                HStack {
                    if appViewModel.separationState.isActive {
                        SwiftUI.ProgressView()
                            .scaleEffect(0.8)
                            .controlSize(.small)
                    } else if appViewModel.separationState == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.appSuccess)
                    } else if appViewModel.separationState == .cancelled {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.appWarning)
                    } else if case .failed = appViewModel.separationState {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                    
                    Text(appViewModel.separationState.statusText)
                        .font(.system(size: AppStyle.bodyFontSize, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                    
                    Spacer()
                }
                
                // Progress bar
                if appViewModel.separationState.isActive {
                    let progress = appViewModel.separationState.progressValue
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(
                                    colors: [Color.appAccent, Color.appAccent.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: geometry.size.width * CGFloat(max(0, min(1, progress))), height: 8)
                        }
                    }
                    .frame(height: 8)
                    .animation(.easeInOut(duration: 0.2), value: progress)
                    
                    HStack {
                        if let resources = appViewModel.separationState.resources {
                            HStack(spacing: 12) {
                                Label(String(format: "CPU %.1f%%", resources.cpuPercent), systemImage: "cpu")
                                Label(String(format: "RAM %.2f GB", resources.memoryGB), systemImage: "memorychip")
                            }
                            .font(.system(size: AppStyle.captionFontSize, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
                        }
                        
                        Spacer()
                        
                        Text("\(Int(appViewModel.separationState.progressValue * 100))%")
                            .font(.system(size: AppStyle.captionFontSize, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
                    }
                }
            }
        }
        .padding(AppStyle.smallPadding)
        .surfaceCard()
    }
}