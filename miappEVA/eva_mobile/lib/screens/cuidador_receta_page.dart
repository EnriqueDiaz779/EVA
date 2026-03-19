import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/alarmas_local_service.dart';
import '../services/medicamento_service.dart';

class CuidadorRecetaPage extends StatefulWidget {
  const CuidadorRecetaPage({super.key});

  @override
  State<CuidadorRecetaPage> createState() => _CuidadorRecetaPageState();
}

class _CuidadorRecetaPageState extends State<CuidadorRecetaPage> {
  final ImagePicker _picker = ImagePicker();

  File? _selectedImage;
  bool _processing = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _pickRecipe(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _selectedImage = File(image.path);
        _error = null;
        _result = null;
      });

      await _processRecipe();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _processRecipe() async {
    final image = _selectedImage;
    if (image == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final result = await MedicamentoService.crearAlarmasDesdeRecetaCuidador(
        imageFile: image,
      );

      await AlarmasLocalService.sincronizarDesdeBackend();

      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _processing = false;
      });
    }
  }

  Widget _buildSourceButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: _processing ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF123C92),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meds = (_result?['medicamentos'] as List?) ?? const [];
    final adulto = _result?['adulto'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: const Color(0xFFDBDBDB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF123C92),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Escanear receta',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crear alarmas desde receta',
                  style: TextStyle(
                    color: Color(0xFF20304D),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Toma una foto o elige una imagen de la galeria. La IA analizara la receta y generara las alarmas del adulto vinculado.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSourceButton(
                label: 'Tomar foto',
                icon: Icons.photo_camera_outlined,
                onTap: () => _pickRecipe(ImageSource.camera),
              ),
              const SizedBox(width: 12),
              _buildSourceButton(
                label: 'Galeria',
                icon: Icons.photo_library_outlined,
                onTap: () => _pickRecipe(ImageSource.gallery),
              ),
            ],
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.file(
                  _selectedImage!,
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
          if (_processing) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE4E2),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF97066)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
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
                  Text(
                    (_result?['message'] ?? 'Resultado de la receta').toString(),
                    style: const TextStyle(
                      color: Color(0xFF20304D),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (adulto != null)
                    Text(
                      'Adulto: ${(adulto['nombre'] ?? 'Sin nombre').toString()}',
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Alarmas creadas: ${(_result?['alarmas_creadas'] ?? 0).toString()}',
                    style: const TextStyle(
                      color: Color(0xFF123C92),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (meds.isEmpty)
                    const Text(
                      'No se detectaron medicamentos en la receta.',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    ...meds.map((item) {
                      final med = Map<String, dynamic>.from(item as Map);
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFD0D5DD)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (med['nombre'] ?? 'Medicamento').toString(),
                              style: const TextStyle(
                                color: Color(0xFF20304D),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Dosis: ${(med['dosis'] ?? 'No especificada').toString()}',
                              style: const TextStyle(
                                color: Color(0xFF475467),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Frecuencia: ${(med['frecuencia'] ?? 'No especificada').toString()}',
                              style: const TextStyle(
                                color: Color(0xFF475467),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Alarmas creadas: ${(med['alarmas_creadas'] ?? 0).toString()}',
                              style: const TextStyle(
                                color: Color(0xFF123C92),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
