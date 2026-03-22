import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';
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
      final oldLastId = _lastId;

      final result = await ChatService.obtenerMensajes(
        afterId: initial ? 0 : _lastId,
        limit: 50,
      );

      if (!mounted) return;

      final nuevos = result.mensajes;
      final hasNewMessages = initial || nuevos.isNotEmpty;

      setState(() {
        _messages = initial ? nuevos : [..._messages, ...nuevos];
        _currentUserId = result.emisorId;
        _lastId = result.lastId;
        _error = null;
      });

      if (_lastId > 0 && _lastId != oldLastId) {
        await ChatService.marcarVistos(upToId: _lastId);
      }

      if (hasNewMessages) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom(force: initial);
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

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final isNearBottom = (position.maxScrollExtent - position.pixels) <= 120;

    if (force || isNearBottom) {
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '--:--';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  PreferredSizeWidget _buildTopBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(58),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 58,
          color: const Color(0xFF123C92),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Chat con adulto mayor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
    );
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
      appBar: _buildTopBar(),
      body: Column(
        children: [
          Expanded(
            child: _buildMessagesList(),
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _startVoiceInput,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          _listening ? Colors.red : const Color(0xFF123C92),
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 30,
          color: const Color(0xFF123C92),
        ),
      ),
    );
  }
}