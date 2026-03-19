import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/cuidador_location_model.dart';

class CuidadorMapCard extends StatefulWidget {
  final CuidadorLocationState? locationState;
  final List<CuidadorLocationPoint> routePoints;
  final bool routeEnabled;
  final VoidCallback onToggleRoute;
  final VoidCallback onRefresh;

  const CuidadorMapCard({
    super.key,
    required this.locationState,
    required this.routePoints,
    required this.routeEnabled,
    required this.onToggleRoute,
    required this.onRefresh,
  });

  @override
  State<CuidadorMapCard> createState() => _CuidadorMapCardState();
}

class _CuidadorMapCardState extends State<CuidadorMapCard> {
  final MapController _mapController = MapController();
  double _currentZoom = 15;

  void _zoomBy(double delta, LatLng center) {
    final nextZoom = (_currentZoom + delta).clamp(3.0, 18.0);
    _mapController.move(center, nextZoom);
    setState(() {
      _currentZoom = nextZoom;
    });
  }

  void _centerOnLatest(LatLng center) {
    _mapController.move(center, _currentZoom);
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.locationState?.latest;
    final hasPoint = latest != null;
    final center = hasPoint
        ? LatLng(latest.lat, latest.lng)
        : const LatLng(19.4326, -99.1332);
    final initialZoom = hasPoint ? 15.0 : 5.0;
    final route = widget.routePoints.map((e) => LatLng(e.lat, e.lng)).toList();

    if ((_currentZoom - initialZoom).abs() > 10) {
      _currentZoom = initialZoom;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_pin, color: Color(0xFFE0427A)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ubicacion del Adulto Mayor',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF20304D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 280,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: initialZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onMapEvent: (event) {
                        setState(() {
                          _currentZoom = event.camera.zoom;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.eva_mobile',
                      ),
                      if (widget.routeEnabled && route.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: route,
                              strokeWidth: 5,
                              color: const Color(0xFFFF7A1A),
                            ),
                          ],
                        ),
                      if (hasPoint)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: center,
                              width: 44,
                              height: 44,
                              child: const Icon(
                                Icons.location_on,
                                color: Color(0xFF16B7D6),
                                size: 44,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      children: [
                        _ZoomButton(
                          icon: Icons.add,
                          onTap: () => _zoomBy(1, center),
                        ),
                        const SizedBox(height: 8),
                        _ZoomButton(
                          icon: Icons.remove,
                          onTap: () => _zoomBy(-1, center),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PillButton(
                label: widget.routeEnabled ? 'Ruta ON' : 'Ruta OFF',
                active: widget.routeEnabled,
                onTap: widget.onToggleRoute,
              ),
              const SizedBox(width: 10),
              _PillButton(
                label: 'Centrar',
                active: false,
                onTap: hasPoint ? () => _centerOnLatest(center) : () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ZoomButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.95),
      borderRadius: BorderRadius.circular(12),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            color: const Color(0xFF344054),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFF7A1A) : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? const Color(0xFFFF7A1A) : const Color(0xFFD0D5DD),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF344054),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
