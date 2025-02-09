//
import SwiftUI

@main
struct YourAppNameApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Model (Part, PartsData, Layout, PlacedPart, SavedDiagram)

// 切り出すシートの構造体
class Part: Identifiable, ObservableObject, Codable {
    let id: UUID
    @Published var longSide: Double
    @Published var shortSide: Double
    @Published var quantity: Int
    let color: Color
    
    enum CodingKeys: CodingKey {
        case id, longSide, shortSide, quantity, color
    }
    
    init(id: UUID = UUID(), longSide: Double, shortSide: Double, quantity: Int, color: Color) {
        self.id = id
        self.longSide = longSide
        self.shortSide = shortSide
        self.quantity = quantity
        self.color = color
    }
    
    // デコード
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        longSide = try container.decode(Double.self, forKey: .longSide)
        shortSide = try container.decode(Double.self, forKey: .shortSide)
        quantity = try container.decode(Int.self, forKey: .quantity)
        color = try container.decode(Color.self, forKey: .color)
    }
    
    // エンコード
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(longSide, forKey: .longSide)
        try container.encode(shortSide, forKey: .shortSide)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(color, forKey: .color)
    }
    
    // パーツをコピーする際は、新しいIDを割り振る
    func copy() -> Part {
        return Part(
            id: UUID(),
            longSide: self.longSide,
            shortSide: self.shortSide,
            quantity: self.quantity,
            color: self.color
        )
    }
}

class PartsData: ObservableObject {
    @Published var parts: [Part] = []
}

/// レイアウト結果を表す構造体
struct Layout: Codable {
    var baseLongSide: Double
    let baseShortSide: Double
    let kerf: Double
    var placedParts: [PlacedPart]
}

class PlacedPart: Identifiable, ObservableObject, Codable {
    let id: UUID
    @Published var x: Double
    @Published var y: Double
    let longSide: Double
    let shortSide: Double
    let color: Color

    enum CodingKeys: CodingKey {
        case id, x, y, longSide, shortSide, color
    }

    init(x: Double, y: Double, longSide: Double, shortSide: Double, color: Color) {
        self.id = UUID()
        self.x = x
        self.y = y
        self.longSide = longSide
        self.shortSide = shortSide
        self.color = color
    }

    // デコード
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        longSide = try container.decode(Double.self, forKey: .longSide)
        shortSide = try container.decode(Double.self, forKey: .shortSide)
        color = try container.decode(Color.self, forKey: .color)
    }

    // エンコード
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(longSide, forKey: .longSide)
        try container.encode(shortSide, forKey: .shortSide)
        try container.encode(color, forKey: .color)
    }
}

// カット図の保存用 (品番は削除し、名前のみ保持)
struct SavedDiagram: Codable {
    let layouts: [Layout]
    let parts: [Part]
    let name: String
}

// MARK: - Color の Codable 実装
extension Color: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let colorData = try container.decode(Data.self)
        
        if let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            self = Color(uiColor)
        } else {
            self = .black
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let uiColor = UIColor(self)
        let data = try NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false)
        try container.encode(data)
    }
}

// MARK: - PackingAlgorithm（幅固定・長さ可変、回転可否切替対応）

