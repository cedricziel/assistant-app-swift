import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct LoginView: View {
    enum Mode {
        case initial
        case additional

        var title: String {
            switch self {
            case .initial:
                "Welcome"
            case .additional:
                "Add Account"
            }
        }
    }

    var mode: Mode = .initial

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore

    @State private var serverAddress: String = "https://assistant.local"
    @State private var displayName: String = ""
    @State private var apiToken: String = ""
    @State private var routingMode: RoutingMode = .assistantBackend
    @State private var directProvider: AssistantAccount.ModelProvider = .openAI
    @State private var openAIAuthMode: AssistantAccount.ProviderAuth = .apiKey
    @State private var syncInICloud = true
    @FocusState private var focusedField: Field?

    enum RoutingMode: String {
        case assistantBackend
        case directProviders
    }

    enum Field {
        case server
        case name
        case token
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Assistant")
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Form {
                Section("Routing") {
                    Picker("Route conversations", selection: $routingMode) {
                        Text("Assistant backend").tag(RoutingMode.assistantBackend)
                        Text("Direct providers").tag(RoutingMode.directProviders)
                    }
                }

                if routingMode == .directProviders {
                    Section("Providers") {
                        Picker("Primary provider", selection: $directProvider) {
                            Text("OpenAI").tag(AssistantAccount.ModelProvider.openAI)
                            Text("Local model").tag(AssistantAccount.ModelProvider.local)
                        }
                    }

                    if directProvider == .openAI {
                        Section("Authentication") {
                            Picker("Mode", selection: $openAIAuthMode) {
                                Text("API key").tag(AssistantAccount.ProviderAuth.apiKey)
                                Text("ChatGPT Plus/Pro").tag(AssistantAccount.ProviderAuth.chatGPTSubscription)
                            }
                        }
                    }
                }

                Section("Sync") {
                    Toggle("Sync in iCloud", isOn: $syncInICloud)
                }

                if routingMode == .assistantBackend {
                    Section("Server") {
                        Group {
                            #if os(iOS)
                            TextField("https://assistant.local", text: $serverAddress)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            #else
                            TextField("https://assistant.local", text: $serverAddress)
                            #endif
                        }
                        .focused($focusedField, equals: .server)
                    }
                }

                if requiresManualCredential {
                    Section("Credentials") {
                        Group {
                            #if os(iOS)
                            SecureField(tokenPlaceholder, text: $apiToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            #else
                            SecureField(tokenPlaceholder, text: $apiToken)
                            #endif
                        }
                        .focused($focusedField, equals: .token)
                    }
                }

                if let pending = accountStore.pendingOpenAIAuthorization {
                    Section("Authorization") {
                        Text(pending.instructions)
                            .foregroundStyle(.secondary)
                        Text("Code: \(pending.userCode)")
                            .font(.body.monospaced().bold())
                        Button("Copy Code") {
                            copyToClipboard(pending.userCode)
                        }
                        Button("Open ChatGPT Authorization") {
                            open(url: pending.verificationURL)
                        }
                    }
                }

                Section("Profile") {
                    Group {
                        #if os(iOS)
                        TextField("Display name", text: $displayName)
                            .textInputAutocapitalization(.words)
                        #else
                        TextField("Display name", text: $displayName)
                        #endif
                    }
                    .focused($focusedField, equals: .name)
                }

                Section {
                    Button(action: authenticate) {
                        if accountStore.isAuthenticating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnectDisabled)

                    if let error = accountStore.authenticationError {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }

                if accountStore.hasAccounts {
                    Section("Connected accounts") {
                        ForEach(accountStore.accounts) { account in
                            AccountBadgeView(account: account)
                                .onTapGesture {
                                    accountStore.selectAccount(account)
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            focusedField = initialFocusedField
        }
        .onChange(of: routingMode) { _, newValue in
            if newValue == .assistantBackend {
                syncInICloud = true
            }
            if newValue == .directProviders, directProvider == .local {
                apiToken = ""
            }
            focusedField = initialFocusedField
        }
        .onChange(of: directProvider) { _, newValue in
            if newValue == .local {
                openAIAuthMode = .none
                apiToken = ""
            } else if openAIAuthMode == .none {
                openAIAuthMode = .apiKey
            }
            focusedField = initialFocusedField
        }
        .onChange(of: openAIAuthMode) { _, _ in
            focusedField = initialFocusedField
        }
    }
}

private extension LoginView {
    var subtitle: String {
        switch routingMode {
        case .assistantBackend:
            "All turns go through your Assistant backend. iCloud sync is enabled by default."
        case .directProviders:
            if directProvider == .openAI, openAIAuthMode == .chatGPTSubscription {
                "Use your ChatGPT Plus/Pro subscription directly from this app."
            } else if directProvider == .openAI {
                "Connect OpenAI with an API key to send messages directly."
            } else {
                "Use a local on-device provider and keep data under your sync policy."
            }
        }
    }

    var tokenPlaceholder: String {
        if routingMode == .assistantBackend {
            "API token"
        } else {
            "OpenAI API key"
        }
    }

    var initialFocusedField: Field? {
        if routingMode == .assistantBackend {
            return .server
        }

        if directProvider == .openAI, openAIAuthMode == .chatGPTSubscription {
            return .name
        }

        return .token
    }

    var syncPolicy: AssistantAccount.SyncPolicy {
        if syncInICloud {
            return .iCloud(.init())
        }
        return .deviceOnly
    }

    var routing: AssistantAccount.Routing {
        switch routingMode {
        case .assistantBackend:
            let serverURL = URL(string: serverAddress) ?? URL(string: "https://assistant.local")!
            return .assistantBackend(
                .init(
                    server: ServerEnvironment(
                        name: serverURL.host ?? serverURL.absoluteString,
                        baseURL: serverURL,
                        kind: .remote,
                    ),
                    credentialKind: .apiKey,
                ),
            )
        case .directProviders:
            let profile = AssistantAccount.ProviderProfile(
                provider: directProvider,
                auth: directProvider == .openAI ? openAIAuthMode : .none,
                label: directProvider == .openAI ? "OpenAI" : "Local",
                isEnabled: true,
            )
            return .directProviders(
                .init(
                    providers: [profile],
                    defaultProviderID: profile.id,
                ),
            )
        }
    }

    func authenticate() {
        Task {
            await accountStore.login(
                serverAddress: serverAddress,
                apiToken: apiToken,
                displayName: displayName,
                routing: routing,
                syncPolicy: syncPolicy,
            )
            if let account = accountStore.activeAccount {
                _ = chatStore.ensureDefaultThread(for: account)
            }
        }
    }

    var isConnectDisabled: Bool {
        let missingServer = routingMode == .assistantBackend && serverAddress.isBlank
        let missingCredential = requiresManualCredential && apiToken.isBlank
        return missingCredential || missingServer
    }

    var requiresManualCredential: Bool {
        if routingMode == .assistantBackend {
            return true
        }
        if directProvider == .openAI, openAIAuthMode == .chatGPTSubscription {
            return false
        }
        return directProvider == .openAI
    }

    func open(url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    func copyToClipboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

#Preview {
    LoginView()
        .environmentObject(AccountStore())
        .environmentObject(ChatStore())
}
