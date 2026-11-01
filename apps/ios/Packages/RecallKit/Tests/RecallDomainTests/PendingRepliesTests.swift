import Foundation
import Testing
@testable import RecallDomain

@Suite("Waiting for the iPhone")
struct PendingRepliesTests {
    @Test func aReplyIsTakenOnceThenGone() {
        let pending = PendingReplies<String>()
        pending.put("a", "handler")
        #expect(pending.take("a") == "handler")
        #expect(pending.take("a") == nil)  // the timeout, coming second, finds nothing
        #expect(pending.count == 0)
    }

    @Test func aTimedOutRequestDropsTheLateReply() {
        let pending = PendingReplies<String>()
        pending.put("a", "handler")
        #expect(pending.take("a") != nil)  // timeout fires first and answers
        #expect(pending.take("a") == nil)  // the iPhone's late reply is dropped
    }

    @Test func otherRequestsAreUntouched() {
        let pending = PendingReplies<Int>()
        pending.put("a", 1)
        pending.put("b", 2)
        _ = pending.take("a")
        #expect(pending.take("b") == 2)
    }

    @Test func theWaitIsLongEnoughForTheGuideButNotForever() {
        #expect(PendingReplies<Int>.timeout == .seconds(25))
        #expect(WatchReply.phoneDidNotAnswer.say?.contains("didn't answer") == true)
    }
}
