import SwiftUI

@Observable
final class OnboardingViewModel {
    var currentStep: OnboardingStep = .level
    var selectedLevel: EnglishLevel?
    var selectedEnvironment: LearningEnvironment?
    var selectedHour: Int = 9
    var selectedMinute: Int = 0

    var notificationTime: Date {
        get {
            var components = DateComponents()
            components.hour = selectedHour
            components.minute = selectedMinute
            return Calendar.current.date(from: components) ?? .now
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            selectedHour = components.hour ?? 9
            selectedMinute = components.minute ?? 0
        }
    }

    var canProceed: Bool {
        switch currentStep {
        case .level:       return selectedLevel != nil
        case .environment: return selectedEnvironment != nil
        case .time:        return true
        case .complete:    return true
        }
    }

    var progress: Double {
        switch currentStep {
        case .level:       return 0.33
        case .environment: return 0.66
        case .time:        return 1.0
        case .complete:    return 1.0
        }
    }

    func next() {
        withAnimation(.easeInOut(duration: 0.3)) {
            switch currentStep {
            case .level:       currentStep = .environment
            case .environment: currentStep = .time
            case .time:        currentStep = .complete
            case .complete:    completeOnboarding()
            }
        }
    }

    func back() {
        withAnimation(.easeInOut(duration: 0.3)) {
            switch currentStep {
            case .level:       break
            case .environment: currentStep = .level
            case .time:        currentStep = .environment
            case .complete:    currentStep = .time
            }
        }
    }

    func completeOnboarding() {
        guard let level = selectedLevel,
              let environment = selectedEnvironment else { return }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(level.rawValue, forKey: "selectedLevel")
        UserDefaults.standard.set(environment.rawValue, forKey: "selectedEnvironment")
        UserDefaults.standard.set(selectedHour, forKey: "notificationHour")
        UserDefaults.standard.set(selectedMinute, forKey: "notificationMinute")
    }
}

enum OnboardingStep {
    case level
    case environment
    case time
    case complete
}
