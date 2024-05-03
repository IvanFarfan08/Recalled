import Foundation

// This struct is used to decode JSON data from API responses.
struct RecallDetails: Codable {
    var recallInfo: String
    var userPrompt: String
}
