import SwiftUI

typealias PhoneStyle = CompanionStyle

struct PhoneRule: View {
    var body: some View { Rectangle().fill(PhoneStyle.line).frame(height: 0.5).accessibilityHidden(true) }
}

struct PhonePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
