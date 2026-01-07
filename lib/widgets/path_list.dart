import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import '../models/track_data.dart';

class PathList extends StatefulWidget {
  final List<TrackData> tracks;
  final Set<String> selectedTrackIds;
  
  final Function(String id, bool isMultiSelect) onSelect;
  final VoidCallback onSelectAll; 
  final Function(int oldIndex, int newIndex) onReorder;
  final Function(String id) onToggleVisibility;
  final Function(String id, Color newColor) onColorChanged;
  final Function(String id, String newName) onRename;
  
  // Actions
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
  // Helper: Color Picker
  void _showColorPicker(BuildContext context, TrackData track) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Select Color"),
          content: Wrap(
            spacing: 10, runSpacing: 10,
            children: [
              Colors.blue, Colors.red, Colors.green, Colors.orange, 
              Colors.purple, Colors.black, Colors.teal, Colors.amber,
              Colors.indigo, Colors.brown, Colors.pink, Colors.grey
            ].map((color) {
              return GestureDetector(
                onTap: () {
                  widget.onColorChanged(track.id, color);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // Helper: Rename Dialog
  void _showRenameDialog(BuildContext context, TrackData track) {
    TextEditingController controller = TextEditingController(text: track.name);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Rename Track"),
          content: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (value) {
              widget.onRename(track.id, value);
              Navigator.of(ctx).pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                widget.onRename(track.id, controller.text);
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
    bool showJoin = widget.selectedTrackIds.length > 1;
    bool areAllSelected = widget.tracks.isNotEmpty && 
                          widget.selectedTrackIds.length == widget.tracks.length;

    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        width: 250,
        color: Colors.white,
        child: Column(
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey[200],
              width: double.infinity,
              child: const Text(
                "Path List",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            
            // SELECT ALL OPTION (Only if multiple paths exist)
            if (widget.tracks.length > 1)
              InkWell(
                onTap: widget.onSelectAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        areAllSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 12),
                      Text(
                        areAllSelected ? "Deselect All" : "Select All",
                        style: TextStyle(color: Colors.grey[800], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

            // LIST
            Expanded(
              child: ReorderableListView.builder(
                onReorder: widget.onReorder,
                buildDefaultDragHandles: false,
                itemCount: widget.tracks.length,
                itemBuilder: (context, index) {
                  final track = widget.tracks[index];
                  final isSelected = widget.selectedTrackIds.contains(track.id);

                  return ReorderableDragStartListener(
                    key: ValueKey(track.id),
                    index: index,
                    child: Material(
                      color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        leading: GestureDetector(
                          onTap: () => _showColorPicker(context, track),
                          child: Container(width: 24, height: 24, decoration: BoxDecoration(color: track.color, shape: BoxShape.circle, border: Border.all(color: Colors.grey, width: 1))),
                        ),
                        title: GestureDetector(
                          onDoubleTap: () => _showRenameDialog(context, track),
                          child: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(decoration: null, color: track.isVisible ? Colors.black : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        ),
                        trailing: IconButton(
                          icon: Icon(track.isVisible ? Icons.visibility : Icons.visibility_off, color: track.isVisible ? Colors.black : Colors.grey, size: 20),
                          onPressed: () => widget.onToggleVisibility(track.id),
                        ),
                        onTap: () {
                          bool isMulti = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
                          if (!isMulti && isSelected && widget.selectedTrackIds.length > 1) {
                            isMulti = true; 
                          }
                          widget.onSelect(track.id, isMulti);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1),

            // 1. JOIN BUTTON (Top of the bottom section)
            if (showJoin)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
                child: ElevatedButton.icon(
                  onPressed: widget.onJoin,
                  icon: const Icon(Icons.merge_type, size: 18),
                  label: Text("JOIN ${widget.selectedTrackIds.length} PATHS"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ),

            // 2. CREATE NEW PATH BUTTON (Middle of the bottom section)
            InkWell(
              onTap: widget.onCreateNew,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                   // Separator line at the top to distinguish from list/join button
                   border: Border(top: BorderSide(color: Colors.grey[300]!)),
                   // Subtle blue tint to indicate creation
                   color: Colors.blue.withOpacity(0.05),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Create New Path",
                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            // 3. FOOTER TOOLS (Bottom)
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _footerBtn(Icons.upload_file, "Import", widget.onImport),
                  _footerBtn(Icons.save, "Export", widget.onSave),
                  _footerBtn(Icons.delete, "Delete Selected", widget.onDelete),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footerBtn(IconData icon, String label, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon),
      tooltip: label,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}