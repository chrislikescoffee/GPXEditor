import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import 'package:cross_file/cross_file.dart'; // For Drag & Drop
import 'package:universal_html/html.dart' as html; // Required for Web Download

// --- DATA MODELS ---
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

class GpxImportData {
  final List<ImportedTrack> tracks;
  final List<ImportedWaypoint> waypoints;
  GpxImportData({required this.tracks, required this.waypoints});
}

// --- SERVICE CLASS ---
class GpxService {
  
  // 1. IMPORT VIA BUTTON (File Picker)
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

          if (xmlString.isNotEmpty) {
            final data = _parseRawGpx(xmlString, fallbackName);
            parsedTracks.addAll(data.tracks);
            parsedWaypoints.addAll(data.waypoints);
          }
        } catch (e) {
          print("Error parsing GPX file ${file.name}: $e");
        }
      }
    }
    return GpxImportData(tracks: parsedTracks, waypoints: parsedWaypoints);
  }

  // 2. IMPORT VIA DRAG & DROP
  Future<GpxImportData> parseDragDropFiles(List<XFile> files) async {
    List<ImportedTrack> parsedTracks = [];
    List<ImportedWaypoint> parsedWaypoints = [];

    for (var file in files) {
      if (!file.name.toLowerCase().endsWith('.gpx')) continue;

      String fallbackName = file.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), '');
      try {
        String xmlString = await file.readAsString();
        if (xmlString.isNotEmpty) {
           final data = _parseRawGpx(xmlString, fallbackName);
           parsedTracks.addAll(data.tracks);
           parsedWaypoints.addAll(data.waypoints);
        }
      } catch (e) {
        print("Error reading dropped file ${file.name}: $e");
      }
    }

    return GpxImportData(tracks: parsedTracks, waypoints: parsedWaypoints);
  }

  // 3. SHARED PARSING LOGIC
  GpxImportData _parseRawGpx(String xmlString, String fallbackName) {
    List<ImportedTrack> tracks = [];
    List<ImportedWaypoint> waypoints = [];

    final gpx = GpxReader().fromString(xmlString);

    // Parse Tracks
    for (var trk in gpx.trks) {
      List<List<LatLng>> trackSegments = [];
      for (var seg in trk.trksegs) {
        List<LatLng> segmentPoints = seg.trkpts
            .map((pt) => LatLng(pt.lat!, pt.lon!))
            .toList();
        if (segmentPoints.isNotEmpty) trackSegments.add(segmentPoints);
      }

      if (trackSegments.isNotEmpty) {
        String finalName = (trk.name != null && trk.name!.isNotEmpty) 
            ? trk.name! 
            : fallbackName;

        tracks.add(ImportedTrack(
          name: finalName,
          segments: trackSegments,
        ));
      }
    }

    // Parse Waypoints
    for (var wpt in gpx.wpts) {
      if (wpt.lat != null && wpt.lon != null) {
        String? linkUrl;
        if (wpt.links.isNotEmpty) linkUrl = wpt.links.first.href;

        waypoints.add(ImportedWaypoint(
          name: wpt.name ?? fallbackName,
          point: LatLng(wpt.lat!, wpt.lon!),
          description: wpt.desc,
          comment: wpt.cmt,
          symbol: wpt.sym,
          link: linkUrl,
        ));
      }
    }

    return GpxImportData(tracks: tracks, waypoints: waypoints);
  }

  // 4. EXPORT LOGIC
  Future<void> exportGpx(String filename, List<dynamic> tracks, List<dynamic> waypoints) async {
    final gpx = Gpx();
    gpx.creator = "TimeInLoo GPX Editor";

    // Convert Tracks
    for (var t in tracks) {
      final trk = Trk();
      trk.name = t.name;
      
      for (var segPoints in t.segments) {
        final seg = Trkseg();
        for (var pt in segPoints) {
          seg.trkpts.add(Wpt(lat: pt.latitude, lon: pt.longitude));
        }
        trk.trksegs.add(seg);
      }
      gpx.trks.add(trk);
    }

    // Convert Waypoints
    for (var w in waypoints) {
      final wpt = Wpt(
        lat: w.point.latitude,
        lon: w.point.longitude,
        name: w.name,
        desc: w.description,
        cmt: w.comment,
        sym: w.symbol,
      );
      if (w.link != null && w.link!.isNotEmpty) {
        wpt.links.add(Link(href: w.link!));
      }
      gpx.wpts.add(wpt);
    }

    final xmlString = GpxWriter().asString(gpx, pretty: true);

    // Trigger Download (Web)
    if (kIsWeb) {
      final bytes = utf8.encode(xmlString);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", "$filename.gpx")
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      // Basic print for non-web environments just in case
      print("Export content generated for $filename.gpx");
    }
  }
}