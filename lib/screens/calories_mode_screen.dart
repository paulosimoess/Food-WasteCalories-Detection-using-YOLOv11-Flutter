import 'package:flutter/material.dart';
import 'calories_screen.dart';
import 'gallery_calories_screen.dart';

class CaloriesModeScreen extends StatelessWidget {
  const CaloriesModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contador de Calorias')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Escolher imagem da galeria',
              subtitle: 'Seleciona uma foto e calcula as calorias.',
              icon: Icons.photo_library_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GalleryCaloriesScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Abrir câmara (tempo real)',
              subtitle: 'Aponta para o prato e deteta em direto.',
              icon: Icons.camera_alt_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CaloriesScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
          color: Colors.white.withOpacity(0.04),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.7))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}