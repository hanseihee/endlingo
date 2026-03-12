import SwiftUI

struct MeaningSelectionGrid: View {
    let meanings: [WordMeaning]
    @Binding var selected: Set<UUID>

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(meanings) { item in
                let isOn = selected.contains(item.id)
                Button {
                    if isOn {
                        selected.remove(item.id)
                    } else {
                        selected.insert(item.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if !item.pos.isEmpty {
                            Text(item.pos)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                                .font(.callout)
                                .foregroundStyle(.primary)
                            if !item.synonyms.isEmpty {
                                Text(item.synonyms.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? .blue : .secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isOn ? Color.blue.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isOn ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
