import SwiftUI
import SwiftData
import PhotosUI

struct FoodView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PantryItem.name) private var pantry: [PantryItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \CookLog.date, order: .reverse) private var logs: [CookLog]
    @State private var tab = 0
    @State private var scanning = false
    @State private var editingItem: PantryItem?
    @State private var addingItem = false
    @State private var addingRecipe = false
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Seção", selection: $tab) {
                    Text("Estoque").tag(0)
                    Text("Receitas").tag(1)
                    Text("Histórico").tag(2)
                }
                .pickerStyle(.segmented)
                switch tab {
                case 0: pantryTab
                case 1: recipesTab
                default: historyTab
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .screenBackground()
        .navigationTitle("Minha alimentação")
        .toolbar {
            Menu {
                Button("Fotografar compras", systemImage: "camera") { scanning = true }
                Button("Adicionar alimento", systemImage: "plus") { addingItem = true }
                Button("Nova receita", systemImage: "book") { addingRecipe = true }
            } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $scanning) { PantryScanView() }
        .sheet(isPresented: $addingItem) { PantryItemEditor(item: nil) }
        .sheet(item: $editingItem) { PantryItemEditor(item: $0) }
        .sheet(isPresented: $addingRecipe) { RecipeEditor() }
    }

    private var pantryTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { scanning = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fotografar compras").font(.headline)
                        Text("Identificação no próprio iPhone. Você confirma cada item.").font(.caption).opacity(0.9)
                    }
                    Spacer()
                }
                .gradientCard(.food)
            }
            .buttonStyle(.plain)

            if pantry.isEmpty {
                EmptyStateView(icon: "cart", title: "Estoque vazio", message: "Diga \"comprei ovos, arroz e frango\" ou fotografe as compras.")
            }
            ForEach(pantry) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        if let exp = item.expiresAt {
                            Text("Validade \(Fmt.relativeDay(exp))").font(.caption)
                                .foregroundStyle(exp < Date().adding(days: 3) ? .red : .secondary)
                        }
                    }
                    Spacer()
                    Button { change(item, -1) } label: { Image(systemName: "minus.circle") }
                    Text("\(Fmt.number(item.quantity)) \(item.unit)").font(.subheadline).monospacedDigit().frame(minWidth: 60)
                    Button { change(item, 1) } label: { Image(systemName: "plus.circle") }
                }
                .buttonStyle(.plain)
                .font(.title3)
                .card(padding: 12)
                .onTapGesture { editingItem = item }
                .contextMenu { Button("Remover", systemImage: "trash", role: .destructive) { context.delete(item); context.saveQuietly() } }
            }
        }
    }

    private func change(_ item: PantryItem, _ delta: Double) {
        let step = item.unit == "kg" || item.unit == "L" ? 0.5 * delta : (item.unit == "g" || item.unit == "ml" ? 100 * delta : delta)
        item.quantity = max(0, item.quantity + step)
        if item.quantity == 0 { context.delete(item) }
        context.saveQuietly()
    }

    private var recipesTab: some View {
        let suggestions = RecipeEngine.suggestions(recipes: recipes, pantry: pantry)
        let filtered = recipes.filter { search.isEmpty || $0.name.folded.contains(search.folded) || $0.tags.contains { $0.folded.contains(search.folded) } }
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Com o que você tem em casa")
            if suggestions.isEmpty {
                Text(pantry.isEmpty ? "Adicione alimentos ao estoque para receber sugestões." : "Nenhuma receita do catálogo combina com o estoque atual.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(suggestions.prefix(6)) { s in
                NavigationLink { RecipeDetailView(recipe: s.recipe) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.recipe.name).font(.headline)
                            Spacer()
                            Text(Fmt.percent(s.score)).font(.caption.weight(.bold)).foregroundStyle(.green)
                        }
                        Text("\(s.recipe.minutes) min · \(s.have.count) de \(s.have.count + s.missing.count) ingredientes em casa")
                            .font(.caption).foregroundStyle(.secondary)
                        if !s.missing.isEmpty {
                            Text("Falta: \(s.missing.joined(separator: ", "))").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
            SectionHeader(title: "Catálogo")
            TextField("Buscar receita ou tag", text: $search).textFieldStyle(.roundedBorder)
            ForEach(filtered) { r in
                NavigationLink { RecipeDetailView(recipe: r) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.subheadline.weight(.semibold))
                            Text("\(r.minutes) min" + (r.kcal.map { " · ~\(Int($0)) kcal" } ?? "") + (r.tags.isEmpty ? "" : " · " + r.tags.joined(separator: ", ")))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if r.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            let favorites = recipes.filter(\.isFavorite)
            if !favorites.isEmpty {
                SectionHeader(title: "Favoritas")
                ForEach(favorites) { r in
                    NavigationLink { RecipeDetailView(recipe: r) } label: { Label(r.name, systemImage: "heart.fill").card(padding: 12) }
                        .buttonStyle(.plain)
                }
            }
            SectionHeader(title: "Receitas preparadas")
            if logs.isEmpty { Text("Toque em \"Preparei hoje\" em uma receita para registrar.").foregroundStyle(.secondary) }
            ForEach(logs.prefix(50)) { l in
                HStack {
                    Text(l.recipeName).font(.subheadline)
                    Spacer()
                    Text(Fmt.short(l.date)).font(.caption).foregroundStyle(.secondary)
                }
                .card(padding: 12)
            }
        }
    }
}

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantry: [PantryItem]
    @State private var cooked = false

    var body: some View {
        let stock = Set(pantry.filter { $0.quantity > 0 }.map { RecipeEngine.canonical($0.name) })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.name).font(.title2.bold())
                    Text("\(recipe.minutes) min · \(recipe.servings) porção(ões)").opacity(0.9)
                }
                .gradientCard(.food)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingredientes").font(.headline)
                    ForEach(Array(recipe.ingredientNames.enumerated()), id: \.offset) { i, name in
                        let has = RecipeEngine.has(name, in: stock)
                        HStack {
                            Image(systemName: has ? "checkmark.circle.fill" : "circle").foregroundStyle(has ? .green : .secondary)
                            Text(name)
                            Spacer()
                            if i < recipe.ingredientQuantities.count {
                                Text(recipe.ingredientQuantities[i]).foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Modo de preparo").font(.headline)
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.caption.bold()).frame(width: 22, height: 22).background(Color.orange.opacity(0.2), in: Circle())
                            Text(step).font(.subheadline)
                        }
                    }
                }
                .card()

                if recipe.kcal != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Informação nutricional estimada (por porção)").font(.headline)
                        HStack {
                            nutrient("kcal", recipe.kcal)
                            nutrient("Proteínas", recipe.protein, "g")
                            nutrient("Carboidratos", recipe.carbs, "g")
                            nutrient("Gorduras", recipe.fat, "g")
                        }
                        Text("Valores aproximados, apenas para referência. Não substituem orientação de nutricionista.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .card()
                }

                Button {
                    context.insert(CookLog(recipeID: recipe.id, recipeName: recipe.name))
                    context.saveQuietly()
                    cooked = true
                } label: { Label("Preparei hoje", systemImage: "frying.pan") }
                .buttonStyle(PrimaryButtonStyle(module: .food))
                if !recipe.isBuiltIn {
                    Button("Excluir receita", role: .destructive) { context.delete(recipe); context.saveQuietly(); dismiss() }
                }
            }
            .padding()
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { recipe.isFavorite.toggle(); context.saveQuietly() } label: {
                Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
            }
            .tint(.pink)
        }
        .alert("Registrado no histórico", isPresented: $cooked) { Button("OK") {} }
    }

    private func nutrient(_ label: String, _ value: Double?, _ unit: String = "") -> some View {
        VStack(spacing: 2) {
            Text(value.map { "\(Int($0))\(unit)" } ?? "–").font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecipeEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minutes = 20
    @State private var servings = 1
    @State private var ingredients = ""
    @State private var steps = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $name)
                Stepper("Tempo: \(minutes) min", value: $minutes, in: 5...240, step: 5)
                Stepper("Porções: \(servings)", value: $servings, in: 1...20)
                Section(footer: Text("Um por linha. Use \"nome - quantidade\", ex.: Ovos - 2 unidades")) {
                    TextField("Ingredientes", text: $ingredients, axis: .vertical).lineLimit(4...10)
                }
                Section(footer: Text("Um passo por linha.")) {
                    TextField("Modo de preparo", text: $steps, axis: .vertical).lineLimit(4...12)
                }
            }
            .navigationTitle("Nova receita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let r = Recipe(name: name.trimmed)
                        let lines = ingredients.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
                        r.ingredientNames = lines.map { $0.components(separatedBy: " - ").first?.trimmed ?? $0 }
                        r.ingredientQuantities = lines.map { $0.components(separatedBy: " - ").dropFirst().joined(separator: " - ").trimmed }
                        r.steps = steps.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
                        r.minutes = minutes; r.servings = servings
                        context.insert(r)
                        context.saveQuietly()
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
        }
    }
}

