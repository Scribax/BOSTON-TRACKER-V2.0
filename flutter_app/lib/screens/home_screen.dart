import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth/auth_bloc.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
import '../models/trip.dart';
import '../models/user.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _socketService = SocketService();
  LocationService? _locationService;
  late StorageService _storageService;
  late ApiService _apiService;
  Trip? _activeTrip;
  bool _isLoading = false;
  String? _error;
  TripMetrics? _liveMetrics;
  StreamSubscription<TripMetrics>? _metricsSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketSubscription;
  Timer? _tripPollingTimer;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    _storageService = StorageService();
    await _storageService.init();
    _apiService = ApiService(_storageService);
    _locationService = LocationService(_apiService);
    
    final user = await _storageService.getUser();
    if (user != null && user.token != null) {
      _socketService.connect(user.id, user.token!);
      _setupSocketListeners();
    }
    
    _loadActiveTrip();
  }

  void _setupSocketListeners() {
    _socketSubscription?.cancel();
    _socketSubscription = _socketService.events.listen((event) {
      if (event['type'] == 'tripStopped') {
        final data = event['data'];
        _showTripStoppedDialog(data);
      }
    });
  }

  void _showTripStoppedDialog(Map<String, dynamic> data) {
    // Stop tracking locally - trip already stopped on backend
    _locationService?.stopTracking();
    if (mounted) {
      setState(() {
        _activeTrip = null;
        _liveMetrics = null;
      });
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.stop_circle, color: AppTheme.dangerColor),
            SizedBox(width: 8),
            Text('Viaje Detenido'),
          ],
        ),
        content: Text(
          'Tu viaje ha sido detenido desde el dashboard.\n\n'
          'Distancia: ${((data['totalMileage'] ?? 0) as num).toStringAsFixed(2)} km\n'
          'Duración: ${((data['duration'] ?? 0) as num).toInt() ~/ 60} min',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadActiveTrip() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await _apiService.getActiveTrip();
      
      if (response.success) {
        setState(() {
          _activeTrip = response.data;
          _error = null;
        });
        
        // If has active trip, resume tracking
        if (_activeTrip != null && _activeTrip!.isActive) {
          final user = await _storageService.getUser();
          _startLocationTracking(deliveryName: user?.name);
        }
      } else {
        setState(() => _error = response.error);
      }
    } catch (e) {
      setState(() => _error = 'Error cargando viaje');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startTrip() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await _apiService.startTrip();
      
      if (response.success && response.data != null) {
        setState(() {
          _activeTrip = response.data;
          _error = null;
        });
        final user = await _storageService.getUser();
        _startLocationTracking(deliveryName: user?.name);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Viaje iniciado'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else {
        setState(() => _error = response.error ?? 'Error iniciando viaje');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.error ?? 'Error iniciando viaje'),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Error de conexión');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de conexión'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _stopTrip() async {
    setState(() => _isLoading = true);
    
    _locationService?.stopTracking();
    
    try {
      final response = await _apiService.stopTrip();
      
      if (response.success) {
        setState(() {
          _activeTrip = null;
          _error = null;
          _liveMetrics = null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Viaje completado'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else {
        setState(() => _error = response.error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.error ?? 'Error deteniendo viaje'),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Error de conexión');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startLocationTracking({String? deliveryName}) {
    _metricsSubscription?.cancel();
    _locationService?.startTracking(deliveryName: deliveryName);
    _metricsSubscription = _locationService?.metrics.listen((metrics) {
      if (mounted) {
        setState(() => _liveMetrics = metrics);
      }
    });
    _startTripPolling();
  }

  void _startTripPolling() {
    _tripPollingTimer?.cancel();
    _tripPollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || _activeTrip == null) return;
      try {
        final response = await _apiService.getActiveTrip();
        if (response.success && response.data == null) {
          // Trip was stopped externally (by admin)
          _locationService?.stopTracking();
          _tripPollingTimer?.cancel();
          if (mounted) {
            setState(() {
              _activeTrip = null;
              _liveMetrics = null;
            });
            _showTripStoppedDialog({'totalMileage': 0, 'duration': 0});
          }
        }
      } catch (_) {}
    });
  }

  void _logout() {
    _locationService?.stopTracking();
    _socketService.disconnect();
    context.read<AuthBloc>().add(LogoutRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        User? user;
        if (state is AuthAuthenticated) {
          user = state.user;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Boston Tracker'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _logout,
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(user),
        );
      },
    );
  }

  Widget _buildContent(User? user) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryColor,
                    child: Text(
                      user?.name.substring(0, 1).toUpperCase() ?? 'D',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, ${user?.name ?? 'Delivery'}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          user?.employeeId ?? '',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Trip Status
          if (_activeTrip != null) ...[
            Text(
              'Viaje Activo',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _buildTripCard(),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'El viaje solo puede ser finalizado por el administrador.',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // No active trip
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.local_shipping,
                      size: 80,
                      color: AppTheme.textSecondary.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No hay viaje activo',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Presiona el botón para iniciar',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _startTrip,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('INICIAR VIAJE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.successColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripCard() {
    final distanceKm = _liveMetrics != null
        ? _liveMetrics!.totalDistanceM / 1000
        : _activeTrip?.mileage ?? 0.0;
    final distanceStr = distanceKm >= 1
        ? '${distanceKm.toStringAsFixed(2)} km'
        : '${(_liveMetrics?.totalDistanceM ?? ((_activeTrip?.mileage ?? 0) * 1000).round())} m';
    final speedStr = '${_liveMetrics?.currentSpeed ?? _activeTrip?.averageSpeed.round() ?? 0} km/h';
    final durationSec = _liveMetrics?.totalTime ?? _activeTrip?.duration ?? 0;
    final durationStr = durationSec >= 3600
        ? '${durationSec ~/ 3600}h ${(durationSec % 3600) ~/ 60}m'
        : durationSec >= 60
            ? '${durationSec ~/ 60}m ${durationSec % 60}s'
            : '${durationSec}s';

    return Card(
      color: AppTheme.successColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(Icons.route, distanceStr, 'Distancia'),
                _buildMetricItem(Icons.timer, durationStr, 'Duración'),
                _buildMetricItem(Icons.speed, speedStr, 'Velocidad'),
              ],
            ),
            if (_liveMetrics != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricItem(
                    Icons.speed,
                    '${_liveMetrics!.maxSpeed} km/h',
                    'Vel. Máx',
                  ),
                  _buildMetricItem(
                    Icons.gps_fixed,
                    '${_liveMetrics!.validLocations}',
                    'Puntos GPS',
                  ),
                  _buildMetricItem(
                    Icons.trending_up,
                    '${_liveMetrics!.averageSpeed} km/h',
                    'Vel. Prom',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.successColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.successColor,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    _socketSubscription?.cancel();
    _tripPollingTimer?.cancel();
    _locationService?.dispose();
    _socketService.dispose();
    super.dispose();
  }
}
