import Foundation

/// Catálogo local de receitas simples, econômicas e equilibradas.
/// Valores nutricionais são ESTIMATIVAS aproximadas por porção, apenas para referência.
struct CatalogRecipe {
    let key: String
    let name: String
    let minutes: Int
    let servings: Int
    let ingredients: [(String, String)] // (nome, quantidade)
    let steps: [String]
    let kcal: Double, protein: Double, carbs: Double, fat: Double
    let tags: [String]

    func makeModel() -> Recipe {
        let r = Recipe(name: name)
        r.catalogKey = key
        r.ingredientNames = ingredients.map(\.0)
        r.ingredientQuantities = ingredients.map(\.1)
        r.steps = steps
        r.minutes = minutes
        r.servings = servings
        r.kcal = kcal; r.protein = protein; r.carbs = carbs; r.fat = fat
        r.tags = tags
        r.isBuiltIn = true
        return r
    }
}

enum RecipeCatalog {
    static let all: [CatalogRecipe] = [
        CatalogRecipe(key: "omelete-legumes", name: "Omelete de legumes", minutes: 10, servings: 1,
                      ingredients: [("Ovos", "2 unidades"), ("Tomate", "1/2 unidade"), ("Cebola", "1/4 unidade"), ("Sal", "a gosto")],
                      steps: ["Bata os ovos com uma pitada de sal.", "Pique o tomate e a cebola e misture aos ovos.", "Despeje em frigideira untada e cozinhe em fogo baixo, tampado, por 4 minutos.", "Dobre ao meio e sirva."],
                      kcal: 190, protein: 13, carbs: 6, fat: 12, tags: ["rápida", "proteica"]),
        CatalogRecipe(key: "arroz-feijao-ovo", name: "Prato feito com ovo", minutes: 15, servings: 1,
                      ingredients: [("Arroz", "1 xícara cozido"), ("Feijão", "1 concha"), ("Ovos", "1 unidade"), ("Alface", "folhas a gosto")],
                      steps: ["Aqueça o arroz e o feijão já cozidos.", "Frite ou cozinhe o ovo.", "Monte o prato com salada de alface."],
                      kcal: 480, protein: 19, carbs: 72, fat: 11, tags: ["econômica", "equilibrada"]),
        CatalogRecipe(key: "frango-grelhado-batata", name: "Frango grelhado com batata", minutes: 30, servings: 2,
                      ingredients: [("Frango", "300 g de peito"), ("Batata", "2 unidades"), ("Alho", "2 dentes"), ("Limão", "1/2 unidade"), ("Sal", "a gosto")],
                      steps: ["Tempere o frango com alho, limão e sal.", "Cozinhe as batatas em cubos por 12 minutos.", "Grelhe o frango 5 minutos de cada lado.", "Doure as batatas na mesma frigideira e sirva."],
                      kcal: 390, protein: 38, carbs: 33, fat: 9, tags: ["proteica"]),
        CatalogRecipe(key: "frango-arroz-brocolis", name: "Frango com arroz e brócolis", minutes: 25, servings: 2,
                      ingredients: [("Frango", "300 g"), ("Arroz", "1 xícara cru"), ("Brócolis", "1 maço pequeno"), ("Alho", "2 dentes"), ("Sal", "a gosto")],
                      steps: ["Cozinhe o arroz.", "Doure o frango em cubos com alho.", "Cozinhe o brócolis no vapor por 5 minutos.", "Misture tudo e ajuste o sal."],
                      kcal: 520, protein: 40, carbs: 68, fat: 8, tags: ["equilibrada", "marmita"]),
        CatalogRecipe(key: "macarrao-alho-oleo-atum", name: "Macarrão alho e óleo com atum", minutes: 20, servings: 2,
                      ingredients: [("Macarrão", "200 g"), ("Atum", "1 lata"), ("Alho", "3 dentes"), ("Azeite", "2 colheres"), ("Sal", "a gosto")],
                      steps: ["Cozinhe o macarrão em água com sal.", "Doure o alho no azeite.", "Junte o atum escorrido e o macarrão.", "Misture bem e sirva."],
                      kcal: 560, protein: 30, carbs: 78, fat: 14, tags: ["rápida", "econômica"]),
        CatalogRecipe(key: "carne-moida-batata", name: "Carne moída com batata", minutes: 30, servings: 3,
                      ingredients: [("Carne moída", "400 g"), ("Batata", "3 unidades"), ("Cebola", "1 unidade"), ("Tomate", "1 unidade"), ("Sal", "a gosto")],
                      steps: ["Refogue a cebola e a carne até dourar.", "Junte o tomate picado.", "Acrescente batatas em cubos e um pouco de água.", "Cozinhe tampado por 15 minutos."],
                      kcal: 410, protein: 29, carbs: 28, fat: 19, tags: ["marmita"]),
        CatalogRecipe(key: "panqueca-banana-aveia", name: "Panqueca de banana e aveia", minutes: 10, servings: 1,
                      ingredients: [("Banana", "1 unidade"), ("Ovos", "1 unidade"), ("Aveia", "2 colheres")],
                      steps: ["Amasse a banana.", "Misture o ovo e a aveia.", "Cozinhe em frigideira antiaderente, 2 minutos de cada lado."],
                      kcal: 250, protein: 10, carbs: 36, fat: 7, tags: ["café da manhã", "rápida"]),
        CatalogRecipe(key: "crepioca", name: "Crepioca com queijo", minutes: 8, servings: 1,
                      ingredients: [("Ovos", "1 unidade"), ("Tapioca", "2 colheres"), ("Queijo", "1 fatia")],
                      steps: ["Misture o ovo e a goma de tapioca.", "Despeje na frigideira quente.", "Recheie com queijo, dobre e sirva."],
                      kcal: 260, protein: 13, carbs: 25, fat: 11, tags: ["café da manhã", "rápida"]),
        CatalogRecipe(key: "mexido-ovos-cuscuz", name: "Cuscuz com ovos mexidos", minutes: 15, servings: 1,
                      ingredients: [("Flocão de milho", "1/2 xícara"), ("Ovos", "2 unidades"), ("Sal", "a gosto")],
                      steps: ["Hidrate o flocão com água e sal por 5 minutos.", "Cozinhe no vapor (cuscuzeira) por 8 minutos.", "Faça os ovos mexidos e sirva junto."],
                      kcal: 380, protein: 16, carbs: 48, fat: 11, tags: ["econômica", "café da manhã"]),
        CatalogRecipe(key: "sopa-legumes", name: "Sopa de legumes", minutes: 30, servings: 3,
                      ingredients: [("Batata", "2 unidades"), ("Cenoura", "1 unidade"), ("Abobrinha", "1 unidade"), ("Cebola", "1 unidade"), ("Sal", "a gosto")],
                      steps: ["Pique todos os legumes.", "Refogue a cebola.", "Junte os legumes e cubra com água.", "Cozinhe por 20 minutos e ajuste o sal."],
                      kcal: 150, protein: 4, carbs: 30, fat: 2, tags: ["leve", "econômica"]),
        CatalogRecipe(key: "salada-grao-bico", name: "Salada de grão-de-bico", minutes: 10, servings: 2,
                      ingredients: [("Grão-de-bico", "1 lata ou 1 xícara cozido"), ("Tomate", "1 unidade"), ("Cebola", "1/2 unidade"), ("Limão", "1/2 unidade"), ("Azeite", "1 colher")],
                      steps: ["Escorra o grão-de-bico.", "Pique tomate e cebola.", "Tempere com limão, azeite e sal."],
                      kcal: 260, protein: 11, carbs: 35, fat: 8, tags: ["vegetariana", "sem fogão"]),
        CatalogRecipe(key: "iogurte-frutas-aveia", name: "Iogurte com frutas e aveia", minutes: 5, servings: 1,
                      ingredients: [("Iogurte", "1 pote"), ("Banana", "1 unidade"), ("Aveia", "2 colheres")],
                      steps: ["Coloque o iogurte em uma tigela.", "Adicione banana em rodelas e aveia."],
                      kcal: 280, protein: 11, carbs: 45, fat: 6, tags: ["lanche", "sem fogão"]),
        CatalogRecipe(key: "tilapia-legumes", name: "Peixe assado com legumes", minutes: 30, servings: 2,
                      ingredients: [("Peixe", "2 filés"), ("Batata", "2 unidades"), ("Cenoura", "1 unidade"), ("Limão", "1 unidade"), ("Azeite", "1 colher")],
                      steps: ["Tempere o peixe com limão e sal.", "Corte legumes em rodelas finas.", "Asse tudo a 200 °C por 25 minutos."],
                      kcal: 340, protein: 32, carbs: 30, fat: 9, tags: ["proteica", "forno"]),
        CatalogRecipe(key: "feijao-tropeiro-simples", name: "Mexido de feijão com ovo", minutes: 15, servings: 2,
                      ingredients: [("Feijão", "2 xícaras cozido"), ("Ovos", "2 unidades"), ("Farinha de mandioca", "4 colheres"), ("Cebola", "1/2 unidade")],
                      steps: ["Refogue a cebola.", "Junte os ovos e mexa.", "Acrescente o feijão escorrido e a farinha aos poucos."],
                      kcal: 360, protein: 17, carbs: 50, fat: 9, tags: ["econômica"]),
        CatalogRecipe(key: "wrap-frango", name: "Wrap de frango", minutes: 15, servings: 2,
                      ingredients: [("Pão folha", "2 unidades"), ("Frango", "200 g desfiado"), ("Alface", "folhas"), ("Tomate", "1 unidade"), ("Requeijão", "2 colheres")],
                      steps: ["Aqueça o frango desfiado temperado.", "Passe requeijão no pão folha.", "Recheie com frango, alface e tomate e enrole."],
                      kcal: 380, protein: 30, carbs: 35, fat: 12, tags: ["rápida", "lanche"]),
        CatalogRecipe(key: "arroz-de-forno", name: "Arroz de forno com frango", minutes: 35, servings: 4,
                      ingredients: [("Arroz", "3 xícaras cozido"), ("Frango", "250 g desfiado"), ("Milho", "1 lata"), ("Queijo", "100 g"), ("Tomate", "1 unidade")],
                      steps: ["Misture arroz, frango, milho e tomate picado.", "Coloque em refratário e cubra com queijo.", "Asse até gratinar (15 minutos)."],
                      kcal: 430, protein: 26, carbs: 52, fat: 12, tags: ["forno", "marmita"]),
        CatalogRecipe(key: "pure-batata-carne", name: "Purê de batata com carne", minutes: 30, servings: 2,
                      ingredients: [("Batata", "4 unidades"), ("Leite", "1/2 xícara"), ("Manteiga", "1 colher"), ("Carne moída", "250 g")],
                      steps: ["Cozinhe e amasse as batatas com leite e manteiga.", "Refogue a carne moída temperada.", "Sirva o purê com a carne por cima."],
                      kcal: 470, protein: 28, carbs: 42, fat: 20, tags: ["conforto"]),
        CatalogRecipe(key: "salada-atum", name: "Salada completa com atum", minutes: 10, servings: 1,
                      ingredients: [("Atum", "1 lata"), ("Alface", "1 prato"), ("Tomate", "1 unidade"), ("Milho", "2 colheres"), ("Ovos", "1 cozido")],
                      steps: ["Lave e corte as folhas e o tomate.", "Junte atum, milho e ovo cozido.", "Tempere com azeite, limão e sal."],
                      kcal: 330, protein: 34, carbs: 14, fat: 15, tags: ["leve", "proteica", "sem fogão"]),
        CatalogRecipe(key: "abobora-refogada-carne", name: "Abóbora refogada com carne", minutes: 25, servings: 2,
                      ingredients: [("Abóbora", "400 g"), ("Carne moída", "200 g"), ("Cebola", "1 unidade"), ("Alho", "2 dentes")],
                      steps: ["Refogue cebola, alho e carne.", "Junte a abóbora em cubos e um pouco de água.", "Cozinhe tampado até amaciar."],
                      kcal: 330, protein: 24, carbs: 22, fat: 15, tags: ["equilibrada"]),
        CatalogRecipe(key: "lentilha-arroz", name: "Arroz com lentilha", minutes: 30, servings: 3,
                      ingredients: [("Arroz", "1 xícara cru"), ("Lentilha", "1 xícara"), ("Cebola", "1 unidade"), ("Azeite", "1 colher")],
                      steps: ["Cozinhe a lentilha por 10 minutos.", "Refogue a cebola, junte arroz, lentilha e água.", "Cozinhe até secar. Sirva com cebola dourada por cima."],
                      kcal: 390, protein: 16, carbs: 70, fat: 5, tags: ["vegetariana", "econômica"]),
        CatalogRecipe(key: "vitamina-banana", name: "Vitamina de banana", minutes: 5, servings: 1,
                      ingredients: [("Leite", "300 ml"), ("Banana", "1 unidade"), ("Aveia", "1 colher")],
                      steps: ["Bata tudo no liquidificador e sirva gelado."],
                      kcal: 300, protein: 12, carbs: 45, fat: 8, tags: ["lanche", "rápida"]),
    ]
}

