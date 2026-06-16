import SwiftUI

// MARK: - ManualWorkoutView
// Retroactive workout entry — pick start/end time + activity type + optional distance, POST to /v1/manual-workout.
// Presented as a sheet from WorkoutsView.

struct ManualWorkoutView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @Environment(\.dismiss) private var dismiss

    var onWorkoutLogged: (() async -> Void)? = nil

    // MARK: - State
    @State private var startDate: Date = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var selectedType: WorkoutType? = nil
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil

    // Distance roller: tens, ones, tenths, hundredths  → "xx.xx"
    @State private var distTens:      Int = 0
    @State private var distOnes:      Int = 0
    @State private var distTenths:    Int = 0
    @State private var distHundredths: Int = 0
    @State private var distanceEnabled = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                        timeSection
                        activitySection
                        distanceSection
                        if let err = errorMessage {
                            errorBanner(err)
                        }
                        submitButton
                    }
                    .padding(WH.Spacing.md)
                }
            }
            .navigationTitle("Log Workout")
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

    // MARK: - Time section

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("WORKOUT WINDOW")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .kerning(0.8)

            VStack(spacing: 1) {
                datePickerRow(label: "Start", selection: $startDate)
                Divider().background(WH.Color.separator)
                datePickerRow(label: "End", selection: $endDate)
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))

            if endDate <= startDate {
                Text("End time must be after start time")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.recoveryRed)
                    .padding(.top, 2)
            } else {
                Text(durationLabel)
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                    .padding(.top, 2)
            }
        }
    }

    private func datePickerRow(label: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .frame(width: 40, alignment: .leading)
            Spacer()
            DatePicker("", selection: selection, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.sm)
    }

    private var durationLabel: String {
        let secs = Int(endDate.timeIntervalSince(startDate))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m workout" }
        return "\(m)m workout"
    }

    // MARK: - Activity section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("ACTIVITY TYPE (OPTIONAL)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .kerning(0.8)

            VStack(spacing: 1) {
                ForEach(WorkoutType.allCases) { type in
                    activityRow(type)
                    if type != WorkoutType.allCases.last {
                        Divider().background(WH.Color.separator)
                    }
                }
            }
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        }
    }

    private func activityRow(_ type: WorkoutType) -> some View {
        Button {
            selectedType = (selectedType == type) ? nil : type
        } label: {
            HStack(spacing: WH.Spacing.md) {
                Image(systemName: type.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(type.color)
                    .frame(width: 24)
                Text(type.displayName)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Spacer()
                if selectedType == type {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(type.color)
                }
            }
            .padding(.horizontal, WH.Spacing.md)
            .padding(.vertical, WH.Spacing.sm + 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Distance section

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack {
                Text("DISTANCE (OPTIONAL)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
                    .kerning(0.8)
                Spacer()
                Toggle("", isOn: $distanceEnabled)
                    .labelsHidden()
                    .tint(WH.Color.strainBlue)
            }

            if distanceEnabled {
                VStack(spacing: WH.Spacing.sm) {
                    // Roller
                    HStack(spacing: 0) {
                        digitRoller($distTens)
                        digitRoller($distOnes)
                        Text(".")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(WH.Color.textPrimary)
                            .frame(width: 16)
                        digitRoller($distTenths)
                        digitRoller($distHundredths)
                        Text(" mi")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(WH.Color.textSecondary)
                            .padding(.leading, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WH.Spacing.md)
                    .background(WH.Color.surface,
                                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))

                    if distanceMiValue > 0 {
                        Text(String(format: "%.2f miles", distanceMiValue))
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
        }
    }

    private func digitRoller(_ binding: Binding<Int>) -> some View {
        Picker("", selection: binding) {
            ForEach(0..<10, id: \.self) { n in
                Text("\(n)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                    .tag(n)
            }
        }
        .pickerStyle(.wheel)
        .frame(width: 52, height: 100)
        .clipped()
    }

    private var distanceMiValue: Double {
        guard distanceEnabled else { return 0 }
        let v = Double(distTens) * 10 + Double(distOnes) + Double(distTenths) * 0.1 + Double(distHundredths) * 0.01
        return v
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Text("Log Workout")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WH.Spacing.md)
            .background(
                endDate > startDate
                    ? WH.Color.strainBlue
                    : WH.Color.strainBlue.opacity(0.35),
                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
            )
            .foregroundStyle(.white)
        }
        .disabled(endDate <= startDate || isSubmitting)
        .padding(.top, WH.Spacing.sm)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WH.Color.recoveryRed)
            Text(message)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface2,
                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    // MARK: - Network

    private func submit() async {
        guard endDate > startDate else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let dist: Double? = distanceEnabled && distanceMiValue > 0 ? distanceMiValue : nil
        let ok = await metrics.logManualWorkout(
            startTs: startDate.timeIntervalSince1970,
            endTs: endDate.timeIntervalSince1970,
            kind: selectedType?.rawValue,
            distanceMi: dist
        )
        if ok {
            await onWorkoutLogged?()
            dismiss()
        } else {
            errorMessage = "Couldn't log workout — check that the server has HR data for this window."
        }
    }
}

#Preview {
    ManualWorkoutView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
}