import EventKit
import Foundation

enum MeetingLinks {
    private static let patterns: [String] = [
        #"https?://[a-zA-Z0-9.-]*zoom\.us/[^\s<>"']+"#,
        #"https?://meet\.google\.com/[^\s<>"']+"#,
        #"https?://teams\.microsoft\.com/l/meetup-join/[^\s<>"']+"#,
        #"https?://teams\.live\.com/meet/[^\s<>"']+"#,
        #"https?://[a-zA-Z0-9.-]*webex\.com/[^\s<>"']+"#,
        #"https?://[a-zA-Z0-9.-]*whereby\.com/[^\s<>"']+"#,
    ]

    static func detect(in event: EKEvent) -> URL? {
        var haystacks: [String] = []
        if let url = event.url?.absoluteString { haystacks.append(url) }
        if let location = event.location { haystacks.append(location) }
        if let notes = event.notes { haystacks.append(notes) }
        return detect(in: haystacks)
    }

    static func detect(in haystacks: [String]) -> URL? {
        for text in haystacks {
            for pattern in patterns {
                if let range = text.range(of: pattern, options: .regularExpression),
                   let url = URL(string: String(text[range])) {
                    return url
                }
            }
        }
        return nil
    }
}
