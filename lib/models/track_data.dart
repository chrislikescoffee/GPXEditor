import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

class TrackData {
  final String id;
  String name;
  Color color;
  
  // NEW: A list of segments, where each segment is a list of points.
  List<List<LatLng>> segments; 
  
  bool isVisible;
  bool isSaved;

  TrackData({
    required this.id,
    required this.name,
    required this.color,
    required this.segments,
    this.isVisible = true,
    this.isSaved = false,
    
  });

  factory TrackData.create({
    required String name,
    required Color color,
    required List<List<LatLng>> segments,
    bool isSaved = false,
  }) {
    return TrackData(
      id: const Uuid().v4(),
      name: name,
      color: color,
      segments: segments,
      isVisible: true,
    );
  }

  // Helper: Flattens all segments into one list (useful for simple calculations)
  List<LatLng> get flattenedPoints {
    return segments.expand((element) => element).toList();
  }
}