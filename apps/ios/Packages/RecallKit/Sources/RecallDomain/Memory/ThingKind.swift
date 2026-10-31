import Foundation

/// What kind of thing it is, for its icon: read from the user's own name for it first, then the label the scan gave.
/// Only a thing Recall is sure about gets its own icon; an unsure one gets the box, so the picture never claims more
/// than the scan knows.
public enum ThingKind: String, CaseIterable, Sendable {
    case keys, wallet, handbag, backpack, book, bottle, glasses, phone, remote, mug, laptop, headphones, charger, watch,
         passport, unknown

    /// Words people and the scan use, longest first so "remote control" wins over "remote".
    static let words: [(String, ThingKind)] = [
        ("remote control", .remote), ("reading glasses", .glasses), ("water bottle", .bottle), ("key ring", .keys),
        ("handbag", .handbag), ("purse", .handbag), ("tote", .handbag), ("bag", .handbag), ("clutch", .handbag),
        ("backpack", .backpack), ("rucksack", .backpack),
        ("keys", .keys), ("key", .keys), ("wallet", .wallet), ("cardholder", .wallet),
        ("book", .book), ("notebook", .book), ("bottle", .bottle), ("flask", .bottle),
        ("sunglasses", .glasses), ("spectacles", .glasses), ("glasses", .glasses),
        ("phone", .phone), ("iphone", .phone), ("mobile", .phone), ("remote", .remote),
        ("mug", .mug), ("cup", .mug), ("laptop", .laptop), ("macbook", .laptop),
        ("headphones", .headphones), ("earphones", .headphones), ("airpods", .headphones), ("earbuds", .headphones),
        ("charger", .charger), ("cable", .charger), ("watch", .watch), ("passport", .passport),
    ].sorted { $0.0.count > $1.0.count }

    /// The kind named by `name` (the user's) or else `label` (the scan's); `.unknown` when neither says.
    public static func of(label: String, name: String? = nil) -> ThingKind {
        for text in [name, label].compactMap({ $0?.lowercased() }) {
            let tokens = Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
            for (word, kind) in words {
                let hit = word.contains(" ") ? text.contains(word) : tokens.contains(word) || tokens.contains(word + "s")
                if hit { return kind }
            }
        }
        return .unknown
    }

    /// How a list names a group of this kind ("Bags", "Keys").
    public var plural: String {
        switch self {
        case .keys: "Keys"
        case .wallet: "Wallets"
        case .handbag: "Bags"
        case .backpack: "Backpacks"
        case .book: "Books"
        case .bottle: "Bottles"
        case .glasses: "Glasses"
        case .phone: "Phones"
        case .remote: "Remotes"
        case .mug: "Mugs"
        case .laptop: "Laptops"
        case .headphones: "Headphones"
        case .charger: "Chargers"
        case .watch: "Watches"
        case .passport: "Passports"
        case .unknown: "Other things"
        }
    }
}

extension Thing {
    /// What it is, from its name or label (whatever the certainty).
    public var kind: ThingKind { ThingKind.of(label: label, name: name) }

    /// The icon to show: its kind when Recall is sure (or the user checked it), else the box.
    public var iconKind: ThingKind { needsReview && !confirmed ? .unknown : kind }
}
