import Foundation

struct HaloAPI {
    var baseURL = URL(string: "https://archangel-halo.replit.app")!
    var role = "field"

    func request(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(role, forHTTPHeaderField: "X-Halo-Role")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func jobs(propertyID: String) async throws -> Data {
        try await request(path: "/api/jobs?propertyId=\(propertyID)")
    }

    func updateJob(id: String, payload: Data) async throws -> Data {
        try await request(path: "/api/jobs/\(id)", method: "PATCH", body: payload)
    }
}
