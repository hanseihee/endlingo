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

            Tab("단어장", image: "tab-vocabulary", value: 1) {
                VocabularyView()
            }

            Tab("퀴즈", image: "tab-quiz", value: 2) {
                QuizTabView()
            }

            Tab("전화영어", image: "tab-phone", value: 3) {
                PhoneCallLauncherView()
            }

            Tab("프로필", image: "tab-profile", value: 4) {
                ProfileView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Color.accentColor)
    }
}

#Preview {
    ContentView()
}