struct PackingAlgorithm {
    /// 幅固定＋長さ可変 (簡易ギロチン法) の例
    static func packPartsFixedWidthBestFit(
        parts: [Part],
        fixedWidth: Double,
        kerf: Double,
        allowRotation: Bool
    ) -> Layout {

        // 1) パーツを並べる順番は面積降順など(ここでは面積降順)
        let sortedParts = parts.sorted {
            ($0.longSide * $0.shortSide) > ($1.longSide * $1.shortSide)
        }

        // 2) 初期フリー領域
        var freeRectangles: [FreeRectangle] = [
            FreeRectangle(x: 0, y: 0, width: fixedWidth, height: 0)
        ]
        var placedParts: [PlacedPart] = []
        var currentSheetLength: Double = 0

        // 3) パーツを順に配置
        for part in sortedParts {

            // 回転候補
            let candidate1 = (w: part.shortSide + kerf, h: part.longSide + kerf, rotated: false)
            let candidate2 = (w: part.longSide + kerf, h: part.shortSide + kerf, rotated: true)
            let candidates = allowRotation ? [candidate1, candidate2] : [candidate1]

            // (A) 既存フリー領域に入るか探す
            if let (chosenCandidate, chosenIndex) = findBestFit(freeRects: freeRectangles, candidates: candidates) {
                // 置けた
                let placed = PlacedRect(
                    x: freeRectangles[chosenIndex].x,
                    y: freeRectangles[chosenIndex].y,
                    width: chosenCandidate.w,
                    height: chosenCandidate.h,
                    color: part.color
                )

                // シート長の更新
                let bottom = placed.y + placed.height
                if bottom > currentSheetLength {
                    let addedHeight = bottom - currentSheetLength
                    currentSheetLength = bottom
                    // フリー領域の高さ0を伸ばす (簡易)
                    for i in 0..<freeRectangles.count {
                        if freeRectangles[i].height < 0.001 {
                            freeRectangles[i].height += addedHeight
                        }
                    }
                }

                // 置いた領域を既存freeRectから切り取る
                var updatedFree = freeRectangles
                let removedRect = updatedFree.remove(at: chosenIndex)
                let splitted = subtractRect(freeRect: removedRect, placedRect: placed)
                updatedFree.append(contentsOf: splitted)
                updatedFree = cleanUpFreeRectangles(updatedFree)
                freeRectangles = updatedFree

                let placedPart = PlacedPart(
                    x: placed.x,
                    y: placed.y,
                    longSide: placed.height,
                    shortSide: placed.width,
                    color: part.color
                )
                placedParts.append(placedPart)
            }
            else {
                // (B) 既存フリー領域に入らない → シート長を下に伸ばす
                let needed = part.longSide + kerf
                let prevLength = currentSheetLength
                currentSheetLength += needed
                freeRectangles.append(
                    FreeRectangle(x: 0, y: prevLength, width: fixedWidth, height: needed)
                )

                // 再度挑戦
                if let (chosenCandidate, chosenIndex) = findBestFit(freeRects: freeRectangles, candidates: candidates) {
                    let placed = PlacedRect(
                        x: freeRectangles[chosenIndex].x,
                        y: freeRectangles[chosenIndex].y,
                        width: chosenCandidate.w,
                        height: chosenCandidate.h,
                        color: part.color
                    )
                    let bottom = placed.y + placed.height
                    if bottom > currentSheetLength {
                        currentSheetLength = bottom
                    }

                    var updatedFree = freeRectangles
                    let removedRect = updatedFree.remove(at: chosenIndex)
                    let splitted = subtractRect(freeRect: removedRect, placedRect: placed)
                    updatedFree.append(contentsOf: splitted)
                    updatedFree = cleanUpFreeRectangles(updatedFree)
                    freeRectangles = updatedFree

                    let placedPart = PlacedPart(
                        x: placed.x,
                        y: placed.y,
                        longSide: placed.height,
                        shortSide: placed.width,
                        color: part.color
                    )
                    placedParts.append(placedPart)
                }
                // さらに入らないならあきらめる
            }
        }

        // 結果をLayoutにまとめる
        return Layout(
            baseLongSide: currentSheetLength,
            baseShortSide: fixedWidth,
            kerf: kerf,
            placedParts: placedParts
        )
    }

    private static func findBestFit(
        freeRects: [FreeRectangle],
        candidates: [(w: Double, h: Double, rotated: Bool)]
    ) -> ((w: Double, h: Double, rotated: Bool), Int)? {

        var bestIndex: Int? = nil
        var bestCandidate: (w: Double, h: Double, rotated: Bool)? = nil
        var bestScore = Double.greatestFiniteMagnitude

        for (idx, fr) in freeRects.enumerated() {
            for c in candidates {
                if c.w <= fr.width && c.h <= fr.height {
                    let freeArea = fr.width * fr.height
                    let partArea = c.w * c.h
                    let score = freeArea - partArea
                    if score < bestScore {
                        bestScore = score
                        bestIndex = idx
                        bestCandidate = c
                    }
                }
            }
        }

        if let i = bestIndex, let bc = bestCandidate {
            return (bc, i)
        }
        return nil
    }

    private static func subtractRect(
        freeRect: FreeRectangle,
        placedRect: PlacedRect
    ) -> [FreeRectangle] {
        if !doOverlap(freeRect: freeRect, placedRect: placedRect) {
            return [freeRect]
        }
        var results: [FreeRectangle] = []

        let frLeft   = freeRect.x
        let frRight  = freeRect.x + freeRect.width
        let frTop    = freeRect.y
        let frBottom = freeRect.y + freeRect.height

        let prLeft   = placedRect.x
        let prRight  = placedRect.x + placedRect.width
        let prTop    = placedRect.y
        let prBottom = placedRect.y + placedRect.height

        // 上余り
        if prTop > frTop {
            results.append(
                FreeRectangle(
                    x: frLeft,
                    y: frTop,
                    width: freeRect.width,
                    height: prTop - frTop
                )
            )
        }
        // 下余り
        if prBottom < frBottom {
            results.append(
                FreeRectangle(
                    x: frLeft,
                    y: prBottom,
                    width: freeRect.width,
                    height: frBottom - prBottom
                )
            )
        }
        // 左余り
        if prLeft > frLeft {
            let newWidth = prLeft - frLeft
            let topY = max(frTop, prTop)
            let bottomY = min(frBottom, prBottom)
            let cutHeight = bottomY - topY
            if cutHeight > 0 {
                results.append(
                    FreeRectangle(
                        x: frLeft,
                        y: topY,
                        width: newWidth,
                        height: cutHeight
                    )
                )
            }
        }
        // 右余り
        if prRight < frRight {
            let newWidth = frRight - prRight
            let topY = max(frTop, prTop)
            let bottomY = min(frBottom, prBottom)
            let cutHeight = bottomY - topY
            if cutHeight > 0 {
                results.append(
                    FreeRectangle(
                        x: prRight,
                        y: topY,
                        width: newWidth,
                        height: cutHeight
                    )
                )
            }
        }
        return results
    }

