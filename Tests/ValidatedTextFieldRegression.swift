import AppKit
import SwiftUI

final class ValidatedTextFieldTests {
    @MainActor
    func testFocusLossWithoutUserEditDoesNotCommit() {
        var text = "3000"
        var commits = 0
        let view = ValidatedTextField(text: Binding(get: { text }, set: { text = $0 }),
                                      filter: { _, value in value }, onCommit: { commits += 1 })
        let coordinator = view.makeCoordinator()
        let field = NSTextField(string: text)
        coordinator.field = field
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        expectEqual(commits, 0, "Opening a window and clearing initial focus must not send a lamp command")
    }

    @MainActor
    func testUserEditCommitsOnceDespiteRepeatedEndEditing() {
        var text = "3000"
        var commits = 0
        let view = ValidatedTextField(text: Binding(get: { text }, set: { text = $0 }),
                                      filter: { _, value in value }, onCommit: { commits += 1 })
        let coordinator = view.makeCoordinator()
        let field = NSTextField(string: "4000")
        coordinator.field = field
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let ended = Notification(name: NSControl.textDidEndEditingNotification, object: field)
        coordinator.controlTextDidEndEditing(ended)
        coordinator.controlTextDidEndEditing(ended)
        expectEqual(text, "4000")
        expectEqual(commits, 1)
    }

    @MainActor
    func testDeviceRefreshAndRejectedInputDoNotCommit() {
        var text = "3000"
        var commits = 0
        let view = ValidatedTextField(text: Binding(get: { text }, set: { text = $0 }),
                                      filter: { old, _ in old }, onCommit: { commits += 1 })
        let coordinator = view.makeCoordinator()
        let field = NSTextField(string: "4000")
        coordinator.field = field
        text = "4000" // Device refresh, not keyboard input.
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        field.stringValue = "invalid"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        expectEqual(text, "4000")
        expectEqual(commits, 0)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    precondition(actual == expected, "Expected \(expected), got \(actual). \(message)", file: file, line: line)
}

@main
struct RegressionTests {
    @MainActor static func main() {
        let tests = ValidatedTextFieldTests()
        tests.testFocusLossWithoutUserEditDoesNotCommit()
        tests.testUserEditCommitsOnceDespiteRepeatedEndEditing()
        tests.testDeviceRefreshAndRejectedInputDoNotCommit()
        print("PASS: 3 text-field regression tests; no lamp/network calls made.")
    }
}
