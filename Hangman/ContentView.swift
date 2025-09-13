//
//  ContentView.swift
//  Hangman
//
//  Created by 林嘉誠 on 2025/9/12.
//

import SwiftUI
import AVFoundation

private let defaultLives = 7

// 題庫分類
private enum Category: String, CaseIterable, Identifiable {
    case animals = "動物"
    case objects = "物品"
    case actions = "動作"
    
    var id: String { rawValue }
    
    var words: [String] {
        switch self {
        case .animals:
            return [
                "CAT", "DOG", "ELEPHANT", "TIGER", "LION",
                "GIRAFFE", "KANGAROO", "PANDA", "MONKEY", "ZEBRA",
                "WHALE", "DOLPHIN", "EAGLE", "OWL", "RABBIT"
            ]
        case .objects:
            return [
                "TABLE", "CHAIR", "COMPUTER", "PHONE", "BOTTLE",
                "UMBRELLA", "BACKPACK", "KEYBOARD", "HEADPHONE", "CAMERA",
                "NOTEBOOK", "PENCIL", "SCISSORS", "MIRROR", "CLOCK"
            ]
        case .actions:
            return [
                "RUN", "JUMP", "SWIM", "SING", "DANCE",
                "WRITE", "READ", "DRIVE", "COOK", "PAINT",
                "CLIMB", "THINK", "LAUGH", "CRY", "LISTEN"
            ]
        }
    }
}

// 短促提示音（系統音效）
private enum SoundPlayer {
    static func playCorrect() {
        AudioServicesPlaySystemSound(SystemSoundID(1057)) // 輕快提示
    }
    static func playWrong() {
        AudioServicesPlaySystemSound(SystemSoundID(1022)) // 低沉提示
    }
}

// 背景音樂/較長音效（mp3/wav 由專案資源提供）
private final class BGMPlayer {
    static let shared = BGMPlayer()
    private var player: AVAudioPlayer?

    func play(resource name: String, ext: String = "mp3", volume: Float = 1.0) {
        stop()
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            // 資源缺失時安靜失敗
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true, options: [])
            
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = volume
            p.prepareToPlay()
            p.play()
            self.player = p
        } catch {
            // 播放失敗忽略
        }
    }
    
    func stop() {
        player?.stop()
        player = nil
    }
}

struct ContentView: View {
    @State private var selectedCategory: Category? = nil
    @State private var targetWord: String = ""
    @State private var guessedLetters: Set<Character> = []
    @State private var remainingLives: Int = defaultLives
    @State private var isGameOver: Bool = false
    @State private var isWin: Bool = false
    
    var maskedWord: String {
        targetWord.map { guessedLetters.contains($0) ? String($0) : "_" }
            .joined(separator: " ")
    }
    
