import XCTest
@testable import HaloField

final class HaloAPITests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testFetchJobsMapsLiveHaloShape() async throws {
        let payload = """
        {"jobs":[
          {
            "id":"c5c766ff-56e2-43d3-a3dc-4c4cf5b8bc29",
            "jobNo":"B44-816",
            "propertyId":"49dec4b1-1dc5-4b59-8025-0c0bc14d35ce",
            "propertyName":"Thornbury at Chase Oaks",
            "unitNo":"816",
            "category":"Wall Prep & Paint (2 BR)",
            "description":"Wall Prep & Paint (2 BR), Cabinet Paint (2 BR), Make Ready Package",
            "status":"open",
            "boardStatus":"filled",
            "scheduledOn":"2026-09-30",
            "scheduledTime":"08:00",
            "crewLeaderId":"crew-1",
            "crewLeaderName":"Marco",
            "tasks":[
              {
                "id":"11111111-1111-1111-1111-111111111111",
                "title":"Wall Prep & Paint (2 BR)",
                "detail":"EA",
                "isComplete":false,
                "requiresPhoto":true
              },
              {
                "id":"22222222-2222-2222-2222-222222222222",
                "title":"Cabinet Paint (2 BR)",
                "isComplete":true,
                "requiresPhoto":true
              }
            ],
            "createdAt":"2026-09-30T12:00:00.000Z"
          }
        ]}
        """.data(using: .utf8)!

        let api = makeAPI(status: 200, data: payload)
        let jobs = try await api.fetchJobs(activationToken: "test-token-1234567890")

        XCTAssertEqual(jobs.count, 1)
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.id, "c5c766ff-56e2-43d3-a3dc-4c4cf5b8bc29")
        XCTAssertEqual(job.jobNo, "B44-816")
        XCTAssertEqual(job.propertyName, "Thornbury at Chase Oaks")
        XCTAssertEqual(job.unit, "816")
        XCTAssertEqual(job.state, .scheduled)
        XCTAssertEqual(job.crewLeaderName, "Marco")
        XCTAssertEqual(job.tasks.count, 2)
        XCTAssertEqual(job.tasks[0].id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(job.tasks[0].title, "Wall Prep & Paint (2 BR)")
        XCTAssertEqual(job.tasks[0].detail, "EA")
        XCTAssertEqual(job.tasks[1].isComplete, true)
    }

    func testCompletedJobsMapClosed() async throws {
        let payload = """
        {"jobs":[{"id":"job-2","propertyName":"Avalon","unitNo":"927","description":"Cabinet Paint","status":"complete"}]}
        """.data(using: .utf8)!

        let jobs = try await makeAPI(status: 200, data: payload).fetchJobs(activationToken: "test-token-1234567890")

        XCTAssertEqual(jobs.first?.state, .complete)
        XCTAssertEqual(jobs.first?.isClosed, true)
        XCTAssertEqual(jobs.first?.tasks.first?.isComplete, true)
    }

    func testHTTPFailureSurfacesServerMessage() async {
        let payload = #"{"error":"Jobs unavailable"}"#.data(using: .utf8)!

        do {
            _ = try await makeAPI(status: 503, data: payload).fetchJobs(activationToken: "test-token-1234567890")
            XCTFail("Expected fetchJobs to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Jobs unavailable"))
        }
    }

    func testInvalidRowsAreDroppedWithoutCrashingValidJobs() async throws {
        let payload = """
        {"jobs":[
          {"propertyName":"Missing ID"},
          {"id":"job-3","propertyName":"The Emerson","unitNo":"803","description":"Final clean","status":"active"}
        ]}
        """.data(using: .utf8)!

        let jobs = try await makeAPI(status: 200, data: payload).fetchJobs(activationToken: "test-token-1234567890")

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].id, "job-3")
        XCTAssertEqual(jobs[0].state, .active)
    }

    private func makeAPI(status: Int, data: Data) -> HaloAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-1234567890")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        return HaloAPI(baseURL: URL(string: "https://example.test")!, session: session)
    }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("MockURLProtocol.handler was not set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