/// Sugere receitas a partir do estoque, priorizando o que já existe em casa.
enum RecipeEngine {
    /// Ingredientes de despensa básica ignorados no cálculo.
    static let staples: Set<String> = ["sal", "pimenta", "agua", "oleo", "azeite", "acucar", "alho", "temperos"]

    static func canonical(_ name: String) -> String {
        var n = name.folded.trimmed
        n = n.replacingOccurrences(of: #"\s+de\s+"#, with: " ", options: .regularExpression)
        n = n.replacingOccurrences(of: "-", with: " ")
        if n.hasSuffix("oes") { n = String(n.dropLast(3)) + "ao" }
        else if n.hasSuffix("s") && n.count > 3 { n = String(n.dropLast()) }
        return n
    }

    static func has(_ ingredient: String, in pantry: Set<String>) -> Bool {
        let c = canonical(ingredient)
        if staples.contains(c) { return true }
        return pantry.contains { $0 == c || $0.contains(c) || c.contains($0) }
    }

    struct Suggestion: Identifiable {
        let recipe: Recipe
        let have: [String]
        let missing: [String]
        var id: UUID { recipe.id }
        var score: Double {
            let total = have.count + missing.count
            return total == 0 ? 0 : Double(have.count) / Double(total)
        }
    }

    static func suggestions(recipes: [Recipe], pantry: [PantryItem], minScore: Double = 0.5) -> [Suggestion] {
        let stock = Set(pantry.filter { $0.quantity > 0 }.map { canonical($0.name) })
        return recipes.map { r in
            let relevant = r.ingredientNames.filter { !staples.contains(canonical($0)) }
            let have = relevant.filter { has($0, in: stock) }
            let missing = relevant.filter { !has($0, in: stock) }
            return Suggestion(recipe: r, have: have, missing: missing)
        }
        .filter { $0.score >= minScore && !$0.have.isEmpty }
        .sorted { ($0.score, -$0.recipe.minutes) > ($1.score, -$1.recipe.minutes) }
    }
}
