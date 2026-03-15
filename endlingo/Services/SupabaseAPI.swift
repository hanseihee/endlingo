import Foundation

/// Supabase REST API 공통 헬퍼 - HTTP 요청 중복 제거
enum SupabaseAPI {

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - CRUD

    /// GET: 테이블에서 데이터 조회
    @MainActor
    static func fetch<T: Decodable>(
        _ table: String,
        query: String = "select=*",
        token: String? = nil
    ) async -> [T] {
        guard var request = makeRequest("\(table)?\(query)") else { return [] }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), !data.isEmpty else {
                return []
            }
            if let first = data.first, first != UInt8(ascii: "[") { return [] }
            return try decoder.decode([T].self, from: data)
        } catch {
            return []
        }
    }

    /// POST: 데이터 삽입
    @discardableResult
    static func insert<T: Encodable>(
        _ item: T,
        table: String,
        token: String,
        prefer: String = "resolution=ignore-duplicates"
    ) async -> Bool {
        guard var request = makeRequest(table, method: "POST") else { return false }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try? encoder.encode(item)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status < 400
        } catch {
            return false
        }
    }

    /// DELETE: 데이터 삭제
    static func delete(
        _ table: String,
        filter: String,
        token: String
    ) async {
        guard var request = makeRequest("\(table)?\(filter)", method: "DELETE") else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Private

    private static func makeRequest(_ path: String, method: String = "GET") -> URLRequest? {
        guard let url = URL(string: "\(SupabaseConfig.restBaseURL)/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}
