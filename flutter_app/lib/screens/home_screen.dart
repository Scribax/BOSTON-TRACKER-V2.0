import 'dart:ui' show FontFeature;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/auth/auth_bloc.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
import '../services/foreground_service.dart';
import '../services/destination_service.dart';
import '../models/trip.dart';
import '../models/user.dart';
import '../models/delivery_destination.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _socketService = SocketService();
  LocationService? _locationService;
  DestinationService? _destinationService;
  late StorageService _storageService;
  late ApiService _apiService;
  Trip? _activeTrip;
  bool _isLoading = false;
  String? _error;
  TripMetrics? _liveMetrics;
  DeliveryDestination? _lastDestination;
  StreamSubscription<TripMetrics>? _metricsSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketSubscription;
  StreamSubscription<DeliveryDestination>? _destinationSubscription;
  StreamSubscription<void>? _unauthorizedSubscription;
  Timer? _tripPollingTimer;
  Timer? _clockTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    // Reconnect socket if it dropped while in background
    if (!_socketService.isConnected) {
      final user = await _storageService.getUser();
      if (user != null && user.token != null) {
        _setupSocketListeners();
        _socketService.connect(user.id, user.token!);
      }
    }
    // Immediately check if trip was stopped while app was in background
    if (_activeTrip != null) {
      _loadActiveTripSilently();
    }
  }

  Future<void> _loadActiveTripSilently() async {
    try {
      final response = await _apiService.getActiveTrip();
      if (response.success && response.data == null && _activeTrip != null) {
        _locationService?.stopTracking();
        await ForegroundService.stopService();
        _tripPollingTimer?.cancel();
        _clockTimer?.cancel();
        final trip = _activeTrip;
        if (mounted) {
          setState(() {
            _activeTrip = null;
            _liveMetrics = null;
          });
          _showTripStoppedDialog({
            'totalMileage': trip?.mileage ?? 0,
            'duration': trip?.duration ?? 0,
          });
        }
      } else if (response.success && response.data != null) {
        if (mounted) setState(() => _activeTrip = response.data);
        final user = await _storageService.getUser();
        if (_activeTrip != null && user != null && user.name.isNotEmpty) {
          await _ensureForegroundTracking(userName: user.name);
        }
      }
    } catch (_) {}
  }

  Future<void> _initServices() async {
    _storageService = StorageService();
    await _storageService.init();
    _apiService = ApiService(_storageService);
    _locationService = LocationService(_apiService);
    _destinationService = DestinationService(_storageService);
    await _destinationService!.init();
    _destinationService!.bindAckEmitter((payload) {
      _socketService.emit('deliveryDestinationAck', payload);
    });
    _setupSocketListeners();

    _unauthorizedSubscription = _apiService.onUnauthorized.listen((_) {
      _locationService?.stopTracking();
      _destinationSubscription?.cancel();
      _socketService.disconnect();
      _storageService.clearAll();
      if (mounted) context.read<AuthBloc>().add(LogoutRequested());
    });

    final user = await _storageService.getUser();
    if (user != null && user.token != null) {
      _socketService.connect(user.id, user.token!);
    }
    _destinationSubscription = _destinationService?.destinations.listen((destination) {
      if (mounted) {
        setState(() => _lastDestination = destination);
      }
    });
    _lastDestination = await (_destinationService?.getLastDestination() ?? Future.value(null));
    
    _loadActiveTrip();
  }

  void _setupSocketListeners() {
    _socketSubscription?.cancel();
    _socketSubscription = _socketService.events.listen((event) async {
      if (event['type'] == 'tripStopped') {
        final data = event['data'];
        _locationService?.stopTracking();
        await ForegroundService.stopService();
        _tripPollingTimer?.cancel();
        _showTripStoppedDialog(data);
      } else if (event['type'] == 'forceLogout') {
        final reason = event['data']?['reason'] as String? ?? 'Tu cuenta fue desactivada.';
        _forceLogout(reason);
      } else if (event['type'] == 'networkRestored') {
        _locationService?.flushQueue();
      } else if (event['type'] == 'deliveryDestination') {
        final data = event['data'];
        _destinationService?.handleIncomingPayload(Map<String, dynamic>.from(data));
      } else if (event['type'] == 'deliveryDestinationAck') {
        // Backend ACK handled by socket service; no extra UI needed here.
      }
    });
  }

  Future<void> _showMapsFallback(DeliveryDestination destination) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('Abrir en navegador'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final uri = Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=${destination.latitude},${destination.longitude}',
                );
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copiar coordenadas'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Clipboard.setData(
                  ClipboardData(text: '${destination.latitude}, ${destination.longitude}'),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Coordenadas copiadas')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _forceLogout(String reason) async {
    _locationService?.stopTracking();
    await ForegroundService.stopService();
    _tripPollingTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _activeTrip = null;
      _liveMetrics = null;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: AppTheme.dangerColor),
            SizedBox(width: 8),
            Text('Sesión cerrada'),
          ],
        ),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthBloc>().add(LogoutRequested());
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _showTripStoppedDialog(Map<String, dynamic> data) {
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
          await _ensureForegroundTracking(userName: user?.name);
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
        await _ensureForegroundTracking(userName: user?.name);
        _startLocationTracking(deliveryName: user?.name);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.gps_fixed, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('¡Viaje iniciado! GPS activo y enviando señal.')),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    await ForegroundService.stopService();

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
    _startClock();
  }

  Future<void> _ensureForegroundTracking({String? userName}) async {
    final user = await _storageService.getUser();
    final tripId = _activeTrip?.id;
    if (user == null || tripId == null || user.token == null) return;

    await ForegroundService.saveCredentials(
      userId: user.id,
      token: user.token!,
      baseUrl: ApiService.baseUrl,
      deliveryName: userName ?? user.name,
    );

    final started = await ForegroundService.startService(
      deliveryName: userName ?? user.name,
      tripId: tripId,
    );
    if (started) {
      ForegroundService.sendCommand('updateMetadata');
    }
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeTrip != null) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(_activeTrip!.startTime).inSeconds;
        });
      }
    });
    // Set immediately so the UI shows the correct value right away
    if (_activeTrip != null) {
      _elapsedSeconds = DateTime.now().difference(_activeTrip!.startTime).inSeconds;
    }
  }

  String get _elapsedFormatted {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2,'0')}m';
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  void _startTripPolling() {
    _tripPollingTimer?.cancel();
    final String? trackedTripId = _activeTrip?.id;
    final DateTime startedAt = DateTime.now();
    _tripPollingTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || _activeTrip == null) return;
      // Grace period: ignore first 30s to avoid false positives during startup
      if (DateTime.now().difference(startedAt).inSeconds < 30) return;
      try {
        final response = await _apiService.getActiveTrip();
        if (response.success && response.data == null) {
          // Only stop if the trip that disappeared is the one we started
          if (_activeTrip?.id != trackedTripId) return;
          _locationService?.stopTracking();
          await ForegroundService.stopService();
          _tripPollingTimer?.cancel();
          if (mounted) {
            final trip = _activeTrip;
            setState(() {
              _activeTrip = null;
              _liveMetrics = null;
            });
            _showTripStoppedDialog({
              'totalMileage': trip?.mileage ?? 0,
              'duration': trip?.duration ?? 0,
            });
          }
        }
      } catch (_) {}
    });
  }

  void _logout() async {
    _locationService?.stopTracking();
    await ForegroundService.stopService();
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
                onPressed: _activeTrip != null ? null : _logout,
                tooltip: _activeTrip != null ? 'No podés cerrar sesión durante un viaje' : 'Cerrar sesión',
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
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
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

            if (_lastDestination != null) ...[
              Card(
                color: Colors.blue.shade50,
                child: ListTile(
                  leading: const Icon(Icons.place, color: Colors.blue),
                  title: Text(_lastDestination!.label ?? 'Última ubicación asignada'),
                  subtitle: Text(
                    '${_lastDestination!.latitude.toStringAsFixed(5)}, ${_lastDestination!.longitude.toStringAsFixed(5)}',
                  ),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      final opened = await _destinationService?.openInMaps(_lastDestination!) ?? false;
                      if (!opened) {
                        await _showMapsFallback(_lastDestination!);
                      }
                    },
                    child: const Text('Abrir'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
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
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.55,
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
            // Live clock
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    _elapsedFormatted,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: 2,
                    ),
                  ),
                  const Text('Tiempo transcurrido', style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricItem(Icons.route, distanceStr, 'Distancia'),
                  const SizedBox(width: 24),
                  _buildMetricItem(Icons.speed, speedStr, 'Velocidad'),
                ],
              ),
            ),
            if (_liveMetrics != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricItem(
                      Icons.speed,
                      '${_liveMetrics!.maxSpeed} km/h',
                      'Vel. Máx',
                    ),
                    const SizedBox(width: 24),
                    _buildMetricItem(
                      Icons.gps_fixed,
                      '${_liveMetrics!.validLocations}',
                      'Puntos GPS',
                    ),
                    const SizedBox(width: 24),
                    _buildMetricItem(
                      Icons.trending_up,
                      '${_liveMetrics!.averageSpeed} km/h',
                      'Vel. Prom',
                    ),
                  ],
                ),
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
    WidgetsBinding.instance.removeObserver(this);
    _metricsSubscription?.cancel();
    _socketSubscription?.cancel();
    _destinationSubscription?.cancel();
    _unauthorizedSubscription?.cancel();
    _tripPollingTimer?.cancel();
    _clockTimer?.cancel();
    _locationService?.dispose();
    _socketService.dispose();
    _apiService.dispose();
    super.dispose();
  }
}
