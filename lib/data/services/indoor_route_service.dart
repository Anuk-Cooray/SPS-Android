
/// Represents a location in the sample parking layout.
class IndoorRouteNode {
  final String id;
  final String label;

  const IndoorRouteNode({
    required this.id,
    required this.label,
  });
}

/// Represents a walkable connection between two locations.
class IndoorRouteEdge {
  final String from;
  final String to;
  final double distanceMeters;

  const IndoorRouteEdge({
    required this.from,
    required this.to,
    required this.distanceMeters,
  });
}

/// Contains the calculated route and walking instructions.
class IndoorRouteResult {
  final List<IndoorRouteNode> nodes;
  final double totalDistanceMeters;
  final List<String> instructions;

  const IndoorRouteResult({
    required this.nodes,
    required this.totalDistanceMeters,
    required this.instructions,
  });

  List<String> get nodeIds => nodes.map((node) => node.id).toList();
}

/// Calculates a shortest walking route through the sample
/// parking layout using Dijkstra's algorithm.
///
/// Distances are illustrative, not measured real-world distances.
class IndoorRouteService {
  static const String entranceId = 'entrance';

  final Map<String, IndoorRouteNode> _nodes = {
    'entrance': const IndoorRouteNode(
      id: 'entrance',
      label: 'Main Entrance',
    ),
    'junction_a': const IndoorRouteNode(
      id: 'junction_a',
      label: 'Junction A',
    ),
    'junction_b': const IndoorRouteNode(
      id: 'junction_b',
      label: 'Junction B',
    ),
    'junction_c': const IndoorRouteNode(
      id: 'junction_c',
      label: 'Junction C',
    ),
    'aisle_west': const IndoorRouteNode(
      id: 'aisle_west',
      label: 'West Aisle',
    ),
    'aisle_center': const IndoorRouteNode(
      id: 'aisle_center',
      label: 'Central Aisle',
    ),
    'aisle_east': const IndoorRouteNode(
      id: 'aisle_east',
      label: 'East Aisle',
    ),
    'sector_1': const IndoorRouteNode(
      id: 'sector_1',
      label: 'Sector 1',
    ),
    'sector_2': const IndoorRouteNode(
      id: 'sector_2',
      label: 'Sector 2',
    ),
    'sector_3': const IndoorRouteNode(
      id: 'sector_3',
      label: 'Sector 3',
    ),
    'sector_4': const IndoorRouteNode(
      id: 'sector_4',
      label: 'Sector 4',
    ),
    'sector_5': const IndoorRouteNode(
      id: 'sector_5',
      label: 'Sector 5',
    ),
    'sector_6': const IndoorRouteNode(
      id: 'sector_6',
      label: 'Sector 6',
    ),
    'sector_7': const IndoorRouteNode(
      id: 'sector_7',
      label: 'Sector 7',
    ),
  };

  final List<IndoorRouteEdge> _edges = const [
    IndoorRouteEdge(
      from: 'entrance',
      to: 'junction_a',
      distanceMeters: 12,
    ),
    IndoorRouteEdge(
      from: 'junction_a',
      to: 'aisle_west',
      distanceMeters: 10,
    ),
    IndoorRouteEdge(
      from: 'junction_a',
      to: 'aisle_center',
      distanceMeters: 15,
    ),
    IndoorRouteEdge(
      from: 'aisle_center',
      to: 'junction_b',
      distanceMeters: 8,
    ),
    IndoorRouteEdge(
      from: 'junction_b',
      to: 'aisle_west',
      distanceMeters: 12,
    ),
    IndoorRouteEdge(
      from: 'junction_b',
      to: 'aisle_east',
      distanceMeters: 14,
    ),
    IndoorRouteEdge(
      from: 'junction_b',
      to: 'sector_3',
      distanceMeters: 6,
    ),
    IndoorRouteEdge(
      from: 'junction_b',
      to: 'sector_4',
      distanceMeters: 7,
    ),
    IndoorRouteEdge(
      from: 'aisle_east',
      to: 'junction_c',
      distanceMeters: 9,
    ),
    IndoorRouteEdge(
      from: 'aisle_east',
      to: 'sector_5',
      distanceMeters: 5,
    ),
    IndoorRouteEdge(
      from: 'junction_c',
      to: 'sector_6',
      distanceMeters: 6,
    ),
    IndoorRouteEdge(
      from: 'junction_c',
      to: 'sector_7',
      distanceMeters: 8,
    ),
    IndoorRouteEdge(
      from: 'aisle_west',
      to: 'sector_1',
      distanceMeters: 5,
    ),
    IndoorRouteEdge(
      from: 'aisle_west',
      to: 'sector_2',
      distanceMeters: 7,
    ),
  ];

