import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

class WaypointData {
  final String id;
  String name;
  LatLng point;
  String? description;
  String? comment; // NEW
  String? symbol;  // NEW
  String? link;    // NEW
  Color color;
  bool isVisible;

  WaypointData({
    required this.id,
    required this.name,
    required this.point,
    this.description,
    this.comment,
    this.symbol,
    this.link,
    this.color = Colors.red,
    this.isVisible = true,
  });

  factory WaypointData.create({
    required String name,
    required LatLng point,
    Color color = Colors.red,
    String? description,
    String? comment,
    String? symbol,
    String? link,
  }) {
    return WaypointData(
      id: const Uuid().v4(),
      name: name,
      point: point,
      color: color,
      description: description,
      comment: comment,
      symbol: symbol,
      link: link,
    );
  }
}