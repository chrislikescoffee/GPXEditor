import 'package:flutter/material.dart';
import '../enums/editor_mode.dart';

class ToolPalette extends StatelessWidget {
  // Callbacks
  final VoidCallback onCut;
  final VoidCallback onMove;
  final VoidCallback onExtend;
  final VoidCallback onReverse;
  final VoidCallback onDeletePoint;
  final VoidCallback onSimplify;
  final VoidCallback onCreateWaypoint; // NEW

  // Flags
  final bool isCutEnabled;
  final bool isExtendEnabled;
  final bool isReverseEnabled;
  final bool isMoveEnabled;
  final bool isDeletePointEnabled;
  final bool isSimplifyEnabled;
  final bool isCreateWaypointEnabled; // NEW
  final EditorMode activeMode;

  const ToolPalette({
    super.key,
    required this.onCut,
    required this.onMove,
    required this.onExtend,
    required this.onReverse,
    required this.onDeletePoint,
    required this.onSimplify,
    required this.onCreateWaypoint, // NEW
    
    this.isCutEnabled = true,
    this.isExtendEnabled = true,
    this.isReverseEnabled = true,
    this.isMoveEnabled = true,
    this.isDeletePointEnabled = true,
    this.isSimplifyEnabled = true,
    this.isCreateWaypointEnabled = true, // NEW
    required this.activeMode,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Container(
        width: 200, 
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10, runSpacing: 10, 
              children: [
                _buildToolBtn(Icons.content_cut, isCutEnabled ? "Cut Track" : "Select exactly one track", onCut, enabled: isCutEnabled, isActive: activeMode == EditorMode.cut),
                _buildToolBtn(Icons.open_with, isMoveEnabled ? "Move Points" : "Select exactly one track", onMove, enabled: isMoveEnabled, isActive: activeMode == EditorMode.edit),
                _buildToolBtn(Icons.remove_circle_outline, isDeletePointEnabled ? "Delete Points" : "Select exactly one track", onDeletePoint, enabled: isDeletePointEnabled, isActive: activeMode == EditorMode.deletePoint),
                _buildToolBtn(Icons.edit_road, isExtendEnabled ? "Extend Line" : "Select exactly one track", onExtend, enabled: isExtendEnabled, isActive: activeMode == EditorMode.extend),
                _buildToolBtn(Icons.swap_calls, isReverseEnabled ? "Reverse" : "Select track(s)", onReverse, enabled: isReverseEnabled, isActive: activeMode == EditorMode.reverse),
                _buildToolBtn(Icons.auto_fix_high, isSimplifyEnabled ? "Simplify" : "Select exactly one track", onSimplify, enabled: isSimplifyEnabled, isActive: false),

                // NEW: Create Waypoint Button
                _buildToolBtn(
                  Icons.add_location_alt, 
                  isCreateWaypointEnabled ? "Add Waypoint" : "Select a track to add waypoint", 
                  onCreateWaypoint,
                  enabled: isCreateWaypointEnabled,
                  isActive: activeMode == EditorMode.createWaypoint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolBtn(IconData icon, String tooltip, VoidCallback onTap, {bool enabled = true, bool isActive = false}) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: isActive ? BoxDecoration(color: Colors.blue.withOpacity(0.2), shape: BoxShape.circle) : null,
        child: IconButton(
          icon: Icon(icon),
          color: isActive ? Colors.blue : (enabled ? Colors.black : Colors.grey.withOpacity(0.3)),
          onPressed: enabled ? onTap : null, 
          splashRadius: 20, 
        ),
      ),
    );
  }
}