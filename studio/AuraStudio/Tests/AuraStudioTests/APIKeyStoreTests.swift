import XCTest
@testable import AuraStudio

/// Round-trip real contra el Keychain de la maquina que corre los
/// tests (sin mock: es la unica forma de probar que `SecItemAdd`/
/// `SecItemUpdate`/`SecItemDelete` funcionan de verdad). Se limpia
/// siempre en tearDown para no dejar una key de prueba en el llavero
/// real de quien corre la suite.
final class APIKeyStoreTests: XCTestCase {
    override func tearDown() {
        APIKeyStore.delete(for: .fanartTV)
        super.tearDown()
    }

    func testKeyIsNotPresentBeforeSaving() {
        APIKeyStore.delete(for: .fanartTV)
        XCTAssertFalse(APIKeyStore.hasKey(for: .fanartTV))
        XCTAssertNil(APIKeyStore.load(for: .fanartTV))
    }

    func testSaveThenLoadRoundTrips() {
        APIKeyStore.save("test-key-12345", for: .fanartTV)
        XCTAssertTrue(APIKeyStore.hasKey(for: .fanartTV))
        XCTAssertEqual(APIKeyStore.load(for: .fanartTV), "test-key-12345")
    }

    func testSavingTwiceUpdatesRatherThanDuplicates() {
        APIKeyStore.save("first-value", for: .fanartTV)
        APIKeyStore.save("second-value", for: .fanartTV)
        XCTAssertEqual(APIKeyStore.load(for: .fanartTV), "second-value")
    }

    func testDeleteRemovesTheKey() {
        APIKeyStore.save("to-be-deleted", for: .fanartTV)
        APIKeyStore.delete(for: .fanartTV)
        XCTAssertFalse(APIKeyStore.hasKey(for: .fanartTV))
    }
}
