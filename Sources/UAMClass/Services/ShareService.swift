import AppKit

/// Wrapper de NSSharingServicePicker para compartir con Mail, Messages, AirDrop, etc.
enum ShareService {
    /// Muestra el picker anclado a la vista provista.
    static func share(_ items: [Any], from view: NSView) {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    /// Alternativa: presenta el picker anclado al mouse cursor.
    static func shareAtCursor(_ items: [Any]) {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        share(items, from: view)
    }
}
