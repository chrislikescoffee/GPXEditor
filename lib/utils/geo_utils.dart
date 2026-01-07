import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

class GeoUtils {
  static const Distance _distance = Distance();

  /// Finds the split index and exact point on the polyline closest to [clickPoint].
  /// Returns a record: (index of the point BEFORE the cut, exact split LatLng).
  /// Returns null if the click is too far away (threshold in meters).
  static (int, LatLng)? findNearestPointOnLine(
      LatLng clickPoint, List<LatLng> polyline, {double thresholdMeters = 100}) {
    
    if (polyline.length < 2) return null;

    double minDistance = double.infinity;
    int closestIndex = -1;
    LatLng closestPoint = const LatLng(0, 0);

    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i+1];
      
      // Find nearest point on this specific segment
      final projected = _projectPointOnSegment(clickPoint, p1, p2);
      
      // Calculate distance from click to that projected point
      final dist = _distance.as(LengthUnit.Meter, clickPoint, projected);

      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
        closestPoint = projected;
      }
    }

    if (minDistance > thresholdMeters) return null;

    return (closestIndex, closestPoint);
  }

  /// Simplifies the path using the Ramer-Douglas-Peucker algorithm.
  /// [epsilon] is the maximum distance (in meters) a point can deviate from the line 
  /// between its neighbors before it is kept.
  static List<LatLng> simplifyTrack(List<LatLng> points, double epsilon) {
    if (points.length < 3) return List.from(points);

    // Find the point with the maximum distance
    double maxDistance = 0;
    int index = 0;
    int end = points.length - 1;

    for (int i = 1; i < end; i++) {
      double d = _perpendicularDistance(points[i], points[0], points[end]);
      if (d > maxDistance) {
        maxDistance = d;
        index = i;
      }
    }

    // If max distance is greater than epsilon, recursively simplify
    if (maxDistance > epsilon) {
      List<LatLng> recResults1 = simplifyTrack(points.sublist(0, index + 1), epsilon);
      List<LatLng> recResults2 = simplifyTrack(points.sublist(index, end + 1), epsilon);

      // Build the result list
      List<LatLng> result = List.from(recResults1);
      result.removeLast(); // Remove duplicate point where segments meet
      result.addAll(recResults2);
      return result;
    } else {
      return [points[0], points[end]];
    }
  }

  // --- INTERNAL HELPERS ---

  // Calculate perpendicular distance from point P to line segment AB
  static double _perpendicularDistance(LatLng p, LatLng a, LatLng b) {
    // Project p onto the line AB
    LatLng projected = _projectPointOnSegment(p, a, b);
    // Measure distance in meters
    return _distance.as(LengthUnit.Meter, p, projected);
  }

  // Math to project point P onto line segment AB
  static LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final double x = p.longitude;
    final double y = p.latitude;
    final double x1 = a.longitude;
    final double y1 = a.latitude;
    final double x2 = b.longitude;
    final double y2 = b.latitude;

    final double C = x2 - x1;
    final double D = y2 - y1;

    final double dot = (x - x1) * C + (y - y1) * D;
    final double lenSq = C * C + D * D;
    
    if (lenSq == 0) return a; // Points a and b are the same

    double param = dot / lenSq;

    // Clamp param to segment [0, 1]
    if (param < 0) param = 0;
    else if (param > 1) param = 1;

    final double xx = x1 + param * C;
    final double yy = y1 + param * D;

    return LatLng(yy, xx);
  }
}