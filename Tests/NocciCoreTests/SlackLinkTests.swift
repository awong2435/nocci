import Foundation
import Testing
@testable import NocciCore

struct SlackLinkTests {
    @Test func buildsTheMessageLinkLikeCopyLink() {
        let url = SlackLink.messageURL(notificationID: "C012AB3CD_1761234567.123456", workspace: "https://team.slack.com")
        #expect(url?.absoluteString == "https://team.slack.com/archives/C012AB3CD/p1761234567123456")
    }

    @Test func acceptsTheWorkspaceInAnyCommonForm() {
        for text in ["team.slack.com", "https://team.slack.com/", " TEAM.slack.com ", "https://team.slack.com/archives/C1/p1"] {
            #expect(SlackLink.normalizedWorkspace(text) == "team.slack.com")
        }
    }

    @Test func refusesNonSlackHostsAndOddIDs() {
        #expect(SlackLink.normalizedWorkspace("evil.example.com") == nil)
        #expect(SlackLink.normalizedWorkspace("") == nil)
        #expect(SlackLink.messageURL(notificationID: "C012AB3CD_1761234567.123456", workspace: "") == nil)
        #expect(SlackLink.messageURL(notificationID: "not-a-slack-id", workspace: "team.slack.com") == nil)
    }
}
