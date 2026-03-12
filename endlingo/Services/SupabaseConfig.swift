import Foundation

enum SupabaseConfig {
    static let projectURL = URL(string: "https://alvawqinuacabfnqduoy.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFsdmF3cWludWFjYWJmbnFkdW95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNjExNDgsImV4cCI6MjA4ODgzNzE0OH0.C-gnavFBHa-gIyvoGngaYfV6htDTiFyOmj5MemIlzhY"

    static let restBaseURL = "https://alvawqinuacabfnqduoy.supabase.co/rest/v1"
    static let functionsBaseURL = "https://alvawqinuacabfnqduoy.supabase.co/functions/v1"

    private static let kstFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f
    }()

    static var todayDateString: String {
        kstFormatter.string(from: Date())
    }
}