  /// Calculates the shortest route from [startNodeId] to a sector.
  ///
  /// [slotId] is included in the final instruction. This graph
  /// navigates to a sector rather than an individual parking bay.
  IndoorRouteResult calculateRoute({
    required int destinationSector,
    required String slotId,
    String startNodeId = entranceId,
  }) {
    if (destinationSector < 1 || destinationSector > 7) {
      throw ArgumentError.value(
        destinationSector,
        'destinationSector',
        'Sector must be between 1 and 7.',
      );
    }

    if (slotId.trim().isEmpty) {
      throw ArgumentError.value(
        slotId,
        'slotId',
        'A parking slot ID is required.',
      );
    }

    if (!_nodes.containsKey(startNodeId)) {
      throw ArgumentError.value(
        startNodeId,
        'startNodeId',
        'Starting location does not exist in the parking layout.',
      );
    }

    final destinationId = 'sector_$destinationSector';

    final distances = <String, double>{
      for (final id in _nodes.keys) id: double.infinity,
    };

    final previous = <String, String>{};
    final visited = <String>{};

    final adjacency = <String, List<IndoorRouteEdge>>{
      for (final id in _nodes.keys) id: <IndoorRouteEdge>[],
    };

    for (final edge in _edges) {
      if (!_nodes.containsKey(edge.from) ||
          !_nodes.containsKey(edge.to) ||
          edge.distanceMeters <= 0) {
        throw StateError('The parking graph contains an invalid edge.');
      }

      adjacency[edge.from]!.add(edge);

      adjacency[edge.to]!.add(
        IndoorRouteEdge(
          from: edge.to,
          to: edge.from,
          distanceMeters: edge.distanceMeters,
        ),
      );
    }

    distances[startNodeId] = 0;

    while (true) {
      String? current;
      var shortestDistance = double.infinity;

      for (final id in _nodes.keys) {
        if (!visited.contains(id) &&
            distances[id]! < shortestDistance) {
          current = id;
          shortestDistance = distances[id]!;
        }
      }

      if (current == null) break;
      if (current == destinationId) break;

      visited.add(current);

      for (final edge in adjacency[current]!) {
        if (visited.contains(edge.to)) continue;

        final alternative =
            distances[current]! + edge.distanceMeters;

        if (alternative < distances[edge.to]!) {
          distances[edge.to] = alternative;
          previous[edge.to] = current;
        }
      }
    }

    if (distances[destinationId] == double.infinity) {
      throw StateError(
        'No route found to Sector $destinationSector.',
      );
    }

    final pathIds = <String>[];
    String? current = destinationId;

    while (current != null) {
      pathIds.add(current);

      if (current == startNodeId) break;

      current = previous[current];
    }

    if (pathIds.isEmpty || pathIds.last != startNodeId) {
      throw StateError('Could not reconstruct the walking route.');
    }

    final orderedIds = pathIds.reversed.toList();
    final routeNodes = orderedIds.map((id) => _nodes[id]!).toList();

    final instructions = <String>[
      'Start at ${routeNodes.first.label}.',
    ];

    for (var i = 1; i < routeNodes.length; i++) {
      instructions.add('Continue to ${routeNodes[i].label}.');
    }

    instructions.add(
      'Enter Sector $destinationSector and locate '
      'your booked slot ${slotId.trim()}.',
    );

    return IndoorRouteResult(
      nodes: routeNodes,
      totalDistanceMeters: distances[destinationId]!,
      instructions: instructions,
    );
  }
}
