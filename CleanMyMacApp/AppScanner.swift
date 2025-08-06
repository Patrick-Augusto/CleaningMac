import AppKit
import Foundation

extension String {
    func appleScriptPath() -> String? {
        // Check if path exists
        if !FileManager.default.fileExists(atPath: self) {
            print("Aviso: O caminho não existe: \(self)")
            return nil
        }

        // Create a file URL to ensure proper path formatting
        let fileURL = URL(fileURLWithPath: self)

        // Convert to AppleScript's file reference format which handles special characters better
        let filePath = fileURL.path.replacingOccurrences(of: "\"", with: "\\\"")

        // Use the "alias" format which is more robust for AppleScript
        // This format is preferred over POSIX file when dealing with special characters
        return "POSIX file \"\(filePath)\""
    }
}

class AppScanner: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var isDeleting: Bool = false

    func scanApps() {
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["kMDItemContentType == \"com.apple.application-bundle\""]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let paths = output.split(whereSeparator: \.isNewline).map { String($0) }
                    self.updateAppList(with: paths)
                }
            } catch {
                print("Erro ao buscar aplicativos: \(error)")
            }
        }
    }

    private func updateAppList(with paths: [String]) {
        var appInfos: [AppInfo] = []

        for path in paths {
            if let bundle = Bundle(path: path),
                let appName = bundle.infoDictionary?["CFBundleName"] as? String
            {

                let icon = NSWorkspace.shared.icon(forFile: path)

                let size = sizeOfDirectory(atPath: path)
                let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

                let appInfo = AppInfo(
                    name: appName, path: path, icon: icon, size: sizeString,
                    bundleIdentifier: bundle.bundleIdentifier)
                appInfos.append(appInfo)
            }
        }

        DispatchQueue.main.async {
            self.apps = appInfos.sorted { $0.name < $1.name }
        }
    }

    private func sizeOfDirectory(atPath path: String) -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            for item in contents {
                let fullPath = (path as NSString).appendingPathComponent(item)
                if let attributes = try? fileManager.attributesOfItem(atPath: fullPath) {
                    if let fileType = attributes[.type] as? FileAttributeType,
                        fileType == .typeDirectory
                    {
                        totalSize += sizeOfDirectory(atPath: fullPath)
                    } else {
                        totalSize += attributes[.size] as? Int64 ?? 0
                    }
                }
            }
        } catch {
            print("Não foi possível calcular o tamanho do diretório: \(error)")
        }
        return totalSize
    }

    func deleteFiles(atPaths paths: [String], for app: AppInfo) {
        self.isDeleting = true
        DispatchQueue.global(qos: .userInitiated).async {
            // Filter valid paths and convert them to AppleScript format
            var validPaths: [String] = []

            for path in paths {
                if let appleScriptPath = path.appleScriptPath() {
                    validPaths.append(appleScriptPath)
                }
            }

            // Check if we have any valid paths
            if validPaths.isEmpty {
                DispatchQueue.main.async {
                    self.isDeleting = false
                    print("Nenhum arquivo válido para mover para a lixeira")
                }
                return
            }
            
            // Função para mover para a lixeira usando shell comandos em vez de AppleScript
            func moveToTrashWithShell() {
                var successCount = 0
                var failureCount = 0
                
                for path in paths {
                    // Garantir que o caminho existe
                    if !FileManager.default.fileExists(atPath: path) {
                        print("Arquivo não existe: \(path)")
                        failureCount += 1
                        continue
                    }
                    
                    // Usar mv para mover para a Lixeira
                    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
                    let trashPath = "\(homeDirectory)/.Trash"
                    
                    // Extrair o nome do arquivo do caminho
                    let fileName = (path as NSString).lastPathComponent
                    let destinationPath = "\(trashPath)/\(fileName)"
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/mv")
                    process.arguments = [path, destinationPath]
                    
                    do {
                        try process.run()
                        process.waitUntilExit()
                        
                        if process.terminationStatus == 0 {
                            successCount += 1
                        } else {
                            failureCount += 1
                            print("Erro ao mover \(path) para a lixeira")
                        }
                    } catch {
                        failureCount += 1
                        print("Erro ao executar mv: \(error.localizedDescription)")
                    }
                }
                
                DispatchQueue.main.async {
                    self.isDeleting = false
                    print("Arquivos movidos para a lixeira: \(successCount), falhas: \(failureCount)")
                    
                    // Remove o app da lista apenas se pelo menos um arquivo foi removido com sucesso
                    if successCount > 0 {
                        if let index = self.apps.firstIndex(where: { $0.id == app.id }) {
                            self.apps.remove(at: index)
                        }
                    }
                }
            }

            // Tenta primeiro com AppleScript
            let filesList = validPaths.joined(separator: ", ")

            // Create the AppleScript
            let scriptSource = """
                tell application "Finder"
                    set theFiles to {\(filesList)}
                    move theFiles to trash
                end tell
                """
            print("Executing AppleScript:\n\(scriptSource)")
            if let script = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                
                // Pausa breve para dar tempo à lixeira de processar os arquivos
                // antes de prosseguir com outras operações
                Thread.sleep(forTimeInterval: 0.5)

                DispatchQueue.main.async {
                    if let error = error {
                        print("Erro ao mover para a lixeira via AppleScript: \(error)")
                        print("Caminhos que tentamos mover: \(paths)")
                        
                        // Se falhou com AppleScript, tenta com shell
                        print("Tentando mover arquivos para a lixeira usando shell commands...")
                        moveToTrashWithShell()
                    } else {
                        // Sucesso com AppleScript
                        self.isDeleting = false
                        
                        // Remove o app da lista apenas se a exclusão foi bem-sucedida
                        if let index = self.apps.firstIndex(where: { $0.id == app.id }) {
                            self.apps.remove(at: index)
                        }
                    }
                }
            }
        }
    }

    func findResidualFiles(for app: AppInfo) -> [String] {
        var residualFiles: [String] = []
        let fileManager = FileManager.default
        let searchPaths = [
            "~/Library/Application Support",
            "~/Library/Caches",
            "~/Library/Preferences",
            "~/Library/Logs",
            "~/Library/Containers",
            "~/Library/Cookies",
        ].map { NSString(string: $0).expandingTildeInPath }

        let appName = app.name.replacingOccurrences(of: ".app", with: "")
        var searchTerms = [appName]
        if let bundleId = app.bundleIdentifier {
            searchTerms.append(bundleId)
        }

        for path in searchPaths {
            do {
                let items = try fileManager.contentsOfDirectory(atPath: path)
                for item in items {
                    for term in searchTerms {
                        if item.localizedCaseInsensitiveContains(term) {
                            let fullPath = (path as NSString).appendingPathComponent(item)
                            residualFiles.append(fullPath)
                        }
                    }
                }
            } catch {
                // O diretório pode não existir, o que é normal.
                continue
            }
        }
        return residualFiles
    }

    func getContentsOfDirectory(atPath path: String) -> [String] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path)
            return contents.sorted()
        } catch {
            print("Erro ao ler o conteúdo do diretório: \(error)")
            return []
        }
    }
    
    // Método para buscar aplicativos com um termo específico
    func searchApps(with searchTerm: String) -> [AppInfo] {
        if searchTerm.isEmpty {
            return apps
        }
        
        return apps.filter { app in
            let nameMatches = app.name.localizedCaseInsensitiveContains(searchTerm)
            let bundleIdMatches = app.bundleIdentifier?.localizedCaseInsensitiveContains(searchTerm) ?? false
            let pathMatches = app.path.localizedCaseInsensitiveContains(searchTerm)
            
            return nameMatches || bundleIdMatches || pathMatches
        }
    }
    
    // Método para esvaziar a lixeira usando diretamente os comandos rm
    func emptyTrashUsingShell(completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // No macOS, a lixeira do usuário está em ~/.Trash/
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
            let trashDirectory = "\(homeDirectory)/.Trash"
            
            print("Verificando o conteúdo da lixeira em \(trashDirectory)...")
            
            // Primeiro, vamos verificar se há arquivos na lixeira
            do {
                let trashContents = try FileManager.default.contentsOfDirectory(atPath: trashDirectory)
                
                if trashContents.isEmpty {
                    print("Lixeira já está vazia.")
                    DispatchQueue.main.async {
                        completion(true, "A lixeira já está vazia.")
                    }
                    return
                }
                
                print("Encontrados \(trashContents.count) itens na lixeira.")
                
                // Vamos usar 'rm -rf' para remover todos os arquivos da lixeira
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/rm")
                process.arguments = ["-rf", "\(trashDirectory)/*"]
                
                // Configurar saídas para capturar erros
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                let status = process.terminationStatus
                
                if status == 0 {
                    print("Lixeira esvaziada com sucesso!")
                    DispatchQueue.main.async {
                        completion(true, nil)
                    }
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    var errorMessage = "Erro ao esvaziar a lixeira"
                    
                    if let errorText = String(data: errorData, encoding: .utf8), !errorText.isEmpty {
                        errorMessage = errorText
                    }
                    
                    print("Erro ao esvaziar a lixeira: \(errorMessage)")
                    
                    // Em caso de erro, tentamos uma abordagem alternativa usando o comando find
                    // que pode ser mais seguro para lidar com nomes de arquivos especiais
                    print("Tentando abordagem alternativa com o comando find...")
                    
                    let findProcess = Process()
                    findProcess.executableURL = URL(fileURLWithPath: "/usr/bin/find")
                    findProcess.arguments = [trashDirectory, "-mindepth", "1", "-delete"]
                    
                    let findErrorPipe = Pipe()
                    findProcess.standardError = findErrorPipe
                    
                    try findProcess.run()
                    findProcess.waitUntilExit()
                    
                    let findStatus = findProcess.terminationStatus
                    
                    if findStatus == 0 {
                        print("Lixeira esvaziada com sucesso usando método alternativo!")
                        DispatchQueue.main.async {
                            completion(true, nil)
                        }
                    } else {
                        let findErrorData = findErrorPipe.fileHandleForReading.readDataToEndOfFile()
                        var findErrorMessage = errorMessage
                        
                        if let findErrorText = String(data: findErrorData, encoding: .utf8), !findErrorText.isEmpty {
                            findErrorMessage = findErrorText
                        }
                        
                        print("Erro ao esvaziar a lixeira com método alternativo: \(findErrorMessage)")
                        DispatchQueue.main.async {
                            completion(false, "Não foi possível esvaziar a lixeira: \(findErrorMessage)")
                        }
                    }
                }
            } catch {
                print("Erro ao acessar a pasta da lixeira: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, "Erro ao acessar a pasta da lixeira: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct AppInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let icon: NSImage?
    let size: String
    let bundleIdentifier: String?

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
