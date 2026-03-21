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
      _listening = true;
    });

    await _speech.listen(
      localeId: 'es_MX',
      partialResults: true,
      onResult: (result) async {
        if (!mounted) return;
        setState(() {
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
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Confirmar mensaje',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Dijiste:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF173A8A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Enviar',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5E7EB),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Repetir',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 170), // 👈 IMPORTANTE
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final mine = message.emisorId == _currentUserId;

                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
                          constraints: const BoxConstraints(maxWidth: 310),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFF173A8A)
                                : Colors.white,
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
                                  fontSize: 20,
                                  height: 1.45,
                                  color: mine
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _formatTime(message.creadoEn),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: mine
                                      ? Colors.white70
                                      : Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            floatingActionButton: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _sending ? null : _toggleListen,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 20,
                            color: Colors.black26,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Container(
                          color: _listening
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF173A8A),
                          child: Icon(
                            _listening ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                            size: 55,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sending
                        ? 'Enviando...'
                        : _listening
                            ? 'Escuchando...'
                            : 'Hablar con mi cuidador',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            ),

            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
          );
            } 
          }
