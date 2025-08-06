import SwiftUI

struct AppRowView: View {
    let app: AppInfo
    @ObservedObject var appScanner: AppScanner

    @State private var isExpanded = false
    @State private var contents: [String]? = nil
    @State private var showingDeleteAlert = false
    @State private var filesToDelete: [String] = []

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                if let contents = contents {
                    if contents.isEmpty {
                        Text("Nenhum conteúdo encontrado.")
                            .padding(.leading)
                    } else {
                        ForEach(contents, id: \.self) { item in
                            Text(item)
                                .padding(.leading)
                        }
                    }
                } else {
                    ProgressView()
                        .padding(.leading)
                        .onAppear(perform: loadContents)
                }
            },
            label: {
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 40, height: 40)
                    }
                    VStack(alignment: .leading) {
                        Text(app.name).font(.headline)
                        Text(app.path).font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(app.size).font(.body)
                        .padding(.trailing, 8)  // Adiciona espaço entre o tamanho e o botão
                    Button(action: {
                        self.filesToDelete = [app.path] + appScanner.findResidualFiles(for: app)
                        self.showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)  // Define tamanho fixo para o botão
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.trailing, 16)  // Adiciona padding à direita para evitar sobreposição com scroll
                }
                .contentShape(Rectangle())
            }
        )
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Confirmar Exclusão"),
                message: Text(
                    "Você tem certeza que deseja mover os seguintes arquivos para a lixeira?\n\n\(filesToDelete.joined(separator: "\n"))"
                ),
                primaryButton: .destructive(Text("Excluir")) {
                    appScanner.deleteFiles(atPaths: filesToDelete, for: app)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func loadContents() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedContents = appScanner.getContentsOfDirectory(atPath: app.path)
            DispatchQueue.main.async {
                self.contents = loadedContents
            }
        }
    }
}
