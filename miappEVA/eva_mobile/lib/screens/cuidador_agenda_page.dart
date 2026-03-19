import 'package:flutter/material.dart';

import '../models/cuidador_agenda_item.dart';
import '../services/cuidador_agenda_service.dart';
import '../widgets/cuidador_agenda_card.dart';

typedef AgendaDateAction = Future<void> Function(DateTime date);
typedef AgendaItemAction = Future<void> Function(CuidadorAgendaItem item);

class CuidadorAgendaPage extends StatefulWidget {
  final List<CuidadorAgendaItem> initialItems;
  final DateTime initialSelectedDate;
  final AgendaDateAction onCreateAlarm;
  final AgendaDateAction onCreateAppointment;
  final AgendaItemAction onEditItem;
  final AgendaItemAction onDeleteItem;

  const CuidadorAgendaPage({
    super.key,
    required this.initialItems,
    required this.initialSelectedDate,
    required this.onCreateAlarm,
    required this.onCreateAppointment,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  @override
  State<CuidadorAgendaPage> createState() => _CuidadorAgendaPageState();
}

class _CuidadorAgendaPageState extends State<CuidadorAgendaPage> {
  late List<CuidadorAgendaItem> _items;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _items = List<CuidadorAgendaItem>.from(widget.initialItems);
    _selectedDate = widget.initialSelectedDate;
  }

  Future<void> _refreshAgenda() async {
    final updated = await CuidadorAgendaService.obtenerAgenda();
    if (!mounted) return;
    setState(() {
      _items = updated;
    });
  }

  Future<void> _handleCreateAlarm(DateTime date) async {
    await widget.onCreateAlarm(date);
    await _refreshAgenda();
  }

  Future<void> _handleCreateAppointment(DateTime date) async {
    await widget.onCreateAppointment(date);
    await _refreshAgenda();
  }

  Future<void> _handleEditItem(CuidadorAgendaItem item) async {
    await widget.onEditItem(item);
    await _refreshAgenda();
  }

  Future<void> _handleDeleteItem(CuidadorAgendaItem item) async {
    await widget.onDeleteItem(item);
    await _refreshAgenda();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDBDBDB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF123C92),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Agenda del cuidador',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
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
                  'Alarmas y citas',
                  style: TextStyle(
                    color: Color(0xFF20304D),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Aqui puedes revisar, crear, editar o eliminar recordatorios y citas del adulto mayor.',
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
          CuidadorAgendaCard(
            items: _items,
            selectedDate: _selectedDate,
            onSelectedDateChanged: (value) {
              setState(() {
                _selectedDate = value;
              });
            },
            onCreateAlarm: _handleCreateAlarm,
            onCreateAppointment: _handleCreateAppointment,
            onEditItem: _handleEditItem,
            onDeleteItem: _handleDeleteItem,
          ),
        ],
      ),
    );
  }
}
