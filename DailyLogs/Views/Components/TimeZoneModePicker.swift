import SwiftUI

struct TimeZoneModePicker: View {
    @Binding var mode: TimeDisplayMode

    var body: some View {
        Picker("", selection: $mode) {
            ForEach(TimeDisplayMode.allCases) { option in
                Text(option.shortTitle).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}
