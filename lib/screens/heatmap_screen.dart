import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/heatmap_service.dart'; // Contains HeatmapGrid
import '../services/heatmap_cache_service.dart';
import '../services/csv_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../widgets/heatmap_2d.dart';
import '../widgets/heatmap_3d.dart';
import '../widgets/heatmap_surface_3d.dart';
import '../widgets/heatmap_legend.dart';
import '../widgets/plant_status_legend.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../services/gltf_service.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_settings.dart';
import '../providers/csv_data_provider.dart';
import '../services/run_segmentation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class HeatmapScreen extends StatefulWidget {
  final bool embedded;
  const HeatmapScreen({super.key, this.embedded = false});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final heatmapService = HeatmapService();
  final HeatmapSurface3DController _surface3DController = HeatmapSurface3DController();
  // Sentinel for "farm average" selection when a farm is chosen
  static const int _farmAverageSentinel = -2;
  final List<String> metrics = [
    'Plant Status',
    'pH',
    'Temperature',
    'Humidity',
    'EC',
    'N',
    'P',
    'K',
    'All'
  ];
  String currentMetric = 'All';
  // New: multi-select metrics, default all selected
  Set<String> selectedMetrics = {};
  DateTime? startTime;
  DateTime? endTime;
  bool is3DView = false;
  // Store last computed grid and metric to enable caching for user CSVs too
  String? _lastKeySeed; // Either asset content or provider dataset hash
  bool _lastKeyIsRaw = false; // true when seed is a raw key (not a file path)
  bool isLoading = true;
  List<List<double>>? gridData;
  double minValue = 0.0;
  double maxValue = 0.0;
  double geographicWidthRatio = 1.0; // NEW: Aspect ratio for shape correction
  // Selection info for clicked cell
  int? _selectedRow;
  int? _selectedCol;
  Map<String, double>? _selectedValues;
  double? _selectedLat;
  double? _selectedLon;
  String? gltfModelPath;
  Key _modelViewerKey = UniqueKey();
  List<double>? _optimalRangeOverride; // averaged optimal range when selecting multiple metrics
  // Run selection state
  List<RunSegment> _runs = const [];
  int _selectedRunIndex = -1; // -1 means full range
  List<FarmCluster> _farms = const [];
  int? _selectedFarmId; // selected farm (null = all farms)

  @override
  void initState() {
    super.initState();
    _loadData();
    // Default select all base metrics (exclude 'All') or use persisted settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final saved = context.read<AppSettings>().selectedMetrics;
        setState(() {
          // Default: only numeric metrics selected; Plant Status off by default
          final base = metrics.where((m) => m != 'All' && m != 'Plant Status').toSet();
          selectedMetrics = saved.isNotEmpty ? saved : base;
        });
        _updateGridAndValues();
      } catch (_) {
        setState(() {
          selectedMetrics = metrics.where((m) => m != 'All' && m != 'Plant Status').toSet();
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If provider data changes while on this screen, refresh
    try {
      final provider = context.read<CSVDataProvider>();
      if (provider.hasData && provider.sourceKey.isNotEmpty && provider.sourceKey != _lastKeySeed) {
        final points = _pointsFromProvider(provider);
        heatmapService.setPoints(points);
        setState(() {
          final segs = RunSegmentationService.segmentRuns(
            timestamps: provider.timestamps,
            lats: provider.latitudes,
            lons: provider.longitudes,
          );
          final assignment = RunSegmentationService.assignFarms(
            runs: segs,
            lats: provider.latitudes,
            lons: provider.longitudes,
          );
          _runs = assignment.runs;
          _farms = assignment.farms;
          // Default to latest farm average if farms exist; otherwise latest run
          if (_farms.isNotEmpty) {
            int latestFarmId = _farms.first.id;
            DateTime latestEnd = DateTime.fromMillisecondsSinceEpoch(0);
            for (final f in _farms) {
              for (final idx in f.runIndices) {
                final end = _runs[idx].endTime;
                if (end.isAfter(latestEnd)) { latestEnd = end; latestFarmId = f.id; }
              }
            }
            _selectedFarmId = latestFarmId;
            final farmIndices = _runsForFarm(latestFarmId);
            if (farmIndices.isNotEmpty) {
              final farmStart = farmIndices.map((i) => _runs[i].startTime).reduce((a, b) => a.isBefore(b) ? a : b);
              final farmEnd = farmIndices.map((i) => _runs[i].endTime).reduce((a, b) => a.isAfter(b) ? a : b);
              startTime = farmStart;
              endTime = farmEnd;
              _selectedRunIndex = _farmAverageSentinel; // farm average
            }
          } else if (_runs.isNotEmpty) {
            int latestIdx = 0;
            DateTime latestEnd = _runs[0].endTime;
            for (int i = 1; i < _runs.length; i++) {
              if (_runs[i].endTime.isAfter(latestEnd)) { latestEnd = _runs[i].endTime; latestIdx = i; }
            }
            _selectedRunIndex = latestIdx;
            startTime = _runs[latestIdx].startTime;
            endTime = _runs[latestIdx].endTime;
          } else {
            startTime = provider.timestamps.reduce((a, b) => a.isBefore(b) ? a : b);
            endTime = provider.timestamps.reduce((a, b) => a.isAfter(b) ? a : b);
            _selectedRunIndex = -1;
          }
          currentMetric = 'All';
          isLoading = false;
          _lastKeySeed = provider.sourceKey;
          _lastKeyIsRaw = true;
        });
        _updateGridAndValues();
        unawaited(_ensurePngForCurrent(_lastKeySeed!, isRawKey: true));
      }
    } catch (_) {}
  }

  List<HeatmapPoint> _pointsFromParsed(Map<String, List<dynamic>> parsed) {
    final timestamps = parsed['timestamps']?.cast<DateTime>() ?? <DateTime>[];
    final lats = parsed['latitudes']?.cast<double>() ?? <double>[];
    final lons = parsed['longitudes']?.cast<double>() ?? <double>[];
    if (timestamps.isEmpty || lats.isEmpty || lons.isEmpty) return [];

    // Map unique lat/lon to grid indices
    final uniqueLats = lats.toSet().toList()..sort();
    final uniqueLons = lons.toSet().toList()..sort();
    final latToY = {for (int i = 0; i < uniqueLats.length; i++) uniqueLats[i]: i};
    final lonToX = {for (int i = 0; i < uniqueLons.length; i++) uniqueLons[i]: i};

    List<HeatmapPoint> pts = [];
    for (int i = 0; i < timestamps.length; i++) {
      final t = timestamps[i];
      final lat = lats[i];
      final lon = lons[i];
      if (t == null || lat.isNaN || lon.isNaN) continue;
      final String? statusRaw = (parsed['plant_status']?.length ?? 0) > i ? parsed['plant_status']![i]?.toString() : null;
      final metrics = <String, double>{
        'pH': (parsed['pH']?[i] as double?) ?? double.nan,
        'Temperature': (parsed['temperature']?[i] as double?)?.toDouble() ?? double.nan,
        'Humidity': (parsed['humidity']?[i] as double?)?.toDouble() ?? double.nan,
        'EC': (parsed['ec']?[i] as double?)?.toDouble() ?? double.nan,
        'N': (parsed['N']?[i] as double?)?.toDouble() ?? double.nan,
        'P': (parsed['P']?[i] as double?)?.toDouble() ?? double.nan,
        'K': (parsed['K']?[i] as double?)?.toDouble() ?? double.nan,
        // Encode plant status as symptom count if present
        if (statusRaw != null)
          'Plant Status': encodePlantStatus(statusRaw).toDouble(),
      };
      pts.add(HeatmapPoint(
        x: lonToX[lon] ?? 0,
        y: latToY[lat] ?? 0,
        t: t,
        metrics: metrics,
        plantStatusRaw: statusRaw,
        symptoms: statusRaw != null ? parseSymptomsFromStatus(statusRaw) : null,
      ));
    }
    return pts;
  }

  List<HeatmapPoint> _pointsFromProvider(CSVDataProvider provider) {
    final timestamps = provider.timestamps;
    final lats = provider.latitudes;
    final lons = provider.longitudes;
    if (timestamps.isEmpty || lats.isEmpty || lons.isEmpty) return [];

    final uniqueLats = lats.toSet().toList()..sort();
    final uniqueLons = lons.toSet().toList()..sort();
    final latToY = {for (int i = 0; i < uniqueLats.length; i++) uniqueLats[i]: i};
    final lonToX = {for (int i = 0; i < uniqueLons.length; i++) uniqueLons[i]: i};

    final List<HeatmapPoint> pts = [];
    for (int i = 0; i < timestamps.length; i++) {
      final t = timestamps[i];
      final lat = lats[i];
      final lon = lons[i];
      if (lat.isNaN || lon.isNaN) continue;
      final String? statusRaw = (i < provider.plantStatus.length) ? provider.plantStatus[i] : null;
      final metrics = <String, double>{
        'pH': (i < provider.pH.length) ? provider.pH[i] : double.nan,
        'Temperature': (i < provider.temperature.length) ? provider.temperature[i] : double.nan,
        'Humidity': (i < provider.humidity.length) ? provider.humidity[i] : double.nan,
        'EC': (i < provider.ec.length) ? provider.ec[i] : double.nan,
        'N': (i < provider.n.length) ? provider.n[i] : double.nan,
        'P': (i < provider.p.length) ? provider.p[i] : double.nan,
        'K': (i < provider.k.length) ? provider.k[i] : double.nan,
        'Plant Status': statusRaw != null
            ? encodePlantStatus(statusRaw).toDouble()
            : double.nan,
      };
      pts.add(HeatmapPoint(
        x: lonToX[lon] ?? 0,
        y: latToY[lat] ?? 0,
        t: t,
        metrics: metrics,
        lat: lat,
        lon: lon,
        plantStatusRaw: statusRaw,
        symptoms: statusRaw != null ? parseSymptomsFromStatus(statusRaw) : null,
      ));
    }
    return pts;
  }

  void _handleCellSelection(int row, int col) {
    if (gridData == null || gridData!.isEmpty) return;
    final bool isSingle = selectedMetrics.length == 1;
    final String selectedLabel = isSingle ? selectedMetrics.first : 'Average';

    // Estimate lat/lon if axes are available by linear mapping of indices
    double? lat, lon;
    // We don't have direct access here; could compute from heatmapService points' extents
    try {
      final pts = heatmapService.points.where((p) => p.lat != null && p.lon != null).toList();
      if (pts.isNotEmpty) {
        final lats = pts.map((p) => p.lat!).toList()..sort();
        final lons = pts.map((p) => p.lon!).toList()..sort();
        final minLat = lats.first, maxLat = lats.last;
        final minLon = lons.first, maxLon = lons.last;
        final rows = gridData!.length, cols = gridData![0].length;
        lat = rows > 1 ? minLat + (maxLat - minLat) * (row / (rows - 1)) : minLat;
        lon = cols > 1 ? minLon + (maxLon - minLon) * (col / (cols - 1)) : minLon;
      }
    } catch (_) {}

    // Interpolate values for each selected metric at estimated lat/lon
    final Map<String, double> values = {};
    if (isSingle) {
      values[selectedLabel] = gridData![row][col];
    } else {
      if (lat != null && lon != null) {
        final metricsList = selectedMetrics.toList();
        final all = interpolateAtForMetrics(
          points: heatmapService.points,
          metrics: metricsList,
          lat: lat,
          lon: lon,
          start: startTime!,
          end: endTime!,
        );
        values.addAll(all);
      }
      values['Average'] = gridData![row][col];
    }

    setState(() {
      _selectedRow = row;
      _selectedCol = col;
      _selectedValues = values;
      _selectedLat = lat;
      _selectedLon = lon;
    });
  }

  Widget _buildSelectionInfo() {
    if (_selectedValues == null) return const SizedBox.shrink();
    final isPlantStatus = _selectedValues!.keys.length == 1 && _selectedValues!.keys.first == 'Plant Status';
    final List<Widget> chips = [];
    if (isPlantStatus) {
      // Always show indices and coordinates first
      chips.add(_InfoChip(label: _selectedRow != null && _selectedCol != null ? "r=${_selectedRow}, c=${_selectedCol}" : "r=?, c=?"));
      if (_selectedLat != null && _selectedLon != null) {
        chips.add(_InfoChip(label: "lat ${_selectedLat!.toStringAsFixed(5)}"));
        chips.add(_InfoChip(label: "lon ${_selectedLon!.toStringAsFixed(5)}"));
      }
      // Show all symptoms for this selected cell (nearest sample)
      final v = _selectedValues!['Plant Status'] ?? double.nan;
      final code = v.isNaN ? 0 : v.round();
      if (code == -1) {
        chips.add(_InfoChip(label: 'No Turmeric Detected', color: colorForPlantStatusCode(code)));
      } else {
        // Add a count chip
        chips.add(_InfoChip(label: "count: $code", color: colorForPlantStatusCode(code)));
        List<String> syms = [];
        if (_selectedLat != null && _selectedLon != null && startTime != null && endTime != null) {
          syms = nearestSymptomsAt(
            points: heatmapService.points,
            lat: _selectedLat!,
            lon: _selectedLon!,
            start: startTime!,
            end: endTime!,
          );
        }
        if (syms.isEmpty) {
          chips.add(_InfoChip(label: 'No symptoms'));
        } else {
          for (final s in syms) {
            chips.add(_InfoChip(label: s));
          }
        }
      }
    } else {
      // Always show indices first
      chips.add(_InfoChip(label: _selectedRow != null && _selectedCol != null ? "r=${_selectedRow}, c=${_selectedCol}" : "r=?, c=?"));
      if (_selectedLat != null && _selectedLon != null) {
        chips.add(_InfoChip(label: "lat ${_selectedLat!.toStringAsFixed(5)}"));
        chips.add(_InfoChip(label: "lon ${_selectedLon!.toStringAsFixed(5)}"));
      }
      // Show metric values
      _selectedValues!.forEach((k, v) {
        final String text = v.isFinite ? v.toStringAsFixed(2) : 'N/A';
        chips.add(_InfoChip(label: "$k: $text"));
      });
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  // Tiny pill chip used for selection info
  Widget _InfoChip({required String label, Color? color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D20) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color ?? (isDark ? Colors.white24 : Colors.black12)),
        boxShadow: [BoxShadow(color: (color ?? Colors.black).withOpacity(0.06), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Future<void> _loadData() async {
    try {
      // Prefer live provider CSV if available
      final provider = context.read<CSVDataProvider>();
      if (provider.hasData) {
        final points = _pointsFromProvider(provider);
        heatmapService.setPoints(points);
        if (!mounted) return;
        setState(() {
          final segs = RunSegmentationService.segmentRuns(
            timestamps: provider.timestamps,
            lats: provider.latitudes,
            lons: provider.longitudes,
          );
          final assignment = RunSegmentationService.assignFarms(
            runs: segs,
            lats: provider.latitudes,
            lons: provider.longitudes,
          );
          _runs = assignment.runs;
          _farms = assignment.farms;
          if (_runs.isNotEmpty) {
            int latestIdx = 0;
            DateTime latestEnd = _runs[0].endTime;
            for (int i = 1; i < _runs.length; i++) {
              if (_runs[i].endTime.isAfter(latestEnd)) { latestEnd = _runs[i].endTime; latestIdx = i; }
            }
            _selectedRunIndex = latestIdx;
            startTime = _runs[latestIdx].startTime;
            endTime = _runs[latestIdx].endTime;
          } else {
            startTime = provider.timestamps.reduce((a, b) => a.isBefore(b) ? a : b);
            endTime = provider.timestamps.reduce((a, b) => a.isAfter(b) ? a : b);
            _selectedRunIndex = -1;
          }
          currentMetric = 'All';
          isLoading = false;
          _lastKeySeed = provider.sourceKey;
          _lastKeyIsRaw = true;
        });
        _updateGridAndValues();
        await _ensurePngForCurrent(_lastKeySeed!, isRawKey: true);
        return;
      }

      // Fallback: use default asset (lat/lon/timestamp grid)
      final csvAssetPath = 'assets/simulated_soil_square.csv';
      List<HeatmapPoint> points = await HeatmapService.parseCsvAsset(csvAssetPath);
      if (points.isEmpty) {
        final csvString = await rootBundle.loadString(csvAssetPath);
        final parsed = await CSVService.parseCSV(csvString);
        points = _pointsFromParsed(parsed);
      }
      heatmapService.setPoints(points);

      if (!mounted) return;

      if (points.isNotEmpty) {
        // Compute full available time range from CSV
        final DateTime minT = points.map((p) => p.t).reduce((a, b) => a.isBefore(b) ? a : b);
        final DateTime maxT = points.map((p) => p.t).reduce((a, b) => a.isAfter(b) ? a : b);

        setState(() {
          startTime = minT;
          endTime = maxT;
          _runs = const [];
          _farms = const [];
          _selectedFarmId = null;
          _selectedRunIndex = -1;
          // Start with 'All' to ensure visibility by default
          currentMetric = 'All';
          isLoading = false;
        });
        _updateGridAndValues();
        // After grid computed, auto-generate PNG for default metric if missing
        _lastKeySeed = csvAssetPath;
        _lastKeyIsRaw = false;
        await _ensurePngForCurrent(csvAssetPath);
        // Fallback: if grid looks empty, try metric 'pH' then 'All' with full range again
        if (!_hasFinite(gridData)) {
          setState(() { currentMetric = 'pH'; });
          _updateGridAndValues();
          if (!_hasFinite(gridData)) {
            setState(() { currentMetric = 'All'; startTime = minT; endTime = maxT; });
            _updateGridAndValues();
          }
        }
      } else {
        // Ensure spinner clears even when dataset is empty
        setState(() {
          startTime = null;
          endTime = null;
          gridData = [];
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  void _updateGridAndValues() {
    if (heatmapService.points.isEmpty || startTime == null || endTime == null) {
      setState(() {
        gridData = [];
        minValue = 0;
        maxValue = 0;
        geographicWidthRatio = 1.0; // Reset ratio
        _optimalRangeOverride = null;
      });
      return;
    }

    // If nothing selected, show no data
    if (selectedMetrics.isEmpty) {
      setState(() {
        gridData = [];
        _optimalRangeOverride = null;
      });
      return;
    }

    HeatmapGrid heatmapData;
    if (selectedMetrics.isNotEmpty && selectedMetrics.length > 1) {
      // Multi-select averaging
      heatmapData = heatmapService.createUniformGridFromLatLonForMetrics(
        metrics: selectedMetrics.toList(),
        start: startTime!,
        end: endTime!,
        targetCols: null,
        targetRows: null,
      );
      _optimalRangeOverride = heatmapService.averageOptimalRange(selectedMetrics.toList());
    } else {
      // Single metric (or none) uses currentMetric
      final metricToUse = selectedMetrics.isNotEmpty ? selectedMetrics.first : currentMetric;
      heatmapData = heatmapService.createUniformGridFromLatLon(
        metric: metricToUse,
        start: startTime!,
        end: endTime!,
        targetCols: null,
        targetRows: null,
      );
      _optimalRangeOverride = null;
    }

    final newGrid = heatmapData.grid; // Extract grid data
    final allValues = newGrid.expand((row) => row).where((v) => !v.isNaN).toList();
    
    if (allValues.isNotEmpty) {
      final min = allValues.reduce((a, b) => a < b ? a : b);
      final max = allValues.reduce((a, b) => a > b ? a : b);

      double adjustedMin = min;
      double adjustedMax = max;
      if (adjustedMin == adjustedMax) {
        adjustedMin = adjustedMin - 0.01;
        adjustedMax = adjustedMax + 0.01;
      }

      setState(() {
        gridData = newGrid;
        minValue = adjustedMin;
        maxValue = adjustedMax;
        geographicWidthRatio = heatmapData.widthRatio; // NEW: Set aspect ratio
        _selectedRow = null; // reset selection after recompute
        _selectedCol = null;
        _selectedValues = null;
        _selectedLat = heatmapData.latAxis != null && _selectedRow != null ? heatmapData.latAxis![_selectedRow!] : null;
        _selectedLon = heatmapData.lonAxis != null && _selectedCol != null ? heatmapData.lonAxis![_selectedCol!] : null;
      });
    } else {
      // When no finite values are present, still provide a non-zero range for UI
      setState(() {
        gridData = newGrid;
        minValue = 0;
        maxValue = 1;
        geographicWidthRatio = heatmapData.widthRatio; // NEW: Still set ratio even if empty
        _selectedRow = null;
        _selectedCol = null;
        _selectedValues = null;
        _selectedLat = null;
        _selectedLon = null;
      });
    }
  }

  Future<void> _ensurePngForCurrent(String keySeed, {bool isRawKey = false}) async {
    try {
      if (gridData == null || gridData!.isEmpty) return;
      // Create a stable key from dataset seed + metric
      final String seed = isRawKey
          ? keySeed
          : await DefaultAssetBundle.of(context).loadString(keySeed);
      // Include selection set in the cache key to avoid collisions
      final List<String> sel = selectedMetrics.toList()..sort();
      final String metricKey = sel.length > 1 ? 'AVG_${sel.join('_')}' : (sel.isNotEmpty ? sel.first : currentMetric);
      final key = HeatmapCacheService.buildKey(csvContent: seed, metric: metricKey);
      // Use app documents for cached assets to avoid permission issues
      final exists = await HeatmapCacheService.existsPng(key, basePath: null);
      if (!exists) {
        final img = await renderHeatmapImage(
          grid: gridData!,
          metricLabel: sel.length == 1 ? sel.first : 'Average',
          minValue: minValue,
          maxValue: maxValue,
          cellSize: 24,
          optimalRangeOverride: _optimalRangeOverride,
        );
        await HeatmapCacheService.writePng(key, img, basePath: null);
      }
    } catch (_) {
      // Ignore caching errors silently for now
    }
  }

  Widget _buildTexturedPlaneViewer() {
    // Build/locate PNG for current metric and return a model-viewer with a plane textured by it
    return FutureBuilder<String>(
      future: _buildOrGetGltfDataUriForCurrent(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final uri = snapshot.data!;
        return ModelViewer(
          key: _modelViewerKey,
          src: uri,
          cameraControls: true,
          autoRotate: false,
          ar: false,
          disableZoom: false,
          exposure: 1.0,
          cameraOrbit: '0deg 65deg 100%',
          fieldOfView: '45deg',
          alt: 'Textured heatmap plane',
        );
      },
    );
  }

  Future<String> _buildOrGetGltfDataUriForCurrent() async {
    // Ensure PNG exists for current dataset
    String seed;
    if (_lastKeySeed != null) {
      seed = _lastKeyIsRaw
          ? _lastKeySeed!
          : await DefaultAssetBundle.of(context).loadString(_lastKeySeed!);
    } else {
      // fallback to asset
      seed = await DefaultAssetBundle.of(context).loadString('assets/simulated_soil_square.csv');
    }
    final List<String> sel = selectedMetrics.toList()..sort();
    final String metricKey = sel.length > 1 ? 'AVG_${sel.join('_')}' : (sel.isNotEmpty ? sel.first : currentMetric);
    final key = HeatmapCacheService.buildKey(csvContent: seed, metric: metricKey);
    // Keep cache internal to app storage to avoid permission issues
    if (!await HeatmapCacheService.existsPng(key, basePath: null)) {
      if (gridData != null && gridData!.isNotEmpty) {
        final img = await renderHeatmapImage(
          grid: gridData!,
          metricLabel: sel.length == 1 ? sel.first : 'Average',
          minValue: minValue,
          maxValue: maxValue,
          cellSize: 24,
          optimalRangeOverride: _optimalRangeOverride,
        );
        await HeatmapCacheService.writePng(key, img, basePath: null);
      }
    }
    // Read PNG and embed in glTF JSON (data URIs)
    final pngFile = await HeatmapCacheService.getPngFile(key, basePath: null);
    final bytes = await pngFile.readAsBytes();
    final json = GltfService.buildTexturedPlaneGltfJson(bytes);
    return GltfService.gltfJsonToDataUri(json);
  }

  bool _hasFinite(List<List<double>>? grid) {
    if (grid == null || grid.isEmpty || grid.first.isEmpty) return false;
    for (final row in grid) {
      for (final v in row) {
        if (v.isFinite) return true;
      }
    }
    return false;
  }

  void _onMetricChanged(String newMetric) {
    setState(() {
      // Toggle selection in multi-select panel
      if (newMetric == 'All') {
        // handled by toggle button elsewhere
      } else {
        if (newMetric == 'Plant Status') {
          // Selecting Plant Status deselects everything else
          selectedMetrics = {'Plant Status'};
        } else {
          // Selecting any numeric metric removes Plant Status if it was selected
          if (selectedMetrics.contains('Plant Status')) {
            selectedMetrics.remove('Plant Status');
          }
          if (selectedMetrics.contains(newMetric)) {
            selectedMetrics.remove(newMetric);
          } else {
            selectedMetrics.add(newMetric);
          }
        }
      }
      // Keep currentMetric in sync for single selection cases
      currentMetric = selectedMetrics.length == 1 ? selectedMetrics.first : 'All';
      // Force 3D viewer to reload when metric changes
      if (is3DView) {
        _modelViewerKey = UniqueKey();
      }
    });
    // Persist selection
    try {
      context.read<AppSettings>().setSelectedMetrics(selectedMetrics);
    } catch (_) {}
    _updateGridAndValues();
    // Try generating PNG for this metric in background
    if (_lastKeySeed != null) {
      unawaited(_ensurePngForCurrent(_lastKeySeed!, isRawKey: _lastKeyIsRaw));
    }
  }

  bool get _areAllSelected => selectedMetrics.length == metrics.where((m) => m != 'All' && m != 'Plant Status').length;

  void _toggleSelectAll() {
    setState(() {
      if (_areAllSelected) {
        // Deselect all -> show nothing
        selectedMetrics.clear();
      } else {
        // Select all base metrics
        selectedMetrics = metrics.where((m) => m != 'All' && m != 'Plant Status').toSet();
      }
      currentMetric = selectedMetrics.length == 1 ? selectedMetrics.first : 'All';
      if (is3DView) {
        _modelViewerKey = UniqueKey();
      }
    });
    try {
      context.read<AppSettings>().setSelectedMetrics(selectedMetrics);
    } catch (_) {}
    _updateGridAndValues();
    if (_lastKeySeed != null) {
      unawaited(_ensurePngForCurrent(_lastKeySeed!, isRawKey: _lastKeyIsRaw));
    }
  }

  void _onMetricLongPress(String metric) {
    setState(() {
      selectedMetrics = {metric};
      currentMetric = metric;
      if (is3DView) {
        _modelViewerKey = UniqueKey();
      }
    });
    try {
      context.read<AppSettings>().setSelectedMetrics(selectedMetrics);
    } catch (_) {}
    _updateGridAndValues();
    if (_lastKeySeed != null) {
      unawaited(_ensurePngForCurrent(_lastKeySeed!, isRawKey: _lastKeyIsRaw));
    }
  }

  Future<void> _selectDateRange() async {
    // Show date picker first
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: startTime ?? DateTime.now(),
    );

    if (pickedDate != null) {
      // Then show time picker
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(startTime ?? DateTime.now()),
      );

      if (pickedTime != null) {
        final newStartTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        setState(() {
          startTime = newStartTime;
          endTime = newStartTime.add(const Duration(hours: 1)); // Set a default end time
        });
        _updateGridAndValues();
      }
    }
  }

  void _toggleView() {
    setState(() {
      is3DView = !is3DView;
    });

    // In this app we render 3D with a custom painter instead of glTF assets
    gltfModelPath = null;
  }

  // Helpers for farm-based run selection
  List<int> _runsForFarm(int farmId) {
    final farm = _farms.firstWhere((f) => f.id == farmId);
    return List<int>.from(farm.runIndices);
  }

  void _selectFarmAverage(int farmId) {
    final indices = _runsForFarm(farmId);
    if (indices.isEmpty) return;
    final farmStart = indices.map((i) => _runs[i].startTime).reduce((a, b) => a.isBefore(b) ? a : b);
    final farmEnd = indices.map((i) => _runs[i].endTime).reduce((a, b) => a.isAfter(b) ? a : b);
    setState(() {
      _selectedFarmId = farmId;
      _selectedRunIndex = _farmAverageSentinel; // farm average sentinel
      startTime = farmStart;
      endTime = farmEnd;
    });
    _updateGridAndValues();
  }

  void _selectSpecificRun(int runIndex) {
    if (runIndex < 0 || runIndex >= _runs.length) return;
    final run = _runs[runIndex];
    setState(() {
      _selectedFarmId = _farms.firstWhere((f) => f.runIndices.contains(runIndex)).id;
      _selectedRunIndex = runIndex;
      startTime = run.startTime;
      endTime = run.endTime;
    });
    _updateGridAndValues();
  }

  Future<bool> _ensureStoragePermission() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdk = androidInfo.version.sdkInt;
    if (sdk >= 30) {
      if (await Permission.manageExternalStorage.isGranted) return true;
      final status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    } else {
      if (await Permission.storage.isGranted) return true;
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  void _reset3DView() {
    // For the custom 3D surface, call controller.reset().
    // For the (unused) model_viewer path, keep reload fallback.
    _surface3DController.reset();
    setState(() { _modelViewerKey = UniqueKey(); });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Widget bodyContent = isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Top horizontal legend is rendered inside Heatmap2D; below is the date range control
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _selectDateRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      startTime != null && endTime != null
                          ? (_selectedRunIndex >= 0
                              ? 'Run ${_selectedRunIndex + 1}: ${startTime!.toString().split('.')[0]} - ${endTime!.toString().split('.')[0]}'
                              : 'Viewing Data from ${startTime!.toString().split('.')[0]} to ${endTime!.toString().split('.')[0]}')
                          : 'Select Date & Time Range',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Farm/Run selector pills (minimal, themed)
                  if (_farms.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ..._farms.map((f) {
                            final bool isSelectedFarm = _selectedFarmId == f.id && _selectedRunIndex == _farmAverageSentinel;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: FilterChip(
                                label: Text('Farm ${f.id}'),
                                selected: isSelectedFarm,
                                onSelected: (_) => _selectFarmAverage(f.id),
                              ),
                            );
                          }),
                          if (_selectedFarmId != null)
                            PopupMenuButton<int>(
                              tooltip: 'Select specific run',
                              icon: const Icon(Icons.more_horiz),
                              onSelected: (runIdx) => _selectSpecificRun(runIdx),
                              itemBuilder: (context) {
                                final runIndices = _runsForFarm(_selectedFarmId!);
                                runIndices.sort((a, b) => _runs[a].startTime.compareTo(_runs[b].startTime));
                                return [
                                  PopupMenuItem<int>(
                                    value: _farmAverageSentinel,
                                    child: const Text('Farm Average'),
                                    onTap: () => _selectFarmAverage(_selectedFarmId!),
                                  ),
                                  const PopupMenuDivider(),
                                  ...List.generate(runIndices.length, (i) {
                                    final idx = runIndices[i];
                                    final run = _runs[idx];
                                    return PopupMenuItem<int>(
                                      value: idx,
                                      child: Text('Run ${i + 1} • ${run.startTime.toString().split('.')[0]}'),
                                    );
                                  }),
                                ];
                              },
                            ),
                        ],
                      ),
                    ),
                  if (_farms.isNotEmpty) const SizedBox(height: 8),
                  // Metrics row (top) with toggle button
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...metrics
                            .where((m) => m != 'All')
                            .map((m) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onLongPress: () => _onMetricLongPress(m),
                                    child: FilterChip(
                                      label: Text(m),
                                      selected: selectedMetrics.contains(m),
                                      onSelected: (_) => _onMetricChanged(m),
                                    ),
                                  ),
                                ))
                            .toList(),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          icon: Icon(_areAllSelected ? Icons.clear_all : Icons.select_all),
                          onPressed: _toggleSelectAll,
                          label: Text(_areAllSelected ? 'Clear All' : 'Select All'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (gridData != null && gridData!.isNotEmpty)
                    Builder(builder: (context) {
                      final String label = selectedMetrics.length == 1 ? selectedMetrics.first : 'Average';
                      if (label == 'Plant Status') {
                        return const SizedBox(
                          height: 28,
                          child: PlantStatusLegend(axis: Axis.horizontal, isDense: true, spacing: 8),
                        );
                      }
                      return SizedBox(
                        height: 36,
                        child: HeatmapLegend(
                          minValue: minValue,
                          maxValue: maxValue,
                          metricLabel: label,
                          isDark: isDark,
                          axis: Axis.horizontal,
                          thickness: 14,
                          gradientMode: GradientMode.valueBased,
                          optimalRangeOverride: _optimalRangeOverride,
                        ),
                      );
                    }),
                  if (gridData != null && gridData!.isNotEmpty)
                    const SizedBox(height: 8),
                  Expanded(
                    child: (gridData != null && gridData!.isNotEmpty)
                        ? (is3DView
                            ? HeatmapSurface3D(
                                grid: gridData!,
                                metricLabel: selectedMetrics.length == 1 ? selectedMetrics.first : 'Average',
                                minValue: minValue,
                                maxValue: maxValue,
                                optimalRangeOverride: _optimalRangeOverride,
                                showIndices: true,
                                controller: _surface3DController,
                                onCellTap: (r, c) {
                                  if (r < 0 || c < 0) {
                                    setState(() { _selectedValues = null; _selectedRow = null; _selectedCol = null; });
                                  } else {
                                    _handleCellSelection(r, c);
                                  }
                                },
                                highlightRow: _selectedRow,
                                highlightCol: _selectedCol,
                              )
                            : Heatmap2D(
                                grid: gridData!,
                                geographicWidthRatio: geographicWidthRatio,
                                metricLabel: selectedMetrics.length == 1 ? selectedMetrics.first : 'Average',
                                minValue: minValue,
                                maxValue: maxValue,
                                optimalRangeOverride: _optimalRangeOverride,
                                showIndices: true,
                                onCellTap: (r, c) {
                                  if (r < 0 || c < 0) {
                                    setState(() { _selectedValues = null; _selectedRow = null; _selectedCol = null; });
                                  } else {
                                    _handleCellSelection(r, c);
                                  }
                                },
                                highlightRow: _selectedRow,
                                highlightCol: _selectedCol,
                              ))
                        : const Center(
                            child: Text("No data to display for the selected metric and time range."),
                          ),
                  ),
                  if (_selectedValues != null) ...[
                    const SizedBox(height: 6),
                    _buildSelectionInfo(),
                  ],
                  const SizedBox(height: 12),
                  if (!is3DView && (gridData != null && gridData!.isNotEmpty))
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Export heatmap PNG'),
                      onPressed: () async {
                        try {
                          // Ask for external storage permission when exporting
                          final granted = await _ensureStoragePermission();
                          if (!granted) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Storage permission denied. Saving to app storage instead.')),
                              );
                            }
                          }
                          final img = await renderHeatmapImage(
                            grid: gridData!,
                            metricLabel: selectedMetrics.length == 1 ? selectedMetrics.first : 'Average',
                            minValue: minValue,
                            maxValue: maxValue,
                            cellSize: 16,
                            showGridLines: false,
                            optimalRangeOverride: _optimalRangeOverride,
                          );
                          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
                          if (bytes != null) {
                          final settings = context.read<AppSettings>();
                          // Normalize and avoid duplicating 'heatmaps' folder name
                          Directory base;
                          if (settings.saveDirectory.isNotEmpty) {
                            base = Directory(settings.saveDirectory);
                          } else {
                            base = await getApplicationDocumentsDirectory();
                          }
                          final String normalizedBase = base.path.replaceAll('\\', '/').replaceAll(RegExp(r"/+$"), '');
                          final bool endsWithHeatmaps = normalizedBase.toLowerCase().endsWith('/heatmaps');
                          final Directory exportDir = Directory(endsWithHeatmaps ? normalizedBase : '$normalizedBase/heatmaps');
                          if (!await exportDir.exists()) {
                            await exportDir.create(recursive: true);
                          }
                            final safeMetric = currentMetric.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
                            final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
                            final path = '${exportDir.path}/heatmap_${safeMetric}_$timestamp.png';
                            final file = File(path);
                            try {
                              await file.writeAsBytes(bytes.buffer.asUint8List());
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Saved PNG: $path')),
                                );
                              }
                            } on FileSystemException catch (e) {
                              // Fallback to app documents dir when permission denied
                              final fallbackBase = await getApplicationDocumentsDirectory();
                              final fallbackDir = Directory('${fallbackBase.path}/heatmaps');
                              if (!await fallbackDir.exists()) {
                                await fallbackDir.create(recursive: true);
                              }
                              final fallbackPath = '${fallbackDir.path}/heatmap_${safeMetric}_$timestamp.png';
                              final fallbackFile = File(fallbackPath);
                              await fallbackFile.writeAsBytes(bytes.buffer.asUint8List());
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Saved to app storage (no permission for chosen dir). Path: $fallbackPath')),
                                );
                              }
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Failed to encode PNG bytes')),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to render PNG: $e')),
                            );
                          }
                        }
                      },
                    ),
                ],
            ),
          );

    if (widget.embedded) return bodyContent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Heatmap Viewer'),
        actions: [
          // Quick farm selection in app bar for minimalist access
          if (_farms.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'Select Farm/Run',
              icon: const Icon(Icons.agriculture),
              onSelected: (value) {
                if (value == _farmAverageSentinel) {
                  if (_selectedFarmId != null) _selectFarmAverage(_selectedFarmId!);
                } else {
                  _selectSpecificRun(value);
                }
              },
              itemBuilder: (context) {
                final items = <PopupMenuEntry<int>>[];
                for (final f in _farms) {
                  items.add(PopupMenuItem<int>(
                    enabled: false,
                    child: Text('Farm ${f.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ));
                  items.add(PopupMenuItem<int>(
                    value: _farmAverageSentinel,
                    child: const Text('• Farm Average'),
                    onTap: () => _selectFarmAverage(f.id),
                  ));
                  final runIndices = List<int>.from(f.runIndices)..sort((a, b) => _runs[a].startTime.compareTo(_runs[b].startTime));
                  for (int i = 0; i < runIndices.length; i++) {
                    final idx = runIndices[i];
                    items.add(PopupMenuItem<int>(
                      value: idx,
                      child: Text('• Run ${i + 1}'),
                    ));
                  }
                  items.add(const PopupMenuDivider());
                }
                if (items.isNotEmpty && items.last is PopupMenuDivider) {
                  items.removeLast();
                }
                return items;
              },
            ),
          IconButton(
            icon: Icon(is3DView ? Icons.view_agenda : Icons.view_in_ar),
            onPressed: _toggleView,
            tooltip: 'Toggle 2D/3D View',
          ),
          if (is3DView)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset 3D view',
              onPressed: _reset3DView,
            ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Set image save directory',
            onPressed: () async {
              await _promptSaveDirectory(context);
            },
          ),
        ],
      ),
      body: bodyContent,
    );
  }

  Future<void> _promptSaveDirectory(BuildContext context) async {
    final controller = TextEditingController(
      text: context.read<AppSettings>().saveDirectory,
    );
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Set save directory'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Directory path',
                  hintText: '/storage/emulated/0/Download',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Browse...'),
                  onPressed: () async {
                    final path = await FilePicker.platform.getDirectoryPath();
                    if (path != null) {
                      controller.text = path;
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tip: Choose a writable folder (not root of /storage). Files go into a heatmaps subfolder.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                context.read<AppSettings>().setSaveDirectory(controller.text.trim());
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRunsDialog() async {
    final provider = context.read<CSVDataProvider>();
    if (!provider.hasData) return;
    if (_runs.isEmpty) {
      setState(() {
        final segs = RunSegmentationService.segmentRuns(
          timestamps: provider.timestamps,
          lats: provider.latitudes,
          lons: provider.longitudes,
        );
        final assignment = RunSegmentationService.assignFarms(
          runs: segs,
          lats: provider.latitudes,
          lons: provider.longitudes,
        );
        _runs = assignment.runs;
        _farms = assignment.farms;
      });
    }
    await showDialog(
      context: context,
      builder: (ctx) {
        int? selectedFarmId;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Widget buildFarmList() {
              if (_farms.isEmpty) return const Text('No farms detected');
              return ListView.builder(
                shrinkWrap: true,
                itemCount: _farms.length,
                itemBuilder: (context, i) {
                  final farm = _farms[i];
                  final subtitle = 'lat ${farm.minLat.toStringAsFixed(5)}..${farm.maxLat.toStringAsFixed(5)}, '
                      'lon ${farm.minLon.toStringAsFixed(5)}..${farm.maxLon.toStringAsFixed(5)}\n'
                      '${farm.runIndices.length} runs';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${farm.id}')),
                      title: Text('Farm ${farm.id}'),
                      subtitle: Text(subtitle),
                      onTap: () => setLocalState(() { selectedFarmId = farm.id; }),
                    ),
                  );
                },
              );
            }

            Widget buildRunList(int farmId) {
              final farm = _farms.firstWhere((f) => f.id == farmId);
              final runsForFarm = farm.runIndices
                ..sort((a, b) => _runs[a].startTime.compareTo(_runs[b].startTime));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Farm ${farm.id}: lat ${farm.minLat.toStringAsFixed(5)}..${farm.maxLat.toStringAsFixed(5)}, '
                      'lon ${farm.minLon.toStringAsFixed(5)}..${farm.maxLon.toStringAsFixed(5)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: runsForFarm.length,
                      itemBuilder: (context, idx) {
                        final runIdx = runsForFarm[idx];
                        final run = _runs[runIdx];
                        final subtitle = '${run.startTime.toString().split('.')[0]} — ${run.endTime.toString().split('.')[0]}';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedRunIndex = runIdx;
                                startTime = run.startTime;
                                endTime = run.endTime;
                              });
                              _updateGridAndValues();
                              Navigator.of(ctx).pop();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(child: Text('${idx + 1}')),
                                      const SizedBox(width: 8),
                                      Text('Run ${idx + 1}', style: Theme.of(context).textTheme.titleMedium),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                                  const SizedBox(height: 8),
                                  _buildRunPreview(run),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Row(
                children: [
                  if (selectedFarmId != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setLocalState(() { selectedFarmId = null; }),
                    ),
                  Text(selectedFarmId == null ? 'Select Farm' : 'Select Run'),
                ],
              ),
              content: SizedBox(
                width: 460,
                height: 520,
                child: selectedFarmId == null ? buildFarmList() : buildRunList(selectedFarmId!),
              ),
              actions: [
                TextButton(
                  onPressed: () { Navigator.of(ctx).pop(); },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRunPreview(RunSegment run) {
    // Build a small grid for this run
    HeatmapGrid heatmapData;
    if (selectedMetrics.isNotEmpty && selectedMetrics.length > 1) {
      heatmapData = heatmapService.createUniformGridFromLatLonForMetrics(
        metrics: selectedMetrics.toList(),
        start: run.startTime,
        end: run.endTime,
        targetCols: 32,
        targetRows: 32,
      );
    } else {
      final metricToUse = selectedMetrics.isNotEmpty ? selectedMetrics.first : currentMetric;
      heatmapData = heatmapService.createUniformGridFromLatLon(
        metric: metricToUse,
        start: run.startTime,
        end: run.endTime,
        targetCols: 32,
        targetRows: 32,
      );
    }
    final grid = heatmapData.grid;
    final values = grid.expand((r) => r).where((v) => v.isFinite).toList();
    double minV = 0, maxV = 1;
    if (values.isNotEmpty) {
      minV = values.reduce((a, b) => a < b ? a : b);
      maxV = values.reduce((a, b) => a > b ? a : b);
      if (minV == maxV) { minV -= 0.01; maxV += 0.01; }
    }
    final label = selectedMetrics.length == 1 ? selectedMetrics.first : 'Average';
    return SizedBox(
      height: 120,
      child: Heatmap2D(
        grid: grid,
        geographicWidthRatio: heatmapData.widthRatio,
        metricLabel: label,
        minValue: minV,
        maxValue: maxV,
        optimalRangeOverride: selectedMetrics.length > 1
            ? heatmapService.averageOptimalRange(selectedMetrics.toList())
            : null,
        showIndices: false,
        showGridLines: false,
      ),
    );
  }
}
