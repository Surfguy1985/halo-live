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

    func testValidateActivationUsesNativeGateway() async throws {
        let payload = #"{"ok":true,"crew":{"id":"crew-1","name":"Field Crew"},"capabilities":{"nativePushDeliveryConfigured":false}}"#.data(using: .utf8)!
        let info = try await makeAPI(status: 200, data: payload).validateActivation(token: "test-token-1234567890")
        XCTAssertEqual(info.crewID, "crew-1")
        XCTAssertEqual(info.crewName, "Field Crew")
        XCTAssertFalse(info.nativePushDeliveryConfigured)
    }

    func testRejectedActivationRemainsRejected() async {
        let payload = #"{"error":"Invalid or expired HALO activation token"}"#.data(using: .utf8)!
        do {
            _ = try await makeAPI(status: 401, data: payload).validateActivation(token: "test-token-1234567890")
            XCTFail("Invalid activation must not succeed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"))
            XCTAssertTrue(error.localizedDescription.contains("Invalid or expired"))
        }
    }

    func testFetchJobsMapsLiveHaloShape() async throws {
        let payload = """
        {"jobs":[
          {
            "id":"c5c766ff-56e2-43d3-a3dc-4c4cf5b8bc29",
            "jobNo":"B44-816",
            "propertyId":"49dec4b1-1dc5-4b59-8025-0c0bc14d35ce",
            "propertyName":"Thornbury at Chase Oaks",
            "propertyLatitude":33.0198,
            "propertyLongitude":-96.6989,
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
        XCTAssertEqual(job.propertyLatitude, 33.0198)
        XCTAssertEqual(job.propertyLongitude, -96.6989)
        XCTAssertEqual(job.unit, "816")
        XCTAssertEqual(job.state, .scheduled)
        XCTAssertEqual(job.crewLeaderName, "Marco")
        XCTAssertEqual(job.tasks.count, 2)
        XCTAssertEqual(job.tasks[0].id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(job.tasks[0].title, "Wall Prep & Paint (2 BR)")
        XCTAssertEqual(job.tasks[0].detail, "EA")
        XCTAssertEqual(job.tasks[1].isComplete, true)
    }


    func testFetchJobsMapsProofReworkAndCloseoutState() async throws {
        let payload = """
        {"jobs":[
          {
            "id":"job-rework-1",
            "propertyName":"Thornbury at Chase Oaks",
            "unitNo":"2418",
            "description":"Make Ready",
            "status":"active",
            "photoCount":7,
            "beforePhotoCount":4,
            "afterPhotoCount":3,
            "flaggedCount":1,
            "rework":true,
            "reworkNotes":"Touch up paint near entry.",
            "reworkItems":[
              {"id":"job-rework-1:rework:0","index":0,"text":"Touch up paint","checked":false},
              {"id":"job-rework-1:rework:1","index":1,"text":"Replace switch plate","checked":true}
            ],
            "closeoutStage":"needs_attention",
            "closeoutBlockers":["PO missing"],
            "readyForWalk":true,
            "walkVerified":false
          }
        ]}
        """.data(using: .utf8)!

        let jobs = try await makeAPI(status: 200, data: payload).fetchJobs(
            activationToken: "test-token-1234567890"
        )

        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.photoCount, 7)
        XCTAssertEqual(job.beforePhotoCount, 4)
        XCTAssertEqual(job.afterPhotoCount, 3)
        XCTAssertEqual(job.flaggedCount, 1)
        XCTAssertEqual(job.needsRework, true)
        XCTAssertEqual(job.reworkNotes, "Touch up paint near entry.")
        XCTAssertEqual(job.reworkItems?.count, 2)
        XCTAssertEqual(job.unresolvedReworkCount, 1)
        XCTAssertEqual(job.closeoutStage, "needs_attention")
        XCTAssertEqual(job.closeoutBlockers, ["PO missing"])
        XCTAssertEqual(job.readyForWalk, true)
        XCTAssertEqual(job.walkVerified, false)
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

    func testSecurityGatewayDenialDoesNotMasqueradeAsInvalidToken() async {
        let payload = "<html><title>Cloudflare Access denied</title><body>Error 1010</body></html>".data(using: .utf8)!
        do {
            _ = try await makeAPI(status: 403, data: payload).validateActivation(token: "test-token-1234567890")
            XCTFail("Gateway denial must not activate the device")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("security gateway blocked"))
            XCTAssertFalse(error.localizedDescription.contains("<html>"))
            XCTAssertFalse(error.localizedDescription.contains("Invalid or expired"))
        }
    }

    func testGrokReplyMapsNativeAssistantResponse() async throws {
        let payload = #"{"ok":true,"reply":"Unit 816 needs after photos before closeout.","model":"grok-4.6","groundedAt":"2026-10-01T01:45:00.000Z"}"#.data(using: .utf8)!
        let reply = try await makeAPI(status: 200, data: payload).askGrok(
            message: "What is next?",
            jobID: "unit-816",
            history: [HaloGrokTurn(role: "assistant", content: "Ready when you are.")],
            activationToken: "test-token-1234567890"
        )

        XCTAssertEqual(reply.reply, "Unit 816 needs after photos before closeout.")
        XCTAssertEqual(reply.model, "grok-4.6")
        XCTAssertEqual(reply.groundedAt, "2026-10-01T01:45:00.000Z")
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
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Halo-Activation"), "test-token-1234567890")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Crew tokens must not be interpreted as Base44 user credentials")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Id"), "6aa4569d140d940e1d779ace")
            XCTAssertEqual(request.url?.path, "/functions/nativeFieldMobile")
            XCTAssertEqual(request.httpMethod, "POST")
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
