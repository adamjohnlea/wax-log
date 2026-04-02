import SwiftUI

struct NotesTab: View {
    @ObservedObject var release: Release
    @Environment(\.managedObjectContext) private var viewContext
    @State private var editedNotes: String = ""
    @State private var editedRating: Int16 = 0
    @State private var editedMediaCondition: String = ""
    @State private var editedSleeveCondition: String = ""
    @State private var hasChanges = false
    @State private var isPushing = false
    @State private var pushResult: PushResult?

    private let conditions = [
        "", "Mint (M)", "Near Mint (NM or M-)", "Very Good Plus (VG+)",
        "Very Good (VG)", "Good Plus (G+)", "Good (G)", "Fair (F)", "Poor (P)"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Rating
            GroupBox("Rating") {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            editedRating = editedRating == star ? 0 : Int16(star)
                            hasChanges = true
                        } label: {
                            Image(systemName: star <= editedRating ? "star.fill" : "star")
                                .foregroundStyle(star <= editedRating ? .yellow : .secondary)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                        .accessibilityAddTraits(star <= editedRating ? .isSelected : [])
                    }

                    if editedRating > 0 {
                        Button("Clear") {
                            editedRating = 0
                            hasChanges = true
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Condition
            GroupBox("Condition") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Media") {
                        Picker("Media Condition", selection: $editedMediaCondition) {
                            Text("Not Graded").tag("")
                            ForEach(conditions.filter { !$0.isEmpty }, id: \.self) { condition in
                                Text(condition).tag(condition)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: editedMediaCondition) { hasChanges = true }
                    }

                    LabeledContent("Sleeve") {
                        Picker("Sleeve Condition", selection: $editedSleeveCondition) {
                            Text("Not Graded").tag("")
                            ForEach(conditions.filter { !$0.isEmpty }, id: \.self) { condition in
                                Text(condition).tag(condition)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: editedSleeveCondition) { hasChanges = true }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Personal Notes
            GroupBox("Personal Notes") {
                TextEditor(text: $editedNotes)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .onChange(of: editedNotes) { hasChanges = true }
            }

            // Action buttons
            HStack {
                // Push result feedback
                if let result = pushResult {
                    Label(result.message, systemImage: result.isSuccess ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(result.isSuccess ? .green : .red)
                }

                Spacer()

                if hasChanges {
                    Button("Revert") {
                        loadFromRelease()
                        hasChanges = false
                    }

                    Button("Save Changes") {
                        saveChanges()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if release.isCollection {
                    Button {
                        pushToDiscogs()
                    } label: {
                        if isPushing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Push to Discogs", systemImage: "arrow.up.circle")
                        }
                    }
                    .disabled(isPushing || hasChanges)
                    .help(hasChanges ? "Save changes first before pushing to Discogs" : "Push rating, condition, and notes to Discogs")
                }
            }
        }
        .onAppear {
            loadFromRelease()
        }
    }

    private func loadFromRelease() {
        editedNotes = release.personalNotes ?? ""
        editedRating = release.rating
        editedMediaCondition = release.mediaCondition ?? ""
        editedSleeveCondition = release.sleeveCondition ?? ""
    }

    private func saveChanges() {
        release.personalNotes = editedNotes.isEmpty ? nil : editedNotes
        release.rating = editedRating
        release.mediaCondition = editedMediaCondition.isEmpty ? nil : editedMediaCondition
        release.sleeveCondition = editedSleeveCondition.isEmpty ? nil : editedSleeveCondition

        try? viewContext.save()
        hasChanges = false
    }

    private func pushToDiscogs() {
        isPushing = true
        pushResult = nil
        let objectID = release.objectID

        Task {
            do {
                let syncService = SyncService()
                try await syncService.pushReleaseToDiscogs(objectID)
                pushResult = PushResult(isSuccess: true, message: "Pushed to Discogs")
            } catch {
                pushResult = PushResult(isSuccess: false, message: error.localizedDescription)
            }
            isPushing = false
        }
    }

    private struct PushResult {
        let isSuccess: Bool
        let message: String
    }
}
