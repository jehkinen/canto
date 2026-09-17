import SwiftUI

extension View {
    /// Lets the user pick one entry when the keychain holds several OpenAI keys.
    func keychainKeyChooser() -> some View {
        modifier(KeychainKeyChooser())
    }
}

private struct KeychainKeyChooser: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content.confirmationDialog("Choose an OpenAI key", isPresented: $model.isChoosingKeychainItem) {
            ForEach(model.keychainMatches) { item in
                Button(item.account.isEmpty ? item.title : "\(item.title) (\(item.account))") {
                    model.useKeychainItem(item)
                }
            }
        } message: {
            Text("macOS will ask to allow access to the selected item.")
        }
    }
}
