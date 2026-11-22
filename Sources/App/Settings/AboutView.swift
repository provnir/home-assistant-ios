import Shared
import SwiftUI

/// About Khala: what the app is, where its source lives, and the projects it is built on. Khala is a personal
/// fork, so the upstream companion app's beta, review, translation, community and social links are left out;
/// the Acknowledgements (the open-source licences Khala ships under) stay.
struct AboutView: View {
    @State private var showVersionAlert = false

    var body: some View {
        List {
            AppleLikeListTopRowHeader(
                image: nil,
                headerImageAlternativeView: AnyView(
                    Image(uiImage: Asset.logo.image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .accessibilityHidden(true)
                ),
                title: KhalaText.About.appName,
                subtitle: KhalaText.About.version(HomeAssistantAPI.clientVersionDescription)
            )
            .onTapGesture {
                showVersionAlert = true
            }

            Section {
                Text(KhalaText.About.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(KhalaText.About.khalaSection) {
                Link(KhalaText.About.sourceCode, destination: KhalaText.About.sourceURL)
            }

            Section {
                Link(KhalaText.About.companionApp, destination: KhalaText.About.companionURL)
                Link(KhalaText.About.homeAssistant, destination: AppConstants.WebURLs.homeAssistant)
                Link(KhalaText.About.companionDocs, destination: AppConstants.WebURLs.companionAppDocs)
            } header: {
                Text(KhalaText.About.builtOnSection)
            } footer: {
                Text(KhalaText.About.builtOnFooter)
            }

            Section {
                NavigationLink(destination: AcknowledgementsView()) {
                    Text(L10n.About.Acknowledgements.title)
                }
            }
        }
        .navigationTitle(KhalaText.aboutKhala)
        .alert(isPresented: $showVersionAlert) {
            Alert(
                title: Text(""),
                message: Text(HomeAssistantAPI.clientVersionDescription),
                primaryButton: .default(Text(L10n.copyLabel), action: {
                    UIPasteboard.general.string = HomeAssistantAPI.clientVersionDescription
                }),
                secondaryButton: .cancel(Text(L10n.cancelLabel))
            )
        }
    }
}
