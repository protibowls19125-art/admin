import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../theme/bauhaus_theme.dart';
import 'bauhaus_button.dart';

/// What the map picker hands back to the checkout form.
class LocationPickerResult {
  final double latitude;
  final double longitude;

  /// Single-line, human-readable address (best effort from reverse geocoding).
  final String formattedAddress;

  /// Parsed components used to pre-fill the address fields.
  final String addressLine; // house/road/area
  final String city;
  final String pincode;

  const LocationPickerResult({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    required this.addressLine,
    required this.city,
    required this.pincode,
  });

  /// Shareable maps link the admin/rider can tap to navigate.
  String get mapsLink =>
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
}

/// Full-screen "drop a pin" delivery location picker (Zomato/Swiggy style),
/// backed by free OpenStreetMap tiles + Nominatim geocoding — no API key.
class LocationPickerPage extends StatefulWidget {
  /// Where to center the map initially (e.g. a previously picked spot).
  final LatLng? initialLocation;

  const LocationPickerPage({super.key, this.initialLocation});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  // Default to a central India view until we know better.
  static const _fallbackCenter = LatLng(20.5937, 78.9629);

  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();

  LatLng _center = _fallbackCenter;
  double _zoom = 16;
  String _address = 'Move the map to pin your location';
  LocationPickerResult? _resolved;
  bool _resolving = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _center = widget.initialLocation!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reverseGeocode());
    } else {
      // Do NOT auto-request GPS on open — that fired a browser permission
      // prompt every single time the picker was shown (and again on every
      // reopen). Location is only requested when the user taps "Use my
      // location"; otherwise they can search or tap/drag the pin.
      _zoom = 5;
      _address = "Search, tap the map, or use 'My location'";
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Reverse geocode (coords → address) ────────────────────────────────────
  Future<void> _reverseGeocode() async {
    setState(() => _resolving = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': _center.latitude.toString(),
        'lon': _center.longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': 'MProtiDining/1.0 (delivery location picker)',
        'Accept': 'application/json',
      });
      if (res.statusCode != 200) throw Exception('geocode ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      _resolved = _parse(body);
      _address = _resolved?.formattedAddress ?? 'Selected location';
    } catch (_) {
      // Still allow confirming with raw coordinates.
      _resolved = LocationPickerResult(
        latitude: _center.latitude,
        longitude: _center.longitude,
        formattedAddress:
            '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
        addressLine: '',
        city: '',
        pincode: '',
      );
      _address = "Couldn't fetch address — pin location saved";
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  LocationPickerResult _parse(Map<String, dynamic> body) {
    final a = (body['address'] as Map?)?.cast<String, dynamic>() ?? {};
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = a[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      return '';
    }

    final line = [
      pick(['house_number']),
      pick(['road', 'pedestrian', 'footway', 'neighbourhood']),
      pick(['suburb', 'quarter', 'residential']),
    ].where((s) => s.isNotEmpty).join(', ');

    final city = pick(['city', 'town', 'village', 'municipality', 'county']);
    final pincode = pick(['postcode']);

    return LocationPickerResult(
      latitude: _center.latitude,
      longitude: _center.longitude,
      formattedAddress:
          (body['display_name'] ?? '$line $city $pincode').toString(),
      addressLine: line,
      city: city,
      pincode: pincode,
    );
  }

  // ── Forward geocode (search box → coords) ─────────────────────────────────
  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _resolving = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': query.trim(),
        'limit': '1',
        'addressdetails': '1',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': 'MProtiDining/1.0 (delivery location picker)',
        'Accept': 'application/json',
      });
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) {
        _toast('No results for "$query"');
        return;
      }
      final first = list.first as Map<String, dynamic>;
      final lat = double.parse(first['lat'].toString());
      final lon = double.parse(first['lon'].toString());
      _center = LatLng(lat, lon);
      _mapController.move(_center, 16);
      await _reverseGeocode();
    } catch (_) {
      _toast('Search failed, please try again');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  // ── Current GPS location ──────────────────────────────────────────────────
  Future<void> _locateMe() async {
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _toast('Location services are off');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission denied — drag the map instead');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _center = LatLng(pos.latitude, pos.longitude);
      _mapController.move(_center, 17);
      await _reverseGeocode();
    } catch (_) {
      _toast("Couldn't get your location — drag the map instead");
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BauhausTheme.background,
      body: Stack(
        children: [
          // ── Map ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              minZoom: 3,
              maxZoom: 19,
              // Tap anywhere to drop the pin on that exact spot.
              onTap: (tapPosition, latlng) {
                setState(() => _center = latlng);
                _reverseGeocode();
              },
              onPositionChanged: (camera, hasGesture) {
                _zoom = camera.zoom;
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mproti.dining.user',
                maxZoom: 19,
              ),
              // Draggable pin that marks the exact delivery location.
              DragMarkers(
                markers: [
                  DragMarker(
                    point: _center,
                    size: const Size(50, 50),
                    // Anchor the pin's tip on the point.
                    offset: const Offset(0, -22),
                    dragOffset: const Offset(0, -40),
                    builder: (context, point, isDragging) => Icon(
                      Icons.location_on,
                      size: isDragging ? 56 : 48,
                      color: BauhausTheme.accentRed,
                      shadows: const [
                        Shadow(color: Colors.black38, blurRadius: 4),
                      ],
                    ),
                    onDragEnd: (details, point) {
                      setState(() => _center = point);
                      _reverseGeocode();
                    },
                  ),
                ],
              ),
            ],
          ),

          // ── Center reference crosshair ──
          IgnorePointer(
            child: Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.65),
                  border: Border.all(
                    color: BauhausTheme.primaryBlack.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: BauhausTheme.primaryBlack,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Top: back + search ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  _circleBtn(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: BauhausTheme.white,
                        borderRadius:
                            BorderRadius.circular(BauhausTheme.radiusPill),
                        boxShadow: BauhausTheme.floatingShadow,
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _search,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search area, street, landmark…',
                          hintStyle: GoogleFonts.inter(
                              fontSize: 13, color: BauhausTheme.mediumGrey),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward, size: 20),
                            onPressed: () => _search(_searchCtrl.text),
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom: address card + confirm ──
          Align(
            alignment: Alignment.bottomCenter,
            child: _bottomCard(),
          ),
        ],
      ),
      floatingActionButton: Padding(
        // Lift above the bottom card.
        padding: const EdgeInsets.only(bottom: 180),
        child: FloatingActionButton.extended(
          backgroundColor: BauhausTheme.white,
          foregroundColor: BauhausTheme.primaryBlack,
          onPressed: _locating ? null : _locateMe,
          icon: _locating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, color: BauhausTheme.accentRed),
          label: Text('Use my location',
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _circleBtn({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: BauhausTheme.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: BauhausTheme.primaryBlack),
        ),
      ),
    );
  }

  Widget _bottomCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: BauhausTheme.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: BauhausTheme.floatingShadow,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DELIVERING TO',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: BauhausTheme.mediumGrey)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on,
                    size: 20, color: BauhausTheme.accentRed),
                const SizedBox(width: 8),
                Expanded(
                  child: _resolving
                      ? Row(
                          children: [
                            const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 10),
                            Text('Locating address…',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: BauhausTheme.mediumGrey)),
                          ],
                        )
                      : Text(_address,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: BauhausTheme.primaryBlack)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.touch_app,
                    size: 14, color: BauhausTheme.mediumGrey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tap the map or drag the pin to set the exact spot',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: BauhausTheme.mediumGrey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            BauhausButton(
              label: 'CONFIRM LOCATION',
              height: 48,
              onPressed: (_resolving || _resolved == null)
                  ? null
                  : () => Navigator.of(context).pop(_resolved),
            ),
          ],
        ),
      ),
    );
  }
}
