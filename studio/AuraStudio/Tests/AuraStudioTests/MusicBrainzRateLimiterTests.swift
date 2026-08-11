import XCTest
@testable import AuraStudio

/// MusicBrainz aplica 1 pedido/segundo por IP de forma estricta. Estos
/// tests fijan la aritmetica del limitador sin dormir de verdad: se
/// inyecta la marca de tiempo en vez de esperar en tiempo real.
final class MusicBrainzRateLimiterTests: XCTestCase {
    func testFirstRequestDoesNotWait() async {
        let limiter = MusicBrainzRateLimiter()
        let delay = await limiter.pendingDelay(now: Date())
        XCTAssertEqual(delay, 0)
    }

    func testImmediateSecondRequestWaitsAlmostAFullSecond() async {
        let limiter = MusicBrainzRateLimiter()
        let start = Date()
        await limiter.reserve(at: start)

        let delay = await limiter.pendingDelay(now: start.addingTimeInterval(0.2))
        XCTAssertEqual(delay, 0.8, accuracy: 0.001)
    }

    func testNoWaitOnceTheIntervalHasElapsed() async {
        let limiter = MusicBrainzRateLimiter()
        let start = Date()
        await limiter.reserve(at: start)

        let delay = await limiter.pendingDelay(now: start.addingTimeInterval(1.5))
        XCTAssertEqual(delay, 0)
    }

    func testIntervalIsConfigurable() async {
        let limiter = MusicBrainzRateLimiter(minimumInterval: 3)
        let start = Date()
        await limiter.reserve(at: start)

        let delay = await limiter.pendingDelay(now: start.addingTimeInterval(1))
        XCTAssertEqual(delay, 2, accuracy: 0.001)
    }

    /// El limitador es compartido por todos los clientes justamente
    /// porque el limite es por IP: dos instancias de MusicBrainzClient no
    /// pueden gastar cada una su propio pedido por segundo.
    func testSharedInstanceIsTheSameActor() async {
        let a = MusicBrainzRateLimiter.shared
        let b = MusicBrainzRateLimiter.shared
        XCTAssertTrue(a === b)
    }
}
