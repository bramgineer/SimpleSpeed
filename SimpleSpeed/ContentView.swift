//
//  ContentView.swift
//  SimpleSpeed
//
//  Created by verdi65 on 10/14/25.
//

import SwiftUI
import AVFoundation

// MARK: - Quiz Model

enum SessionState { case idle, showingTarget, running, finished }

struct Trial: Identifiable {
    let id = UUID()
    let index: Int
    let isTarget: Bool
    let midi: Int
    var onsetUptime: TimeInterval? = nil
    var responseUptime: TimeInterval? = nil
    var responded: Bool = false
    
    var hit: Bool? {
        guard responded else { return nil }
        return isTarget
    }
    
    var isWithinWindow: Bool {
        guard let onset = onsetUptime, let resp = responseUptime else { return false }
        return (resp - onset) * 1000.0 <= 1750.0
    }
}

@MainActor
final class QuizVM: ObservableObject {
    // Config (Simple Speed)
    let interOnsetMs = 2250
    let responseWindowMs = 1750
    let targetLabelMs = 1500
    let totalTrials = 16
    let numTargets = 4
    let noteDurationSec = 1.0
    
    // White keys C4–B4 (MIDI)
    let whiteMIDIs = [60, 62, 64, 65, 67, 69, 71]
    
    // State
    @Published var state: SessionState = .idle
    @Published var targetMIDI: Int = 60
    @Published var targetName: String = "C4"
    @Published var currentIndex: Int = -1
    @Published var trials: [Trial] = []
    @Published var summary: (hits: Int, misses: Int, fas: Int, crs: Int, dprime: Double) = (0,0,0,0,0)
    
    private let audio = SineEngine()
    private var isRespondable = false // guards the response window
    
    // Allow same pitch to occur in consecutive trials (default: true)
    @Published var allowImmediateRepeat: Bool = true
    
    // If set, use this fixed target MIDI for the next quiz; if nil, choose randomly.
    var preferredTargetMIDI: Int? = nil
    
    init() {
        audio.start()
    }
    
    func startQuiz() {
        // Choose a target from white keys (fixed if provided, else random)
        let chosen: Int
        if let pref = preferredTargetMIDI {
            chosen = pref
        } else {
            chosen = whiteMIDIs.randomElement()!
        }
        targetMIDI = chosen
        targetName = Self.noteName(midi: targetMIDI)
        
        // Build 16 trials, pick 4 target positions
        var targetSlots = Set<Int>()
        if allowImmediateRepeat {
            while targetSlots.count < numTargets {
                targetSlots.insert(Int.random(in: 0..<totalTrials))
            }
        } else {
            // ensure targets are not adjacent to avoid immediate repeats of target tone
            var attempts = 0
            repeat {
                attempts += 1
                targetSlots.removeAll(keepingCapacity: true)
                while targetSlots.count < numTargets {
                    targetSlots.insert(Int.random(in: 0..<totalTrials))
                }
                // bail-out guard, though with 16 slots and 4 targets this will almost always succeed quickly
                if attempts > 2000 { break }
            } while QuizVM.hasAdjacent(targetSlots)
        }
        
        var seq: [Trial] = []
        for i in 0..<totalTrials {
            let isTarget = targetSlots.contains(i)
            var midi: Int
            if isTarget {
                midi = targetMIDI
                // if immediate repeats are disallowed, target slots were chosen non-adjacent, so no need to adjust here
            } else {
                var cand = Self.randomDistractor(excluding: targetMIDI, from: whiteMIDIs)
                if !allowImmediateRepeat, let prev = seq.last?.midi {
                    var tries = 0
                    while cand == prev && tries < 32 {
                        cand = Self.randomDistractor(excluding: targetMIDI, from: whiteMIDIs)
                        tries += 1
                    }
                }
                midi = cand
            }
            // final guard: if still equal to previous and repeats not allowed, swap to any other distractor
            if !allowImmediateRepeat, let prev = seq.last?.midi, midi == prev {
                if let alt = whiteMIDIs.filter({ $0 != prev && $0 != targetMIDI }).randomElement() {
                    midi = alt
                }
            }
            seq.append(Trial(index: i, isTarget: isTarget, midi: midi))
        }
        trials = seq
        currentIndex = -1
        summary = (0,0,0,0,0)
        
        state = .showingTarget
        // Play target tone & show label for 1.5 s
        audio.play(midi: targetMIDI, duration: 1.0)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(targetLabelMs) * 1_000_000)
            await runSequence()
        }
    }
    
    private func runSequence() async {
        state = .running
        for i in 0..<trials.count {
            currentIndex = i
            let onset = ProcessInfo.processInfo.systemUptime
            audio.play(midi: trials[i].midi, duration: noteDurationSec)
            isRespondable = true
            trials[i].onsetUptime = onset
            
            // Close response window after 1750 ms
            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.responseWindowMs ?? 1750) * 1_000_000)
                await MainActor.run { self?.isRespondable = false }
            }
            // Wait for IOI 2250 ms before next note
            try? await Task.sleep(nanoseconds: UInt64(interOnsetMs) * 1_000_000)
        }
        finish()
    }
    
    func respondTapped() {
        guard state == .running, currentIndex >= 0, currentIndex < trials.count else { return }
        guard isRespondable, trials[currentIndex].responded == false else { return }
        let resp = ProcessInfo.processInfo.systemUptime
        trials[currentIndex].responded = true
        trials[currentIndex].responseUptime = resp
    }
    
    private func finish() {
        state = .finished
        
        // Score
        var hits = 0, misses = 0, fas = 0, crs = 0
        for t in trials {
            if t.isTarget {
                if t.responded, t.isWithinWindow { hits += 1 } else { misses += 1 }
            } else {
                if t.responded, t.isWithinWindow { fas += 1 } else { crs += 1 }
            }
        }
        let d = Self.dPrime(hits: hits, misses: misses, fas: fas, crs: crs)
        summary = (hits, misses, fas, crs, d)
    }
    
    func reset() {
        trials.removeAll()
        currentIndex = -1
        state = .idle
    }
    
    // MARK: - Helpers
    
    private static func randomDistractor(excluding: Int, from pool: [Int]) -> Int {
        var choices = pool.filter { $0 != excluding }
        return choices.randomElement()!
    }
    
    private static func hasAdjacent(_ set: Set<Int>) -> Bool {
        for v in set {
            if set.contains(v - 1) || set.contains(v + 1) { return true }
        }
        return false
    }
    
    static func noteName(midi: Int) -> String {
        let names = ["C","C♯","D","E♭","E","F","F♯","G","A♭","A","B♭","B"]
        let pc = midi % 12
        let octave = (midi / 12) - 1
        return "\(names[pc])\(octave)"
    }
    
    static func dPrime(hits: Int, misses: Int, fas: Int, crs: Int) -> Double {
        // Signal detection d' with log-linear correction (Hautus)
        let h = Double(hits), m = Double(misses), f = Double(fas), c = Double(crs)
        let hr = (h + 0.5) / (h + m + 1.0)
        let far = (f + 0.5) / (f + c + 1.0)
        func z(_ p: Double) -> Double {
            // Inverse CDF of standard normal using approximant
            return sqrt(2) * erfinv(2*p - 1)
        }
        return z(hr) - z(far)
    }
}

