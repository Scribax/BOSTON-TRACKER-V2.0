import 'package:flutter/material.dart';
import '../config/theme.dart';

class TripScreen extends StatelessWidget {
  const TripScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Viaje'),
      ),
      body: const Center(
        child: Text('Pantalla de detalle del viaje'),
      ),
    );
  }
}
