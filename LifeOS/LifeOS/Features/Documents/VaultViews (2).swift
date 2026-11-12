import SwiftUI
import SwiftData
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

struct VaultView: View {
    @Query(sort: \VaultDocument.createdAt, order: .reverse) private var documents: [VaultDocument]
    @State private var folder: String?
    @State private var search = ""
    @State private var importing = false

    private var folders: [String] { Array(Set(documents.map(\.folder))).sorted() }
    private var filtered: [VaultDocument] {
        documents.filter { d in
            (folder == nil || d.folder == folder) &&
            (search.isEmpty || d.title.folded.contains(search.folded) || d.category.label.folded.contains(search.folded)
             || d.notes.folded.contains(search.folded) || d.originalFileName.folded.contains(search.folded))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.teal)
                    Text("Arquivos criptografados (AES-256) com chave guardada no Keychain deste iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Chip(title: "Todos", isSelected: folder == nil) { folder = nil }
                        ForEach(folders, id: \.self) { f in Chip(title: f, isSelected: folder == f) { folder = f } }
                    }
                }
                if filtered.isEmpty {
                    EmptyStateView(icon: "doc.on.doc", title: "Nenhum documento",
                                   message: "Guarde editais, comprovantes, recibos e anotações com segurança.",
                                   actionTitle: "Adicionar") { importing = true }
                }
                ForEach(filtered) { DocumentRow(document: $0) }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .searchable(text: $search, prompt: "Buscar documentos")
        .screenBackground()
        .navigationTitle("Documentos")
        .toolbar { Button { importing = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $importing) { VaultImportSheet() }
    }
}

struct DocumentRow: View {
    let document: VaultDocument
    @Environment(\.modelContext) private var context
    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var authFor: Action?
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var error: String?

    enum Action: String, Identifiable { case open, share; var id: String { rawValue } }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: document.category.icon, tint: .teal)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(document.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if document.isSensitive { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange) }
                }
                Text("\(document.folder) · \(document.category.label) · \(Fmt.bytes(Int64(document.byteSize)))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Abrir", systemImage: "eye") { request(.open) }
                Button("Exportar", systemImage: "square.and.arrow.up") { request(.share) }
                Button("Editar informações", systemImage: "pencil") { editing = true }
                Button("Excluir", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
        }
        .card(padding: 12)
        .contentShape(Rectangle())
        .onTapGesture { request(.open) }
        .sheet(item: $authFor) { action in
            AuthGateView(reason: "Abrir documento protegido") { perform(action) }
        }
        .quickLookPreview($previewURL)
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { if $0 == nil { shareURL = nil } })) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $editing) { DocumentEditor(document: document) }
        .confirmationDialog("Excluir \"\(document.title)\" definitivamente? O arquivo criptografado será apagado e não poderá ser recuperado (exceto por um backup).",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                VaultStorage.delete(document.storedFileName)
                context.delete(document)
                context.saveQuietly()
            }
        }
        .alert("Erro", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }

    private func request(_ action: Action) {
        if document.isSensitive { authFor = action } else { perform(action) }
    }

    private func perform(_ action: Action) {
        guard !document.storedFileName.isEmpty else { error = "Este documento não possui arquivo (não foi incluído no backup restaurado)."; return }
        do {
            let url = try VaultStorage.temporaryCopy(of: document)
            switch action {
            case .open: previewURL = url
            case .share: shareURL = url
            }
        } catch {
            self.error = "Não foi possível abrir o arquivo. A chave do cofre pode não estar disponível neste aparelho."
        }
    }
}

struct VaultImportSheet: View {
    var subject: Subject? = nil
    var contest: Contest? = nil
    var defaultCategory: DocumentCategory = .outro

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allDocs: [VaultDocument]
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pending: (data: Data, name: String, ext: String)?
    @State private var title = ""
    @State private var folder = "Geral"
    @State private var category: DocumentCategory = .outro
    @State private var sensitive = false
    @State private var notes = ""
    @State private var noteText = ""
    @State private var mode = 0
    @State private var error: String?

