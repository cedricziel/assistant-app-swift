import SwiftUI

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
    @State private var accountType: AssistantAccount.AccountType = .remote
    @State private var remoteProvider: AssistantAccount.RemoteProvider = .assistantBackend
    @FocusState private var focusedField: Field?

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
                Section("Account") {
                    Picker("Storage", selection: $accountType) {
                        Text("Remote backend").tag(AssistantAccount.AccountType.remote)
                        Text("On this device").tag(AssistantAccount.AccountType.localDevice)
                        Text("iCloud sync").tag(AssistantAccount.AccountType.localICloud)
                    }
                }

                if accountType == .remote {
                    Section("Provider") {
                        Picker("Remote provider", selection: $remoteProvider) {
                            Text("Assistant backend").tag(AssistantAccount.RemoteProvider.assistantBackend)
                            Text("OpenAI").tag(AssistantAccount.RemoteProvider.openAI)
                        }
                    }

                    if remoteProvider == .assistantBackend {
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
        .onChange(of: accountType) { _, newValue in
            if newValue != .remote {
                remoteProvider = .assistantBackend
            }
            focusedField = initialFocusedField
        }
        .onChange(of: remoteProvider) { _, _ in
            focusedField = initialFocusedField
        }
    }

    private var subtitle: String {
        switch accountType {
        case .remote:
            switch remoteProvider {
            case .assistantBackend:
                "Sign in with a server and token to continue."
            case .openAI:
                "Connect OpenAI with an API key to send messages directly."
            }
        case .localDevice, .localICloud:
            "Create a local profile to keep conversations on your devices."
        }
    }

    private var tokenPlaceholder: String {
        switch remoteProvider {
        case .assistantBackend:
            "API token"
        case .openAI:
            "OpenAI API key"
        }
    }

    private var initialFocusedField: Field? {
        guard accountType == .remote else {
            return .name
        }

        if remoteProvider == .assistantBackend {
            return .server
        }

        return .token
    }

    private func authenticate() {
        Task {
            await accountStore.login(
                serverAddress: serverAddress,
                apiToken: apiToken,
                displayName: displayName,
                accountType: accountType,
                remoteProvider: remoteProvider,
            )
            if let account = accountStore.activeAccount {
                _ = chatStore.ensureDefaultThread(for: account)
            }
        }
    }

    private var isConnectDisabled: Bool {
        switch accountType {
        case .remote:
            let missingServer = remoteProvider == .assistantBackend && serverAddress.isBlank
            return apiToken.isBlank || missingServer
        case .localDevice, .localICloud:
            return false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AccountStore())
        .environmentObject(ChatStore())
}
