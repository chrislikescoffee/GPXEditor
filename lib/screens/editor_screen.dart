import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:desktop_drop/desktop_drop.dart'; // Drag & Drop
import 'package:cross_file/cross_file.dart';    // File Type

// Widgets
import '../widgets/tool_palette.dart';
import '../widgets/path_list.dart';

// Logic & Models
import '../services/gpx_service.dart';
import '../enums/editor_mode.dart';
import '../models/track_data.dart';
import '../models/waypoint_data.dart';
import '../utils/geo_utils.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final MapController _mapController = MapController();
  final GpxService _gpxService = GpxService();

  // Data
  List<TrackData> tracks = [];
  List<WaypointData> waypoints = []; 
  Set<String> _selectedTrackIds = {};
  
  final List<Color> _trackColors = [
    Colors.blue, Colors.orange, Colors.purple, Colors.green, 
    Colors.teal, Colors.red, Colors.pink, Colors.indigo, 
    Colors.amber, Colors.brown, Colors.cyan, Colors.lime
  ];

  // State
  EditorMode _currentMode = EditorMode.view;
  bool? _extendFromEnd;
  
  // Map Style: 0 = Light, 1 = Dark Grey, 2 = Satellite
  int _mapStyleIndex = 0; 
  bool get _isDarkTheme => _mapStyleIndex == 1 || _mapStyleIndex == 2;

  // Cut Tool State
  LatLng? _previewCutPoint;
  List<LatLng>? _previewGreenPath; // Path BEFORE the cut
  List<LatLng>? _previewRedPath;   // Path AFTER the cut
  
  // UI State
  bool _isLoading = false;
  bool _isDraggingFile = false; // For DropTarget overlay
  String? _statusMessage;
  Timer? _statusTimer;

  // --- HELPERS ---

  TrackData? get _primarySelectedTrack {
    if (_selectedTrackIds.length != 1) return null;
    try {
      return tracks.firstWhere((t) => t.id == _selectedTrackIds.first);
    } catch (e) {
      return null;
    }
  }

  String _getUniqueName(String baseName) {
    String currentName = baseName;
    int counter = 1;
    bool exists(String name) => tracks.any((t) => t.name == name);
    while (exists(currentName)) {
      currentName = "$baseName $counter";
      counter++;
    }
    return currentName;
  }
  
  void _showStatus(String message) {
    _statusTimer?.cancel();
    setState(() => _statusMessage = message);
    _statusTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _statusMessage = null);
    });
  }

  // --- MAP CONTROLS ---

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  void _fitToContent() {
    if (tracks.isEmpty && waypoints.isEmpty) return;

    List<LatLng> allPoints = [];
    for (var t in tracks) {
      if (t.isVisible) {
        for (var seg in t.segments) {
          allPoints.addAll(seg);
        }
      }
    }
    for (var w in waypoints) {
      if (w.isVisible) allPoints.add(w.point);
    }

    if (allPoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(allPoints);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  // --- HOVER LOGIC (Smart Cut Tool) ---
  void _handleHover(PointerHoverEvent event) {
    if (_currentMode != EditorMode.cut || _primarySelectedTrack == null) {
      if (_previewCutPoint != null) {
        setState(() {
          _previewCutPoint = null;
          _previewGreenPath = null;
          _previewRedPath = null;
        });
      }
      return;
    }

    final point = _mapController.camera.pointToLatLng(
      math.Point(event.localPosition.dx, event.localPosition.dy)
    );

    final targetTrack = _primarySelectedTrack!;
    LatLng? bestPoint;
    double closestDist = double.infinity;
    
    int bestSegIndex = -1;
    int bestSplitIndex = -1; 

    for (int i = 0; i < targetTrack.segments.length; i++) {
      var seg = targetTrack.segments[i];
      var result = GeoUtils.findNearestPointOnLine(point, seg, thresholdMeters: 200); 
      
      if (result != null) {
        final dist = const Distance().as(LengthUnit.Meter, point, result.$2);
        if (dist < closestDist) {
          closestDist = dist;
          bestPoint = result.$2;
          bestSegIndex = i;
          bestSplitIndex = result.$1;
        }
      }
    }

    if (bestPoint != _previewCutPoint) {
      List<LatLng>? green;
      List<LatLng>? red;

      if (bestPoint != null && bestSegIndex != -1) {
        // Construct Green Path (Start -> Cut)
        final fullSegment = targetTrack.segments[bestSegIndex];
        green = fullSegment.sublist(0, bestSplitIndex + 1);
        green.add(bestPoint);

        // Construct Red Path (Cut -> End)
        red = [bestPoint];
        red.addAll(fullSegment.sublist(bestSplitIndex + 1));
      }

      setState(() {
        _previewCutPoint = bestPoint;
        _previewGreenPath = green;
        _previewRedPath = red;
      });
    }
  }

  // --- FILE ACTIONS ---

  Future<void> _handleImport() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 50)); 

    try {
      final importData = await _gpxService.importFiles();
      _processImportedData(importData);
      _showStatus("Imported ${importData.tracks.length} tracks.");
    } catch (e) {
      _showStatus("Error importing files: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleDroppedFiles(List<XFile> files) async {
    setState(() => _isLoading = true);
    try {
      final importData = await _gpxService.parseDragDropFiles(files);
      _processImportedData(importData);
      _showStatus("Imported ${importData.tracks.length} tracks from drop.");
    } catch (e) {
      _showStatus("Error processing drop: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _processImportedData(GpxImportData importData) {
    setState(() {
      // 1. Process Tracks
      if (importData.tracks.isNotEmpty) {
        for (var data in importData.tracks) {
          String uniqueName = _getUniqueName(data.name);
          Color assignedColor = _trackColors[tracks.length % _trackColors.length];

          final newTrack = TrackData.create(
            name: uniqueName,
            color: assignedColor,
            segments: data.segments,
            isSaved: true, // Imported files are "saved"
          );
          tracks.add(newTrack);
          _selectedTrackIds.add(newTrack.id);
        }
      }

      // 2. Process Waypoints
      if (importData.waypoints.isNotEmpty) {
        for (var wpt in importData.waypoints) {
          waypoints.add(WaypointData.create(
            name: wpt.name,
            point: wpt.point,
            description: wpt.description,
            comment: wpt.comment,
            symbol: wpt.symbol,
            link: wpt.link,
            color: Colors.red,
          ));
        }
      }
    });

    // Zoom Logic
    if (importData.tracks.isNotEmpty || importData.waypoints.isNotEmpty) {
      _fitToContent();
    }
  }

  void _handleDeleteSelected() {
    if (_selectedTrackIds.isEmpty) return;
    int count = _selectedTrackIds.length;
    setState(() {
      tracks.removeWhere((t) => _selectedTrackIds.contains(t.id));
      _selectedTrackIds.clear();
      _currentMode = EditorMode.view;
    });
    _showStatus("Deleted $count tracks.");
  }

  void _handleSave() async {
    // 1. Determine targets
    List<TrackData> targets = [];
    if (_selectedTrackIds.isNotEmpty) {
      targets = tracks.where((t) => _selectedTrackIds.contains(t.id)).toList();
    } else {
      targets = List.from(tracks);
    }

    if (targets.isEmpty && waypoints.isEmpty) {
      _showStatus("Nothing to export.");
      return;
    }

    setState(() => _isLoading = true);
    int count = 0;

    try {
      // 2. Export Tracks
      for (var track in targets) {
        await _gpxService.exportGpx(track.name, [track], waypoints);
        setState(() => track.isSaved = true);
        count++;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 3. Export Waypoints only
      if (targets.isEmpty && waypoints.isNotEmpty) {
         await _gpxService.exportGpx("waypoints", [], waypoints);
         if (count == 0) count = 1; 
      }

      // 4. Summary
      if (mounted) {
         showDialog(
           context: context,
           builder: (ctx) => AlertDialog(
             title: const Text("Export Complete"),
             content: Text("$count path(s) saved to your downloads."),
             actions: [
               TextButton(
                 onPressed: () => Navigator.of(ctx).pop(),
                 child: const Text("OK"),
               )
             ],
           ),
         );
      }
    } catch (e) {
      _showStatus("Export failed: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- TRACK TOOLS ---

  void _handleCreateNew() {
    setState(() {
      _currentMode = EditorMode.create;
      final newTrack = TrackData.create(
        name: _getUniqueName("New Route"),
        color: Colors.red,
        segments: [[]],
        isSaved: false, 
      );
      tracks.add(newTrack);
      _selectedTrackIds.clear();
      _selectedTrackIds.add(newTrack.id);
    });
    _showStatus("Tap on map to add points.");
  }

  void _handleCut() {
    if (_primarySelectedTrack == null) return;
    setState(() => _currentMode = EditorMode.cut);
    _showStatus("Tap the line where you want to cut it.");
  }

  void _performCut(TrackData original, int segIndex, int splitIndex, LatLng splitPoint) {
    setState(() {
      List<LatLng> targetSegment = original.segments[segIndex];
      List<LatLng> segmentA = targetSegment.sublist(0, splitIndex + 1);
      segmentA.add(splitPoint);
      List<LatLng> segmentB = [splitPoint];
      segmentB.addAll(targetSegment.sublist(splitIndex + 1));

      List<List<LatLng>> segmentsA = [];
      segmentsA.addAll(original.segments.sublist(0, segIndex));
      segmentsA.add(segmentA);

      List<List<LatLng>> segmentsB = [];
      segmentsB.add(segmentB);
      segmentsB.addAll(original.segments.sublist(segIndex + 1));

      final part1 = TrackData.create(name: "${original.name} (Part 1)", color: original.color, segments: segmentsA);
      final part2 = TrackData.create(name: "${original.name} (Part 2)", color: original.color, segments: segmentsB);

      int originalIndex = tracks.indexOf(original);
      tracks.removeAt(originalIndex);
      tracks.insert(originalIndex, part2);
      tracks.insert(originalIndex, part1);
      
      _selectedTrackIds.clear();
      _selectedTrackIds.add(part1.id);
      _currentMode = EditorMode.view;

      _previewCutPoint = null;
      _previewGreenPath = null;
      _previewRedPath = null;
    });
    _showStatus("Track split successfully.");
  }

  void _handleJoin() {
    if (_selectedTrackIds.length < 2) return;
    setState(() {
      List<TrackData> tracksToJoin = tracks.where((t) => _selectedTrackIds.contains(t.id)).toList();
      tracksToJoin.sort((a, b) => tracks.indexOf(a).compareTo(tracks.indexOf(b)));

      // FLATTEN all segments into ONE continuous list
      List<LatLng> singleContinuousSegment = [];
      for (var t in tracksToJoin) {
        for (var seg in t.segments) {
          singleContinuousSegment.addAll(seg);
        }
      }

      final firstTrack = tracksToJoin.first;
      final newTrack = TrackData.create(
        name: "${firstTrack.name} (Joined)",
        color: firstTrack.color,
        segments: [singleContinuousSegment], 
        isSaved: false, 
      );

      for (var t in tracksToJoin) tracks.remove(t);
      tracks.insert(0, newTrack);
      _selectedTrackIds.clear();
      _selectedTrackIds.add(newTrack.id);
    });
    _showStatus("Tracks joined into a single continuous path.");
  }

  void _handleGroup() {
    if (_selectedTrackIds.length < 2) return;
    setState(() {
      List<TrackData> tracksToGroup = tracks.where((t) => _selectedTrackIds.contains(t.id)).toList();
      tracksToGroup.sort((a, b) => tracks.indexOf(a).compareTo(tracks.indexOf(b)));

      // COLLECT segments but keep them SEPARATE (Network/Branches)
      List<List<LatLng>> collectedSegments = [];
      for (var t in tracksToGroup) {
        collectedSegments.addAll(t.segments);
      }

      final firstTrack = tracksToGroup.first;
      final newTrack = TrackData.create(
        name: "${firstTrack.name} (Group)",
        color: firstTrack.color,
        segments: collectedSegments,
        isSaved: false, 
      );

      for (var t in tracksToGroup) tracks.remove(t);
      tracks.insert(0, newTrack);
      _selectedTrackIds.clear();
      _selectedTrackIds.add(newTrack.id);
    });
    _showStatus("Tracks grouped into a network.");
  }

  void _handleReverse() {
    if (_selectedTrackIds.isEmpty) {
      _showStatus("Select tracks to reverse.");
      return;
    }
    setState(() {
      for (var id in _selectedTrackIds) {
        final track = tracks.firstWhere((t) => t.id == id);
        track.segments = track.segments.reversed.map((seg) => seg.reversed.toList()).toList();
        track.isSaved = false;
      }
    });
    _showStatus("Reversed ${_selectedTrackIds.length} tracks.");
  }

  void _handleExtend() {
    if (_primarySelectedTrack == null) return;
    setState(() {
      _currentMode = EditorMode.extend;
      _extendFromEnd = null; 
    });
    _showStatus("Tap the Green (Start) or Red (End) marker.");
  }

  void _handleMove() {
    if (_primarySelectedTrack == null) return;
    setState(() => _currentMode = EditorMode.edit);
    _showStatus("Drag any point to move it.");
  }

  void _handleDeletePoint() {
    if (_primarySelectedTrack == null) return;
    setState(() => _currentMode = EditorMode.deletePoint);
    _showStatus("Tap any point to remove it.");
  }

  void _handleSimplify() {
    if (_primarySelectedTrack == null) return;
    double tolerance = 5.0; 
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Simplify Path"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Adjust tolerance to reduce point count."),
                  const SizedBox(height: 20),
                  Text("${tolerance.toStringAsFixed(1)}m", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Slider(
                    value: tolerance, min: 1.0, max: 50.0, divisions: 49,
                    onChanged: (val) => setDialogState(() => tolerance = val),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _performSimplify(_primarySelectedTrack!, tolerance);
                  },
                  child: const Text("Apply"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _performSimplify(TrackData track, double tolerance) {
    int totalPointsBefore = 0;
    int totalPointsAfter = 0;

    setState(() {
      List<List<LatLng>> newSegments = [];
      for (var seg in track.segments) {
        totalPointsBefore += seg.length;
        var simpleSeg = GeoUtils.simplifyTrack(seg, tolerance);
        newSegments.add(simpleSeg);
        totalPointsAfter += simpleSeg.length;
      }
      track.segments = newSegments;
      track.isSaved = false;
    });

    _showStatus("Simplified: Removed ${totalPointsBefore - totalPointsAfter} points.");
  }

  void _updatePointPosition(int segIndex, int pointIndex, Offset globalPosition) {
    if (_primarySelectedTrack == null) return;
    final point = math.Point(globalPosition.dx, globalPosition.dy);
    final newLatLng = _mapController.camera.pointToLatLng(point);
    setState(() {
      _primarySelectedTrack!.segments[segIndex][pointIndex] = newLatLng;
      _primarySelectedTrack!.isSaved = false;
    });
  }

  // --- WAYPOINT TOOLS ---

  void _handleCreateWaypoint() {
    setState(() => _currentMode = EditorMode.createWaypoint);
    _showStatus("Tap on map to place a waypoint.");
  }

  void _showWaypointDialog(WaypointData wpt) {
    showDialog(
      context: context,
      builder: (ctx) {
        bool isEditing = false;
        final nameCtrl = TextEditingController(text: wpt.name);
        final descCtrl = TextEditingController(text: wpt.description ?? "");
        final cmtCtrl = TextEditingController(text: wpt.comment ?? "");
        final symCtrl = TextEditingController(text: wpt.symbol ?? "");
        final linkCtrl = TextEditingController(text: wpt.link ?? "");

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(isEditing ? "Edit Waypoint" : wpt.name)),
                  if (!isEditing)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => setDialogState(() => isEditing = true),
                    )
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: isEditing
                      ? [
                          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
                          TextField(controller: descCtrl, decoration: const InputDecoration(labelText: "Description")),
                          TextField(controller: cmtCtrl, decoration: const InputDecoration(labelText: "Comment")),
                          TextField(controller: symCtrl, decoration: const InputDecoration(labelText: "Symbol (e.g. Parking)")),
                          TextField(controller: linkCtrl, decoration: const InputDecoration(labelText: "Link URL")),
                        ]
                      : [
                          _infoRow("Description", wpt.description),
                          _infoRow("Comment", wpt.comment),
                          _infoRow("Symbol", wpt.symbol),
                          _infoRow("Link", wpt.link),
                          const SizedBox(height: 10),
                          Text("Lat: ${wpt.point.latitude.toStringAsFixed(5)}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          Text("Lon: ${wpt.point.longitude.toStringAsFixed(5)}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        ],
                ),
              ),
              actions: [
                if (isEditing)
                   TextButton(
                    onPressed: () => setDialogState(() => isEditing = false), 
                    child: const Text("Cancel Edit"),
                  ),
                if (isEditing)
                   TextButton(
                    onPressed: () {
                      setState(() {
                        wpt.name = nameCtrl.text;
                        wpt.description = descCtrl.text;
                        wpt.comment = cmtCtrl.text;
                        wpt.symbol = symCtrl.text;
                        wpt.link = linkCtrl.text;
                      });
                      Navigator.of(context).pop();
                      _showStatus("Waypoint updated.");
                    },
                    child: const Text("Save"),
                  ),
                if (!isEditing) ...[
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () {
                      setState(() => waypoints.remove(wpt));
                      Navigator.of(context).pop();
                      _showStatus("Waypoint deleted.");
                    },
                    child: const Text("Delete Waypoint"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close"),
                  ),
                ]
              ],
            );
          },
        );
      },
    );
  }

  Widget _infoRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  // --- LIST ACTIONS ---

  void _handleSelect(String id, bool isMultiSelect) {
    setState(() {
      if (isMultiSelect) {
        if (_selectedTrackIds.contains(id)) _selectedTrackIds.remove(id);
        else _selectedTrackIds.add(id);
      } else {
        _selectedTrackIds.clear();
        _selectedTrackIds.add(id);
      }
    });
  }

  void _handleSelectAll() {
    setState(() {
      if (_selectedTrackIds.length == tracks.length) _selectedTrackIds.clear();
      else _selectedTrackIds = tracks.map((t) => t.id).toSet();
    });
  }

  void _handleReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final TrackData item = tracks.removeAt(oldIndex);
      tracks.insert(newIndex, item);
    });
  }

  void _handleToggleVis(String id) {
    setState(() {
      final track = tracks.firstWhere((t) => t.id == id);
      track.isVisible = !track.isVisible;
    });
  }

  void _handleColorChange(String id, Color color) {
    setState(() {
      final track = tracks.firstWhere((t) => t.id == id);
      track.color = color;
      track.isSaved = false;
    });
  }

  void _handleRename(String id, String name) {
    setState(() {
      final track = tracks.firstWhere((t) => t.id == id);
      track.name = name;
      track.isSaved = false;
    });
  }

  // --- MAP INTERACTION ---

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    // 1. CREATION
    if (_currentMode == EditorMode.create && _primarySelectedTrack != null) {
      setState(() {
        if (_primarySelectedTrack!.segments.isEmpty) {
          _primarySelectedTrack!.segments.add([point]);
        } else {
          _primarySelectedTrack!.segments.last.add(point);
        }
        _primarySelectedTrack!.isSaved = false;
      });
      return;
    }

    // 2. EXTEND
    if (_currentMode == EditorMode.extend && _primarySelectedTrack != null) {
      if (_extendFromEnd == null) {
        _showStatus("Please tap the Start or End marker first.");
        return;
      }
      setState(() {
        if (_primarySelectedTrack!.segments.isEmpty) {
           _primarySelectedTrack!.segments.add([point]);
           return;
        }
        if (_extendFromEnd == true) {
          _primarySelectedTrack!.segments.last.add(point);
        } else {
          _primarySelectedTrack!.segments.first.insert(0, point);
        }
        _primarySelectedTrack!.isSaved = false;
      });
      return;
    }

    // 3. CREATE WAYPOINT
    if (_currentMode == EditorMode.createWaypoint) {
      final newWpt = WaypointData.create(
        name: "New Waypoint",
        point: point,
        symbol: "Generic", 
      );
      setState(() {
        waypoints.add(newWpt);
        _currentMode = EditorMode.view; 
      });
      _showStatus("Waypoint created.");
      return;
    }

    // 4. CUT
    if (_currentMode == EditorMode.cut && _primarySelectedTrack != null) {
      final targetTrack = _primarySelectedTrack!;
      
      // OPTIMIZED: Use the ghost preview point
      if (_previewCutPoint != null) {
        for (int i = 0; i < targetTrack.segments.length; i++) {
           var seg = targetTrack.segments[i];
           // Use tiny threshold because point is exact
           var result = GeoUtils.findNearestPointOnLine(_previewCutPoint!, seg, thresholdMeters: 5);
           if (result != null) {
             _performCut(targetTrack, i, result.$1, result.$2);
             return;
           }
         }
      }

      // Fallback for click (Mobile)
      double bestDist = double.infinity;
      int bestSegIndex = -1;
      int bestSplitIndex = -1;
      LatLng? bestSplitPoint;

      for (int i = 0; i < targetTrack.segments.length; i++) {
        var seg = targetTrack.segments[i];
        var result = GeoUtils.findNearestPointOnLine(point, seg, thresholdMeters: 500);
        if (result != null) {
          bestSegIndex = i;
          bestSplitIndex = result.$1;
          bestSplitPoint = result.$2;
          break; 
        }
      }

      if (bestSegIndex != -1) {
        _performCut(targetTrack, bestSegIndex, bestSplitIndex, bestSplitPoint!);
      } else {
         _showStatus("Too far from any line.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Prepare Layers
    final borderPolylines = <Polyline>[];
    final trackPolylines = <Polyline>[];

    for (var t in tracks) {
      if (!t.isVisible) continue;
      bool isSel = _selectedTrackIds.contains(t.id);
      
      for (var seg in t.segments) {
        if (seg.isEmpty) continue;
        if (isSel) {
          borderPolylines.add(Polyline(
            points: seg, strokeWidth: 8.0, 
            color: _isDarkTheme ? Colors.white : Colors.black, 
            borderColor: _isDarkTheme ? Colors.black : Colors.white, borderStrokeWidth: 1.0, 
          ));
        }
        trackPolylines.add(Polyline(
          points: seg, strokeWidth: 4.0, color: t.color,
        ));
      }
    }

    // 2. Markers
    List<Marker> markers = [];
    
    // -- WAYPOINTS --
    for (var wpt in waypoints) {
      if (!wpt.isVisible) continue;
      markers.add(Marker(
        point: wpt.point, width: 100, height: 60,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () => _showWaypointDialog(wpt),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _isDarkTheme ? Colors.black87 : Colors.white.withOpacity(0.9), 
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _isDarkTheme ? Colors.white54 : Colors.grey),
                ),
                child: Text(
                  wpt.name, 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis, 
                  style: TextStyle(
                    fontSize: 10, 
                    fontWeight: FontWeight.bold,
                    color: _isDarkTheme ? Colors.white : Colors.black
                  )
                ),
              ),
              const Icon(Icons.location_on, color: Colors.red, size: 30),
            ],
          ),
        ),
      ));
    }

    // -- TRACK ENDPOINTS --
    for (var track in tracks) {
      if (!track.isVisible || track.segments.isEmpty) continue;
      LatLng? startPoint;
      LatLng? endPoint;

      if (track.segments.first.isNotEmpty) startPoint = track.segments.first.first;
      if (track.segments.last.isNotEmpty) endPoint = track.segments.last.last;

      if (startPoint == null && endPoint == null) continue;
      final isSelected = _selectedTrackIds.contains(track.id);
      final double size = isSelected ? 20.0 : 16.0;
      
      Widget buildEndpoint(bool isEnd, LatLng point) {
        bool isInteractive = (_currentMode == EditorMode.extend && isSelected);
        Widget w = Container(
           decoration: BoxDecoration(
             color: isEnd ? Colors.red : Colors.green,
             shape: BoxShape.circle,
             border: Border.all(color: Colors.white, width: 2),
             boxShadow: [if (isSelected) const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
           ),
        );
        if (isInteractive) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                setState(() => _extendFromEnd = isEnd);
                _showStatus("Extending from ${isEnd ? 'End' : 'Start'}.");
              },
              child: w,
            ),
          );
        }
        return w;
      }

      if (startPoint != null) {
        markers.add(Marker(point: startPoint, width: size, height: size, child: buildEndpoint(false, startPoint)));
      }
      if (endPoint != null) {
        markers.add(Marker(point: endPoint, width: size, height: size, child: buildEndpoint(true, endPoint)));
      }
    }

    // -- EDIT HANDLES --
    if (_primarySelectedTrack != null && _primarySelectedTrack!.isVisible) {
      var track = _primarySelectedTrack!;
      bool isMove = _currentMode == EditorMode.edit;
      bool isDel = _currentMode == EditorMode.deletePoint;
      double dotSize = (isMove || isDel) ? 16 : 8;

      for (int i = 0; i < track.segments.length; i++) {
        var seg = track.segments[i];
        for (int j = 0; j < seg.length; j++) {
           LatLng pt = seg[j];
           Color dotColor = isDel ? Colors.red : (isMove ? Colors.white : track.color);
           Color borderColor = isDel ? Colors.white : (isMove ? Colors.black : Colors.white);
           
           Widget dot = Container(
             decoration: BoxDecoration(
               color: dotColor, shape: BoxShape.circle,
               border: Border.all(color: borderColor, width: isMove ? 2 : 1),
             ),
           );

           Widget interactiveWidget;
           if (isMove) {
             interactiveWidget = GestureDetector(
               onPanUpdate: (details) => _updatePointPosition(i, j, details.globalPosition),
               child: dot,
             );
           } else if (isDel) {
             interactiveWidget = GestureDetector(
               onTap: () {
                 setState(() {
                   track.segments[i].removeAt(j);
                   if (track.segments[i].isEmpty) track.segments.removeAt(i);
                   if (track.segments.isEmpty) {
                     tracks.remove(track);
                     _selectedTrackIds.clear();
                     _currentMode = EditorMode.view;
                   }
                   track.isSaved = false;
                 });
                 _showStatus("Point removed.");
               },
               child: dot,
             );
           } else {
             interactiveWidget = dot;
           }

           if (isMove || isDel) {
             markers.add(Marker(
               point: pt, width: dotSize, height: dotSize,
               child: MouseRegion(cursor: isMove ? SystemMouseCursors.grab : SystemMouseCursors.click, child: interactiveWidget),
             ));
           } else {
             markers.add(Marker(point: pt, width: dotSize, height: dotSize, child: dot));
           }
        }
      }
    }

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                // MAP LAYER with HOVER and DRAG & DROP
                MouseRegion(
                  onHover: _handleHover,
                  cursor: _currentMode == EditorMode.cut 
                      ? SystemMouseCursors.precise 
                      : SystemMouseCursors.basic,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const LatLng(51.509364, -0.128928),
                      initialZoom: 13.0,
                      onTap: _onMapTap,
                    ),
                    children: [
                      TileLayer(
                        tileProvider: CancellableNetworkTileProvider(),
                        urlTemplate: _mapStyleIndex == 0
                            ? 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png'
                            : _mapStyleIndex == 1
                                ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
                                : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.timeinloo.gpx_editor',
                      ),
                      
                      PolylineLayer(polylines: borderPolylines),
                      PolylineLayer(polylines: trackPolylines),

                      // --- NEW: CUT PREVIEW GLOW ---
                      if (_currentMode == EditorMode.cut && _previewGreenPath != null && _previewRedPath != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _previewGreenPath!,
                              strokeWidth: 6.0,
                              color: Colors.greenAccent.withOpacity(0.8),
                            ),
                            Polyline(
                              points: _previewRedPath!,
                              strokeWidth: 6.0,
                              color: Colors.redAccent.withOpacity(0.8),
                            ),
                          ],
                        ),
                      
                      MarkerLayer(markers: [
                        ...markers,
                        if (_currentMode == EditorMode.cut && _previewCutPoint != null)
                          Marker(
                            point: _previewCutPoint!,
                            width: 30, height: 30,
                            child: Transform.translate(
                              offset: const Offset(0, -15),
                              child: const Icon(
                                Icons.content_cut, 
                                color: Colors.white, 
                                size: 24,
                                shadows: [
                                  Shadow(blurRadius: 5, color: Colors.black, offset: Offset(0,0))
                                ],
                              ),
                            ),
                          ),
                      ]),
                    ],
                  ),
                ),
                
                // --- TOOL PALETTE ---
                Positioned(
                  top: 20, left: 20,
                  child: Theme(
                    data: _isDarkTheme ? ThemeData.dark() : ThemeData.light(),
                    child: ToolPalette(
                      onCut: _handleCut,
                      onMove: _handleMove,
                      onExtend: _handleExtend,
                      onReverse: _handleReverse,
                      onDeletePoint: _handleDeletePoint,
                      onSimplify: _handleSimplify,
                      onCreateWaypoint: _handleCreateWaypoint,
                      
                      isCutEnabled: _selectedTrackIds.length == 1,
                      isExtendEnabled: _selectedTrackIds.length == 1,
                      isMoveEnabled: _selectedTrackIds.length == 1,
                      isDeletePointEnabled: _selectedTrackIds.length == 1,
                      isSimplifyEnabled: _selectedTrackIds.length == 1,
                      isCreateWaypointEnabled: _selectedTrackIds.length == 1,
                      isReverseEnabled: _selectedTrackIds.isNotEmpty,
                      
                      activeMode: _currentMode,
                    ),
                  ),
                ),
                
                 if (_currentMode != EditorMode.view)
                   Positioned(
                     bottom: 20, right: 100, 
                     child: Theme(
                       data: _isDarkTheme ? ThemeData.dark() : ThemeData.light(),
                       child: FloatingActionButton.extended(
                         onPressed: () => setState(() => _currentMode = EditorMode.view),
                         label: const Text("Done"),
                         icon: const Icon(Icons.check),
                         backgroundColor: _isDarkTheme ? Colors.green[800] : Colors.green,
                         foregroundColor: Colors.white,
                       ),
                     ),
                   ),

                // --- CONTROLS ---
                Positioned(
                  bottom: 20,
                  right: 20, 
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Zoom & Fit Group
                      Card(
                        elevation: 4,
                        color: _isDarkTheme ? const Color(0xFF424242) : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add), 
                              tooltip: "Zoom In",
                              color: _isDarkTheme ? Colors.white : Colors.black,
                              onPressed: _zoomIn,
                            ),
                            Container(height: 1, width: 30, color: Colors.grey[300]),
                            IconButton(
                              icon: const Icon(Icons.remove), 
                              tooltip: "Zoom Out",
                              color: _isDarkTheme ? Colors.white : Colors.black,
                              onPressed: _zoomOut,
                            ),
                            Container(height: 1, width: 30, color: Colors.grey[300]),
                            IconButton(
                              icon: const Icon(Icons.fit_screen), 
                              tooltip: "Fit Content to Screen",
                              color: _isDarkTheme ? Colors.white : Colors.black,
                              onPressed: _fitToContent,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      
                      // Map Style Toggle
                      FloatingActionButton(
                        mini: true,
                        backgroundColor: _isDarkTheme ? const Color(0xFF424242) : Colors.white,
                        onPressed: () {
                          setState(() {
                            // Cycle: 0 -> 1 -> 2 -> 0
                            _mapStyleIndex = (_mapStyleIndex + 1) % 3;
                          });
                        },
                        tooltip: "Switch Map Layer",
                        child: Icon(
                          _mapStyleIndex == 0 ? Icons.wb_sunny_outlined
                          : _mapStyleIndex == 1 ? Icons.dark_mode       
                          : Icons.satellite_alt,                        
                          
                          color: _isDarkTheme ? Colors.white : Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_statusMessage != null)
                  Positioned(
                    bottom: 30, left: 20,
                    child: Material(
                      elevation: 6.0,
                      borderRadius: BorderRadius.circular(8.0),
                      color: Colors.grey[900]!.withOpacity(0.9),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          _statusMessage!,
                          style: const TextStyle(color: Colors.white, fontSize: 13.0),
                        ),
                      ),
                    ),
                  ),

                if (_isLoading)
                  Container(
                    color: Colors.black.withOpacity(0.3),
                    child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
              ],
            ),
          ),

          // --- PATH LIST + DRAG & DROP ZONE ---
          SizedBox(
            width: 250, 
            child: DropTarget(
              onDragDone: (details) {
                setState(() => _isDraggingFile = false);
                _handleDroppedFiles(details.files);
              },
              onDragEntered: (details) {
                setState(() => _isDraggingFile = true);
              },
              onDragExited: (details) {
                setState(() => _isDraggingFile = false);
              },
              child: Stack(
                children: [
                  Container(
                    color: _isDarkTheme ? const Color(0xFF121212) : Colors.white, 
                    child: Theme(
                      data: _isDarkTheme 
                          ? ThemeData.dark().copyWith(
                              scaffoldBackgroundColor: const Color(0xFF121212),
                              cardColor: const Color(0xFF2C2C2C), 
                              dividerColor: Colors.grey[800],
                              textTheme: ThemeData.dark().textTheme.apply(
                                bodyColor: Colors.white,
                                displayColor: Colors.white,
                              ),
                              iconTheme: const IconThemeData(color: Colors.white),
                              listTileTheme: const ListTileThemeData(
                                textColor: Colors.white,
                                iconColor: Colors.white,
                              ),
                            ) 
                          : ThemeData.light(),
                      child: PathList(
                        tracks: tracks,
                        selectedTrackIds: _selectedTrackIds,
                        onSelect: _handleSelect,
                        onSelectAll: _handleSelectAll,
                        onReorder: _handleReorder,
                        onToggleVisibility: _handleToggleVis,
                        onColorChanged: _handleColorChange,
                        onRename: _handleRename,
                        onImport: _handleImport,
                        onSave: _handleSave,
                        onDelete: _handleDeleteSelected,
                        onJoin: _handleJoin,
                        onGroup: _handleGroup,
                        onCreateNew: _handleCreateNew,
                      ),
                    ),
                  ),

                  // DRAG OVERLAY
                  if (_isDraggingFile)
                    Positioned.fill(
                      child: Container(
                        color: Colors.blue.withOpacity(0.8),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.upload_file, color: Colors.white, size: 48),
                              SizedBox(height: 10),
                              Text(
                                "Drop GPX files here",
                                style: TextStyle(
                                  color: Colors.white, 
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}