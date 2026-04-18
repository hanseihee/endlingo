//
//  ContentView.swift
//  endlingo
//
//  Created by seihee han on 3/12/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("오늘의 레슨", image: "tab-lesson", value: 0) {
                LessonView()
            }

            Tab("전화영어", image: "tab-phone", value: 1) {
                PhoneCallLauncherView()
            }

            Tab("단어장", image: "tab-vocabulary", value: 2) {
                VocabularyView()
            }

            Tab("퀴즈", image: "tab-quiz", value: 3) {
                QuizTabView()
            }

            Tab("프로필", image: "tab-profile", value: 4) {
                ProfileView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Color.accentColor)
        // 전화영어 탭 진입 시 interstitial 광고 표시 (Premium·cooldown 자동 처리).
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 {
                InterstitialAdService.shared.showIfReady()
            }
        }
    }
}

#Preview {
    ContentView()
}