    private let maxBytes = 50 * 1024 * 1024

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tipo", selection: $mode) {
                    Text("Arquivo").tag(0)
                    Text("Anotação").tag(1)
                }
                .pickerStyle(.segmented)
                if mode == 0 {
                    Section {
                        Button { showFileImporter = true } label: { Label("Escolher arquivo (PDF, imagem…)", systemImage: "folder") }
                        PhotosPicker(selection: $photoItem, matching: .images) { Label("Escolher foto", systemImage: "photo") }
                        if let p = pending {
                            Label("\(p.name) · \(Fmt.bytes(Int64(p.data.count)))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                } else {
                    Section("Texto") { TextField("Escreva sua anotação", text: $noteText, axis: .vertical).lineLimit(5...15) }
                }
                Section("Informações") {
                    TextField("Título", text: $title)
                    TextField("Pasta", text: $folder)
                    if !folders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(folders, id: \.self) { f in Chip(title: f, isSelected: folder == f) { folder = f } } }
                        }
                    }
                    Picker("Categoria", selection: $category) {
                        ForEach(DocumentCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    Toggle("Sensível (pedir Face ID/senha para abrir)", isOn: $sensitive)
                    TextField("Observações", text: $notes)
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle("Guardar documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar", action: save).disabled(!canSave) }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image, .plainText, .data]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { error = "Não foi possível ler o arquivo."; return }
                guard data.count <= maxBytes else { error = "Arquivo muito grande (máx. 50 MB)."; return }
                pending = (data, url.lastPathComponent, url.pathExtension.lowercased())
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                    guard data.count <= maxBytes else { error = "Imagem muito grande."; return }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    pending = (data, "foto.\(ext)", ext)
                    if title.isEmpty { title = "Foto \(Fmt.short(Date()))" }
                }
            }
            .onAppear {
                category = defaultCategory
                if let subject { folder = subject.name; category = .academico }
                if let contest { folder = contest.organ }
            }
        }
    }

    private var folders: [String] { Array(Set(allDocs.map(\.folder))).sorted() }

    private var canSave: Bool {
        !title.trimmed.isEmpty && (mode == 0 ? pending != nil : !noteText.trimmed.isEmpty)
    }

    private func save() {
        let data: Data
        let fileName: String
        let ext: String
        if mode == 0, let p = pending {
            data = p.data; fileName = VaultStorage.sanitizeFileName(p.name); ext = p.ext
        } else {
            data = Data(noteText.utf8); fileName = VaultStorage.sanitizeFileName(title) + ".txt"; ext = "txt"
        }
        do {
            let stored = try VaultStorage.store(data)
            let doc = VaultDocument(title: String(title.trimmed.prefix(120)))
            doc.folder = folder.trimmed.isEmpty ? "Geral" : String(folder.trimmed.prefix(40))
            doc.category = mode == 1 ? .anotacao : category
            doc.storedFileName = stored
            doc.originalFileName = fileName
            doc.fileExtension = ext
            doc.byteSize = data.count
            doc.isSensitive = sensitive
            doc.notes = notes
            context.insert(doc)
            doc.subject = subject
            doc.contest = contest
            context.saveQuietly()
            dismiss()
        } catch {
            self.error = "Falha ao criptografar o arquivo."
        }
    }
}

struct DocumentEditor: View {
    @Bindable var document: VaultDocument
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query(sort: \Contest.organ) private var contests: [Contest]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Título", text: $document.title)
                TextField("Pasta", text: $document.folder)
                Picker("Categoria", selection: Binding(get: { document.category }, set: { document.category = $0 })) {
                    ForEach(DocumentCategory.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Sensível", isOn: $document.isSensitive)
                TextField("Observações", text: $document.notes, axis: .vertical)
                Section("Vínculos") {
                    Picker("Matéria", selection: $document.subject) {
                        Text("Nenhuma").tag(Subject?.none)
                        ForEach(subjects) { Text($0.name).tag(Optional($0)) }
                    }
                    Picker("Concurso", selection: $document.contest) {
                        Text("Nenhum").tag(Contest?.none)
                        ForEach(contests) { Text($0.displayName).tag(Optional($0)) }
                    }
                }
            }
            .navigationTitle("Documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { context.saveQuietly(); dismiss() } } }
        }
    }
}
