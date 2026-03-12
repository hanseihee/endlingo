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

            Tab("기록", systemImage: "calendar", value: 2) {
                HistoryView()
            }

            Tab("프로필", systemImage: "person.fill", value: 3) {
                ProfileView()
            }
        }
        .tint(.blue)
    }
}

#Preview {
    ContentView()
}
