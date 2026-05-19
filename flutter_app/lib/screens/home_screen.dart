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
  Trip? _activeTrip;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    final storageService = StorageService();
    await storageService.init();
    final apiService = ApiService(storageService);
    
    _locationService = LocationService(apiService);
    
    final user = await storageService.getUser();
    if (user != null && user.token != null) {
      _socketService.connect(user.id, user.token!);
      _setupSocketListeners();
    }
    
    _loadActiveTrip();
  }

  void _setupSocketListeners() {
    _socketService.events.listen((event) {
      if (event['type'] == 'tripStopped') {
        final data = event['data'];
        _showTripStoppedDialog(data);
      }
    });
  }

  void _showTripStoppedDialog(Map<String, dynamic> data) {
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
          'Distancia: ${(data['totalMileage'] ?? 0).toStringAsFixed(2)} km\n'
          'Duración: ${(data['duration'] ?? 0) ~/ 60} min',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _stopTrip();
            },
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadActiveTrip() async {
    setState(() => _isLoading = true);
    
    try {
      final storageService = StorageService();
      await storageService.init();
      final apiService = ApiService(storageService);
      
      final response = await apiService.getActiveTrip();
      
      if (response.success) {
        setState(() {
          _activeTrip = response.data;
          _error = null;
        });
        
        // If has active trip, resume tracking
        if (_activeTrip != null && _activeTrip!.isActive) {
          _startLocationTracking();
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
      final storageService = StorageService();
      await storageService.init();
      final apiService = ApiService(storageService);
      
      final response = await apiService.startTrip();
      
      if (response.success && response.data != null) {
        setState(() {
          _activeTrip = response.data;
          _error = null;
        });
        
        _startLocationTracking();
        
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
      final storageService = StorageService();
      await storageService.init();
      final apiService = ApiService(storageService);
      
      final response = await apiService.stopTrip();
      
      if (response.success) {
        setState(() {
          _activeTrip = null;
          _error = null;
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

  void _startLocationTracking() {
    _locationService?.startTracking();
    
    _locationService?.metrics.listen((metrics) {
      // Update UI with real-time metrics
      if (mounted) {
        setState(() {});
      }
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
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _stopTrip,
                icon: const Icon(Icons.stop),
                label: const Text('DETENER VIAJE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dangerColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
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
    return Card(
      color: AppTheme.successColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  Icons.route,
                  _activeTrip?.formattedMileage ?? '0 m',
                  'Distancia',
                ),
                _buildMetricItem(
                  Icons.timer,
                  _activeTrip?.formattedDuration ?? '0s',
                  'Duración',
                ),
                _buildMetricItem(
                  Icons.speed,
                  '${_activeTrip?.averageSpeed.toStringAsFixed(0) ?? 0} km/h',
                  'Velocidad',
                ),
              ],
            ),
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
    _locationService?.dispose();
    _socketService.dispose();
    super.dispose();
  }
}
