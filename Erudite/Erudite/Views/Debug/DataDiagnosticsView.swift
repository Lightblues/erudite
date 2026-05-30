import SwiftUI

// MARK: - Data Diagnostics View
//
// Read-only diff between bundled words.json and what's in the live DB.
// Surfaced inside DebugPanelView (⌘⇧D → Data tab).
//
// Used to answer "what does v3.0 ai-enrichment actually upgrade?":
// - Per-field coverage delta (how many words gain a chinese def, mnemonic, etc.)
// - Word-set delta (cached words in DB that aren't in the bundle)
// - Version state (DB version vs bundle version)
//
// Pure analysis — no writes. The actual upgrade flow lives in
// WordLoader.seedDatabaseIfNeeded() and runs at app start when the version
// changes.

struct DataDiagnosticsView: View {
    @State private var report: DiagnosticsReport?
    @State private var isRunning: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Words Data Diagnostics")
                    .font(.headline)
                Spacer()
                Button("Run") { Task { await run() } }
                    .disabled(isRunning)
                if isRunning {
                    ProgressView().controlSize(.small)
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        versionSection(report)
                        Divider()
                        countsSection(report)
                        Divider()
                        coverageSection(report)
                        if !report.bundleOnlyIds.isEmpty || !report.dbOnlyIds.isEmpty {
                            Divider()
                            setDeltaSection(report)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else if !isRunning {
                Text("Click Run to compare bundled words.json against the live database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Sections

    private func versionSection(_ r: DiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Version").font(.subheadline.weight(.semibold))
            HStack(spacing: 24) {
                kv("Bundle", r.bundleVersion)
                kv("DB", r.dbVersion ?? "<not tracked>")
                if r.bundleVersion != (r.dbVersion ?? "") {
                    Text("UPGRADE PENDING")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                }
            }
            Text("Generated: \(r.bundleGeneratedAt)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func countsSection(_ r: DiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Word Counts").font(.subheadline.weight(.semibold))
            HStack(spacing: 24) {
                kv("Bundle", "\(r.bundleCount)")
                kv("DB", "\(r.dbCount)")
                kv("Shared", "\(r.sharedCount)")
                kv("Bundle-only", "\(r.bundleOnlyIds.count)")
                kv("DB-only", "\(r.dbOnlyIds.count)")
            }
        }
    }

    private func coverageSection(_ r: DiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Field Upgrades")
                .font(.subheadline.weight(.semibold))
            Text("Words in DB that would gain a field after upgrade. (\"DB has 0\" = bundle has the field but DB row is empty.)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Header
            HStack {
                Text("Field").frame(width: 140, alignment: .leading)
                Text("DB has").frame(width: 80, alignment: .trailing)
                Text("Bundle has").frame(width: 90, alignment: .trailing)
                Text("Δ Upgraded").frame(width: 100, alignment: .trailing)
                    .foregroundStyle(.green)
                Spacer()
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(r.fieldDeltas, id: \.name) { d in
                HStack {
                    Text(d.name).frame(width: 140, alignment: .leading)
                    Text("\(d.dbHas)").frame(width: 80, alignment: .trailing).monospacedDigit()
                    Text("\(d.bundleHas)").frame(width: 90, alignment: .trailing).monospacedDigit()
                    Text(d.upgrades > 0 ? "+\(d.upgrades)" : "0")
                        .frame(width: 100, alignment: .trailing)
                        .monospacedDigit()
                        .foregroundStyle(d.upgrades > 0 ? .green : .secondary)
                    Spacer()
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private func setDeltaSection(_ r: DiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Word Set Delta").font(.subheadline.weight(.semibold))
            if !r.dbOnlyIds.isEmpty {
                Text("In DB but not in bundle (\(r.dbOnlyIds.count)): probably cached lookups from API.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(r.dbOnlyIds.prefix(20).joined(separator: ", "))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
            if !r.bundleOnlyIds.isEmpty {
                Text("In bundle but not in DB (\(r.bundleOnlyIds.count)): will be inserted on upgrade.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(r.bundleOnlyIds.prefix(20).joined(separator: ", "))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
        }
    }

    private func kv(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .monospaced))
        }
    }

    // MARK: - Run

    private func run() async {
        isRunning = true
        error = nil
        defer { isRunning = false }

        guard let db = AppState.shared?.databaseService else {
            error = "Database not initialized."
            return
        }

        do {
            // Off-main: JSON parse + 13K-row scan can take a beat.
            let r = try await Task.detached(priority: .userInitiated) {
                try buildReport(db: db)
            }.value
            self.report = r
        } catch {
            self.error = "\(error)"
        }
    }
}

// MARK: - Report builder
//
// Lives outside the view so it's testable + safe to call off the main actor.

nonisolated struct DiagnosticsReport: Sendable {
    let bundleVersion: String
    let bundleGeneratedAt: String
    let dbVersion: String?
    let bundleCount: Int
    let dbCount: Int
    let sharedCount: Int
    let bundleOnlyIds: [String]
    let dbOnlyIds: [String]
    let fieldDeltas: [FieldDelta]
}

nonisolated struct FieldDelta: Sendable {
    let name: String
    let dbHas: Int
    let bundleHas: Int
    let upgrades: Int   // words in DB where bundle has the field but DB doesn't
}

private nonisolated func buildReport(db: DatabaseService) throws -> DiagnosticsReport {
    let bundle = try WordLoader.loadBundledDatabase()
    let dbWords = try db.fetchAllWords()
    let dbVersion = try? db.metaValue(forKey: "wordsVersion")

    let bundleById = Dictionary(uniqueKeysWithValues: bundle.words.map { ($0.id, $0) })
    let dbById = Dictionary(uniqueKeysWithValues: dbWords.map { ($0.id, $0) })

    let bundleIds = Set(bundleById.keys)
    let dbIds = Set(dbById.keys)
    let sharedIds = bundleIds.intersection(dbIds)

    // Per-field coverage: count words that have a meaningful value for the field.
    let checks: [(String, (Word) -> Bool)] = [
        ("phonetic",          { $0.phonetic?.isEmpty == false }),
        ("definitions",       { !$0.definitions.isEmpty }),
        ("definition.zh",     { $0.definitions.contains { !$0.chinese.isEmpty } }),
        ("definition.en",     { $0.definitions.contains { !$0.english.isEmpty } }),
        ("synonymGroups",     { !$0.synonymGroups.isEmpty }),
        ("antonyms",          { !$0.antonyms.isEmpty }),
        ("examples",          { !$0.examples.isEmpty }),
        ("mnemonics",         { !$0.mnemonics.isEmpty }),
        ("tags",              { !$0.tags.isEmpty }),
        ("roots",             { $0.roots != nil }),
    ]

    let deltas: [FieldDelta] = checks.map { (name, has) in
        let dbHas = dbWords.lazy.filter(has).count
        let bundleHas = bundle.words.lazy.filter(has).count
        // "Upgrades": for the shared set, count rows where bundle has but DB doesn't.
        let upgrades = sharedIds.reduce(into: 0) { acc, id in
            guard let b = bundleById[id], let d = dbById[id] else { return }
            if has(b) && !has(d) { acc += 1 }
        }
        return FieldDelta(name: name, dbHas: dbHas, bundleHas: bundleHas, upgrades: upgrades)
    }

    return DiagnosticsReport(
        bundleVersion: bundle.version,
        bundleGeneratedAt: bundle.generatedAt,
        dbVersion: dbVersion?.isEmpty == false ? dbVersion : nil,
        bundleCount: bundle.words.count,
        dbCount: dbWords.count,
        sharedCount: sharedIds.count,
        bundleOnlyIds: Array(bundleIds.subtracting(dbIds)).sorted(),
        dbOnlyIds: Array(dbIds.subtracting(bundleIds)).sorted(),
        fieldDeltas: deltas
    )
}
