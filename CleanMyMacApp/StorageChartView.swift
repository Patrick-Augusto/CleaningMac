
import SwiftUI

struct StorageChartView: View {
    @ObservedObject var analyzer: StorageAnalyzer

    var body: some View {
        VStack {
            Text("Uso de Disco")
                .font(.title2).padding(.bottom, 5)

            if analyzer.categories.isEmpty {
                ProgressView("Analisando...")
                    .onAppear(perform: analyzer.analyzeStorage)
            } else {
                ZStack {
                    ForEach(analyzer.categories) { category in
                        RingView(category: category)
                    }
                }
                .frame(width: 200, height: 200)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(analyzer.categories) { category in
                        HStack {
                            Circle()
                                .fill(category.color)
                                .frame(width: 10, height: 10)
                            Text("\(category.name): \(category.sizeString)")
                                .font(.caption)
                        }
                    }
                }
                .padding(.top)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}

struct RingView: View {
    let category: StorageCategory

    var body: some View {
        Circle()
            .trim(from: category.startAngle, to: category.endAngle)
            .stroke(category.color, lineWidth: 40)
    }
}
