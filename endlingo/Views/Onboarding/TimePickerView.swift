import SwiftUI

struct TimePickerView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("언제 문장을 받을까요?")
                        .font(.title.bold())
                    Text("매일 정해진 시간에 알림을 보내드릴게요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 32)

                // Time picker
                VStack(spacing: 16) {
                    Image("doodle-bell")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .padding(.bottom, 8)

                    DatePicker(
                        "알림 시간",
                        selection: Binding(
                            get: { viewModel.notificationTime },
                            set: { viewModel.notificationTime = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

                // Suggestion chips
                VStack(alignment: .leading, spacing: 12) {
                    Text("추천 시간")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TimeChip(label: String(localized: "아침 7시"), hour: 7, minute: 0, viewModel: viewModel)
                        TimeChip(label: String(localized: "점심 12시"), hour: 12, minute: 0, viewModel: viewModel)
                        TimeChip(label: String(localized: "저녁 9시"), hour: 21, minute: 0, viewModel: viewModel)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .readableContentWidth(600)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TimeChip: View {
    let label: String
    let hour: Int
    let minute: Int
    @Bindable var viewModel: OnboardingViewModel

    private var isSelected: Bool {
        viewModel.selectedHour == hour && viewModel.selectedMinute == minute
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedHour = hour
                viewModel.selectedMinute = minute
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
