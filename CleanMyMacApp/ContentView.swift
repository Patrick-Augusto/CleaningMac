import SwiftUI

struct ContentView: View {
    @StateObject private var appScanner = AppScanner()
    @StateObject private var storageAnalyzer = StorageAnalyzer()
    @State private var searchText = ""
    @State private var isEmptyingTrash = false
    @State private var showTrashAlert = false
    @State private var trashEmptyResult: (success: Bool, message: String?) = (false, nil)

    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return appScanner.apps
        } else {
            let searchLower = searchText.lowercased()

            return appScanner.apps.filter { app in
                app.name.lowercased().contains(searchLower)
                    || app.path.lowercased().contains(searchLower)
                    || (app.bundleIdentifier?.lowercased().contains(searchLower) ?? false)
            }
        }
    }

    var body: some View {
        VStack {
            HStack {
                Text("Aplicativos Encontrados")
                    .font(.largeTitle)

                Spacer()

                Button(action: {
                    showTrashAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Esvaziar Lixeira")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isEmptyingTrash)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Buscar aplicativos por nome ou pacote...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disableAutocorrection(true)

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding(.horizontal)

            if appScanner.apps.isEmpty {
                ProgressView("Buscando aplicativos...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .padding()
            } else if appScanner.isDeleting {
                ProgressView("Excluindo arquivos...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .padding()
            } else if isEmptyingTrash {
                ProgressView("Esvaziando a lixeira...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .padding()
            } else {
                VStack {
                    if filteredApps.isEmpty && !searchText.isEmpty {
                        // Mostra uma mensagem quando não há resultados de pesquisa
                        VStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                                .padding()
                            Text("Nenhum aplicativo encontrado para '\(searchText)'")
                                .font(.headline)
                            Text("Tente outro termo de pesquisa")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Mostra a lista de aplicativos filtrados
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredApps) { app in
                                    AppRowView(app: app, appScanner: appScanner)
                                        .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 16)  // Adiciona padding horizontal para evitar sobreposição
                            .padding(.trailing, 8)  // Espaço extra à direita para a barra de scroll
                        }
                        .padding(.bottom, 8)  // Adiciona espaço na parte inferior
                    }
                }
            }
        }
        .onAppear {
            appScanner.scanApps()
        }
        .frame(minWidth: 800, minHeight: 500)
        .alert(isPresented: $showTrashAlert) {
            Alert(
                title: Text("Esvaziar a Lixeira"),
                message: Text(
                    "Tem certeza que deseja esvaziar permanentemente a lixeira? Esta ação não pode ser desfeita."
                ),
                primaryButton: .destructive(Text("Esvaziar")) {
                    emptyTrash()
                },
                secondaryButton: .cancel()
            )
        }
        .alert(
            "Resultado da operação",
            isPresented: Binding<Bool>(
                get: { trashEmptyResult.message != nil && !isEmptyingTrash },
                set: { if !$0 { trashEmptyResult.message = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(trashEmptyResult.message ?? "")
            }
        )
    }

    private func emptyTrash() {
        isEmptyingTrash = true

        let scanner = self.appScanner  // Use local copy to avoid reference issues
        scanner.emptyTrashUsingShell { success, message in
            DispatchQueue.main.async {
                self.isEmptyingTrash = false
                if success {
                    self.trashEmptyResult = (true, "A lixeira foi esvaziada com sucesso!")
                } else {
                    let errorMessage = message ?? "Erro desconhecido ao esvaziar a lixeira"
                    self.trashEmptyResult = (false, errorMessage)
                    print("Erro ao esvaziar lixeira: \(errorMessage)")
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