    private static func doOverlap(
        freeRect: FreeRectangle,
        placedRect: PlacedRect
    ) -> Bool {
        let frLeft   = freeRect.x
        let frRight  = freeRect.x + freeRect.width
        let frTop    = freeRect.y
        let frBottom = freeRect.y + freeRect.height

        let prLeft   = placedRect.x
        let prRight  = placedRect.x + placedRect.width
        let prTop    = placedRect.y
        let prBottom = placedRect.y + placedRect.height

        if frRight <= prLeft || frLeft >= prRight { return false }
        if frBottom <= prTop || frTop >= prBottom { return false }
        return true
    }

    private static func cleanUpFreeRectangles(_ rects: [FreeRectangle]) -> [FreeRectangle] {
        var cleaned: [FreeRectangle] = []
        for r in rects {
            if r.width > 0.01 && r.height > 0.01 {
                cleaned.append(r)
            }
        }
        var result: [FreeRectangle] = []
        for i in 0..<cleaned.count {
            let r1 = cleaned[i]
            var contained = false
            for j in 0..<cleaned.count where i != j {
                let r2 = cleaned[j]
                if isContainedIn(r1, r2) {
                    contained = true
                    break
                }
            }
            if !contained {
                result.append(r1)
            }
        }
        return result
    }

    private static func isContainedIn(_ r1: FreeRectangle, _ r2: FreeRectangle) -> Bool {
        return (r1.x >= r2.x)
            && (r1.y >= r2.y)
            && (r1.x + r1.width <= r2.x + r2.width)
            && (r1.y + r1.height <= r2.y + r2.height)
    }
}

struct FreeRectangle {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct PlacedRect {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let color: Color
}

// MARK: - ContentView（幅と長さの入力、パーツリスト入力、回転トグル、カット図生成）
struct ContentView: View {
    @State private var baseLongSide: String = "10000"
    @State private var baseShortSide: String = "1220"
    @State private var partLongSide: String = ""
    @State private var partShortSide: String = ""
    @State private var partQuantity: String = ""

    @State var layouts: [Layout] = []
    @State var errorMessage: String?
    @State var showErrorAlert: Bool = false
    @FocusState private var isInputActive: Bool
    @State var navigateToDiagramView = false
    @State var partSizeToColor: [String: Color] = [:]
    @State var colorIndex: Int = 0

    @StateObject var partsData = PartsData()

    // ヘルプ
    @State private var showHelpView = false
    // 保存されたカット図
    @State private var showSavedDiagrams = false

    // 回転を許可するか
    @State private var allowRotation: Bool = false
    
    // 「回転を許可」ボタン押した時のアラート
    @State private var showRotationAlert: Bool = false
    
