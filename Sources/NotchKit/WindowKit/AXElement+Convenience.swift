import ApplicationServices
import AppKit

/// AX 属性读写的薄封装，避免到处都是 `AXUIElementCopyAttributeValue` 样板代码。
extension AXUIElement {

    func copyValue(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    func string(_ attribute: String) -> String? {
        copyValue(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool? {
        (copyValue(attribute) as? NSNumber)?.boolValue
    }

    func elements(_ attribute: String) -> [AXUIElement]? {
        copyValue(attribute) as? [AXUIElement]
    }

    /// 读取子元素类型的属性（如 `kAXFocusedWindowAttribute`）。
    ///
    /// 这里必须先用 `CFGetTypeID` 判断再 `unsafeDowncast`：
    /// 直接写 `as? AXUIElement` 会被编译器判定为「条件转换永远成功」而报错
    /// （CFTypeRef 到 CF 类型之间是桥接关系，不是真正的运行时转换）。
    func element(_ attribute: String) -> AXUIElement? {
        guard let value = copyValue(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    func point(_ attribute: String) -> CGPoint? {
        guard let value = copyValue(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    func size(_ attribute: String) -> CGSize? {
        guard let value = copyValue(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    /// 窗口在全局坐标中的矩形（原点左上，与 CGWindowList 一致）
    var frame: CGRect? {
        guard let origin = point(kAXPositionAttribute as String),
              let size = size(kAXSizeAttribute as String) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    func setValue(_ value: CFTypeRef, for attribute: String) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }
}
