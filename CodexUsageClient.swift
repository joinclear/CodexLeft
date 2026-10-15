import Foundation

// 请求方式、窗口分类及剩余比例计算参考 CodexQuotaMenu（MIT，见 LICENSE）。
struct UsageWindow {
    let usedPercent: Double?
    let resetAt: Date?

    var remainingPercent: Int? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return Int(max(0, min(100, 100 - usedPercent)).rounded())
    }

    var remainingText: String {
        remainingPercent.map { "\($0)%" } ?? "--%"
    }
}

struct UsageSnapshot {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    let syncedAt: Date
}

enum UsageError: Error, LocalizedError {
    case credentialsUnavailable
    case invalidCredentials
    case httpStatus(Int)
    case invalidResponse
    case noWindows
    case timeout
    case network

    var errorDescription: String? {
        switch self {
        case .credentialsUnavailable: return "无法读取 Codex 登录信息"
        case .invalidCredentials: return "缺少 Codex 登录令牌或账号 ID"
        case .httpStatus(401): return "登录已失效（HTTP 401），请在 Codex 重新登录"
        case .httpStatus(403): return "接口拒绝访问（HTTP 403）"
        case .httpStatus(let status): return "请求失败（HTTP \(status)）"
        case .invalidResponse: return "用量数据解析失败"
        case .noWindows: return "未找到可识别的额度窗口"
        case .timeout: return "请求超时"
        case .network: return "网络请求失败"
        }
    }
}

final class CodexUsageClient {
    private struct Credentials: Decodable {
        struct Tokens: Decodable {
            let access_token: String
            let account_id: String
        }
        let tokens: Tokens
    }

    private struct Response: Decodable {
        struct RateLimit: Decodable {
            struct Window: Decodable {
                let used_percent: Double?
                let limit_window_seconds: Double?
                let reset_at: Double?
            }
            let primary_window: Window?
            let secondary_window: Window?
        }
        let rate_limit: RateLimit
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    func fetch() async throws -> UsageSnapshot {
        // 每次请求重新读取；不写入凭据，也不输出凭据或响应内容。
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authURL) else {
            throw UsageError.credentialsUnavailable
        }
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              !credentials.tokens.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.tokens.account_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageError.invalidCredentials
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.tokens.access_token)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.tokens.account_id, forHTTPHeaderField: "ChatGPT-Account-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexLeft/1.0", forHTTPHeaderField: "User-Agent")

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw UsageError.timeout
        } catch {
            throw UsageError.network
        }
        return try Self.parseResponse(responseData, response: response)
    }

    static func parseResponse(_ data: Data, response: URLResponse) throws -> UsageSnapshot {
        guard let response = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        guard (200...299).contains(response.statusCode) else {
            throw UsageError.httpStatus(response.statusCode)
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> UsageSnapshot {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw UsageError.invalidResponse
        }
        var fiveHour: UsageWindow?
        var weekly: UsageWindow?
        for window in [response.rate_limit.primary_window, response.rate_limit.secondary_window].compactMap({ $0 }) {
            guard let seconds = window.limit_window_seconds, seconds.isFinite else { continue }
            let value = UsageWindow(
                usedPercent: window.used_percent,
                resetAt: window.reset_at.map { Date(timeIntervalSince1970: $0) }
            )
            switch seconds {
            case (240 * 60)...(360 * 60):
                if fiveHour == nil { fiveHour = value }
            case (6 * 24 * 60 * 60)...(8 * 24 * 60 * 60):
                if weekly == nil { weekly = value }
            default: break
            }
        }
        guard fiveHour != nil || weekly != nil else { throw UsageError.noWindows }
        return UsageSnapshot(fiveHour: fiveHour, weekly: weekly, syncedAt: Date())
    }
}
