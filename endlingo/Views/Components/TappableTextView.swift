import SwiftUI

struct TappableTextView: View {
    let text: String
    var highlightRange: NSRange? = nil
    let onWordTap: (String) -> Void

    private var attributedText: AttributedString {
        let words = text.components(separatedBy: " ")
        var result = AttributedString()
        var charIndex = 0

        for (index, word) in words.enumerated() {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            var attr = AttributedString(word)

            // 현재 읽고 있는 단어 하이라이트
            if let range = highlightRange {
                let wordRange = NSRange(location: charIndex, length: word.count)
                if NSIntersectionRange(wordRange, range).length > 0 {
                    attr.backgroundColor = .teal.opacity(0.3)
                }
            }

            if !cleaned.isEmpty,
               let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
               let url = URL(string: "yeongeohaja-word://\(encoded)") {
                attr.link = url
            }

            result.append(attr)
            charIndex += word.count

            if index < words.count - 1 {
                result.append(AttributedString(" "))
                charIndex += 1
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