    // 現在のアプリバージョン
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "不明"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                ScrollView {
                    VStack {
                        Text("元のシートの幅を設定（mm）")
                            .font(.headline)

                        HStack(spacing: 10) {
                            VStack(alignment: .leading) {
                                Text("長さ(自動計算)")
                                    .font(.caption)
                                TextField("10000", text: $baseLongSide)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .focused($isInputActive)
                            }
                            VStack(alignment: .leading) {
                                Text("幅")
                                    .font(.caption)
                                TextField("1220", text: $baseShortSide)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .focused($isInputActive)
                            }
                        }

                        Toggle("シートの回転を許可", isOn: $allowRotation)
                            .padding(.top, 10)
                            .padding(.bottom, 20)
                            .onChange(of: allowRotation) { oldValue, newValue in
                                if newValue {
                                    showRotationAlert = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        showRotationAlert = false
                                    }
                                }
                            }

                        Text("切り出すシートのサイズと数量を入力")
                            .font(.headline)
                        HStack {
                            TextField("縦", text: $partLongSide)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isInputActive)
                            TextField("横", text: $partShortSide)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isInputActive)
                            TextField("数量", text: $partQuantity)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isInputActive)
                        }

                        HStack {
                            Button(action: addPart) {
                                Text("シートを追加")
                                    .font(.headline)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color(red: 171/255, green: 205/255, blue: 3/255))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }

                            Button(action: {
                                generateLayout()
                            }) {
                                Text("カット図を作成")
                                    .font(.headline)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color(red: 113/255, green: 79/255, blue: 157/255))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)

                        Button(action: {
                            showSavedDiagrams = true
                        }) {
                            Text("保存されたカット図を開く")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gray) // 背景色をグレーに変更
                                        .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .sheet(isPresented: $showSavedDiagrams) {
                            SavedDiagramsView(allowRotation: $allowRotation)
                        }
                    }
                    .padding()
                    .onTapGesture {
                        isInputActive = false
                    }
                    .gesture(
                        DragGesture().onChanged { _ in
                            isInputActive = false
                        }
                    )
                    .alert(isPresented: $showErrorAlert) {
                        Alert(
                            title: Text("エラー"),
                            message: Text(errorMessage ?? ""),
                            dismissButton: .default(Text("OK"))
                        )
                    }
                }

                // 追加されたパーツ一覧
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(partsData.parts) { part in
                            HStack {
                                Text("縦: \(Int(part.longSide))  , 横: \(Int(part.shortSide))   × \(part.quantity)個")
                                    .foregroundColor(part.color)
                                Spacer()
                                Circle()
                                    .fill(part.color)
                                    .frame(width: 20, height: 20)
                                Button(action: {
                                    deletePart(part)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
            .navigationDestination(isPresented: $navigateToDiagramView) {
                DiagramView(
                    layouts: $layouts,
                    parts: $partsData.parts,
                    baseLongSide: Binding(
                        get: { Double(baseLongSide) ?? 0 },
                        set: { baseLongSide = String($0) }
                    ),
                    baseShortSide: Double(baseShortSide) ?? 0,
                    errorMessage: $errorMessage,
                    showErrorAlert: $showErrorAlert,
                    allowRotation: $allowRotation
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showHelpView = true
                    }) {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .sheet(isPresented: $showHelpView) {
                HelpView(appVersion: appVersion)
            }
        }
        .alert(isPresented: $showRotationAlert) {
            Alert(
                title: Text("ご注意ください！"),
                message: Text("シートの回転を許可する場合、木目等の方向性にご注意ください。"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    func addPart() {
        guard let longSide = Double(partLongSide),
              let shortSide = Double(partShortSide),
              let quantity = Int(partQuantity),
              quantity > 0 else {
            return
        }

        if let baseShort = Double(baseShortSide) {
            if shortSide > baseShort {
                errorMessage = "切り出すシートの横が元のシートの幅を超えています。"
                showErrorAlert = true
                return
            }
        }

        let partSizeKey = "\(longSide)-\(shortSide)"
        var color: Color
        if let existingColor = partSizeToColor[partSizeKey] {
            color = existingColor
        } else {
            color = generateColor(index: colorIndex)
            partSizeToColor[partSizeKey] = color
            colorIndex += 1
        }

        let part = Part(longSide: longSide, shortSide: shortSide, quantity: quantity, color: color)
        partsData.parts.append(part)
        sortParts()
        partLongSide = ""
        partShortSide = ""
        partQuantity = ""
    }

    func deletePart(_ part: Part) {
        if let index = partsData.parts.firstIndex(where: { $0.id == part.id }) {
            partsData.parts.remove(at: index)
            sortParts()
        }
    }

    func sortParts() {
        partsData.parts.sort { (part1, part2) -> Bool in
            let area1 = part1.longSide * part1.shortSide * Double(part1.quantity)
            let area2 = part2.longSide * part2.shortSide * Double(part2.quantity)
            return area1 > area2
        }
    }

    func generateLayout() {
        guard let fixedWidth = Double(baseShortSide) else {
            errorMessage = "シートの幅を正しく入力してください。"
            showErrorAlert = true
            return
        }

        var allParts: [Part] = []
        for part in partsData.parts {
            if part.shortSide > fixedWidth {
                DispatchQueue.main.async {
                    errorMessage = "パーツの横(\(part.shortSide))がシートの幅(\(fixedWidth))を超えています。"
                    showErrorAlert = true
                }
                return
            }
            for _ in 0..<part.quantity {
                allParts.append(part.copy())
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let layout = PackingAlgorithm.packPartsFixedWidthBestFit(
                parts: allParts,
                fixedWidth: fixedWidth,
                kerf: 0.0,
                allowRotation: allowRotation
            )

            DispatchQueue.main.async {
                if layout.placedParts.isEmpty {
                    errorMessage = "切り出すシートを配置できませんでした。"
                    showErrorAlert = true
                } else {
                    baseLongSide = String(format: "%.1f", layout.baseLongSide)
                    layouts = [layout]
                    navigateToDiagramView = true
                }
            }
        }
    }

    func generateColor(index: Int) -> Color {
        let hue = Double((index * 37) % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.8)
    }
}

// MARK: - DiagramView
struct DiagramView: View {
    @Binding var layouts: [Layout]
    @Binding var parts: [Part]
    @Binding var baseLongSide: Double
    let baseShortSide: Double
    let kerf: Double = 0.0
    @Binding var errorMessage: String?
    @Binding var showErrorAlert: Bool
    @Binding var allowRotation: Bool

    @State private var showResetConfirmation = false
    @State private var isResetting: Bool = false

    // ★ 保存時に使うアラートのフラグと入力用文字列
    @State private var showSaveAlert: Bool = false
    @State private var diagramNameInput: String = ""

    var body: some View {
        ScrollView {
            VStack {
                Text("必要な長さ: \(Int(baseLongSide)) mm ")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                if isResetting {
                    ProgressView("リセット中...")
                        .padding()
                } else {
                    Text("切り出すシート一覧")
                        .font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(parts) { part in
                                HStack(spacing: 10) {
                                    HStack(spacing: 10) {
                                        Text("縦: \(Int(part.longSide)) ")
                                            .frame(width: 100, alignment: .leading)
                                        Text("横: \(Int(part.shortSide)) ")
                                            .frame(width: 100, alignment: .leading)
                                        Text("数量: \(part.quantity)")
                                            .frame(width: 80, alignment: .leading)
                                    }
                                    Button(action: {
                                        swapDimensions(of: part)
                                    }) {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .foregroundColor(.blue)
                                    }
                                    .disabled(!allowRotation)
                                    Spacer()
                                    Circle()
                                        .fill(part.color)
                                        .frame(width: 20, height: 20)
                                }
                                .padding(.horizontal)
                                .onChange(of: part.longSide) {
                                    recalculateLayout()
                                }
                                .onChange(of: part.shortSide) {
                                    recalculateLayout()
                                }
                                .onChange(of: part.quantity) {
                                    recalculateLayout()
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        deletePart(part)
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    .padding(.bottom)

                    ForEach(layouts.indices, id: \.self) { index in
                        VStack {
                            Text("元のシートサイズ: 縦 \(Int(layouts[index].baseLongSide))   × 横 \(Int(layouts[index].baseShortSide))")
                                .font(.subheadline)
                                .foregroundColor(.gray)

                            WoodCuttingDiagram(
                                baseLongSide: layouts[index].baseLongSide,
                                baseShortSide: layouts[index].baseShortSide,
                                placedParts: $layouts[index].placedParts
                            )
                            .aspectRatio(layouts[index].baseShortSide / layouts[index].baseLongSide, contentMode: .fit)
                            .frame(maxWidth: UIScreen.main.bounds.width)
                            .border(Color.black, width: 2)
                            .padding(.bottom)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationBarTitle("カット図", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("再計算") {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)
                .alert(isPresented: $showResetConfirmation) {
                    Alert(
                        title: Text("確認"),
                        message: Text("本当に再計算しますか？"),
                        primaryButton: .destructive(Text("再計算")) {
                            resetAllParts()
                        },
                        secondaryButton: .cancel(Text("キャンセル"))
                    )
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                // ★ ここでシートではなくアラートを呼び出す
                Button("保存") {
                    diagramNameInput = ""
                    showSaveAlert = true
                }
            }
        }
        // ★ アラートで名前入力（iOS17以降で使えるスタイル）
        .alert("カット図の保存", isPresented: $showSaveAlert, actions: {
            TextField("例: 天板カット図1", text: $diagramNameInput)
            Button("保存") {
                let trimmed = diagramNameInput.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    errorMessage = "カット図の名前を入力してください。"
                    showErrorAlert = true
                    return
                }
                saveDiagram(withName: trimmed)
            }
            Button("キャンセル", role: .cancel) {}
        }, message: {
            Text("カット図に名前を付けて保存します。")
        })
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("エラー"),
                message: Text(errorMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    func saveDiagram(withName name: String) {
        let savedDiagram = SavedDiagram(layouts: layouts, parts: parts, name: name)
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(savedDiagram)
            let sanitizedFileName = sanitizeFileName(name)
            let url = getDocumentsDirectory().appendingPathComponent("\(sanitizedFileName).json")
            try data.write(to: url)
            print("カット図を保存しました: \(url)")
        } catch {
            errorMessage = "カット図の保存に失敗しました: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func swapDimensions(of part: Part) {
        guard let index = parts.firstIndex(where: { $0.id == part.id }) else { return }
        let newLongSide = parts[index].shortSide
        let newShortSide = parts[index].longSide

        if newLongSide > baseLongSide || newShortSide > baseShortSide {
            errorMessage = "縦横を入れ替えると元のシートの寸法を超えてしまいます。"
            showErrorAlert = true
        } else {
            parts[index].longSide = newLongSide
            parts[index].shortSide = newShortSide
            recalculateLayout()
        }
    }

    func deletePart(_ part: Part) {
        if let index = parts.firstIndex(where: { $0.id == part.id }) {
            parts.remove(at: index)
            recalculateLayout()
        }
    }

    func resetAllParts() {
        isResetting = true
        let currentParts = parts.map { $0.copy() }

        DispatchQueue.global(qos: .userInitiated).async {
            var allParts: [Part] = []
            for part in currentParts {
                for _ in 0..<part.quantity {
                    allParts.append(
                        Part(
                            longSide: part.longSide,
                            shortSide: part.shortSide,
                            quantity: 1,
                            color: part.color
                        )
                    )
                }
            }

            guard baseShortSide > 0 else {
                DispatchQueue.main.async {
                    errorMessage = "幅の入力が不正です。"
                    showErrorAlert = true
                    isResetting = false
                }
                return
            }
            let fixedWidth = baseShortSide

            let newLayout = PackingAlgorithm.packPartsFixedWidthBestFit(
                parts: allParts,
                fixedWidth: fixedWidth,
                kerf: 0.0,
                allowRotation: allowRotation
            )
            DispatchQueue.main.async {
                layouts = [newLayout]
                isResetting = false
            }
        }
    }

    func recalculateLayout() {
        guard baseShortSide > 0 else {
            DispatchQueue.main.async {
                errorMessage = "幅の入力が不正です。"
                showErrorAlert = true
                isResetting = false
            }
            return
        }
        let fixedWidth = baseShortSide
        let currentParts = parts.map { $0.copy() }

        DispatchQueue.global(qos: .userInitiated).async {
            var allParts: [Part] = []
            for part in currentParts {
                for _ in 0..<part.quantity {
                    allParts.append(
                        Part(
                            longSide: part.longSide,
                            shortSide: part.shortSide,
                            quantity: 1,
                            color: part.color
                        )
                    )
                }
            }

            let newLayout = PackingAlgorithm.packPartsFixedWidthBestFit(
                parts: allParts,
                fixedWidth: fixedWidth,
                kerf: 0.0,
                allowRotation: allowRotation
            )

            DispatchQueue.main.async {
                self.layouts = [newLayout]
                if newLayout.placedParts.isEmpty {
                    errorMessage = "配置できませんでした。"
                    showErrorAlert = true
                } else {
                    baseLongSide = newLayout.baseLongSide
                }
            }
        }
    }
}

// MARK: - WoodCuttingDiagram
struct WoodCuttingDiagram: View {
    let baseLongSide: Double
    let baseShortSide: Double
    @Binding var placedParts: [PlacedPart]

    // ピンチズーム
    @State private var scale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0

    // 平行移動
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @GestureState private var dragOffset: CGSize = .zero

    // 初期右寄せ用
    @State private var didInitialLayout = false

    // ズームの中心座標(簡易)
    @State private var zoomAnchor: CGPoint = .zero

    // ズーム制限
    private let minScaleValue: CGFloat = 0.5
    private let maxScaleValue: CGFloat = 3.0

    init(
        baseLongSide: Double,
        baseShortSide: Double,
        placedParts: Binding<[PlacedPart]>
    ) {
        self.baseLongSide = baseLongSide
        self.baseShortSide = baseShortSide
        self._placedParts = placedParts
    }
    // 初期ズームの割合。お好みで 0.85, 0.9, 0.95 などに調整
        
    private let initialScaleFactor: CGFloat = 0.75
       
       var body: some View {
           GeometryReader { geometry in
               // (1) ベースとなる大まかなスケールを計算
               let baseScale = min(
                   geometry.size.width / CGFloat(baseShortSide),
                   geometry.size.height / CGFloat(baseLongSide)
               )
               
               // (2) さらに初期ズーム割合を掛け合わせる
               let adjustedBaseScale = baseScale * initialScaleFactor
               
               // ここで scale * gestureScale が乗るので、最終的には
               // totalScale = adjustedBaseScale * scale * gestureScale
               let totalScale = adjustedBaseScale * scale * gestureScale
               
               let diagramWidth = CGFloat(baseShortSide) * totalScale
               let diagramHeight = CGFloat(baseLongSide) * totalScale

               ZStack(alignment: .topLeading) {
                   Rectangle()
                       .fill(Color.gray.opacity(0.2))
                       .frame(width: diagramWidth, height: diagramHeight)

                   drawGridLinesWithLabels(
                       baseLongSide: baseLongSide,
                       baseShortSide: baseShortSide,
                       scale: totalScale
                   )

                   ForEach(placedParts) { part in
                       PlacedPartView(
                           part: part,
                           scale: totalScale,
                           baseLongSide: baseLongSide,
                           baseShortSide: baseShortSide,
                           placedParts: $placedParts
                       )
                   }
               }
               .offset(x: offsetX + dragOffset.width, y: offsetY + dragOffset.height)
               .onAppear {
                   // 初期時に左右中央寄せにしたい場合、 (画面幅 - 図幅)/2 の余白を持つ
                   // もしくは「右寄せにしたい」なら geometry.size.width - diagramWidth
                   if !didInitialLayout {
                       didInitialLayout = true
                       offsetX = (geometry.size.width - diagramWidth) / 2
                       // offsetY も上下に少し余裕がほしいなら、同様に適当に加減
                   }
               }
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .updating($gestureScale) { current, gestureState, _ in
                            gestureState = current
                        }
                        .onEnded { finalScale in
                            let newScale = scale * finalScale
                            scale = max(minScaleValue, min(newScale, maxScaleValue))
                        },
                    DragGesture(minimumDistance: 0)
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onChanged { value in
                            let locationInView = value.location
                            let locX = (locationInView.x - (offsetX + dragOffset.width)) / totalScale
                            let locY = (locationInView.y - (offsetY + dragOffset.height)) / totalScale
                            zoomAnchor = CGPoint(x: locX, y: locY)
                        }
                        .onEnded { value in
                            offsetX += value.translation.width
                            offsetY += value.translation.height
                            // 上には行かない(=offsetY >= 0)
                            if offsetY < 0 {
                                offsetY = 0
                            }
                        }
                )
            )
        }
    }

    func drawGridLinesWithLabels(
        baseLongSide: Double,
        baseShortSide: Double,
        scale: CGFloat
    ) -> some View {
        ZStack {
            Path { path in
                let step: Double = 100
                for x in stride(from: 0, through: baseShortSide, by: step) {
                    let xPos = CGFloat(x) * scale
                    path.move(to: CGPoint(x: xPos, y: 0))
                    path.addLine(to: CGPoint(x: xPos, y: CGFloat(baseLongSide) * scale))
                }
                for y in stride(from: 0, through: baseLongSide, by: step) {
                    let yPos = CGFloat(y) * scale
                    path.move(to: CGPoint(x: 0, y: yPos))
                    path.addLine(to: CGPoint(x: CGFloat(baseShortSide) * scale, y: yPos))
                }
            }
            .stroke(Color.gray, lineWidth: 0.5)

            Path { path in
                let step: Double = 500
                for x in stride(from: 0, through: baseShortSide, by: step) {
                    let xPos = CGFloat(x) * scale
                    path.move(to: CGPoint(x: xPos, y: 0))
                    path.addLine(to: CGPoint(x: xPos, y: CGFloat(baseLongSide) * scale))
                }
                for y in stride(from: 0, through: baseLongSide, by: step) {
                    let yPos = CGFloat(y) * scale
                    path.move(to: CGPoint(x: 0, y: yPos))
                    path.addLine(to: CGPoint(x: CGFloat(baseShortSide) * scale, y: yPos))
                }
            }
            .stroke(Color.red, lineWidth: 1.0)

            drawGridLabels(baseLongSide: baseLongSide, baseShortSide: baseShortSide, scale: scale)
        }
    }

    func drawGridLabels(
        baseLongSide: Double,
        baseShortSide: Double,
        scale: CGFloat
    ) -> some View {
        ZStack {
            ForEach(Array(stride(from: 0.0, through: baseShortSide, by: 500)), id: \.self) { x in
                Text("\(Int(x))")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .position(x: CGFloat(x) * scale, y: -10)
            }
            ForEach(Array(stride(from: 0.0, through: baseLongSide, by: 500)), id: \.self) { y in
                Text("\(Int(y))")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .position(x: -30, y: CGFloat(y) * scale)
            }
        }
    }
}

// MARK: - PlacedPartView
struct PlacedPartView: View {
    @ObservedObject var part: PlacedPart
    let scale: CGFloat
    let baseLongSide: Double
    let baseShortSide: Double
    @Binding var placedParts: [PlacedPart]

    @GestureState private var dragState = DragState.inactive

    var body: some View {
        Rectangle()
            .stroke(Color.white, lineWidth: 2)
            .background(Rectangle().fill(part.color.opacity(0.5)))
            .frame(width: CGFloat(part.shortSide) * scale, height: CGFloat(part.longSide) * scale)
            .overlay(
                ZStack {
                    // 横寸表示
                    if part.shortSide > 200 {
                        Text("\(Int(part.shortSide))  ")
                            .font(.caption)
                            .foregroundColor(.black)
                            .padding(2)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(4)
                            .offset(y: -(CGFloat(part.longSide)*scale)/2 + 10)
                    } else {
                        Text("\(Int(part.shortSide))")
                            .font(.caption2)
                            .foregroundColor(.black)
                            .padding(2)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(4)
                            .offset(y: -(CGFloat(part.longSide)*scale)/2 + 10)
                    }

                    // 縦寸表示
                    if part.longSide > 200 {
                        Text("\(Int(part.longSide))  ")
                            .font(.caption)
                            .foregroundColor(.black)
                            .padding(2)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(4)
                            .rotationEffect(.degrees(-90))
                            .offset(x: -(CGFloat(part.shortSide)*scale)/2 + 10)
                    } else {
                        Text("\(Int(part.longSide))")
                            .font(.caption2)
                            .foregroundColor(.black)
                            .padding(2)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(4)
                            .rotationEffect(.degrees(-90))
                            .offset(x: -(CGFloat(part.shortSide)*scale)/2 + 10)
                    }
                }
            )
            .position(
                x: (CGFloat(part.x) + CGFloat(part.shortSide)/2) * scale + dragState.translation.width,
                y: (CGFloat(part.y) + CGFloat(part.longSide)/2) * scale + dragState.translation.height
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture())
                    .updating($dragState) { value, state, _ in
                        switch value {
                        case .first(true):
                            state = .pressing
                        case .second(true, let drag?):
                            state = .dragging(translation: drag.translation)
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag?):
                            let deltaX = Double(drag.translation.width) / Double(scale)
                            let deltaY = Double(drag.translation.height) / Double(scale)
                            var newX = part.x + deltaX
                            var newY = part.y + deltaY

                            // 左右・上下にはみ出さない
                            if newX < 0 { newX = 0 }
                            if newX + part.shortSide > baseShortSide {
                                newX = baseShortSide - part.shortSide
                            }
                            if newY < 0 { newY = 0 }
                            if newY + part.longSide > baseLongSide {
                                newY = baseLongSide - part.longSide
                            }

                            // 他パーツ重なりチェック
                            let doesOverlap = checkOverlap(newX: newX, newY: newY, part: part)
                            if doesOverlap {
                                newX = part.x
                                newY = part.y
                            }

                            part.x = newX
                            part.y = newY
                        default:
                            break
                        }
                    }
            )
    }

    func checkOverlap(newX: Double, newY: Double, part: PlacedPart) -> Bool {
        for otherPart in placedParts {
            if otherPart.id != part.id {
                let thisLeft = newX
                let thisRight = newX + part.shortSide
                let thisTop = newY
                let thisBottom = newY + part.longSide

                let otherLeft = otherPart.x
                let otherRight = otherPart.x + otherPart.shortSide
                let otherTop = otherPart.y
                let otherBottom = otherPart.y + otherPart.longSide

                if thisRight > otherLeft && thisLeft < otherRight &&
                   thisBottom > otherTop && thisTop < otherBottom {
                    return true
                }
            }
        }
        return false
    }
}

enum DragState {
    case inactive
    case pressing
    case dragging(translation: CGSize)

    var translation: CGSize {
        switch self {
        case .dragging(let t):
            return t
        default:
            return .zero
        }
    }
    var isDragging: Bool {
        switch self {
        case .dragging:
            return true
        default:
            return false
        }
    }
}

// MARK: - SavedDiagramsView
struct SavedDiagramsView: View {
    @Environment(\.presentationMode) var presentationMode

    @Binding var allowRotation: Bool

    @State private var savedDiagrams: [String] = []
    @State private var selectedDiagramName: String?
    @State private var layouts: [Layout] = []
    @State private var parts: [Part] = []
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false
    @State private var navigateToDiagramView = false

    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                ForEach(savedDiagrams, id: \.self) { diagram in
                    Button(action: {
                        loadDiagram(named: diagram)
                    }) {
                        Text(diagram)
                    }
                }
                .onDelete(perform: deleteDiagram)
            }
            .navigationBarTitle("保存されたカット図", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editMode == .active ? "完了" : "編集") {
                        editMode = (editMode == .active) ? .inactive : .active
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .onAppear(perform: loadSavedDiagrams)
            .navigationDestination(isPresented: $navigateToDiagramView) {
                DiagramView(
                    layouts: $layouts,
                    parts: $parts,
                    baseLongSide: Binding(
                        get: { layouts.first?.baseLongSide ?? 0 },
                        set: { newValue in
                            if let index = layouts.indices.first {
                                layouts[index].baseLongSide = newValue
                            }
                        }
                    ),
                    baseShortSide: layouts.first?.baseShortSide ?? 0,
                    errorMessage: $errorMessage,
                    showErrorAlert: $showErrorAlert,
                    allowRotation: $allowRotation
                )
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("エラー"),
                    message: Text(errorMessage ?? ""),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    func loadSavedDiagrams() {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: getDocumentsDirectory(),
                includingPropertiesForKeys: nil
            )
            savedDiagrams = files
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
        } catch {
            errorMessage = "保存されたカット図の読み込みに失敗しました: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func loadDiagram(named name: String) {
        let url = getDocumentsDirectory().appendingPathComponent("\(name).json")
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let savedDiagram = try decoder.decode(SavedDiagram.self, from: data)
            layouts = savedDiagram.layouts
            parts = savedDiagram.parts
            navigateToDiagramView = true
        } catch {
            errorMessage = "カット図の読み込みに失敗しました: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func deleteDiagram(at offsets: IndexSet) {
        for index in offsets {
            let name = savedDiagrams[index]
            let url = getDocumentsDirectory().appendingPathComponent("\(name).json")
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                errorMessage = "カット図の削除に失敗しました: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
        savedDiagrams.remove(atOffsets: offsets)
    }

    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - HelpView
// MARK: - HelpView
struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    var appVersion: String

    var body: some View {
        NavigationView {
            ScrollView {
                Text(helpText)
                    .padding()

                // ★ ここにバージョン情報を表示
                Text("現在のバージョン: \(appVersion)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .navigationTitle("ヘルプ")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    let helpText = """
     ヘルプ・ガイド

    1. 元のシートの設定
    元のシートの幅を入力してください。（例: 1220 mm）  
    シートの長さは入力された幅と選択されたアルゴリズムに基づいて自動的に計算されます。

    2. パーツの追加
    切り出すシートのサイズ（縦・横）と数量を入力し、「シートを追加」ボタンを押すと、リストにパーツが追加されます。  
    同じサイズのパーツは自動的に同じ色で表示されます。

    3. カット図の作成
    「カット図を作成」ボタンを押すと、選択されたパーツの配置がアルゴリズムによって計算され、カット図が生成されます。  
    *回転を許可* オプションをONにすると、パーツの縦横を↑↓ボタンで90度入れ替えて配置することが可能になります。  
    ただし、アルゴリズムの特性上、必ずしも最適な配置結果が得られるわけではありません。複数回試行することで、より効率的な結果が得られる場合があります。

    4. カット図の編集
    生成されたカット図では、以下の操作が可能です：

    - *長押しでパーツを移動*  
      パーツを長押しすることでドラッグ操作が可能になり、自由に位置を変更できます。  
      移動中に他のパーツと重なりが検出されると、自動的に元の位置に戻ります。  
      重なりを避けて配置を調整してください。

    - *ピンチズームとドラッグ*  
      カット図全体をピンチ操作でズームイン・ズームアウトできます。  
      また、ドラッグ操作でカット図を移動させ、画面内で自由に閲覧できます。

    5. カット図の保存と読み込み
    - *保存*  
      カット図を保存する際には、保存ボタンを押すとアラートが表示され、名前を入力して保存できます。  
      保存されたカット図は後で読み込むことが可能です。

    - *読み込み*  
      「保存されたカット図を開く」ボタンから、過去に保存したカット図を選択して読み込むことができます。  
      読み込んだカット図は編集や再保存が可能です。

    6. 注意事項
    - *アルゴリズムの限界* 
      使用している配置アルゴリズムは複雑な配置や最適な配置を必ずしも実現できるわけではありません。  
      配置結果が意図したものと異なる場合は、パーツの順序や数量、回転の許可設定を調整して再度試行してください。

    - *木目や方向性の注意*  
      シートの回転を許可する場合、木目や素材の方向性に注意してください。  
      意図しない方向にパーツが配置されると、製作後の品質に影響を与える可能性があります。

    
    """
}

// MARK: - キーボードを閉じる処理
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