// Simple erf^-1 approximant (good enough for d′ UI)
fileprivate func erfinv(_ x: Double) -> Double {
    // Winitzki approximation
    let a = 0.147
    let ln = log(1 - x*x)
    let t = (2/(Double.pi*a)) + ln/2
    let root = sqrt(t*t - ln/a)
    return (x >= 0 ? 1 : -1) * sqrt(root - t)
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var vm = QuizVM()
    @State private var randomTarget: Bool = false
    @State private var selectedMIDI: Int = 60 // C4 default
    @State private var allowRepeats: Bool = true
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Simple Speed (Sine)").font(.title2).bold()
            switch vm.state {
            case .idle:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Press Start to begin.\nYou’ll see a target note for 1.5 s, then hear 16 notes.\nTap “Heard it!” whenever the target plays.")
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                    
                    Toggle("Random target each run", isOn: $randomTarget)
                        .toggleStyle(.switch)
                    
                    Toggle("Allow same pitch twice in a row", isOn: $allowRepeats)
                        .toggleStyle(.switch)
                    
                    Text("Select Target Note").font(.headline).padding(.top, 4)
                    // Table of selectable target tones (white keys C4–B4)
                    List {
                        ForEach(vm.whiteMIDIs, id: \.self) { m in
                            HStack {
                                Text(QuizVM.noteName(midi: m))
                                Spacer()
                                if m == selectedMIDI && !randomTarget {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !randomTarget else { return }
                                selectedMIDI = m
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                    .disabled(randomTarget)
                    .opacity(randomTarget ? 0.5 : 1.0)
                    
                    Button("Start") {
                        vm.preferredTargetMIDI = randomTarget ? nil : selectedMIDI
                        vm.allowImmediateRepeat = allowRepeats
                        vm.startQuiz()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                
            case .showingTarget:
                VStack(spacing: 8) {
                    Text("Target Note").font(.headline)
                    Text(vm.targetName).font(.system(size: 48, weight: .bold, design: .rounded))
                    ProgressView().progressViewStyle(.circular)
                        .padding(.top, 8)
                }
                
            case .running:
                VStack(spacing: 8) {
                    Text("Target: \(vm.targetName)").font(.headline)
                    ProgressView(value: Double(vm.currentIndex + 1), total: Double(vm.totalTrials))
                        .tint(.blue)
                        .padding(.horizontal)
                    Text("Note \(vm.currentIndex + 1) / \(vm.totalTrials)")
                        .foregroundStyle(.secondary)
                    Button {
                        vm.respondTapped()
                    } label: {
                        Text("Heard it!")
                            .font(.title3).bold()
                            .frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
                
            case .finished:
                VStack(spacing: 12) {
                    Text("Results").font(.title3).bold()
                    resultRow(label: "Hits", value: vm.summary.hits, color: .green)
                    resultRow(label: "Misses", value: vm.summary.misses, color: .red)
                    resultRow(label: "False Alarms", value: vm.summary.fas, color: .orange)
                    resultRow(label: "Correct Rejections", value: vm.summary.crs, color: .blue)
                    Divider()
                    Text(String(format: "d′ = %.2f", vm.summary.dprime))
                        .font(.headline)
                    HStack {
                        Button("Run Again") { vm.reset(); vm.startQuiz() }
                        Button("Reset") { vm.reset() }.tint(.secondary)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
    
    @ViewBuilder
    private func resultRow(label: String, value: Int, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)").bold().foregroundStyle(color)
        }
    }
}

#Preview {
    ContentView()
}
