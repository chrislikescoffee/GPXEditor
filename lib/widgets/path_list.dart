import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // NEW: Required for detecting Ctrl/Cmd keys
import '../models/track_data.dart';

class PathList extends StatefulWidget {
  final List<TrackData> tracks;
  final Set<String> selectedTrackIds;
  final Function(String, bool) onSelect;
  final VoidCallback onSelectAll;
  final Function(int, int) onReorder;
  final Function(String) onToggleVisibility;
  final Function(String, Color) onColorChanged;
  final Function(String, String) onRename;
  final VoidCallback onImport;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final VoidCallback onJoin;
  final VoidCallback onCreateNew;

  const PathList({
    super.key,
    required this.tracks,
    required this.selectedTrackIds,
    required this.onSelect,
    required this.onSelectAll,
    required this.onReorder,
    required this.onToggleVisibility,
    required this.onColorChanged,
    required this.onRename,
    required this.onImport,
    required this.onSave,
    required this.onDelete,
    required this.onJoin,
    required this.onCreateNew,
  });

  @override
  State<PathList> createState() => _PathListState();
}

class _PathListState extends State<PathList> {
  
  void _showColorPicker(BuildContext context, String trackId, Color currentColor) {
    final colors = [
      Colors.blue, Colors.orange, Colors.purple, Colors.green,
      Colors.teal, Colors.red, Colors.pink, Colors.indigo,
      Colors.amber, Colors.brown, Colors.cyan, Colors.lime,
      Colors.black, Colors.grey,
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Pick Color"),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((c) {
              return GestureDetector(
                onTap: () {
                  widget.onColorChanged(trackId, c);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey, width: 1),
                  ),
                  child: c == currentColor
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, String trackId, String currentName) {
    TextEditingController controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Rename Track"),
          content: TextField(
            controller: controller,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                widget.onRename(trackId, controller.text);
                Navigator.of(ctx).pop();
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    final headerStyle = TextStyle(
      fontWeight: FontWeight.bold, 
      fontSize: 16,
      color: isDarkMode ? Colors.white : Colors.black87
    );

    return Column(
      children: [
        // --- HEADER ---
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!
              )
            ),
            color: isDarkMode ? Colors.black12 : Colors.grey[50],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Paths", style: headerStyle),
              TextButton(
                onPressed: widget.onSelectAll,
                child: Text(
                  widget.selectedTrackIds.length == widget.tracks.length && widget.tracks.isNotEmpty
                      ? "Deselect All"
                      : "Select All",
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        // --- LIST ---
        Expanded(
          child: widget.tracks.isEmpty
              ? Center(
                  child: Text(
                    "No tracks yet.\nImport a GPX file\nor create new.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ReorderableListView.builder(
                  onReorder: widget.onReorder,
                  itemCount: widget.tracks.length,
                  itemBuilder: (context, index) {
                    final track = widget.tracks[index];
                    final isSelected = widget.selectedTrackIds.contains(track.id);

                    Color itemBgColor;
                    if (isSelected) {
                      itemBgColor = isDarkMode 
                          ? Colors.teal.withOpacity(0.3) 
                          : Colors.blue.withOpacity(0.1);
                    } else {
                      itemBgColor = Theme.of(context).cardColor;
                    }

                    return Container(
                      key: ValueKey(track.id),
                      decoration: BoxDecoration(
                        color: itemBgColor,
                        border: Border(
                          bottom: BorderSide(
                            color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!
                          )
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                track.isVisible ? Icons.visibility : Icons.visibility_off,
                                color: track.isVisible 
                                    ? (isDarkMode ? Colors.grey[400] : Colors.grey[600]) 
                                    : Colors.grey[300],
                                size: 20,
                              ),
                              onPressed: () => widget.onToggleVisibility(track.id),
                              tooltip: "Toggle Visibility",
                            ),
                            GestureDetector(
                              onTap: () => _showColorPicker(context, track.id, track.color),
                              child: Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(
                                  color: track.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDarkMode ? Colors.white54 : Colors.grey, 
                                    width: 1
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        title: GestureDetector(
                          onDoubleTap: () => _showRenameDialog(context, track.id, track.name),
                          child: Text(
                            track.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Icon(
                            Icons.drag_handle, 
                            color: isDarkMode ? Colors.grey[600] : Colors.grey[400]
                          ),
                        ),

                        // FIX: Detect Keyboard Modifiers for Multi-Select
                        onTap: () {
                          bool isMulti = HardwareKeyboard.instance.isControlPressed || 
                                         HardwareKeyboard.instance.isMetaPressed || 
                                         HardwareKeyboard.instance.isShiftPressed;
                          widget.onSelect(track.id, isMulti);
                        },
                      ),
                    );
                  },
                ),
        ),

        // --- BOTTOM ACTIONS ---
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.black12 : Colors.grey[100],
            border: Border(
              top: BorderSide(
                color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!
              )
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Join Paths (Conditionally Visible)
              if (widget.selectedTrackIds.length > 1) ...[
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: widget.onJoin,
                    icon: const Icon(Icons.merge_type, size: 18),
                    label: const Text("Join Selected Paths"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkMode ? Colors.grey[800] : Colors.white,
                      foregroundColor: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 2. Create New (Full Width)
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: widget.onCreateNew,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Create New Path"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? Colors.grey[800] : Colors.white,
                    foregroundColor: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 3. File Operations Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: _ActionButton(
                    icon: Icons.upload_file, 
                    label: "Import", 
                    onTap: widget.onImport,
                    isDark: isDarkMode,
                  )),
                  Expanded(child: _ActionButton(
                    icon: Icons.save_alt, 
                    label: "Export", 
                    onTap: widget.onSave, 
                    color: Colors.blue,
                    isDark: isDarkMode,
                  )),
                  Expanded(child: _ActionButton(
                    icon: Icons.delete, 
                    label: "Delete", 
                    onTap: widget.onDelete, 
                    color: Colors.red,
                    isDark: isDarkMode,
                  )),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Helper Widget
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool isDark;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? (isDark ? Colors.white70 : Colors.black87);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: iconColor)),
          ],
        ),
      ),
    );
  }
}