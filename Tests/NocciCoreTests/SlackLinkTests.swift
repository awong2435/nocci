import Foundation
import Testing
@testable import NocciCore

struct SlackLinkTests {
    @Test func buildsTheAppLinkWithTeamChannelAndMessage() {
        let url = SlackLink.appURL(notificationID: "C012AB3CD_1761234567.123456", teamID: "T01ABCDEF")
        #expect(url?.absoluteString == "slack://channel?team=T01ABCDEF&id=C012AB3CD&message=1761234567.123456")
    }

    @Test func acceptsTheTeamIDInCommonPastedForms() {
        for text in ["T01ABCDEF", " t01abcdef ", "https://app.slack.com/client/T01ABCDEF/C012AB3CD"] {
            #expect(SlackLink.normalizedTeamID(text) == "T01ABCDEF")
        }
    }

    @Test func refusesOddTeamIDsAndNotificationIDs() {
        #expect(SlackLink.normalizedTeamID("") == nil)
        #expect(SlackLink.normalizedTeamID("example.slack.com") == nil)
        #expect(SlackLink.appURL(notificationID: "C012AB3CD_1761234567.123456", teamID: "") == nil)
        #expect(SlackLink.appURL(notificationID: "not-a-slack-id", teamID: "T01ABCDEF") == nil)
    }
}
