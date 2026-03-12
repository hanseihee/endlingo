import SwiftUI

struct SpeakButton: View {
    let text: String
    let id: String
    var font: Font = .caption
    var color: Color = .blue

    @State private var speech = SpeechService.shared

    var body: some View {
        Button {
            speech.speak(text, id: id)
        } label: {
            Image(systemName: speech.isSpeaking(id: id) ? "speaker.wave.3.fill" : "speaker.wave.2")
                .font(font)
                .foregroundStyle(color)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
