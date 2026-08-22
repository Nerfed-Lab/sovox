import WidgetKit
import SwiftUI

@main
struct SovoxWidgetBundle: WidgetBundle {
    var body: some Widget {
        SovoxLiveActivityWidget()
        SovoxControl()
    }
}
