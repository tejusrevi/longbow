import CoreGraphics
import LongbowCore

/// A person built from parts, in the spirit of Notion Faces (spec A14a).
/// Stored as small integers, never as an image. Every archer in the game —
/// Bjorn, Gus, every preset — is made only from these parts, so anyone you
/// see can be built in the editor. The one exception is Tiger.
struct Avatar: Codable, Hashable {
    var head = 0
    var skin = 0
    var hair = 0
    var brows = 0
    var eyes = 0
    var nose = 0
    var mouth = 0
    var facialHair = 0
    var glasses = 0
    var accessory = 0
    var outfit = 0
    /// 0 black, 1 brown, 2 blonde, 3 grey.
    var hairTone = 0
    /// Tiger, the tabby cat. Only reachable from "Start from"; ignores every
    /// part (Tiger does not do makeovers).
    var tiger = false

    init(head: Int = 0, skin: Int = 0, hair: Int = 0, brows: Int = 0, eyes: Int = 0, nose: Int = 0, mouth: Int = 0,
         facialHair: Int = 0, glasses: Int = 0, accessory: Int = 0, outfit: Int = 0, hairTone: Int = 0,
         tiger: Bool = false) {
        self.head = head; self.skin = skin; self.hair = hair; self.brows = brows; self.eyes = eyes
        self.nose = nose; self.mouth = mouth; self.facialHair = facialHair; self.glasses = glasses
        self.accessory = accessory; self.outfit = outfit; self.hairTone = hairTone; self.tiger = tiger
    }

