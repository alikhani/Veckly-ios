import Foundation
import Testing
@testable import Veckly

/// The backend publishes `ErrorResponse.error` as an open enum. A build already
/// in users' hands must still decode an error code added after it shipped —
/// otherwise the whole response fails to decode and the app shows the wrong error.
struct ErrorResponseDecodingTests {
    @Test func decodesAKnownErrorCodeAsTyped() throws {
        let response = try JSONDecoder().decode(
            Components.Schemas.ErrorResponse.self,
            from: Data(#"{"error":"NOT_MEMBER"}"#.utf8)
        )
        #expect(response.error.value1 == .NOT_MEMBER)
    }

    @Test func decodesAnErrorCodeAddedAfterThisBuildShipped() throws {
        let response = try JSONDecoder().decode(
            Components.Schemas.ErrorResponse.self,
            from: Data(#"{"error":"SOME_FUTURE_CODE"}"#.utf8)
        )
        #expect(response.error.value1 == nil)
        #expect(response.error.value2 == "SOME_FUTURE_CODE")
    }
}
