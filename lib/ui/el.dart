/// Widgets that mirror the Element UI components used by erp.webapp
/// (el-result, el-descriptions, el-tag, el-alert, ScannerInput, el-progress)
/// so the PDA screens look like the web pages operators already know.
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class El {
  static const primary = Color(0xFF409EFF);
  static const success = Color(0xFF67C23A);
  static const warning = Color(0xFFE6A23C);
  static const danger = Color(0xFFF56C6C);
  static const info = Color(0xFF909399);
  static const textPrimary = Color(0xFF303133);
  static const textRegular = Color(0xFF606266);
  static const textSecondary = Color(0xFF909399);
  static const border = Color(0xFFDCDFE6);
  static const borderLight = Color(0xFFEBEEF5);
  static const bg = Color(0xFFF0F2F5);
  static const labelBg = Color(0xFFFAFAFA);
  static const sidebar = Color(0xFF304156);
  static const sidebarSub = Color(0xFF1F2D3D);
  static const sidebarActive = Color(0xFF409EFF);
}

enum ElType { primary, success, warning, danger, info }

Color elColor(ElType t) => switch (t) {
      ElType.primary => El.primary,
      ElType.success => El.success,
      ElType.warning => El.warning,
      ElType.danger => El.danger,
      ElType.info => El.info,
    };

/// el-result: big icon, title, sub-title, optional extra (buttons).
class ElResult extends StatelessWidget {
  const ElResult({super.key, required this.type, required this.title, this.subTitle, this.extra, this.icon});

  final ElType type;
  final String title;
  final String? subTitle;
  final Widget? extra;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = type == ElType.primary ? El.info : elColor(type);
    final ic = icon ??
        switch (type) {
          ElType.success => Icons.check_circle,
          ElType.warning => Icons.warning_rounded,
          ElType.danger => Icons.cancel,
          _ => Icons.info,
        };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Column(children: [
        Icon(ic, size: 46, color: c),
        const SizedBox(height: 8),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: El.textPrimary, fontWeight: FontWeight.w600)),
        if (subTitle != null && subTitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subTitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: El.textRegular)),
        ],
        if (extra != null) ...[const SizedBox(height: 10), extra!],
      ]),
    );
  }
}

/// el-alert (light): coloured box with optional icon and description.
class ElAlert extends StatelessWidget {
  const ElAlert({super.key, required this.type, required this.title, this.description, this.margin, this.trailing});

  final ElType type;
  final String title;
  final String? description;
  final EdgeInsets? margin;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = elColor(type);
    final ic = switch (type) {
      ElType.success => Icons.check_circle,
      ElType.warning => Icons.warning_rounded,
      ElType.danger => Icons.cancel,
      _ => Icons.info,
    };
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Color.alphaBlend(c.withValues(alpha: 0.12), Colors.white), borderRadius: BorderRadius.circular(4)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(ic, size: 17, color: c)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: c, fontSize: 14, fontWeight: description == null ? FontWeight.normal : FontWeight.w600)),
            if (description != null && description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(description!, style: TextStyle(color: c, fontSize: 12.5)),
              ),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// el-tag
class ElTag extends StatelessWidget {
  const ElTag(this.text, {super.key, this.type = ElType.primary, this.dark = false, this.small = true});

  final String text;
  final ElType type;
  final bool dark;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = elColor(type);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 9, vertical: small ? 1.5 : 3),
      decoration: BoxDecoration(
        color: dark ? c : Color.alphaBlend(c.withValues(alpha: 0.1), Colors.white),
        border: Border.all(color: dark ? c : Color.alphaBlend(c.withValues(alpha: 0.35), Colors.white)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: dark ? Colors.white : c, fontSize: small ? 12 : 13.5)),
    );
  }
}

/// el-descriptions (vertical, border, 1 column): grey label cell above the value.
class ElDescriptions extends StatelessWidget {
  const ElDescriptions({super.key, this.title, required this.items, this.margin});

