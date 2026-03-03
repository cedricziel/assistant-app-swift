import SwiftUI

struct LoginView: View {
    enum Mode {
        case initial
        case additional

        var title: String {
            switch self {
            case .initial:
                return "Welcome"
            case .additional:
                return "Add Account"
            }
        }
    }

    var mode: Mode = .initial

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var chatStore: ChatStore

    @State private var serverAddress: String = "https://assistant.local"
    @State private var displayName: String = ""
    @State private var apiToken: String = ""
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
                Text("Sign in with a server and token to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Form {
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

                    Group {
#if os(iOS)
                        SecureField("API token", text: $apiToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
#else
                        SecureField("API token", text: $apiToken)
#endif
                    }
                    .focused($focusedField, equals: .token)
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
                    .disabled(apiToken.isBlank || serverAddress.isBlank)

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
            focusedField = .server
        }
    }

    private func authenticate() {
        Task {
            await accountStore.login(
                serverAddress: serverAddress,
                apiToken: apiToken,
                displayName: displayName
            )
            if let account = accountStore.activeAccount {
                _ = chatStore.ensureDefaultThread(for: account)
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AccountStore())
        .environmentObject(ChatStore())
}
