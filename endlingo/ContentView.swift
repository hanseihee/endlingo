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
            Tab("오늘의 레슨", systemImage: "book.fill", value: 0) {
                LessonView()
            }

            Tab("단어장", systemImage: "character.book.closed.fill", value: 1) {
                VocabularyView()
            }

            Tab("퀴즈", systemImage: "questionmark.bubble.fill", value: 2) {
                QuizTabView()
            }

            Tab("기록", systemImage: "calendar", value: 3) {
                HistoryView()
            }

            Tab("프로필", systemImage: "person.fill", value: 4) {
                ProfileView()
            }
        }
        .tint(Color.accentColor)
    }
}

#Preview {
    ContentView()
}
