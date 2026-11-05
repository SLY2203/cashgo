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
  const AgentsMapScreen({super.key, this.destCountry = 'ZA'});

  @override
  State<AgentsMapScreen> createState() => _AgentsMapScreenState();
}

class _AgentsMapScreenState extends State<AgentsMapScreen> {
  final _api = CashGoApi();
  final _mapCtrl = MapController();

  static const _countries = {
    'ZM': ('Zambia', LatLng(-15.4167, 28.2830)),     // Lusaka
    'TZ': ('Tanzania', LatLng(-6.8235, 39.2722)),    // Dar es Salaam
    'ZA': ('South Africa', LatLng(-26.2041, 28.0473)), // Johannesburg
    'ZW': ('Zimbabwe', LatLng(-17.8252, 31.0535)),   // Harare
  };

  late String _country = widget.destCountry;
  List<dynamic> _agents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  LatLng get _center => _countries[_country]!.$2;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final agents = await _api.nearestAgents(
        latitude: _center.latitude,
        longitude: _center.longitude,
        destCountry: _country,
        radiusMeters: 100000, // country-scale for sparse agent networks
      );
      setState(() {
        _agents = agents;
        _loading = false;
      });
      try {
        _mapCtrl.move(_center, 11);
      } catch (_) {/* map not laid out yet — initialCenter covers first load */}
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pickup Agents')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final e in _countries.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value.$1),
                      selected: _country == e.key,
                      onSelected: (_) {
                        setState(() => _country = e.key);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(initialCenter: _center, initialZoom: 11),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.cashgo.app',
                ),
                MarkerLayer(
                  markers: [
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _agents.isEmpty
                    ? const Center(child: Text('No agents in this country yet'))
                    : ListView.builder(
                        itemCount: _agents.length,
                        itemBuilder: (_, i) {
                          final a = _agents[i];
                          final hours = (a['operating_hours'] as Map)
                              .entries
                              .map((e) => '${e.key}: ${e.value}')
                              .join(' · ');
                          return ListTile(
                            leading: const Icon(Icons.store,
                                color: Colors.green),
                            title: Text(a['agent_name']),
                            subtitle: Text(
                                '${a['city']} · ${(a['supported_currencies'] as List).join('/')}\n$hours'),
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
