import SwiftUI

// MARK: - WorkoutRecorderView
// Live-timer screen. Presented as a sheet; transitions from idle → recording → done.

struct WorkoutRecorderView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var live: LiveViewModel
    @Environment(\.dismiss) private var dismiss

    var onWorkoutLogged: (() async -> Void)? = nil

    @StateObject private var vm = WorkoutRecorderViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                VStack(spacing: WH.Spacing.xl) {
                    Spacer()
                    hrDisplay
                    timerDisplay
                    typePickerInline
                    Spacer()
                    actionButtons
                }
                .padding(WH.Spacing.md)
            }
            .navigationTitle("Record Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.discardWorkout()
                        dismiss()
                    }
                    .foregroundStyle(WH.Color.textSecondary)
                }
            }
            .onAppear {
                vm.currentHR = live.state.heartRate
                vm.logAction = { startTs, endTs, kind in
                    await metrics.logManualWorkout(startTs: startTs, endTs: endTs, kind: kind)
                }
            }
            .onChange(of: live.state.heartRate) { hr in
                vm.currentHR = hr
            }
        }
    }

    // MARK: - HR display

    private var hrDisplay: some View {
        VStack(spacing: 4) {
            if let hr = vm.currentHR {
                Text("\(hr)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.recoveryRed)
                    .monospacedDigit()
                Text("bpm")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            } else {
                Text("—")
                    .font(.system(size: 72, weight: .thin, design: .rounded))
                    .foregroundStyle(WH.Color.textSecondary)
                Text("no HR signal")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
    }

    // MARK: - Timer display

    private var timerDisplay: some View {
        Text(vm.isRecording ? vm.elapsedFormatted : "00:00")
            .font(.system(size: 48, weight: .semibold, design: .monospaced))
            .foregroundStyle(vm.isRecording ? WH.Color.textPrimary : WH.Color.textSecondary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.25), value: vm.elapsedSeconds)
    }

    // MARK: - Inline type picker

    private var typePickerInline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WH.Spacing.sm) {
                ForEach(WorkoutType.allCases) { type in
                    Button {
                        vm.selectedType = (vm.selectedType == type) ? nil : type
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 13, weight: .medium))
                            Text(type.displayName)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, WH.Spacing.sm + 2)
                        .padding(.vertical, 7)
                        .background(
                            vm.selectedType == type
                                ? type.color.opacity(0.25)
                                : WH.Color.surface2,
                            in: Capsule()
                        )
                        .foregroundStyle(
                            vm.selectedType == type ? type.color : WH.Color.textSecondary
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                vm.selectedType == type ? type.color.opacity(0.6) : Color.clear,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, WH.Spacing.md)
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: WH.Spacing.sm) {
            if let err = vm.errorMessage {
                Text(err)
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.recoveryRed)
                    .multilineTextAlignment(.center)
            }

            if !vm.isRecording {
                Button {
                    vm.startWorkout()
                } label: {
                    Text("Start Workout")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WH.Spacing.md)
                        .background(WH.Color.recoveryGreen,
                                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
                        .foregroundStyle(.black)
                }
            } else {
                Button {
                    Task {
                        let ok = await vm.stopWorkout()
                        if ok {
                            await onWorkoutLogged?()
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if vm.isSubmitting {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Text("Stop & Save")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WH.Spacing.md)
                    .background(WH.Color.recoveryRed,
                                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(vm.isSubmitting)
            }
        }
        .padding(.bottom, WH.Spacing.lg)
    }
}