import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  
  // Color Palette
  final List<Color> _trackColors = [
    Colors.blue, Colors.orange, Colors.purple, Colors.green, 
    Colors.teal, Colors.red, Colors.pink, Colors.indigo, 
    Colors.amber, Colors.brown, Colors.cyan, Colors.lime
  ];

  // State
  EditorMode _currentMode = EditorMode.view;
  bool? _extendFromEnd; 
  
  // UI State
  bool _isLoading = false;
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

  // --- FILE ACTIONS ---

  Future<void> _handleImport() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 50)); 

    try {
      final importData = await _gpxService.importFiles();
      
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

      // Zoom to fit
      if (tracks.isNotEmpty && tracks.last.segments.isNotEmpty && tracks.last.segments.first.isNotEmpty) {
        _mapController.move(tracks.last.segments.first.first, 16.0);
      } else if (waypoints.isNotEmpty) {
        _mapController.move(waypoints.last.point, 16.0);
      }
      
      _showStatus("Imported ${importData.tracks.length} tracks, ${importData.waypoints.length} waypoints.");

    } catch (e) {
      _showStatus("Error importing files: $e");
    } finally {
      setState(() => _isLoading = false);
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

  void _handleSave() {
    if (tracks.isEmpty && waypoints.isEmpty) {
      _showStatus("Nothing to export.");
      return;
    }

    TextEditingController nameCtrl = TextEditingController(text: "my_route");
    
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Export GPX"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter a name for your file:"),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(suffixText: ".gpx"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop(); 
                final name = nameCtrl.text.isEmpty ? "export" : nameCtrl.text;
                try {
                  setState(() => _isLoading = true);
                  await _gpxService.exportGpx(name, tracks, waypoints);
                  _showStatus("File exported successfully.");
                } catch (e) {
                  _showStatus("Export failed: $e");
                } finally {
                  setState(() => _isLoading = false);
                }
              },
              child: const Text("Export"),
            ),
          ],
        );
      },
    );
  }

  // --- TRACK TOOLS ---

  void _handleCreateNew() {
    setState(() {
      _currentMode = EditorMode.create;
      final newTrack = TrackData.create(
        name: _getUniqueName("New Route"),
        color: Colors.red,
        segments: [[]],
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
    });
    _showStatus("Track split successfully.");
  }

  void _handleJoin() {
    if (_selectedTrackIds.length < 2) return;
    setState(() {
      List<TrackData> tracksToJoin = tracks.where((t) => _selectedTrackIds.contains(t.id)).toList();
      tracksToJoin.sort((a, b) => tracks.indexOf(a).compareTo(tracks.indexOf(b)));

      List<List<LatLng>> mergedSegments = [];
      for (var t in tracksToJoin) {
        mergedSegments.addAll(t.segments);
      }

      final firstTrack = tracksToJoin.first;
      final newTrack = TrackData.create(
        name: "${firstTrack.name} (Merged)",
        color: firstTrack.color,
        segments: mergedSegments,
      );

      for (var t in tracksToJoin) tracks.remove(t);
      tracks.insert(0, newTrack);
      _selectedTrackIds.clear();
      _selectedTrackIds.add(newTrack.id);
    });
    _showStatus("Tracks joined successfully.");
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
    });

    _showStatus("Simplified: Removed ${totalPointsBefore - totalPointsAfter} points.");
  }

  void _updatePointPosition(int segIndex, int pointIndex, Offset globalPosition) {
    if (_primarySelectedTrack == null) return;
    final point = math.Point(globalPosition.dx, globalPosition.dy);
    final newLatLng = _mapController.camera.pointToLatLng(point);
    setState(() {
      _primarySelectedTrack!.segments[segIndex][pointIndex] = newLatLng;
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
        
        // Controllers for editing
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
                          // EDIT MODE FIELDS
                          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
                          TextField(controller: descCtrl, decoration: const InputDecoration(labelText: "Description")),
                          TextField(controller: cmtCtrl, decoration: const InputDecoration(labelText: "Comment")),
                          TextField(controller: symCtrl, decoration: const InputDecoration(labelText: "Symbol (e.g. Parking)")),
                          TextField(controller: linkCtrl, decoration: const InputDecoration(labelText: "Link URL")),
                        ]
                      : [
                          // VIEW MODE FIELDS
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
    });
  }

  void _handleRename(String id, String name) {
    setState(() {
      final track = tracks.firstWhere((t) => t.id == id);
      track.name = name;
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
    // 1. Prepare Layers (FLATTEN SEGMENTS FOR POLYLINE)
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
            color: Colors.white, borderColor: Colors.black, borderStrokeWidth: 1.0, 
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
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
                child: Text(wpt.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(51.509364, -0.128928),
                    initialZoom: 13.0,
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.gpx_editor',
                    ),
                    PolylineLayer(polylines: borderPolylines),
                    PolylineLayer(polylines: trackPolylines),
                    MarkerLayer(markers: markers),
                  ],
                ),
                
                Positioned(
                  top: 20, left: 20,
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
                
                 if (_currentMode != EditorMode.view)
                   Positioned(
                     bottom: 20, right: 20,
                     child: FloatingActionButton.extended(
                       onPressed: () => setState(() => _currentMode = EditorMode.view),
                       label: const Text("Done"),
                       icon: const Icon(Icons.check),
                       backgroundColor: Colors.green,
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

          SizedBox(
            width: 250, 
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
              onCreateNew: _handleCreateNew,
            ),
          ),
        ],
      ),
    );
  }
}