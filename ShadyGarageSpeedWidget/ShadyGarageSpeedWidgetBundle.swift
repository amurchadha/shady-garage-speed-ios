// ShadyGarageSpeedWidgetBundle.swift — widget extension entry point:
// #55 Daily Lugnut home-screen widget + #57 race Live Activity.
import WidgetKit
import SwiftUI

@main
struct ShadyGarageSpeedWidgetBundle: WidgetBundle {
    var body: some Widget {
        LugnutWidget()
        RaceLiveActivity()
    }
}
