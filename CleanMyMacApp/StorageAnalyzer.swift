
import Foundation
import SwiftUI

struct StorageCategory: Identifiable {
    let id = UUID()
    let name: String
    var size: Int64
    var color: Color
    var startAngle: CGFloat = 0.0
    var endAngle: CGFloat = 0.0

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

class StorageAnalyzer: ObservableObject {
    @Published var categories: [StorageCategory] = []

    func analyzeStorage() {
        DispatchQueue.global(qos: .background).async {
            var initialCategories = [
                "Applications": StorageCategory(name: "Aplicativos", size: 0, color: .blue),
                "Pictures": StorageCategory(name: "Imagens", size: 0, color: .green),
                "Music": StorageCategory(name: "Música", size: 0, color: .orange),
                "Movies": StorageCategory(name: "Vídeos", size: 0, color: .red),
                "Documents": StorageCategory(name: "Documentos", size: 0, color: .purple),
                "Other": StorageCategory(name: "Outros", size: 0, color: .gray)
            ]

            let queryTypes = [
                "Applications": "kMDItemContentTypeTree == 'com.apple.application'",
                "Pictures": "kMDItemKind == 'Image'",
                "Music": "kMDItemKind == 'Music'",
                "Movies": "kMDItemKind == 'Movie'",
                "Documents": "kMDItemKind == 'Document'"
            ]

            var totalSize: Int64 = 0

            for (key, query) in queryTypes {
                initialCategories[key]?.size = self.getSizeForQuery(query)
                totalSize += initialCategories[key]?.size ?? 0
            }

            if let systemSize = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemSize] as? NSNumber {
                let usedSize = systemSize.int64Value
                initialCategories["Other"]?.size = usedSize - totalSize
            }

            var finalCategories = Array(initialCategories.values).filter { $0.size > 0 }
            finalCategories.sort { $0.size > $1.size }

            let totalDiskSpace = finalCategories.reduce(0) { $0 + $1.size }
            var currentAngle: CGFloat = 0

            for i in 0..<finalCategories.count {
                let percentage = CGFloat(finalCategories[i].size) / CGFloat(totalDiskSpace)
                finalCategories[i].startAngle = currentAngle
                finalCategories[i].endAngle = currentAngle + percentage
                currentAngle = finalCategories[i].endAngle
            }

            DispatchQueue.main.async {
                self.categories = finalCategories
            }
        }
    }

    private func getSizeForQuery(_ query: String) -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", "/", query, "-attr", "kMDItemPhysicalSize"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let sizes = output.split(separator: "\n").compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
                return sizes.reduce(0, +)
            }
        } catch {
            print("Erro ao executar mdfind: \(error)")
        }
        return 0
    }
}
