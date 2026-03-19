import 'package:flutter/material.dart';
import '../models/cuidador_agenda_item.dart';

class CuidadorAgendaListItem extends StatelessWidget {
  final CuidadorAgendaItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const CuidadorAgendaListItem({
    super.key,
    required this.item,
    this.onEdit,
    this.onDelete,
  });

  Color _badgeColor() {
    if (!item.active) {
      return const Color(0xFF9AA3B8);
    }
    return item.type == 'cita'
        ? const Color(0xFFEF8A17)
        : const Color(0xFF1F9D55);
  }

  String _badgeLabel() {
    if (!item.active) {
      return 'INACTIVA';
    }
    return item.type == 'cita' ? 'CITA' : 'ALARMA';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD9E1F2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF20304D),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _badgeColor(),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _badgeLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.timeText,
                style: const TextStyle(
                  color: Color(0xFF20304D),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_horiz,
                  color: Color(0xFF5E6A86),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit?.call();
                  } else if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Editar'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Eliminar'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