struct PantryItemEditor: View {
    let item: PantryItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = "un"
    @State private var hasExpiry = false
    @State private var expiry = Date().adding(days: 7)
    private let units = ["un", "kg", "g", "L", "ml", "pct", "cx", "lata"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Alimento", text: $name)
                HStack {
                    TextField("Quantidade", text: $quantity).keyboardType(.decimalPad)
                    Picker("Unidade", selection: $unit) { ForEach(units, id: \.self) { Text($0) } }.labelsHidden()
                }
                Toggle("Validade", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Vence em", selection: $expiry, displayedComponents: .date) }
            }
            .navigationTitle(item == nil ? "Adicionar alimento" : "Editar alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let i = item ?? PantryItem(name: name.trimmed)
                        i.name = name.trimmed.capitalizedFirst
                        i.quantity = max(0, Fmt.parseDecimal(quantity) ?? 1)
                        i.unit = unit
                        i.expiresAt = hasExpiry ? expiry : nil
                        if item == nil { context.insert(i) }
                        context.saveQuietly()
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear {
                if let i = item {
                    name = i.name; quantity = Fmt.number(i.quantity); unit = i.unit
                    if let e = i.expiresAt { hasExpiry = true; expiry = e }
                }
            }
        }
    }
}

/// Fotografar/selecionar imagens de compras e confirmar os alimentos identificados.
struct PantryScanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var analyzing = false
    @State private var candidates: [FoodCandidate] = []
    @State private var selected: Set<UUID> = []
    @State private var manual = ""
    @State private var analyzed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("Câmera", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent)
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Galeria", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    if analyzing { ProgressView("Analisando no aparelho…").frame(maxWidth: .infinity) }
                    if analyzed {
                        Text(candidates.isEmpty ? "Não consegui identificar alimentos com segurança. Adicione manualmente abaixo." : "Confirme o que foi identificado:")
                            .font(.subheadline.weight(.semibold))
                        ForEach($candidates) { $c in
                            HStack {
                                Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(c.id) ? .green : .secondary)
                                    .onTapGesture { toggle(c.id) }
                                TextField("Nome", text: $c.name)
                                Spacer()
                                Text(c.source == "texto" ? "texto" : Fmt.percent(c.confidence)).font(.caption).foregroundStyle(.secondary)
                            }
                            .card(padding: 12)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Adicionar manualmente (separe por vírgula)").font(.subheadline.weight(.semibold))
                        TextField("Ex.: 2 kg de arroz, feijão, 12 ovos", text: $manual, axis: .vertical).textFieldStyle(.roundedBorder)
                    }
                    Text("As imagens são analisadas apenas no seu iPhone e não são salvas.").font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Compras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adicionar") { save() }
                        .disabled(selected.isEmpty && manual.trimmed.isEmpty)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in image = img; Task { await analyze(img) } }.ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                    image = img
                    await analyze(img)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func analyze(_ img: UIImage) async {
        analyzing = true
        let found = await FoodRecognizer.recognize(img)
        // mantém o que já foi encontrado em fotos anteriores
        for f in found where !candidates.contains(where: { $0.name == f.name }) {
            candidates.append(f)
            if f.confidence >= 0.3 || f.source == "texto" { selected.insert(f.id) }
        }
        analyzing = false
        analyzed = true
    }

    private func save() {
        var items = candidates.filter { selected.contains($0.id) }.map { GroceryItem(name: $0.name.trimmed, quantity: 1, unit: "un") }
        items += RuleBasedInterpreter().splitItems(manual)
        let existing = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        for item in items where !item.name.isEmpty {
            if let same = existing.first(where: { $0.name.folded == item.name.folded && $0.unit == item.unit }) {
                same.quantity += item.quantity
            } else {
                context.insert(PantryItem(name: item.name, quantity: item.quantity, unit: item.unit))
            }
        }
        context.saveQuietly()
        dismiss()
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
