import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';
import '../services/tts_service.dart';

class AdultoChatPage extends StatefulWidget {
  const AdultoChatPage({super.key});

  @override
  State<AdultoChatPage> createState() => _AdultoChatPageState();
}

class _AdultoChatPageState extends State<AdultoChatPage> {
  static const Duration _pollInterval = Duration(seconds: 3);

  final stt.SpeechToText _speech = stt.SpeechToText();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessageModel> _messages = const [];
  int _currentUserId = 0;
  int _lastId = 0;
  bool _loading = true;
  bool _speechAvailable = false;
  bool _listening = false;
  bool _sending = false;
  String _recognizedText = '';
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
      final shouldScroll = _messages.isEmpty || nextMessages.length > _messages.length;

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

  Future<void> _toggleListen() async {
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

    await TtsService.hablar('Te escucho. Dime el mensaje para tu cuidador.');

    if (!mounted) return;
    setState(() {
      _recognizedText = '';
      _listening = true;
    });

    await _speech.listen(
      localeId: 'es_MX',
      partialResults: true,
      onResult: (result) async {
        if (!mounted) return;
        setState(() {
          _recognizedText = result.recognizedWords;
        });

        if (!result.finalResult) return;
        final recognized = result.recognizedWords.trim();
        await _speech.stop();
        if (!mounted) return;
        setState(() {
          _listening = false;
        });
        if (recognized.isEmpty) return;
        await _confirmAndSend(recognized);
      },
    );
  }

  Future<void> _confirmAndSend(String text) async {
    await TtsService.hablar('Dijiste: $text. Confirma si este es el mensaje correcto.');

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar mensaje'),
        content: Text('Dijiste:\n\n$text'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, repetir'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Si, enviar'),
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
      await TtsService.hablar('Mensaje enviado correctamente.');
      await _loadMessages();
      if (!mounted) return;
      setState(() {
        _recognizedText = '';
      });
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
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE4E4E4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF173A8A),
        foregroundColor: Colors.white,
        title: const Text(
          'Chat con cuidador',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 12,
                  color: Colors.black12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Text(
              'Presiona el microfono, di tu mensaje y confirma antes de enviarlo a tu cuidador.',
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
                                color: mine ? const Color(0xFF173A8A) : Colors.white,
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
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  if (_recognizedText.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        _recognizedText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _toggleListen,
                      icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                      label: Text(
                        _sending
                            ? 'Enviando...'
                            : _listening
                                ? 'Escuchando...'
                                : 'Hablar con mi cuidador',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _listening ? Colors.red : const Color(0xFF173A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
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