  final String? title;
  final List<(String, Object?)> items;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final visible = items.where((i) {
      final v = i.$2;
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      return true;
    }).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: margin ?? const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: El.textPrimary)),
          ),
        Container(
          decoration: BoxDecoration(border: Border.all(color: El.borderLight), color: Colors.white),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: El.borderLight),
              Container(
                color: El.labelBg,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(visible[i].$1, style: const TextStyle(fontSize: 12.5, color: El.textSecondary, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: visible[i].$2 is Widget
                    ? visible[i].$2 as Widget
                    : SelectableText('${visible[i].$2}', style: const TextStyle(fontSize: 14, color: El.textRegular)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Section header like the web's <h3>.
class ElSection extends StatelessWidget {
  const ElSection(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 6, 4),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: El.textPrimary))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// White card with border, like el-card shadow="never".
class ElCard extends StatelessWidget {
  const ElCard({super.key, required this.child, this.margin, this.padding, this.highlight, this.onTap});

  final Widget child;
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final Color? highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: margin ?? const EdgeInsets.fromLTRB(8, 6, 8, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: highlight ?? El.borderLight, width: highlight == null ? 1 : 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(padding: padding ?? const EdgeInsets.all(10), child: child),
    );
    if (onTap == null) return box;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: box);
  }
}

/// el-progress (no text)
class ElProgress extends StatelessWidget {
  const ElProgress({super.key, required this.value, this.complete = false});

  final double value;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 6,
        backgroundColor: El.borderLight,
        valueColor: AlwaysStoppedAnimation(complete ? El.success : El.primary),
      ),
    );
  }
}

/// Mirrors components/Widget/ScannerInput: an input-looking bar showing the
/// placeholder (what to scan), double-scan progress and the last scanned value.
class ScannerBar extends StatelessWidget {
  const ScannerBar({
    super.key,
    required this.placeholder,
    required this.onManual,
    this.busy = false,
    this.disabled = false,
    this.progress,
    this.lastScanned,
    this.error,
  });

  final String placeholder;
  final VoidCallback onManual;
  final bool busy;
  final bool disabled;

  /// e.g. "Scanning Progress: 1 / 2"
  final String? progress;

  /// e.g. "Just scanned: X"
  final String? lastScanned;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: disabled ? null : onManual,
          child: Container(
            height: 44,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: disabled ? const Color(0xFFF5F7FA) : Colors.white,
              border: Border.all(color: error != null ? El.danger : (busy ? El.primary : El.border), width: error != null || busy ? 1.5 : 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const FaIcon(FontAwesomeIcons.barcode, size: 17, color: El.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: disabled ? El.textSecondary : const Color(0xFFA8ABB2))),
              ),
              const Icon(Icons.keyboard, color: El.textSecondary, size: 22),
              const SizedBox(width: 6),
            ]),
          ),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(error!, style: const TextStyle(color: El.danger, fontSize: 12.5))),
        if (progress != null) ElAlert(type: ElType.warning, title: progress!, margin: const EdgeInsets.only(top: 6)),
        if (lastScanned != null) ElAlert(type: ElType.success, title: lastScanned!, margin: const EdgeInsets.only(top: 6)),
      ]),
    );
  }
}

/// A full-width button row at the bottom of a page.
class ElBottomBar extends StatelessWidget {
  const ElBottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: El.borderLight))),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i]),
          ],
        ]),
      ),
    );
  }
}

ButtonStyle elButton(ElType type, {bool plain = false}) {
  final c = elColor(type);
  return FilledButton.styleFrom(
    backgroundColor: plain ? Color.alphaBlend(c.withValues(alpha: 0.1), Colors.white) : c,
    foregroundColor: plain ? c : Colors.white,
    side: plain ? BorderSide(color: Color.alphaBlend(c.withValues(alpha: 0.5), Colors.white)) : null,
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    textStyle: const TextStyle(fontSize: 14.5),
  );
}
