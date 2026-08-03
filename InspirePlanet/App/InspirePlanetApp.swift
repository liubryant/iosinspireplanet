import SwiftUI

@main
struct InspirePlanetApp: App {
    @StateObject private var privacyGate = InspirePrivacyGate()

    var body: some Scene {
        WindowGroup {
            Group {
                if privacyGate.hasAccepted {
                    InspirePlanetRootView()
                        .onAppear {
                            InspireUMengAnalytics.shared.initializeIfAllowed()
                        }
                } else {
                    ZStack {
                        Color.white.ignoresSafeArea()
                        InspirePrivacyAgreementView {
                            privacyGate.accept()
                        }
                        .ignoresSafeArea()
                    }
                }
            }
        }
    }
}
