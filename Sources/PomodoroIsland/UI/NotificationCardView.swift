import SwiftUI

/// 通知卡片：被动横幅 / 按钮 / 选项问答（可附输入框）/ 文本输入
/// 作为通知岛的内容区渲染，本身不带背景与边框
struct NotificationCardView: View {

    let notification: IslandNotification
    let store: NotificationStore

    @State private var multiSelected: Set<String> = []
    @State private var inputText = ""

    private var kind: NotificationKind { notification.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(notification.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            if !notification.message.isEmpty {
                Text(notification.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            controls

            if notification.deadline != nil {
                Text("等待响应中 · \(Int(notification.timeoutSeconds ?? 0))s 后超时")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 头部（来源徽标 + 类型 + 忽略）

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sourceColor)
                .frame(width: 7, height: 7)
            Text(notification.source)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Text(kind.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(kind.color))

            Spacer()

            Button {
                store.respond(notification.id, NotificationResponse(status: "dismissed"))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("忽略")
        }
    }

    /// 来源名哈希 → 稳定配色
    private var sourceColor: Color {
        let name = notification.source
        var hash = 0
        for b in name.utf8 { hash = (hash &* 31 + Int(b)) & 0xFF }
        return Color(hue: Double(hash) / 255.0, saturation: 0.65, brightness: 0.85)
    }

    // MARK: - 交互控件

    @ViewBuilder
    private var controls: some View {
        switch kind {
        case .buttons:
            VStack(spacing: 8) {
                ForEach(notification.buttons) { btn in
                    Button {
                        store.respond(notification.id, NotificationResponse(status: "answered", clicked: btn.label))
                    } label: {
                        Text(btn.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

        case .choice:
            VStack(spacing: 6) {
                // 选项在前
                ForEach(notification.options) { opt in
                    optionRow(opt)
                }

                // 自定义输入紧随其后（与提交按钮同行，垂直对齐）
                if notification.allowCustomInput == true {
                    HStack(spacing: 8) {
                        TextField("自定义回答…", text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .onSubmit(submitInput)

                        submitArrow
                    }
                }

                // 多选时需要提交确认
                if notification.multiSelect {
                    ActionButton(title: multiSelected.isEmpty ? "请选择" : "提交（\(multiSelected.count)）",
                                 accent: kind.color, filled: !multiSelected.isEmpty) {
                        let labels = notification.options
                            .filter { multiSelected.contains($0.id) }
                            .map { $0.label }
                        store.respond(notification.id, NotificationResponse(status: "answered", selected: labels))
                    }
                    .disabled(multiSelected.isEmpty)
                    .opacity(multiSelected.isEmpty ? 0.5 : 1)
                }
            }

        case .input:
            HStack(spacing: 8) {
                TextField(notification.inputPlaceholder, text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .onSubmit(submitInput)

                submitArrow
            }

        default:
            EmptyView()
        }
    }

    /// 单个选项行：单选点击即答，多选切换勾选
    private func optionRow(_ opt: NotificationOption) -> some View {
        Button {
            if notification.multiSelect {
                if multiSelected.contains(opt.id) {
                    multiSelected.remove(opt.id)
                } else {
                    multiSelected.insert(opt.id)
                }
            } else {
                store.respond(notification.id, NotificationResponse(
                    status: "answered", selected: [opt.label]))
            }
        } label: {
            HStack(spacing: 8) {
                if notification.multiSelect {
                    Image(systemName: multiSelected.contains(opt.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(multiSelected.contains(opt.id) ? kind.color : Theme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(opt.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if !opt.detail.isEmpty {
                        Text(opt.detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(multiSelected.contains(opt.id) ? 0.12 : 0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 提交箭头按钮（与输入框同行，垂直对齐）
    private var submitArrow: some View {
        Button(action: submitInput) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(kind.color)
        }
        .buttonStyle(.plain)
        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
    }

    private func submitInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.respond(notification.id, NotificationResponse(status: "answered", text: text))
    }
}
