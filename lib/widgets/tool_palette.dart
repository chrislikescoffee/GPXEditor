import 'package:flutter/material.dart';
import '../enums/editor_mode.dart';

class ToolPalette extends StatelessWidget {
  final VoidCallback onCut;
  final VoidCallback onMove;
  final VoidCallback onExtend;
  final VoidCallback onReverse;
  final VoidCallback onDeletePoint;
  final VoidCallback onSimplify;
  final VoidCallback onCreateWaypoint;

  final bool isCutEnabled;
  final bool isExtendEnabled;
  final bool isMoveEnabled;
  final bool isDeletePointEnabled;
  final bool isSimplifyEnabled;
  final bool isCreateWaypointEnabled;
  final bool isReverseEnabled;

  final EditorMode activeMode;

  const ToolPalette({
    super.key,
    required this.onCut,
    required this.onMove,
    required this.onExtend,
    required this.onReverse,
    required this.onDeletePoint,
    required this.onSimplify,
    required this.onCreateWaypoint,
    required this.isCutEnabled,
    required this.isExtendEnabled,
    required this.isMoveEnabled,
    required this.isDeletePointEnabled,
    required this.isSimplifyEnabled,
    required this.isCreateWaypointEnabled,
    required this.isReverseEnabled,
    required this.activeMode,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Background color for the palette card
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final iconColor = isDark ? Colors.white : Colors.black87;

    return Card(
      elevation: 4,
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          // CONSTRAINT: Width for roughly 2 icons (48px each + padding)
          width: 104, 
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4, // Horizontal space between buttons
            runSpacing: 4, // Vertical space between rows
            children: [
              _ToolButton(
                icon: Icons.content_cut,
                tooltip: "Cut Track",
                isEnabled: isCutEnabled,
                isActive: activeMode == EditorMode.cut,
                onTap: onCut,
                baseColor: iconColor,
              ),
              _ToolButton(
                icon: Icons.merge_type, 
                // Using merge icon for Join/Extend context, or 'add_road'
                // But specifically for 'Extend' logic:
                tooltip: "Extend Track",
                isEnabled: isExtendEnabled,
                isActive: activeMode == EditorMode.extend,
                onTap: onExtend,
                baseColor: iconColor,
                iconData: Icons.add_road, 
              ),
              _ToolButton(
                icon: Icons.open_with,
                tooltip: "Move Points",
                isEnabled: isMoveEnabled,
                isActive: activeMode == EditorMode.edit,
                onTap: onMove,
                baseColor: iconColor,
              ),
              _ToolButton(
                icon: Icons.delete_forever, // Icon for delete point
                tooltip: "Delete Point",
                isEnabled: isDeletePointEnabled,
                isActive: activeMode == EditorMode.deletePoint,
                onTap: onDeletePoint,
                baseColor: iconColor,
                iconData: Icons.remove_circle_outline,
              ),
              _ToolButton(
                icon: Icons.swap_calls,
                tooltip: "Reverse Track",
                isEnabled: isReverseEnabled,
                isActive: false, // Action is instant, no 'mode'
                onTap: onReverse,
                baseColor: iconColor,
              ),
              _ToolButton(
                icon: Icons.auto_fix_high,
                tooltip: "Simplify Track",
                isEnabled: isSimplifyEnabled,
                isActive: false, // Action is instant
                onTap: onSimplify,
                baseColor: iconColor,
              ),
              _ToolButton(
                icon: Icons.add_location_alt,
                tooltip: "Add Waypoint",
                isEnabled: isCreateWaypointEnabled,
                isActive: activeMode == EditorMode.createWaypoint,
                onTap: onCreateWaypoint,
                baseColor: iconColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final IconData? iconData; // Optional override
  final String tooltip;
  final bool isEnabled;
  final bool isActive;
  final VoidCallback onTap;
  final Color baseColor;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isEnabled,
    required this.isActive,
    required this.onTap,
    required this.baseColor,
    this.iconData,
  });

  @override
  Widget build(BuildContext context) {
    // Determine Colors
    Color bg;
    Color fg;

    if (!isEnabled) {
      bg = Colors.transparent;
      fg = baseColor.withOpacity(0.2); // Disabled Grey
    } else if (isActive) {
      bg = Colors.blue;
      fg = Colors.white;
    } else {
      bg = Colors.transparent;
      fg = baseColor;
    }

    return Tooltip(
      message: isEnabled ? tooltip : "$tooltip (Select a track)",
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: isActive 
                  ? Border.all(color: Colors.blueAccent) 
                  : Border.all(color: Colors.transparent),
            ),
            child: Icon(
              iconData ?? icon,
              color: fg,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}