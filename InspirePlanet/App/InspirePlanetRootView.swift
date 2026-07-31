import SwiftUI

struct InspirePlanetRootView: View {
    @StateObject private var model = DigitalHumanConversationModel()

    var body: some View {
        DigitalHumanConversationView(model: model)
            .preferredColorScheme(.light)
    }
}
