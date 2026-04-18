//
//  PostScanFeedbackView.swift
//  InsightApp
//
//  FIX 1: import CoreLocation agregado (resuelve "missing import of defining module '_Loc...'")
//  FIX 2: preview usa variable intermedia para CLLocationCoordinate2D
//

import SwiftUI
import CoreLocation

struct PostScanFeedbackView: View {
    let tile: AccessibilityTile
    let onSubmit: (UserValidation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedExperience: UserValidation.PassExperience? = nil
    @State private var selectedTags: Set<UserValidation.ManualFeedbackTag> = []
    @State private var freeText: String = ""
    @State private var showTags = false

    let teal = Color(red: 136/255, green: 205/255, blue: 212/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    VStack(alignment: .leading, spacing: 12) {
                        Text("¿Pudiste pasar sin problema?")
                            .font(.system(size: 18, weight: .bold, design: .rounded))

                        HStack(spacing: 12) {
                            ForEach(UserValidation.PassExperience.allCases, id: \.self) { exp in
                                ExperienceButton(
                                    experience: exp,
                                    isSelected: selectedExperience == exp,
                                    teal: teal
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedExperience = exp
                                        showTags = true
                                    }
                                }
                            }
                        }
                    }

                    if showTags {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("¿Qué encontraste? (opcional)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(UserValidation.ManualFeedbackTag.allCases, id: \.self) { tag in
                                    TagButton(tag: tag, isSelected: selectedTags.contains(tag), teal: teal) {
                                        withAnimation {
                                            if selectedTags.contains(tag) { selectedTags.remove(tag) }
                                            else { selectedTags.insert(tag) }
                                        }
                                    }
                                }
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if showTags {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comentario adicional (opcional)")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                            TextField("¿Algo más que debamos saber?", text: $freeText, axis: .vertical)
                                .font(.system(size: 15, design: .rounded))
                                .lineLimit(3, reservesSpace: true)
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .transition(.opacity)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationTitle("Tu experiencia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ahora no") { dismiss() }.foregroundColor(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enviar") { submit() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selectedExperience == nil ? .secondary : teal)
                        .disabled(selectedExperience == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func submit() {
        guard let exp = selectedExperience else { return }
        let validation = UserValidation(
            tileID:         tile.id,
            coordinate:     CodableCoordinate(tile.coordinate),
            passExperience: exp,
            manualTags:     Array(selectedTags),
            freeText:       freeText.isEmpty ? nil : freeText,
            createdAt:      Date(),
            profile:        ProfileService.shared.currentProfile.rawValue
        )
        onSubmit(validation)
        dismiss()
    }
}

// MARK: - ExperienceButton

private struct ExperienceButton: View {
    let experience: UserValidation.PassExperience
    let isSelected: Bool
    let teal: Color
    let action: () -> Void

    var expColor: Color {
        switch experience {
        case .fine:        return .green
        case .withTrouble: return .orange
        case .blocked:     return .red
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: experience.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? .white : expColor)
                Text(experience.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? expColor : expColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? expColor : expColor.opacity(0.3), lineWidth: 1.5))
        }
    }
}

// MARK: - TagButton

private struct TagButton: View {
    let tag: UserValidation.ManualFeedbackTag
    let isSelected: Bool
    let teal: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tag.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : teal)
                Text(tag.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(isSelected ? teal : teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? teal : teal.opacity(0.2), lineWidth: 1))
        }
    }
}

// MARK: - Preview

#Preview {
    // FIX: variable intermedia evita el error "missing import of defining module '_Loc...'"
    // que ocurre cuando se usa .init(latitude:longitude:) inline en un argumento de struct
    var coord = CLLocationCoordinate2D()
    coord.latitude  = 25.67
    coord.longitude = -100.31

    return PostScanFeedbackView(
        tile: AccessibilityTile(
            coordinate:         coord,
            accessibilityScore: 72,
            confidenceScore:    0.80,
            reasons:            ["Rampa detectada"],
            sourceType:         .camera,
            detectedLabel:      "ramp"
        )
    ) { _ in }
}