    // Tolerant decoding: faces saved by older builds keep working (A14a.4).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v(_ k: CodingKeys, _ part: Part) -> Int {
            min(max((try? c.decodeIfPresent(Int.self, forKey: k)) ?? 0, 0), part.count - 1)
        }
        head = v(.head, .head); skin = v(.skin, .skin); hair = v(.hair, .hair); brows = v(.brows, .brows)
        eyes = v(.eyes, .eyes); nose = v(.nose, .nose); mouth = v(.mouth, .mouth)
        facialHair = v(.facialHair, .facialHair); glasses = v(.glasses, .glasses)
        accessory = v(.accessory, .accessory); outfit = v(.outfit, .outfit)
        hairTone = v(.hairTone, .hairTone)
        tiger = (try? c.decodeIfPresent(Bool.self, forKey: .tiger)) ?? false
    }

    // MARK: Presets — a mixed, varied crowd.

    static let bjorn = Avatar(head: 0, skin: 1, hair: 1, brows: 1, eyes: 1, nose: 0, mouth: 0, facialHair: 6, outfit: 9)
    static let gus = Avatar(head: 1, skin: 0, hair: 3, brows: 3, eyes: 1, nose: 1, mouth: 0, facialHair: 3, glasses: 1,
                            outfit: 1)
    static let tigerCat = Avatar(tiger: true)

    /// "Start from": the crew, each made only from parts anyone can pick.
    static let presets: [(String, Avatar)] = [
        ("Tej", Avatar(head: 3, skin: 4, hair: 24, brows: 8, eyes: 4, nose: 0, mouth: 2, facialHair: 14, outfit: 14)),
        ("Jaiden", Avatar(head: 1, skin: 2, hair: 2, brows: 1, eyes: 4, nose: 2, mouth: 2, facialHair: 7, outfit: 2)),
        ("Anand", Avatar(head: 5, skin: 2, hair: 28, brows: 1, eyes: 4, nose: 2, mouth: 0, outfit: 2)),
        ("Aravind", Avatar(head: 1, skin: 2, hair: 27, brows: 2, eyes: 6, nose: 6, mouth: 3, facialHair: 13, outfit: 0)),
        ("Tiger", .tigerCat),
        ("Ducky", Avatar(head: 1, skin: 1, hair: 32, brows: 8, eyes: 4, nose: 2, mouth: 10, facialHair: 1, glasses: 6, outfit: 0)),
        ("Dave", Avatar(head: 0, skin: 3, hair: 25, brows: 2, eyes: 4, nose: 7, mouth: 2, facialHair: 5, outfit: 0)),
        ("Piper", Avatar(head: 1, skin: 0, hair: 26, brows: 5, eyes: 4, nose: 0, mouth: 2, accessory: 4, outfit: 15, hairTone: 1)),
        ("Hal", Avatar(head: 6, skin: 2, hair: 30, brows: 8, eyes: 9, nose: 7, mouth: 5, facialHair: 13, accessory: 4,
                       outfit: 17)),
        ("Bontee", Avatar(head: 0, skin: 2, hair: 29, brows: 5, eyes: 4, nose: 0, mouth: 2, accessory: 11, outfit: 16)),
        ("Siggy", Avatar(head: 0, skin: 4, hair: 30, brows: 8, eyes: 4, nose: 0, mouth: 2, facialHair: 7, glasses: 6, outfit: 0)),
        ("Josh", Avatar(head: 1, skin: 4, hair: 28, brows: 3, eyes: 2, nose: 0, mouth: 5, facialHair: 1, glasses: 1, outfit: 0)),
        ("Farhan", Avatar(head: 1, skin: 2, hair: 31, brows: 2, eyes: 4, nose: 6, mouth: 2, facialHair: 7, outfit: 13)),
        ("Issy", Avatar(head: 5, skin: 2, hair: 28, brows: 5, eyes: 4, nose: 0, mouth: 2, facialHair: 1, outfit: 13)),
    ]

    var key: String {
        if tiger { return "tiger" }
        return "\(head).\(skin).\(hair).\(brows).\(eyes).\(nose).\(mouth).\(facialHair).\(glasses).\(accessory).\(outfit).\(hairTone)"
    }

    /// Body art index: the outfit, or Tiger's fur.
    var wardrobe: Int { tiger ? AvatarArt.tigerFur : outfit }

    // MARK: Parts

    enum Part: String, CaseIterable, Identifiable {
        case head, skin, hair, hairTone, brows, eyes, nose, mouth, facialHair, glasses, accessory, outfit
        var id: String { rawValue }

        var count: Int { Self.names[self]!.count }

        func optionName(_ i: Int) -> String {
            let n = Self.names[self]!
            return n[min(max(i, 0), n.count - 1)]
        }

        static let names: [Part: [String]] = [
            .head: ["round", "oval", "square", "angular", "heart", "chiseled", "broad"],
            .skin: ["paper", "light", "medium", "deep", "deepest"],
            .hairTone: ["black", "brown", "blonde", "grey"],
            .hair: ["bald", "curl", "buzz", "comb-over", "curly", "afro", "bun", "mohawk", "long", "spiky",
                    "bob", "ponytail", "braids", "locs", "waves", "hijab", "quiff", "side part", "pixie",
                    "space buns", "pigtails", "top knot", "turban", "big curls", "curly fringe", "tousled", "flowing", "cap",
                    "curly mop", "low bun", "messy waves", "swept", "big tousled"],
            .brows: ["soft", "bushy", "bold", "worried", "unibrow", "thin arch", "angry", "quizzical", "thick",
                     "dots"],
            .eyes: ["dots", "round", "sleepy", "big", "happy", "lashes", "almond", "wink", "side-eye", "tired",
                    "squint"],
            .nose: ["button", "bulb", "long", "nostrils", "small", "snub", "roman", "potato", "wedge", "pinocchio",
                    "beak"],
            .mouth: ["smile", "flat", "grin", "smirk", "oh", "full lips", "cheeky", "laugh", "buck teeth", "wobbly", "beaming"],
            .facialHair: ["none", "stubble", "handlebar", "walrus", "goatee", "full beard", "viking", "short beard",
                          "pencil", "chinstrap", "mutton chops", "horseshoe", "van dyke", "stache + stubble", "faint beard"],
            .glasses: ["none", "round", "square", "shades", "aviators", "cat-eye", "thick rims", "readers",
                       "hearts", "goggles"],
            .accessory: ["none", "freckles", "eye patch", "scar", "hoops", "headphones", "flower", "pencil",
                         "war paint", "sweatband", "bubblegum", "nose pin"],
            .outfit: ["black tee", "stripes", "dotted jumper", "white tee", "overalls", "hoodie", "suit",
                      "hawaiian", "turtleneck", "flannel", "tank top", "scarf", "rain jacket", "white shirt", "dark shirt",
                      "fleece", "embroidered", "tank + chain"],
        ]
    }

    subscript(part: Part) -> Int {
        get {
            switch part {
            case .head: return head
            case .skin: return skin
            case .hair: return hair
            case .hairTone: return hairTone
            case .brows: return brows
            case .eyes: return eyes
            case .nose: return nose
            case .mouth: return mouth
            case .facialHair: return facialHair
            case .glasses: return glasses
            case .accessory: return accessory
            case .outfit: return outfit
            }
        }
        set {
            switch part {
            case .head: head = newValue
            case .skin: skin = newValue
            case .hair: hair = newValue
            case .hairTone: hairTone = newValue
            case .brows: brows = newValue
            case .eyes: eyes = newValue
            case .nose: nose = newValue
            case .mouth: mouth = newValue
            case .facialHair: facialHair = newValue
            case .glasses: glasses = newValue
            case .accessory: accessory = newValue
            case .outfit: outfit = newValue
            }
        }
    }

    /// A random but readable face: facial hair, glasses and accessories are
    /// occasional, so shuffles don't all look the same. Never Tiger.
    static func random() -> Avatar {
        var a = Avatar()
        for p in Part.allCases { a[p] = Int.random(in: 0..<p.count) }
        if Int.random(in: 0..<3) > 0 { a.facialHair = 0 }
        if Int.random(in: 0..<3) > 0 { a.glasses = 0 }
        if Int.random(in: 0..<2) > 0 { a.accessory = 0 }
        if Int.random(in: 0..<3) > 0 { a.hairTone = 0 }
        return a
    }

    /// Hair that hides the ears (scarves, bobs and long hair).
    var coversHead: Bool { [8, 10, 14, 15, 23].contains(hair) }
}

