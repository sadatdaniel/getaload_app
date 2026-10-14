// Shared desktop-style UI: context menus (macOS/GNOME/Windows-like), GNOME-style settings groups, dialogs.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One row of a context menu. [checked] draws a check mark (for choices such as download mode).
class MenuAction {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger, checked, divider;
  const MenuAction(this.label, {this.icon, this.onTap, this.danger = false, this.checked = false}) : divider = false;
  const MenuAction.divider() : label = '', icon = null, onTap = null, danger = false, checked = false, divider = true;
}

/// Opens a compact desktop-style context menu at [at] (global position): right click, long press or a ⋮ button.
Future<void> showContextMenu(BuildContext context, Offset at, List<MenuAction> items, {String? title}) async {
  final cs = Theme.of(context).colorScheme;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final pos = RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size);
  final chosen = await showMenu<int>(
    context: context,
    position: pos,
    color: cs.surface,
    elevation: 8,
    shadowColor: Colors.black26,
    menuPadding: const EdgeInsets.symmetric(vertical: 4),
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: cs.outlineVariant),
    ),
    items: [
      if (title != null)
        PopupMenuItem<int>(
          enabled: false,
          height: 30,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
          ),
        ),
      for (final (i, a) in items.indexed)
        if (a.divider)
          const PopupMenuDivider(height: 9)
        else
          PopupMenuItem<int>(
            value: i,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: a.checked
                      ? Icon(Icons.check, size: 16, color: cs.primary)
                      : (a.icon != null
                            ? Icon(a.icon, size: 16, color: a.danger ? cs.error : cs.onSurfaceVariant)
                            : null),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(a.label, style: TextStyle(fontSize: 13.5, color: a.danger ? cs.error : cs.onSurface)),
                ),
              ],
            ),
          ),
    ],
  );
  if (chosen != null) items[chosen].onTap?.call();
}

/// Where a ⋮ button sits, so its menu opens next to it.
Offset anchorOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(box.size.bottomLeft(Offset.zero));
}

/// Wraps an entry so right click (desktop, web) and long press (touch) open its context menu where it happened.
class ContextMenuArea extends StatelessWidget {
  final Widget child;
  final void Function(Offset at) onMenu;
  const ContextMenuArea({super.key, required this.child, required this.onMenu});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapDown: (d) => onMenu(d.globalPosition),
    onLongPressStart: (d) => onMenu(d.globalPosition),
    child: child,
  );
}

/// A GNOME (libadwaita) style group: a small bold title above a rounded panel of rows separated by hairlines.
class SettingsGroup extends StatelessWidget {
  final String? title, description;
  final List<Widget> children;
  const SettingsGroup({super.key, this.title, this.description, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = children.where((w) => w is! SizedBox || w.height != 0).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text(title!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(description!, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  for (final (i, r) in rows.indexed) ...[
                    if (i > 0) Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                    r,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row: title (and subtitle) on the left, the control on the right; or the control below when wide.
class SettingsRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing, below;
  final VoidCallback? onTap;
  final bool danger;
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Small controls (switches, icons, short text) always sit on the right. Wide ones (choices, sliders,
    // buttons) move under the label on narrow screens instead of squeezing the text into a sliver.
    // Compact controls (a switch, an icon, a text button, a menu) always sit on the right.
    final small =
        trailing is Switch ||
        trailing is IconButton ||
        trailing is Text ||
        trailing is TextButton ||
        trailing is PopupMenuButton;
    return LayoutBuilder(
      builder: (context, box) {
        final stack = trailing != null && !small && box.maxWidth < 560;
        final label = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 14.5, color: danger ? cs.error : cs.onSurface)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
          ],
        );
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: label),
                    if (trailing != null && !stack) ...[
                      const SizedBox(width: 12),
                      // A long value (an address, a peer count) wraps instead of pushing the label off screen.
                      Flexible(
                        child: Align(alignment: Alignment.centerRight, child: trailing!),
                      ),
                    ],
                    if (onTap != null && trailing == null) Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
                if (stack)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(alignment: Alignment.centerLeft, child: trailing!),
                  ),
                if (below != null) Padding(padding: const EdgeInsets.only(top: 8), child: below!),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A row of mutually exclusive choices that looks like a GNOME/macOS segmented control.
class Choice<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const Choice({super.key, required this.options, required this.value, required this.onChanged});

  // Joined buttons when the labels fit on one line; otherwise chips that wrap, so words never break mid-word
  // (narrow phones, large system font).
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final style = Theme.of(context).textTheme.labelLarge; // what SegmentedButton labels use
      final scaler = MediaQuery.textScalerOf(context);
      final need = options.fold<double>(0, (sum, o) {
        final tp = TextPainter(
          text: TextSpan(text: o.$2, style: style),
          textScaler: scaler,
          textDirection: TextDirection.ltr,
        )..layout();
        return sum + tp.width + 40; // the segment's padding and border
      });
      if (need <= box.maxWidth) {
        return SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final (v, l) in options) ButtonSegment(value: v, label: Text(l, maxLines: 1, softWrap: false)),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (v, l) in options)
            ChoiceChip(label: Text(l), selected: v == value, showCheckmark: false, onSelected: (_) => onChanged(v)),
        ],
      );
    },
  );
}

/// A centered confirmation dialog (instead of a bottom sheet). Returns true when the action is chosen.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  Widget? body,
  required String action,
  bool danger = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: body == null ? null : ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

/// A text field with its button: side by side on wide screens, the button under the field on narrow ones
/// (phones with large text squeeze the field otherwise).
class FieldWithButton extends StatelessWidget {
  final Widget field, button;
  const FieldWithButton({super.key, required this.field, required this.button});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth < 480
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [field, const SizedBox(height: 8), button])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: field),
              const SizedBox(width: 8),
              button,
            ],
          ),
  );
}

/// Android or iOS: phone-only features (screen rotation, downloads to the phone) are hidden on the web and on desktops.
final isPhone =
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
