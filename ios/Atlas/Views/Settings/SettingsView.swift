import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                connectorsSection
                dataSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .background(Theme.Palette.paper.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            MetaLabel(text: "Configuration")
            Text("Settings")
                .font(Theme.Font.titleLarge)
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    private var connectorsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Connectors", trailing: "0 of 3 connected")
            VStack(spacing: 12) {
                ConnectorCard(name: "Gmail",
                              icon: "envelope",
                              description: "Pull travel confirmations, decision threads, and meeting recaps into chapters.")
                ConnectorCard(name: "Calendar",
                              icon: "calendar",
                              description: "Surface upcoming events on Today. Auto-tag events to the right chapter.")
                ConnectorCard(name: "Drive",
                              icon: "externaldrive",
                              description: "Index docs and link them to the chapter they belong to.")
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Data")
            VStack(alignment: .leading, spacing: 8) {
                Text("Atlas stores everything locally on this device. No cloud, no auth, no telemetry.")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Text("Delete the app to reset. Seed data will recreate on next launch.")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

struct ConnectorCard: View {
    let name: String
    let icon: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                    Text(name)
                        .font(Theme.Font.serif(20))
                        .foregroundStyle(Theme.Palette.ink)
                }
                Spacer()
                Chip(text: "not connected")
            }
            Text(description)
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineSpacing(2)
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "powerplug")
                        .font(.system(size: 11))
                    Text("Connect (coming soon)")
                        .font(Theme.Font.sans(13))
                }
                .foregroundStyle(Theme.Palette.inkFaint)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Theme.Palette.paper)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous)
                        .strokeBorder(Theme.Palette.borderWarm, lineWidth: 1)
                )
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
