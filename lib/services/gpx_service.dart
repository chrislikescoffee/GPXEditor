import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart'; 
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';

import '../models/track_data.dart';
import '../models/waypoint_data.dart';

// 1. CONTAINER CLASS 
class GpxImportData {
  final List<ImportedTrack> tracks;
  final List<ImportedWaypoint> waypoints;

  GpxImportData({required this.tracks, required this.waypoints});
}

// 2. HELPER MODELS
class ImportedTrack {
  final String name;
  final List<List<LatLng>> segments;

  ImportedTrack({required this.name, required this.segments});
}

class ImportedWaypoint {
  final String name;
  final LatLng point;
  final String? description;
  final String? comment;
  final String? symbol;
  final String? link;

  ImportedWaypoint({
    required this.name, 
    required this.point, 
    this.description,
    this.comment,
    this.symbol,
    this.link,
  });
}

// 3. SERVICE LOGIC
class GpxService {
  
  // --- IMPORT ---
Future<GpxImportData> importFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['gpx'],
      withData: true, 
    );

    List<ImportedTrack> parsedTracks = [];
    List<ImportedWaypoint> parsedWaypoints = [];

    if (result != null) {
      for (var file in result.files) {
        String xmlString = "";

        // Get Filename without extension (e.g. "MyRoute.gpx" -> "MyRoute")
        String fallbackName = file.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), '');

        try {
          if (kIsWeb) {
            if (file.bytes != null) xmlString = utf8.decode(file.bytes!);
          } else {
            if (file.path != null) {
              final ioFile = File(file.path!);
              xmlString = await ioFile.readAsString();
            }
          }

          if (xmlString.isEmpty) continue;

          final gpx = GpxReader().fromString(xmlString);

          // A. Parse Tracks
          for (var trk in gpx.trks) {
            List<List<LatLng>> trackSegments = [];
            for (var seg in trk.trksegs) {
              List<LatLng> segmentPoints = seg.trkpts
                  .map((pt) => LatLng(pt.lat!, pt.lon!))
                  .toList();
              if (segmentPoints.isNotEmpty) trackSegments.add(segmentPoints);
            }

            if (trackSegments.isNotEmpty) {
              // LOGIC FIX: Use filename if internal name is empty or null
              String finalName = (trk.name != null && trk.name!.isNotEmpty) 
                  ? trk.name! 
                  : fallbackName;

              parsedTracks.add(ImportedTrack(
                name: finalName,
                segments: trackSegments,
              ));
            }
          }

          // B. Parse Waypoints
          for (var wpt in gpx.wpts) {
             // ... (Keep existing waypoint logic) ...
             if (wpt.lat != null && wpt.lon != null) {
              String? linkUrl;
              if (wpt.links.isNotEmpty) linkUrl = wpt.links.first.href;

              parsedWaypoints.add(ImportedWaypoint(
                name: wpt.name ?? fallbackName, // Use filename as fallback for Waypoints too
                point: LatLng(wpt.lat!, wpt.lon!),
                description: wpt.desc,
                comment: wpt.cmt,
                symbol: wpt.sym,
                link: linkUrl,
              ));
            }
          }
        } catch (e) {
          print("Error parsing GPX file ${file.name}: $e");
        }
      }
    }

    return GpxImportData(tracks: parsedTracks, waypoints: parsedWaypoints);
  }
  
  // --- EXPORT ---
  Future<void> exportGpx(String fileName, List<TrackData> tracks, List<WaypointData> waypoints) async {
    final gpx = Gpx();
    gpx.creator = "Flutter GPX Editor";
    gpx.metadata = Metadata(
      time: DateTime.now(),
      name: fileName,
    );

    // 1. Convert Waypoints
    gpx.wpts = waypoints.where((w) => w.isVisible).map((wpt) {
      final w = Wpt(
        lat: wpt.point.latitude,
        lon: wpt.point.longitude,
        name: wpt.name,
        desc: wpt.description,
        cmt: wpt.comment,
        sym: wpt.symbol,
      );
      if (wpt.link != null && wpt.link!.isNotEmpty) {
        w.links = [Link(href: wpt.link!)];
      }
      return w;
    }).toList();

    // 2. Convert Tracks
    gpx.trks = tracks.where((t) => t.isVisible).map((trackData) {
      final trk = Trk(name: trackData.name);
      trk.trksegs = trackData.segments.map((segmentPoints) {
        return Trkseg(
          trkpts: segmentPoints.map((p) => Wpt(
            lat: p.latitude,
            lon: p.longitude,
          )).toList(),
        );
      }).toList();
      return trk;
    }).toList();

    // 3. Generate XML
    final xmlString = GpxWriter().asString(gpx, pretty: true);
    final List<int> bytes = utf8.encode(xmlString);

    // 4. Save File (FIXED FOR VERSION 0.3.1)
    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: Uint8List.fromList(bytes),
      fileExtension: 'gpx',    // Replaced 'ext' with 'fileExtension'
      mimeType: MimeType.text, // Kept this as is
    );
  }
}