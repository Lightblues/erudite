import SwiftUI

// MARK: - Debug Panel View

/// In-app log viewer accessible via ⌘⇧D.
/// Shows real-time logs, AI traces, and system stats.
struct DebugPanelView: View {
    @State private var selectedCategory: String? = nil
    @State private var selectedLevel: LogLevel = .debug
    @State private var selectedTab: DebugTab = .logs

    enum DebugTab: String, CaseIterable {
        case logs = "Logs"
        case aiTraces = "AI Traces"
        case stats = "Stats"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 12) {
                ForEach(DebugTab.allCases, id: \.self) { tab in
                    Button(tab.rawValue) {
                        selectedTab = tab
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                Spacer()

                // Category filter
                Picker("", selection: $selectedCategory) {
                    Text("All").tag(nil as String?)
                    Text("AI").tag("AI" as String?)
                    Text("Memory").tag("Memory" as String?)
                    Text("DB").tag("Database" as String?)
                    Text("App").tag("App" as String?)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Button("Clear") {
                    DebugLog.shared.clear()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content
            switch selectedTab {
            case .logs:
                logListView
            case .aiTraces:
                aiTracesView
            case .stats:
                statsView
            }
        }
        .frame(minWidth: 600, minHeight: 300)
    }

    // MARK: - Logs Tab

    private var logListView: some View {
        let entries = DebugLog.shared.filtered(category: selectedCategory, level: selectedLevel)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(entries) { entry in
                    logRow(entry)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.level.symbol)
                .frame(width: 18)

            Text(timeString(entry.timestamp))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text("[\(entry.category)]")
                .foregroundStyle(.purple)
                .frame(width: 70, alignment: .leading)

            Text(entry.message)
                .foregroundStyle(entry.level == .error ? .red : .primary)

            if let err = entry.error {
                Text(err)
                    .foregroundStyle(.red.opacity(0.8))
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - AI Traces Tab

    private var aiTracesView: some View {
        let traces = AITracer.shared.fetchRecent(limit: 30)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                // Header row
                HStack(spacing: 0) {
                    Text("Time").frame(width: 70, alignment: .leading)
                    Text("Model").frame(width: 120, alignment: .leading)
                    Text("Purpose").frame(width: 80, alignment: .leading)
                    Text("In").frame(width: 50, alignment: .trailing)
                    Text("Out").frame(width: 50, alignment: .trailing)
                    Text("Cache").frame(width: 45, alignment: .center)
                    Text("Latency").frame(width: 60, alignment: .trailing)
                    Text("Tools").frame(width: 120, alignment: .leading)
                    Spacer()
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

                Divider()

                ForEach(traces) { trace in
                    traceRow(trace)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func traceRow(_ trace: AITrace) -> some View {
        HStack(spacing: 0) {
            Text(timeString(trace.timestamp))
                .frame(width: 70, alignment: .leading)
            Text(shortModel(trace.model))
                .frame(width: 120, alignment: .leading)
            Text(trace.purpose)
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(trace.purpose == "chat" ? .blue : .orange)
            Text("\(trace.inputTokens)")
                .frame(width: 50, alignment: .trailing)
            Text("\(trace.outputTokens)")
                .frame(width: 50, alignment: .trailing)
            Text(trace.cacheHit ? "✓" : "")
                .frame(width: 45, alignment: .center)
                .foregroundStyle(.green)
            Text("\(trace.latencyMs)ms")
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(trace.latencyMs > 3000 ? .red : .secondary)
            Text(trace.toolCalls.joined(separator: ", "))
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(.secondary)
            if trace.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Stats Tab

    private var statsView: some View {
        let stats = AITracer.shared.todayStats()

        return VStack(alignment: .leading, spacing: 16) {
            Text("Today's AI Usage")
                .font(.headline)

            HStack(spacing: 32) {
                statBox("API Calls", value: "\(stats.calls)")
                statBox("Input Tokens", value: "\(stats.inputTokens)")
                statBox("Output Tokens", value: "\(stats.outputTokens)")
                statBox("Cache Hits", value: "\(stats.cacheHits)")
            }

            Divider()

            HStack {
                Text("Log file: ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(FileLogger.shared.currentLogPath.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding()
    }

    private func statBox(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func shortModel(_ model: String) -> String {
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("haiku") { return "haiku" }
        if model.contains("opus") { return "opus" }
        return String(model.prefix(15))
    }
}

// MARK: - Identifiable conformance for AITrace
extension AITrace: Hashable {
    static func == (lhs: AITrace, rhs: AITrace) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
