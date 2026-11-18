import Testing
@testable import ClaudeUsageBar

struct StatusTitleTests {
    @Test(arguments: [
        (79, StatusTitle.Tone.normal),
        (80, .warning),
        (94, .warning),
        (95, .critical),
        (100, .critical),
    ])
    func toneFollowsUsedPercent(used: Int, expected: StatusTitle.Tone) {
        let value = StatusTitle.Value(usedPercent: used, hasFailure: false)

        #expect(value.text == "\(used)%")
        #expect(value.tone == expected)
    }

    @Test func missingDataShowsPlaceholder() {
        let title = StatusTitle(snapshot: nil, failure: nil)

        #expect(title.session.text == "–%")
        #expect(title.weekly.text == "–%")
        #expect(title.session.tone == .normal)
    }

    @Test func failureMutesLastValues() throws {
        let title = StatusTitle(snapshot: try TestData.snapshot(), failure: .temporary)

        #expect(title.session.text == "21%")
        #expect(title.weekly.text == "74%")
        #expect(title.session.tone == .muted)
        #expect(title.weekly.tone == .muted)
    }
}
