import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/cashgo_api.dart';

/// Nearest cash-pickup agents rendered on an OSM map via flutter_map.
/// Swap in google_maps_flutter by replacing the map widget only — markers list
/// stays identical.
class AgentsMapScreen extends StatefulWidget {
  final String destCountry;
  final LatLng initialCenter; // device location or corridor capital
  const AgentsMapScreen({
    super.key,
    required this.destCountry,
    this.initialCenter = const LatLng(6.5244, 3.3792), // Lagos default
  });

  @override
  State<AgentsMapScreen> createState() => _AgentsMapScreenState();
}

class _AgentsMapScreenState extends State<AgentsMapScreen> {
  final _api = CashGoApi();
  List<dynamic> _agents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final agents = await _api.nearestAgents(
        latitude: widget.initialCenter.latitude,
        longitude: widget.initialCenter.longitude,
        destCountry: widget.destCountry,
      );
      setState(() {
        _agents = agents;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.initialCenter;
    return Scaffold(
      appBar: AppBar(title: const Text('Pickup Agents')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: FlutterMap(
                    options: MapOptions(initialCenter: center, initialZoom: 12),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.cashgo.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: center,
                            child: const Icon(Icons.my_location,
                                color: Colors.blue),
                          ),
                          for (final a in _agents)
                            Marker(
                              point: LatLng(a['latitude'], a['longitude']),
                              width: 90,
                              height: 60,
                              child: Column(
                                children: [
                                  const Icon(Icons.store,
                                      color: Colors.green, size: 28),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    color: Colors.white,
                                    child: Text(
                                      '${(a['distance_m'] / 1000).toStringAsFixed(1)} km',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ListView.builder(
                    itemCount: _agents.length,
                    itemBuilder: (_, i) {
                      final a = _agents[i];
                      final hours = (a['operating_hours'] as Map)
                          .entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join(' · ');
                      return ListTile(
                        leading: const Icon(Icons.store, color: Colors.green),
                        title: Text(a['agent_name']),
                        subtitle:
                            Text('${a['city']} · ${a['address'] ?? ''}\n$hours'),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                '${(a['distance_m'] / 1000).toStringAsFixed(1)} km'),
                            IconButton(
                              icon: const Icon(Icons.directions),
                              onPressed: () => launchUrl(Uri.parse(
                                'https://www.google.com/maps/dir/?api=1'
                                '&destination=${a['latitude']},${a['longitude']}',
                              )),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
