import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';
import '../services/notificacion_service.dart';
import '../services/tts_service.dart';

class CuidadorChatPage extends StatefulWidget {
  const CuidadorChatPage({super.key});

  @override
  State<CuidadorChatPage> createState() => _CuidadorChatPageState();
}

class _CuidadorChatPageState extends State<CuidadorChatPage> {
  static const Duration _pollInterval = Duration(seconds: 3);

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  List<ChatMessageModel> _messages = const [];
  int _currentUserId = 0;
  int _lastId = 0;
  bool _loading = true;
  bool _sending = false;
  bool _speechAvailable = false;
  bool _listening = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    await TtsService.inicializar();
    await _initSpeech();
    await _loadMessages(initial: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _loadMessages();
    });
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening' || status == 'done') {
            setState(() {
              _listening = false;
            });
          }
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _listening = false;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
      });
    }
  }

  Future<void> _loadMessages({bool initial = false}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await ChatService.obtenerMensajes();
      if (!mounted) return;

      final nextMessages = result.mensajes;
      final nextLastId = result.lastId;
      final prevLastId = _lastId;
      final shouldScroll = _messages.isEmpty || nextMessages.length > _messages.length;

      if (!initial && nextLastId > prevLastId) {
        final incoming = nextMessages.where((message) {
          return message.id > prevLastId && message.emisorId != result.emisorId;
        }).toList();

        if (incoming.isNotEmpty) {
          final latest = incoming.last;
          await NotificacionService.mostrarNotificacionMensajeParaCuidador(
            id: 510000 + latest.id,
            cuerpo: latest.mensaje,
          );
        }
      }

      setState(() {
        _messages = nextMessages;
        _currentUserId = result.emisorId;
        _lastId = nextLastId;
        _error = null;
      });

      if (_lastId > 0) {
        await ChatService.marcarVistos(upToId: _lastId);
      }

      if (shouldScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _sendTypedMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
    });

    try {
      await ChatService.enviarMensaje(mensaje: text, tipo: 'texto');
      _messageController.clear();
      await _loadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _sending = false;
      });
    }
  }

  Future<void> _startVoiceInput() async {
    if (!_speechAvailable || _sending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El reconocimiento de voz no esta disponible.')),
      );
      return;
    }

    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() {
        _listening = false;
      });
      return;
    }

    await TtsService.hablar('Te escucho. Dicta el mensaje para tu adulto mayor.');

    if (!mounted) return;
    setState(() {
      _listening = true;
    });

    await _speech.listen(
      localeId: 'es_MX',
      partialResults: false,
      onResult: (result) async {
        if (!result.finalResult) return;
        final recognized = result.recognizedWords.trim();
        await _speech.stop();
        if (!mounted) return;
        setState(() {
          _listening = false;
        });
        if (recognized.isEmpty) return;
        await _confirmAndSendVoice(recognized);
      },
    );
  }

  Future<void> _confirmAndSendVoice(String text) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar mensaje'),
        content: Text('Dijiste:\n\n$text'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Repetir'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _sending = true;
    });

    try {
      await ChatService.enviarMensaje(mensaje: text, tipo: 'audio');
      await _loadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _sending = false;
      });
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '--:--';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE4E4E4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF123C92),
        foregroundColor: Colors.white,
        title: const Text(
          'Chat con adulto mayor',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final mine = message.emisorId == _currentUserId;
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              constraints: const BoxConstraints(maxWidth: 280),
                              decoration: BoxDecoration(
                                color: mine ? const Color(0xFF123C92) : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 8,
                                    color: Colors.black12,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (message.tipo == 'audio')
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        'Mensaje por voz',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: mine ? Colors.white70 : const Color(0xFF123C92),
                                        ),
                                      ),
                                    ),
                                  Text(
                                    message.mensaje,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.35,
                                      color: mine ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _formatTime(message.creadoEn),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: mine ? Colors.white70 : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              color: const Color(0xFFE4E4E4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendTypedMessage(),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _startVoiceInput,
                    style: IconButton.styleFrom(
                      backgroundColor: _listening ? Colors.red : const Color(0xFF123C92),
                      minimumSize: const Size(48, 48),
                    ),
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendTypedMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      minimumSize: const Size(48, 48),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
