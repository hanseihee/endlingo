import SwiftUI

struct TappableTextView: View {
    let text: String
    let onWordTap: (String) -> Void

    private var attributedText: AttributedString {
        let words = text.components(separatedBy: " ")
        var result = AttributedString()

        for (index, word) in words.enumerated() {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            var attr = AttributedString(word)

            if !cleaned.isEmpty,
               let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
               let url = URL(string: "yeongeohaja-word://\(encoded)") {
                attr.link = url
            }

            result.append(attr)

            if index < words.count - 1 {
                result.append(AttributedString(" "))
            }
        }

        return result
    }

    var body: some View {
        Text(attributedText)
            .font(.title3.weight(.medium))
            .tint(.primary)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "yeongeohaja-word",
                   let word = url.host?.removingPercentEncoding {
                    onWordTap(word)
                }
                return .handled
            })
    }
}
