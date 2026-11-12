import UIKit
import Vision

/// Identificação de alimentos 100% no aparelho, usando o framework Vision:
/// 1) classificação de imagem (VNClassifyImageRequest) — rótulos genéricos em inglês;
/// 2) leitura de texto (OCR) — útil para cupom fiscal e embalagens.
/// O resultado é sempre uma SUGESTÃO, confirmada manualmente pelo usuário.
struct FoodCandidate: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var confidence: Double
    var source: String // "imagem" ou "texto"
}

enum FoodRecognizer {

    static func recognize(_ image: UIImage) async -> [FoodCandidate] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            let classify = VNClassifyImageRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            text.recognitionLanguages = ["pt-BR", "en-US"]
            do { try handler.perform([classify, text]) } catch { return [] }

            var found: [String: FoodCandidate] = [:]
            for obs in classify.results ?? [] where obs.confidence > 0.12 {
                if let pt = FoodDictionary.fromVisionLabel(obs.identifier) {
                    let c = FoodCandidate(name: pt, confidence: Double(obs.confidence), source: "imagem")
                    if (found[pt]?.confidence ?? 0) < c.confidence { found[pt] = c }
                }
            }
            for obs in text.results ?? [] {
                guard let line = obs.topCandidates(1).first?.string else { continue }
                for pt in FoodDictionary.fromText(line) where found[pt] == nil {
                    found[pt] = FoodCandidate(name: pt, confidence: Double(obs.confidence), source: "texto")
                }
            }
            return found.values.sorted { $0.confidence > $1.confidence }
        }.value
    }
}

enum FoodDictionary {
    /// Rótulos do classificador do Vision (inglês) -> nome em português.
    static let visionLabels: [String: String] = [
        "banana": "Banana", "apple": "Maçã", "orange": "Laranja", "lemon": "Limão", "lime": "Limão",
        "strawberry": "Morango", "grape": "Uva", "pineapple": "Abacaxi", "watermelon": "Melancia",
        "melon": "Melão", "mango": "Manga", "papaya": "Mamão", "avocado": "Abacate", "pear": "Pera",
        "egg": "Ovos", "bread": "Pão", "baguette": "Pão", "rice": "Arroz", "pasta": "Macarrão",
        "spaghetti": "Macarrão", "noodle": "Macarrão", "potato": "Batata", "sweet_potato": "Batata-doce",
        "tomato": "Tomate", "onion": "Cebola", "garlic": "Alho", "carrot": "Cenoura", "broccoli": "Brócolis",
        "cauliflower": "Couve-flor", "lettuce": "Alface", "cabbage": "Repolho", "cucumber": "Pepino",
        "bell_pepper": "Pimentão", "pepper": "Pimentão", "pumpkin": "Abóbora", "squash": "Abóbora",
        "zucchini": "Abobrinha", "corn": "Milho", "mushroom": "Cogumelo", "beans": "Feijão", "bean": "Feijão",
        "chicken": "Frango", "poultry": "Frango", "meat": "Carne", "beef": "Carne", "steak": "Carne",
        "pork": "Carne suína", "sausage": "Linguiça", "ham": "Presunto", "bacon": "Bacon", "fish": "Peixe",
        "salmon": "Salmão", "tuna": "Atum", "shrimp": "Camarão", "cheese": "Queijo", "milk": "Leite",
        "yogurt": "Iogurte", "butter": "Manteiga", "coffee": "Café", "oats": "Aveia", "cereal": "Cereal",
        "chocolate": "Chocolate", "cookie": "Biscoito", "cracker": "Biscoito", "juice": "Suco",
        "flour": "Farinha", "sugar": "Açúcar", "honey": "Mel", "peanut": "Amendoim", "nut": "Castanhas",
        "coconut": "Coco", "spinach": "Espinafre", "kale": "Couve", "beet": "Beterraba", "olive_oil": "Azeite",
    ]

    /// Palavras (sem acento) encontradas em cupons/embalagens -> nome em português.
    static let textKeywords: [(String, String)] = [
        ("arroz", "Arroz"), ("feijao", "Feijão"), ("ovo", "Ovos"), ("frango", "Frango"), ("peito de frango", "Frango"),
        ("carne moida", "Carne moída"), ("patinho", "Carne"), ("acem", "Carne"), ("alcatra", "Carne"), ("carne", "Carne"),
        ("batata doce", "Batata-doce"), ("batata", "Batata"), ("cebola", "Cebola"), ("alho", "Alho"), ("tomate", "Tomate"),
        ("leite", "Leite"), ("queijo", "Queijo"), ("mussarela", "Queijo"), ("pao folha", "Pão folha"), ("pao", "Pão"), ("macarrao", "Macarrão"),
        ("espaguete", "Macarrão"), ("banana", "Banana"), ("maca", "Maçã"), ("aveia", "Aveia"), ("iogurte", "Iogurte"),
        ("manteiga", "Manteiga"), ("margarina", "Margarina"), ("cenoura", "Cenoura"), ("alface", "Alface"),
        ("brocolis", "Brócolis"), ("peixe", "Peixe"), ("tilapia", "Peixe"), ("atum", "Atum"), ("sardinha", "Sardinha"),
        ("cafe", "Café"), ("farinha de mandioca", "Farinha de mandioca"), ("farinha", "Farinha"), ("mandioca", "Mandioca"),
        ("abobora", "Abóbora"), ("abobrinha", "Abobrinha"), ("pimentao", "Pimentão"), ("laranja", "Laranja"),
        ("limao", "Limão"), ("mamao", "Mamão"), ("presunto", "Presunto"), ("requeijao", "Requeijão"), ("milho", "Milho"),
        ("ervilha", "Ervilha"), ("grao de bico", "Grão-de-bico"), ("lentilha", "Lentilha"), ("tapioca", "Tapioca"),
        ("flocao", "Flocão de milho"), ("cuscuz", "Flocão de milho"), ("azeite", "Azeite"), ("oleo", "Óleo"),
        ("acucar", "Açúcar"), ("sal ", "Sal"), ("linguica", "Linguiça"), ("wrap", "Pão folha"),
    ]

    static func fromVisionLabel(_ label: String) -> String? {
        let l = label.lowercased()
        if let v = visionLabels[l] { return v }
        // rótulos compostos ("granny_smith_apple")
        return visionLabels.first { l.hasSuffix("_" + $0.key) || l.hasPrefix($0.key + "_") }?.value
    }

    static func fromText(_ line: String) -> [String] {
        let f = " " + line.folded + " "
        var result: [String] = []
        var consumed = f
        for (key, name) in textKeywords where consumed.contains(key) {
            if !result.contains(name) { result.append(name) }
            consumed = consumed.replacingOccurrences(of: key, with: " ")
        }
        return result
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
