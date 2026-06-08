import Foundation

/// Short design / UX / motivational lines the dino occasionally muses on,
/// shown — rarely — in a speech bubble above its head.
enum Quotes {
    static let all: [String] = [
        "People ignore design that ignores people.",
        "The next big thing is the one that makes the last big thing usable.",
        "Rule of thumb for UX: More options, more problems.",
        "Design isn’t finished until somebody is using it.",
        "Design is everywhere. From the dress you’re wearing to the smartphone you’re holding, it’s design.",
        "Design creates culture. Culture shapes values. Values determine the future.",
        "If you think good design is expensive, you should look at the cost of bad design.",
        "If we want users to like our software, we should design it to behave like a likeable person: respectful, generous and helpful.",
        "Accidents often produce the best solutions… Only you can recognize the difference between an accident and your original intent.",
        "Show, don’t tell.",
        "Redefine risk.",
        "Support radical exposure to users and customers.",
        "You come from the future.",
        "เหนื่อยก็พัก เจอ BUG ก็อย่าท้อ",
        "สติมาโปรแกรมเกิด สติเตลิด error กระจาย",
    ]

    static func random() -> String { all.randomElement() ?? "" }
}