    var wrongGuesses: [Character] {
        guessedLetters.filter { !targetWord.contains($0) }.sorted()
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // 題庫選擇區（若尚未選擇，顯示 Segmented 選擇器；已選擇則顯示提示與更換按鈕）
                categoryPickerArea
                
                // 吊人圖：依剩餘生命顯示部位
                HangmanFigure(lostLives: defaultLives - remainingLives)
                    .frame(height: 160)
                    .frame(maxWidth: 260)
                    .accessibilityLabel("吊人圖")
                    .accessibilityValue("已失去 \(defaultLives - remainingLives) / \(defaultLives) 生命")
                
                Text("Hangman")
                    .font(.largeTitle.bold())
                
                // 顯示當前題庫提示
                if let selectedCategory {
                    Text("題庫：\(selectedCategory.rawValue)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                Text("剩餘生命：\(remainingLives)")
                    .font(.headline)
                    .foregroundColor(remainingLives > 2 ? .primary : .red)
                
                Text(maskedWord)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .accessibilityLabel(maskedWord.replacingOccurrences(of: " ", with: " "))
                    .padding(.top, 8)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                
                if !wrongGuesses.isEmpty {
                    Text("猜錯：\(String(wrongGuesses))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                KeyboardView(
                    enabled: !isGameOver && selectedCategory != nil && !targetWord.isEmpty,
                    guessedLetters: guessedLetters,
                    onTap: handleGuess
                )
                .padding(.top, 8)
                
                HStack(spacing: 12) {
                    Button(action: resetGame) {
                        Label("重新開始", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCategory == nil)
                    
                    // 可選擇更換題庫（會重開遊戲）
                    Menu {
                        ForEach(Category.allCases) { category in
                            Button(category.rawValue) {
                                changeCategory(to: category)
                            }
                        }
                        if selectedCategory != nil {
                            Button(role: .destructive) {
                                selectedCategory = nil
                                clearGame()
                            } label: {
                                Label("清除選擇", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Label("更換題庫", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding()
            .overlay(alignment: .top) {
                // 若未選擇題庫，顯示提示遮罩
                if selectedCategory == nil {
                    Color.clear
                        .frame(height: 0)
                        .allowsHitTesting(false) // 確保不攔截觸控
                }
            }
            
            // 遊戲結束疊層：顯示 win/lose 圖片與再玩一次
            if isGameOver {
                GameOverOverlay(
                    isWin: isWin,
                    answer: targetWord,
                    onReplay: {
                        BGMPlayer.shared.stop()
                        resetGame()
                    }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
            }
        }
        .onAppear {
            // 起始不自動抽題，等選題庫
            clearGame()
        }
    }
    
    private var categoryPickerArea: some View {
        Group {
            if selectedCategory == nil {
                VStack(spacing: 10) {
                    Text("請選擇題庫開始遊戲")
                        .font(.title3.bold())
                    Picker("題庫", selection: Binding(
                        get: { selectedCategory ?? Category.animals },
                        set: { newValue in
                            selectedCategory = newValue
                            resetGame()
                        }
                    )) {
                        ForEach(Category.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
            } else {
                EmptyView()
            }
        }
    }
    
    private func changeCategory(to newCategory: Category) {
        guard selectedCategory != newCategory else { return }
        selectedCategory = newCategory
        resetGame()
    }
    
    private func handleGuess(_ letter: Character) {
        guard !isGameOver else { return }
        guard letter.isLetter else { return }
        let upper = Character(letter.uppercased())
        guard !guessedLetters.contains(upper) else { return }
        
        guessedLetters.insert(upper)
        
        if !targetWord.contains(upper) {
            remainingLives -= 1
            SoundPlayer.playWrong() // 每次猜錯的短音效（保留）
            if remainingLives <= 0 {
                isWin = false
                isGameOver = true
                // 終局：只播放 wrong.mp3
                BGMPlayer.shared.play(resource: "wrong", ext: "mp3", volume: 1.0)
                return
            }
        } else {
            SoundPlayer.playCorrect() // 每次猜對的短音效（保留）
            // 檢查是否全部揭露
            let allRevealed = targetWord.allSatisfy { guessedLetters.contains($0) }
            if allRevealed {
                isWin = true
                isGameOver = true
                // 終局：只播放 correct.mp3
                BGMPlayer.shared.play(resource: "correct", ext: "mp3", volume: 1.0)
            }
        }
    }
    
    private func resetGame() {
        BGMPlayer.shared.stop()
        guessedLetters = []
        remainingLives = defaultLives
        isGameOver = false
        isWin = false
        
        if let selectedCategory {
            targetWord = selectedCategory.words.randomElement() ?? "SWIFT"
        } else {
            targetWord = ""
        }
    }
    
    private func clearGame() {
        BGMPlayer.shared.stop()
        targetWord = ""
        guessedLetters = []
        remainingLives = defaultLives
        isGameOver = false
        isWin = false
    }
}

// 結束畫面 Overlay
private struct GameOverOverlay: View {
    let isWin: Bool
    let answer: String
    let onReplay: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            // 顯示 win / lose 圖片（需在 Assets 中提供名為 "win"、"lose" 的圖片）
            Image(isWin ? "win" : "lose")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)
                .shadow(radius: 8)
                .padding(.horizontal)
            
            Text(isWin ? "你贏了！" : "遊戲結束")
                .font(.title.bold())
            Text(isWin ? "答對：\(answer)" : "正確答案：\(answer)")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Button {
                onReplay()
            } label: {
                Label("再玩一次", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // 半透明遮罩
            Color.black.opacity(0.35).ignoresSafeArea()
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isWin ? "勝利畫面" : "失敗畫面")
    }
}

// 吊人圖：依序顯示 1) 吊繩 2) 頭 3) 左手 4) 右手 5) 身體 6) 左腳 7) 右腳
private struct HangmanFigure: View {
    let lostLives: Int // 0...7
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            // 基準點與尺寸
            let baseY = h * 0.95
            let baseLeftX = w * 0.15
            let baseRightX = w * 0.85
            let postTopY = h * 0.1
            let postX = baseLeftX
            let beamEndX = w * 0.55
            let ropeX = beamEndX
            let ropeTopY = postTopY
            let ropeBottomY = h * 0.32
            
            let headCenter = CGPoint(x: ropeX, y: ropeBottomY + (h * 0.055))
            let headRadius = h * 0.055
            let neckY = headCenter.y + headRadius
            let torsoBottomY = neckY + h * 0.20
            
            let armSpan = w * 0.16
            let armY = neckY + h * 0.05
            
            let legSpan = w * 0.18
            let legTopY = torsoBottomY
            let legBottomY = legTopY + h * 0.22
            
            // 絞刑台（固定顯示，非生命階段）
            Path { p in
                // 地台
                p.move(to: CGPoint(x: baseLeftX, y: baseY))
                p.addLine(to: CGPoint(x: baseRightX, y: baseY))
                // 立柱
                p.move(to: CGPoint(x: postX, y: baseY))
                p.addLine(to: CGPoint(x: postX, y: postTopY))
                // 橫梁
                p.addLine(to: CGPoint(x: beamEndX, y: postTopY))
                // 小支撐
                p.move(to: CGPoint(x: postX, y: h * 0.35))
                p.addLine(to: CGPoint(x: w * 0.32, y: postTopY))
            }
            .stroke(Color.secondary, lineWidth: 3)
            
            // 1) 吊繩
            if lostLives >= 1 {
                Path { p in
                    p.move(to: CGPoint(x: ropeX, y: ropeTopY))
                    p.addLine(to: CGPoint(x: ropeX, y: ropeBottomY))
                }
                .stroke(Color.primary, lineWidth: 3)
            }
            // 2) 頭
            if lostLives >= 2 {
                Circle()
                    .stroke(Color.primary, lineWidth: 3)
                    .frame(width: headRadius * 2, height: headRadius * 2)
                    .position(headCenter)
            }
            // 3) 左手
            if lostLives >= 3 {
                Path { p in
                    p.move(to: CGPoint(x: ropeX, y: armY))
                    p.addLine(to: CGPoint(x: ropeX - armSpan, y: armY + h * 0.05))
                }
                .stroke(Color.primary, lineWidth: 3)
            }
            // 4) 右手
            if lostLives >= 4 {
                Path { p in
                    p.move(to: CGPoint(x: ropeX, y: armY))
                    p.addLine(to: CGPoint(x: ropeX + armSpan, y: armY + h * 0.05))
                }
                .stroke(Color.primary, lineWidth: 3)
            }
            // 5) 身體
            if lostLives >= 5 {
                Path { p in
                    p.move(to: CGPoint(x: ropeX, y: neckY))
                    p.addLine(to: CGPoint(x: ropeX, y: torsoBottomY))
                }
                .stroke(Color.primary, lineWidth: 3)
            }
            // 6) 左腳
            if lostLives >= 6 {
                Path { p in
                    p.move(to: CGPoint(x: ropeX, y: legTopY))
                    p.addLine(to: CGPoint(x: ropeX - legSpan, y: legBottomY))
                }
                .stroke(Color.primary, lineWidth: 3)
            }
            // 7) 右腳
            if lostLives >= 7 {
                Path { p in
                    p.move(to: CGPoint(x: ropeX, y: legTopY))
                    p.addLine(to: CGPoint(x: ropeX + legSpan, y: legBottomY))
                }
                .stroke(Color.primary, lineWidth: 3)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lostLives)
    }
}

private struct KeyboardView: View {
    let enabled: Bool
    let guessedLetters: Set<Character>
    let onTap: (Character) -> Void
    
    // A–Z 順序，分成四排：7、7、6、6
    private var rows: [[Character]] {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let row1 = Array(letters[0..<7])   // A–G
        let row2 = Array(letters[7..<14])  // H–N
        let row3 = Array(letters[14..<20]) // O–T
        let row4 = Array(letters[20..<26]) // U–Z
        return [row1, row2, row3, row4]
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(rows[rowIndex], id: \.self) { letter in
                        let guessed = guessedLetters.contains(letter)
                        Button(action: { onTap(letter) }) {
                            Text(String(letter))
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .tint(guessed ? .gray : .accentColor)
                        .disabled(!enabled || guessed)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("鍵盤")
    }
}

#Preview {
    ContentView()
}
