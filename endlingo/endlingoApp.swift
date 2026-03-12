//
//  endlingoApp.swift
//  endlingo
//
//  Created by seihee han on 3/12/26.
//

import SwiftUI

@main
struct endlingoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingContainerView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
    }
}
