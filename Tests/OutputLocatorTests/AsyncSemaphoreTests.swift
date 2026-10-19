import XCTest

final class AsyncSemaphoreTests: XCTestCase {
    func testAWaiterBeyondTheLimitWaitsForASignal() async throws {
        let semaphore = AsyncSemaphore(value: 2)
        try await semaphore.wait()
        try await semaphore.wait()
        let third = Task { () -> Date in
            try await semaphore.wait()
            return Date()
        }
        try await Task.sleep(for: .milliseconds(100))

        let released = Date()
        await semaphore.signal()

        let acquired = try await third.value
        XCTAssertGreaterThanOrEqual(acquired, released)
    }

    func testACancelledWaiterLeavesTheQueue() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        try await semaphore.wait()
        let waiter = Task { try await semaphore.wait() }
        try await Task.sleep(for: .milliseconds(50))

        waiter.cancel()

        do {
            try await waiter.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        // The cancelled waiter did not take the slot released next.
        await semaphore.signal()
        try await semaphore.wait()
    }
}
