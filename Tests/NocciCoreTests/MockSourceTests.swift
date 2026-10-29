import Testing
@testable import NocciCore

struct MockSourceTests {
    @Test func emitsOnItsInterval() async {
        var iterator = MockSource(interval: .milliseconds(100)).newItems().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.id == "mock-live-1")
    }
}
