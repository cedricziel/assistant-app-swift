import Foundation

struct OpenAISubscriptionAuthService {
    struct DeviceAuthorization {
        let verificationURL: URL
        let userCode: String
        let deviceAuthID: String
        let pollingInterval: TimeInterval
    }

    struct TokenBundle {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let accountID: String?
    }

    enum AuthError: LocalizedError {
        case invalidResponse
        case authorizationDeclined
        case authorizationTimedOut
        case tokenExchangeFailed
        case decodeFailed(step: String, underlying: Error, responsePreview: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "OpenAI returned an invalid authorization response."
            case .authorizationDeclined:
                "Authorization was declined or could not be completed."
            case .authorizationTimedOut:
                "Authorization timed out. Try connecting again."
            case .tokenExchangeFailed:
                "Could not exchange authorization code for tokens."
            case let .decodeFailed(step, underlying, preview):
                "Failed to decode \(step) response: \(underlying.localizedDescription) [\(preview)]"
            }
        }
    }

    private struct DeviceStartResponse: Decodable {
        let deviceAuthID: String
        let userCode: String
        let interval: String
    }

    private struct DevicePollResponse: Decodable {
        let authorizationCode: String
        let codeVerifier: String
    }

    private struct TokenResponse: Decodable {
        let idToken: String?
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int?
    }

    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let issuerURL = URL(string: "https://auth.openai.com")!
    private let pollingSafetyMarginNanoseconds: UInt64 = 3_000_000_000

    private var snakeCaseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization {
        var request = URLRequest(url: issuerURL.appending(path: "/api/accounts/deviceauth/usercode"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientID])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw AuthError.authorizationDeclined
        }

        let payload: DeviceStartResponse
        do {
            payload = try snakeCaseDecoder.decode(DeviceStartResponse.self, from: data)
        } catch {
            throw AuthError.decodeFailed(
                step: "device authorization",
                underlying: error,
                responsePreview: responsePreview(data),
            )
        }
        let interval = max(Double(payload.interval) ?? 5.0, 1.0)

        return DeviceAuthorization(
            verificationURL: issuerURL.appending(path: "/codex/device"),
            userCode: payload.userCode,
            deviceAuthID: payload.deviceAuthID,
            pollingInterval: interval,
        )
    }

    func pollForTokens(
        authorization: DeviceAuthorization,
        maxWait: TimeInterval = 300,
    ) async throws -> TokenBundle {
        let deadline = Date().addingTimeInterval(maxWait)

        while Date() < deadline {
            var request = URLRequest(url: issuerURL.appending(path: "/api/accounts/deviceauth/token"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "device_auth_id": authorization.deviceAuthID,
                "user_code": authorization.userCode,
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            if httpResponse.statusCode == 200 {
                let codePayload: DevicePollResponse
                do {
                    codePayload = try snakeCaseDecoder.decode(DevicePollResponse.self, from: data)
                } catch {
                    throw AuthError.decodeFailed(
                        step: "device poll",
                        underlying: error,
                        responsePreview: responsePreview(data),
                    )
                }
                return try await exchangeCodeForTokens(
                    authorizationCode: codePayload.authorizationCode,
                    codeVerifier: codePayload.codeVerifier,
                )
            }

            if httpResponse.statusCode != 403, httpResponse.statusCode != 404 {
                throw AuthError.authorizationDeclined
            }

            try await Task
                .sleep(nanoseconds: UInt64(authorization.pollingInterval * 1_000_000_000) +
                    pollingSafetyMarginNanoseconds)
        }

        throw AuthError.authorizationTimedOut
    }

    func refresh(refreshToken: String) async throws -> TokenBundle {
        var request = URLRequest(url: issuerURL.appending(path: "/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLComponents.formEncodedData([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw AuthError.tokenExchangeFailed
        }

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try snakeCaseDecoder.decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.decodeFailed(
                step: "token refresh",
                underlying: error,
                responsePreview: responsePreview(data),
            )
        }
        return TokenBundle(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600)),
            accountID: extractAccountID(from: tokenResponse),
        )
    }

    private func exchangeCodeForTokens(authorizationCode: String, codeVerifier: String) async throws -> TokenBundle {
        var request = URLRequest(url: issuerURL.appending(path: "/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLComponents.formEncodedData([
            "grant_type": "authorization_code",
            "code": authorizationCode,
            "redirect_uri": "https://auth.openai.com/deviceauth/callback",
            "client_id": clientID,
            "code_verifier": codeVerifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw AuthError.tokenExchangeFailed
        }

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try snakeCaseDecoder.decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.decodeFailed(
                step: "token exchange",
                underlying: error,
                responsePreview: responsePreview(data),
            )
        }
        return TokenBundle(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600)),
            accountID: extractAccountID(from: tokenResponse),
        )
    }

    private func extractAccountID(from tokenResponse: TokenResponse) -> String? {
        if let idToken = tokenResponse.idToken,
           let claims = parseJWTClaims(from: idToken),
           let accountID = parseAccountID(from: claims)
        {
            return accountID
        }

        if let claims = parseJWTClaims(from: tokenResponse.accessToken) {
            return parseAccountID(from: claims)
        }

        return nil
    }

    private func parseJWTClaims(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return nil
        }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }

        return dictionary
    }

    private func parseAccountID(from claims: [String: Any]) -> String? {
        if let accountID = claims["chatgpt_account_id"] as? String {
            return accountID
        }

        if let authClaims = claims["https://api.openai.com/auth"] as? [String: Any],
           let accountID = authClaims["chatgpt_account_id"] as? String
        {
            return accountID
        }

        if let organizations = claims["organizations"] as? [[String: Any]],
           let organizationID = organizations.first?["id"] as? String
        {
            return organizationID
        }

        return nil
    }

    /// Truncated preview of response body for error diagnostics (no secrets).
    private func responsePreview(_ data: Data) -> String {
        let raw = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
        return raw.count < data.count ? raw + "..." : raw
    }
}

private extension URLComponents {
    static func formEncodedData(_ values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.map { key, value in
            URLQueryItem(name: key, value: value)
        }
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
