import SwiftUI

/// Modal sheet for selecting a workout type tag.
/// Presented from WorkoutDetailView when the user taps "Tag workout".
struct WorkoutTagPicker: View {
    @Binding var selected: WorkoutType?
    let onSelect: (WorkoutType?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(WorkoutType.allCases) { type in
                            typeRow(type)
                        }
                        // Clear tag option
                        if selected != nil {
                            clearRow
                        }
                    }
                    .background(WH.Color.surface,
                                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
                    .padding(WH.Spacing.md)
                }
            }
            .navigationTitle("Tag Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
        }
    }

    private func typeRow(_ type: WorkoutType) -> some View {
        Button {
            selected = type
            onSelect(type)
            dismiss()
        } label: {
            HStack(spacing: WH.Spacing.md) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(type.color)
                    .frame(width: 28)
                Text(type.displayName)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Spacer()
                if selected == type {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(type.color)
                }
            }
            .padding(.horizontal, WH.Spacing.md)
            .padding(.vertical, WH.Spacing.sm + 2)
        }
        .buttonStyle(.plain)
    }

    private var clearRow: some View {
        Button {
            selected = nil
            onSelect(nil)
            dismiss()
        } label: {
            HStack(spacing: WH.Spacing.md) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
                    .frame(width: 28)
                Text("Remove tag")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, WH.Spacing.md)
            .padding(.vertical, WH.Spacing.sm + 2)
        }
        .buttonStyle(.plain)
    }
}