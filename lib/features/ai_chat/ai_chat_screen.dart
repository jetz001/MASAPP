import 'package:path/path.dart' as p;
// lib/features/ai_chat/ai_chat_screen.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/ai_service.dart';
import '../../core/ai/ai_tool_handler.dart';
import '../../core/ai/rag_document_service.dart';
import '../../core/ai/ai_presentation_pdf_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/auth/auth_provider.dart';
import '../tools_equipment/tool_provider.dart';
import 'ai_chat_provider.dart';
import 'widgets/chat_history_dialog.dart';

class _PendingAttachmentItem {
  final File file;
  final String name;
  final int size;
  final String ext;
  final Uint8List? imageBytes;

  const _PendingAttachmentItem({
    required this.file,
    required this.name,
    required this.size,
    required this.ext,
    this.imageBytes,
  });

  bool get isImage =>
      ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'].contains(ext.toLowerCase());
  bool get isPdf => ext.toLowerCase() == 'pdf';
  bool get isSpreadsheet => ['xlsx', 'xls', 'csv'].contains(ext.toLowerCase());
  bool get isWord => ['doc', 'docx'].contains(ext.toLowerCase());
  bool get isDocument =>
      ['pdf', 'xlsx', 'xls', 'csv', 'txt', 'md', 'doc', 'docx'].contains(ext.toLowerCase());
}

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _sending = false;
  bool _isDragging = false;
  bool _isPasting = false;
  DateTime _lastPasteTime = DateTime.fromMillisecondsSinceEpoch(0);

  static const int _maxAttachments = 5;
  final List<_PendingAttachmentItem> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    Future.microtask(() => ref.read(aiChatProvider.notifier).reloadModel());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _handleClipboardPaste();
    }
    return false;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<bool> _addSingleFile(File file, {bool showFeedback = true}) async {
    try {
      if (!await file.exists()) {
        if (showFeedback && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่พบไฟล์ที่เลือก'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      if (_pendingAttachments.length >= _maxAttachments) {
        if (showFeedback && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('สามารถแนบไฟล์ได้สูงสุด 5 ไฟล์พร้อมกันครับ'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }

      if (_pendingAttachments.any((a) => a.file.path == file.path)) {
        if (showFeedback && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไฟล์นี้ถูกแนบอยู่แล้ว'),
              backgroundColor: Colors.grey,
            ),
          );
        }
        return false;
      }

      final name = p.basename(file.path);
      final size = await file.length();
      final ext = p.extension(file.path).toLowerCase().replaceAll('.', '');

      final allowedExtensions = [
        'pdf',
        'xlsx',
        'xls',
        'csv',
        'txt',
        'md',
        'doc',
        'docx',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'bmp',
        'gif',
      ];

      if (!allowedExtensions.contains(ext)) {
        if (showFeedback && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'ไม่รองรับไฟล์ประเภท .$ext (รองรับ PDF, Word, Excel, CSV, TXT, รูปภาพ)',
              ),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
        return false;
      }

      Uint8List? imageBytes;
      if (['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'].contains(ext)) {
        try {
          imageBytes = await file.readAsBytes();
        } catch (_) {}
      }

      setState(() {
        _pendingAttachments.add(_PendingAttachmentItem(
          file: file,
          name: name,
          size: size,
          ext: ext,
          imageBytes: imageBytes,
        ));
      });

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.attachment_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'แนบไฟล์ $name เรียบร้อยแล้ว (${_pendingAttachments.length}/$_maxAttachments)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
      return true;
    } catch (e) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการโหลดไฟล์: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _handleMultipleFiles(List<File> files) async {
    int added = 0;
    for (final f in files) {
      if (_pendingAttachments.length >= _maxAttachments) break;
      final ok = await _addSingleFile(f, showFeedback: false);
      if (ok) added++;
    }
    if (added > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('แนบไฟล์เรียบร้อยแล้ว (${_pendingAttachments.length}/$_maxAttachments)'),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        allowedExtensions: [
          'pdf',
          'xlsx',
          'xls',
          'csv',
          'txt',
          'md',
          'doc',
          'docx',
          'png',
          'jpg',
          'jpeg',
          'webp',
          'bmp',
          'gif',
        ],
        dialogTitle: 'เลือกไฟล์เอกสาร PDF, Word, Excel หรือรูปภาพ (สูงสุด 5 ไฟล์)',
      );

      if (result == null || result.files.isEmpty) return;
      final files = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
      await _handleMultipleFiles(files);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถเลือกไฟล์ได้: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _handleClipboardPaste({bool allowTextPaste = true}) async {
    final now = DateTime.now();
    if (_isPasting || now.difference(_lastPasteTime).inMilliseconds < 300) {
      return true;
    }
    _isPasting = true;
    _lastPasteTime = now;

    try {
      // 1. Check if clipboard contains raw image bytes (e.g. Snipping Tool, Screenshot, Copy Image)
      try {
        final imageBytes = await Pasteboard.image;
        if (imageBytes != null && imageBytes.isNotEmpty) {
          if (_pendingAttachments.length >= _maxAttachments) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('สามารถแนบไฟล์ได้สูงสุด 5 ไฟล์พร้อมกันครับ'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return true;
          }

          final tempDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final tempFile = File(p.join(tempDir.path, 'screenshot_$timestamp.png'));
          await tempFile.writeAsBytes(imageBytes);

          setState(() {
            _pendingAttachments.add(_PendingAttachmentItem(
              file: tempFile,
              name: 'screenshot_$timestamp.png',
              size: imageBytes.length,
              ext: 'png',
              imageBytes: imageBytes,
            ));
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.image_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('วางรูปภาพจาก Clipboard เรียบร้อยแล้ว (${_pendingAttachments.length}/$_maxAttachments)'),
                  ],
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          }
          return true;
        }
      } catch (e) {
        debugPrint('[Pasteboard.image error]: $e');
      }

      // 2. Check if clipboard contains copied files (e.g. Ctrl+C in File Explorer)
      try {
        final files = await Pasteboard.files();
        if (files.isNotEmpty) {
          final fileList = files.map((p) => File(p)).where((f) => f.existsSync()).toList();
          if (fileList.isNotEmpty) {
            await _handleMultipleFiles(fileList);
            return true;
          }
        }
      } catch (e) {
        debugPrint('[Pasteboard.files error]: $e');
      }

      // 3. Check plain text (can be a local file path OR normal text)
      try {
        final plainData = await Clipboard.getData(Clipboard.kTextPlain);
        final rawText = plainData?.text ?? '';
        if (rawText.isNotEmpty) {
          final trimmed = rawText.trim();
          final cleaned = trimmed.replaceAll('"', '').replaceAll("'", '');
          final file = File(cleaned);
          if (cleaned.length < 300 && await file.exists()) {
            final ext = p.extension(cleaned).toLowerCase().replaceAll('.', '');
            final supported = [
              'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif',
              'pdf', 'xlsx', 'xls', 'csv', 'txt', 'md', 'doc', 'docx'
            ];
            if (supported.contains(ext)) {
              await _addSingleFile(file);
              return true;
            }
          }

          // If allowTextPaste is true, paste normal text directly into text field!
          if (allowTextPaste) {
            final curText = _controller.text;
            final selection = _controller.selection;
            final start = (selection.start >= 0 && selection.start <= curText.length)
                ? selection.start
                : curText.length;
            final end = (selection.end >= 0 && selection.end <= curText.length)
                ? selection.end
                : curText.length;
            final newText = curText.replaceRange(start, end, rawText);
            _controller.text = newText;
            _controller.selection = TextSelection.collapsed(offset: start + rawText.length);
            _focusNode.requestFocus();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: const [
                      Icon(Icons.paste_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('วางข้อความเรียบร้อยแล้ว'),
                    ],
                  ),
                  duration: const Duration(seconds: 1),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              );
            }
            return true;
          }
        }
      } catch (_) {}

      // 4. Windows PowerShell Native Clipboard Fallback for images
      if (Platform.isWindows) {
        try {
          final tempDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final tempFile = File(p.join(tempDir.path, 'screenshot_$timestamp.png'));
          final targetPath = tempFile.path.replaceAll(r'\', r'/');
          final script = [
            'Add-Type -AssemblyName System.Windows.Forms;',
            'Add-Type -AssemblyName System.Drawing;',
            r'$img = [System.Windows.Forms.Clipboard]::GetImage();',
            r'if ($null -ne $img) {',
            r'$img.Save("' + targetPath + r'", [System.Drawing.Imaging.ImageFormat]::Png);',
            '  Write-Output "OK";',
            r'} else {',
            r'  $files = [System.Windows.Forms.Clipboard]::GetFileDropList();',
            r'  if ($null -ne $files -and $files.Count -gt 0) {',
            r'    foreach ($f in $files) { Write-Output "FILE:$f"; }',
            r'  }',
            r'}',
          ].join(' ');
          final res = await Process.run(
            'powershell',
            ['-NoProfile', '-NonInteractive', '-Command', script],
          );
          if (res.exitCode == 0 && await tempFile.exists()) {
            final imageBytes = await tempFile.readAsBytes();
            if (imageBytes.isNotEmpty) {
              if (_pendingAttachments.length >= _maxAttachments) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('สามารถแนบไฟล์ได้สูงสุด 5 ไฟล์พร้อมกันครับ'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                return true;
              }

              setState(() {
                _pendingAttachments.add(_PendingAttachmentItem(
                  file: tempFile,
                  name: 'screenshot_$timestamp.png',
                  size: imageBytes.length,
                  ext: 'png',
                  imageBytes: imageBytes,
                ));
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.image_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text('วางรูปภาพจาก Clipboard เรียบร้อยแล้ว (${_pendingAttachments.length}/$_maxAttachments)'),
                      ],
                    ),
                    duration: const Duration(seconds: 2),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              }
              return true;
            }
          }
        } catch (e) {
          debugPrint('[Windows PowerShell Clipboard Fallback Error]: $e');
        }
      }
    } catch (e) {
      debugPrint('Clipboard paste error: $e');
    } finally {
      _isPasting = false;
    }
    return false;
  }

  void _clearAttachments() {
    setState(() {
      _pendingAttachments.clear();
    });
  }

  Future<void> _showRagDocumentsDialog() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RagDocumentsSheet(
        onRefresh: () => ref.read(aiChatProvider.notifier).reloadModel(),
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    if (_sending) return;

    final user = ref.read(authProvider);
    final attachments = List<_PendingAttachmentItem>.from(_pendingAttachments);

    setState(() {
      _sending = true;
      _pendingAttachments.clear();
    });
    _controller.clear();

    try {
      String finalPrompt = text;
      String? displayText;

      if (attachments.isNotEmpty) {
        final List<String> promptSections = [];
        final List<String> displayNames = [];

        for (int idx = 0; idx < attachments.length; idx++) {
          final item = attachments[idx];
          displayNames.add(item.name);

          if (['pdf', 'xlsx', 'xls', 'txt', 'md', 'csv', 'doc', 'docx'].contains(item.ext)) {
            String docName = item.name;
            String extractedText = '';
            try {
              final res = await RagDocumentService.ingestDocument(file: item.file);
              docName = res['file_name'] ?? item.name;
              extractedText = res['extracted_text']?.toString() ?? '';
            } catch (_) {
              extractedText = '(เอกสารแนบ: $docName)';
            }

            final truncatedText = extractedText.length > 15000
                ? '${extractedText.substring(0, 15000)}\n...(ตัดทอนบางส่วน)...'
                : extractedText;

            promptSections.add(
              '${idx + 1}. [เอกสาร ${item.ext.toUpperCase()}] ชื่อ: "$docName"\n'
              '   - ที่อยู่ไฟล์ (file_path): "${item.file.path}"\n'
              '   - เนื้อหา:\n'
              '${truncatedText.isNotEmpty ? truncatedText : "(ไม่มีเลเยอร์ข้อความหรือเป็นภาพสแกน)"}',
            );
          } else {
            // Image
            promptSections.add(
              '${idx + 1}. [รูปภาพ] ชื่อ: "${item.name}"\n'
              '   - ที่อยู่ไฟล์ (file_path): "${item.file.path}"\n'
              '   - ขนาด: ${(item.size / 1024).toStringAsFixed(1)} KB',
            );
          }
        }

        final userPrompt = text.isNotEmpty
            ? text
            : (attachments.any((a) => a.isDocument)
                ? 'ช่วยอ่านข้อมูลและสเปกทางเทคนิคจากเอกสารที่แนบ แล้วอัปเดตลงระบบให้หน่อยครับ'
                : 'ช่วยอ่านข้อมูลและสเปกทางเทคนิคจากภาพที่แนบ แล้วอัปเดตลงระบบให้หน่อยครับ');

        displayText = attachments.length == 1
            ? '📎 [แนบไฟล์: ${displayNames.first}]\n$userPrompt'
            : '📎 [แนบ ${attachments.length} ไฟล์: ${displayNames.join(', ')}]\n$userPrompt';

        finalPrompt = '$userPrompt\n\n'
            '--- ข้อมูลไฟล์แนบทั้งหมด (จำนวน ${attachments.length} ไฟล์) ---\n'
            '${promptSections.join('\n\n')}\n'
            '--- สิ้นสุดข้อมูลไฟล์แนบ ---';
      }

      final imageBytesList = <Uint8List>[];
      final aiAttachments = <AiAttachment>[];

      for (final a in attachments) {
        Uint8List? bytes = a.imageBytes;
        if (bytes == null || bytes.isEmpty) {
          try {
            if (await a.file.exists()) {
              bytes = await a.file.readAsBytes();
            }
          } catch (_) {}
        }

        if (bytes != null && bytes.isNotEmpty) {
          String mimeType = 'application/octet-stream';
          final ext = a.ext.toLowerCase();
          if (ext == 'pdf') {
            mimeType = 'application/pdf';
          } else if (ext == 'png') {
            mimeType = 'image/png';
          } else if (ext == 'jpg' || ext == 'jpeg') {
            mimeType = 'image/jpeg';
          } else if (ext == 'webp') {
            mimeType = 'image/webp';
          } else if (ext == 'gif') {
            mimeType = 'image/gif';
          }

          if (a.isImage) {
            imageBytesList.add(bytes);
          }

          aiAttachments.add(AiAttachment(
            bytes: bytes,
            mimeType: mimeType,
            fileName: a.name,
          ));
        }
      }

      await ref.read(aiChatProvider.notifier).sendMessage(
            finalPrompt,
            displayText: displayText,
            userId: user?.userId,
            attachments: aiAttachments,
            imageBytesList: imageBytesList,
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการส่งข้อความ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(aiChatProvider);

    // Scroll when messages change
    if (state.messages.isNotEmpty) _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text('MASAPP AI Assistant'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'ประวัติการสนทนา (Chat History)',
            onPressed: () => ChatHistoryDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'เริ่มการสนทนาใหม่ (New Chat)',
            onPressed: () => ref.read(aiChatProvider.notifier).newChat(),
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_rounded),
            tooltip: 'คลังคู่มือ & เอกสาร RAG',
            onPressed: _showRagDocumentsDialog,
          ),
          if (state.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'ล้างบทสนทนานี้',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('ล้างบทสนทนา?'),
                    content: const Text(
                      'ประวัติการสนทนาจะถูกลบออกจากหน้าจอนี้',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('ยกเลิก'),
                      ),
                      FilledButton(
                        onPressed: () {
                          ref.read(aiChatProvider.notifier).clearChat();
                          Navigator.pop(ctx);
                        },
                        child: const Text('ล้าง'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: (detail) async {
            setState(() => _isDragging = false);
            if (detail.files.isNotEmpty) {
              final files = detail.files.map((f) => File(f.path)).toList();
              await _handleMultipleFiles(files);
            }
          },
          child: Stack(
          children: [
            !state.isConfigured
                ? _buildNotConfigured(theme)
                : Column(
                    children: [
                      Expanded(
                        child: state.messages.isEmpty
                            ? _buildWelcome(theme)
                            : _buildMessageList(state, theme),
                      ),
                      _buildInputBar(theme),
                    ],
                  ),
            if (_isDragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.25),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primary,
                                  theme.colorScheme.tertiary,
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.file_download_rounded,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'วางไฟล์ที่นี่เพื่อแนบเข้าสู่ AI Chat',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'รองรับไฟล์คู่มือ PDF, สเปรดชีต Excel, CSV, Text และรูปภาพ',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotConfigured(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.key_off_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'ยังไม่ได้ตั้งค่า API Key',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'กรุณาเลือกผู้ให้บริการ AI แล้วตั้งค่า API Key\nAI จะค้นหาได้เฉพาะข้อมูลในฐานข้อมูล MASAPP เท่านั้น\nหากเป็น provider บน cloud ระบบจะแจ้งก่อนเมื่อไม่มีอินเทอร์เน็ต',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _showApiKeyDialog,
              icon: const Icon(Icons.key),
              label: const Text('ตั้งค่า API Key'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcome(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'สวัสดีครับ! ผม MASAPP AI',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'ผมสามารถช่วยค้นหาและวิเคราะห์ข้อมูลในระบบได้ครับ\nลองถามเกี่ยวกับเครื่องจักร ใบแจ้งซ่อม อะไหล่ หรือสถิติต่างๆ',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(AiChatState state, ThemeData theme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: state.messages.length,
      itemBuilder: (ctx, i) => _MessageBubble(message: state.messages[i]),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_pendingAttachments.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.attach_file_rounded,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ไฟล์แนบ (${_pendingAttachments.length}/$_maxAttachments)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      if (_pendingAttachments.length > 1)
                        InkWell(
                          onTap: _sending ? null : _clearAttachments,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Text(
                              'ลบทั้งหมด',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade400,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(_pendingAttachments.length, (idx) {
                        final item = _pendingAttachments[idx];
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.isImage && item.imageBytes != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.memory(
                                    item.imageBytes!,
                                    width: 22,
                                    height: 22,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                Icon(
                                  item.isPdf
                                      ? Icons.picture_as_pdf_rounded
                                      : item.isSpreadsheet
                                          ? Icons.table_chart_rounded
                                          : item.isImage
                                              ? Icons.image_rounded
                                              : Icons.description_rounded,
                                  size: 18,
                                  color: item.isSpreadsheet
                                      ? Colors.green.shade700
                                      : item.isPdf
                                          ? Colors.red.shade600
                                          : theme.colorScheme.primary,
                                ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 160),
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '(${ (item.size / 1024).toStringAsFixed(0) } KB)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: _sending
                                    ? null
                                    : () => setState(() => _pendingAttachments.removeAt(idx)),
                                borderRadius: BorderRadius.circular(10),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file_rounded),
                tooltip: 'แนบไฟล์เอกสาร PDF / Excel / Word / รูปภาพ (สูงสุด 5 ไฟล์)',
                onPressed: _sending ? null : _pickAttachment,
              ),
              IconButton(
                icon: const Icon(Icons.content_paste_go_rounded),
                tooltip: 'วางข้อความ รูปภาพ หรือไฟล์จาก Clipboard (Ctrl+V)',
                onPressed: _sending ? null : () => _handleClipboardPaste(allowTextPaste: true),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Actions(
                  actions: {
                    PasteTextIntent: CallbackAction<PasteTextIntent>(
                      onInvoke: (intent) async {
                        final handled = await _handleClipboardPaste();
                        if (!handled) {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null && data!.text!.isNotEmpty) {
                            final text = _controller.text;
                            final selection = _controller.selection;
                            final start = selection.start >= 0 ? selection.start : text.length;
                            final end = selection.end >= 0 ? selection.end : text.length;
                            final newText = text.replaceRange(start, end, data.text!);
                            _controller.text = newText;
                            _controller.selection = TextSelection.collapsed(
                              offset: start + data.text!.length,
                            );
                          }
                        }
                        return null;
                      },
                    ),
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !_sending,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _pendingAttachments.isNotEmpty
                          ? 'พิมพ์คำถามเกี่ยวกับ ${_pendingAttachments.length} ไฟล์ที่แนบไว้ แล้วกดส่ง...'
                          : 'ถามเกี่ยวกับข้อมูลในระบบ, ลากไฟล์มาวาง หรือกด Ctrl+V วางรูปภาพที่นี่...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (_sending)
                FilledButton(
                  onPressed: _stopGenerating,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
                  ),
                  child: const Icon(Icons.stop_rounded, size: 24),
                )
              else
                FilledButton(
                  onPressed: _send,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
                  ),
                  child: const Icon(Icons.send_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _stopGenerating() {
    ref.read(aiChatProvider.notifier).stopGeneration();
    setState(() {
      _sending = false;
    });
  }

  Future<void> _showApiKeyDialog() async {
    final initialConfig = await AiService.loadConfig();
    if (!mounted) return;
    final keyController = TextEditingController(text: initialConfig.apiKey);
    final modelController = TextEditingController(text: initialConfig.model);
    final baseUrlController = TextEditingController(
      text:
          initialConfig.baseUrl ??
          initialConfig.definition.defaultBaseUrl ??
          '',
    );
    var selectedProvider = initialConfig.provider;
    bool testing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final definition = AiProviderCatalog.of(selectedProvider);
          return AlertDialog(
            title: Text('ตั้งค่า ${definition.displayName}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.helpText,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AiProviderKind>(
                  initialValue: selectedProvider,
                  decoration: const InputDecoration(
                    labelText: 'AI Provider',
                    prefixIcon: Icon(Icons.hub_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: AiProviderCatalog.providers.map((provider) {
                    return DropdownMenuItem(
                      value: provider.kind,
                      child: Text(provider.displayName),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    final savedConfig = await AiService.loadConfigForProvider(
                      value,
                    );
                    setS(() {
                      selectedProvider = value;
                      keyController.text = savedConfig.apiKey;
                      modelController.text = savedConfig.model;
                      baseUrlController.text =
                          savedConfig.baseUrl ??
                          savedConfig.definition.defaultBaseUrl ??
                          '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    prefixIcon: Icon(Icons.memory_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (definition.supportsCustomBaseUrl) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      prefixIcon: Icon(Icons.link_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: definition.keyLabel,
                    hintText: definition.keyHint,
                    prefixIcon: const Icon(Icons.key),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ยกเลิก'),
              ),
              if (testing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton(
                  onPressed: () async {
                    final config = AiProviderConfig(
                      provider: selectedProvider,
                      apiKey: keyController.text.trim(),
                      model: modelController.text.trim().isEmpty
                          ? definition.defaultModel
                          : modelController.text.trim(),
                      baseUrl: definition.supportsCustomBaseUrl
                          ? baseUrlController.text.trim()
                          : definition.defaultBaseUrl,
                    );
                    if (!config.isComplete) return;
                    setS(() => testing = true);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final ok = await AiService.testConfig(config);
                    if (ok) {
                      await AiService.saveConfig(config);
                      await ref.read(aiChatProvider.notifier).reloadModel();
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'ตั้งค่า ${definition.displayName} สำเร็จ!',
                            ),
                          ),
                        );
                      }
                    } else {
                      setS(() => testing = false);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${definition.displayName} เชื่อมต่อไม่ได้ หรือค่าไม่ถูกต้อง',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('ทดสอบและบันทึก'),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Message Bubble ──────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;

    // Check if user message has attachment header
    String? attachmentHeader;
    String cleanContent = message.content;
    if (isUser && message.content.startsWith('📎 [')) {
      final lineBreak = message.content.indexOf('\n');
      if (lineBreak != -1) {
        attachmentHeader = message.content.substring(0, lineBreak).replaceAll('📎 ', '').replaceAll('[', '').replaceAll(']', '');
        cleanContent = message.content.substring(lineBreak + 1).trim();
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 10, top: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 16,
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary.withValues(alpha: 0.9)
                    : message.isError
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: Border.all(
                  color: isUser
                      ? theme.colorScheme.primary.withValues(alpha: 0.4)
                      : message.isError
                          ? theme.colorScheme.error.withValues(alpha: 0.3)
                          : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: message.isLoading
                  ? _ThinkingLoadingBubble(message: message)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (attachmentHeader != null) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.attachment_rounded, size: 14, color: Colors.white70),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    attachmentHeader,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (!isUser &&
                            ((message.reasoningSteps.isNotEmpty &&
                                    message.reasoningSteps.length > 1) ||
                                (message.reasoningContent != null &&
                                    message.reasoningContent!
                                        .trim()
                                        .isNotEmpty)))
                          _ReasoningSection(
                            steps: message.reasoningSteps,
                            reasoningContent: message.reasoningContent,
                          ),
                        _MessageContent(
                          message: message,
                          overrideContent: cleanContent,
                        ),
                      ],
                    ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ThinkingLoadingBubble extends StatelessWidget {
  final ChatMessage message;
  const _ThinkingLoadingBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = message.reasoningSteps;
    final hasReasoningContent = message.reasoningContent != null &&
        message.reasoningContent!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'กำลังคิดและประมวลผล...',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (steps.isNotEmpty || hasReasoningContent) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...steps.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final step = entry.value;
                  final isLast = idx == steps.length - 1;

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: isLast && !hasReasoningContent ? 0 : 4,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 6),
                          child: Icon(
                            isLast
                                ? Icons.play_arrow_rounded
                                : Icons.check_circle_rounded,
                            size: 13,
                            color: isLast
                                ? theme.colorScheme.primary
                                : Colors.green.shade600,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            step,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: isLast
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.8),
                              fontWeight:
                                  isLast ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (hasReasoningContent) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      message.reasoningContent!.trim(),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.35,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ReasoningSection extends StatefulWidget {
  final List<String> steps;
  final String? reasoningContent;

  const _ReasoningSection({
    required this.steps,
    this.reasoningContent,
  });

  @override
  State<_ReasoningSection> createState() => _ReasoningSectionState();
}

class _ReasoningSectionState extends State<_ReasoningSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.steps.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'กระบวนการคิด (${count > 0 ? '$count ขั้นตอน' : 'Reasoning'})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 8, thickness: 0.5),
                  ...widget.steps.map((step) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2, right: 6),
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 12,
                                color: Colors.green.shade600,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                step,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  if (widget.reasoningContent != null &&
                      widget.reasoningContent!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        widget.reasoningContent!.trim(),
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  final ChatMessage message;
  final String? overrideContent;

  const _MessageContent({required this.message, this.overrideContent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final textColor = isUser
        ? theme.colorScheme.onPrimary
        : message.isError
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onSurface;

    final contentToRender = overrideContent ?? message.content;
    final baseStyle = TextStyle(
      color: textColor,
      fontSize: isUser ? 14 : 13.5,
      height: 1.55,
      letterSpacing: 0.15,
    );

    final blocks = _AiMessageBlockParser.parse(contentToRender);
    if (blocks.length == 1 && blocks.first.type == _AiMessageBlockType.text) {
      return _MarkdownTextRenderer(
        text: contentToRender,
        baseStyle: baseStyle,
        isUser: isUser,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) {
        switch (block.type) {
          case _AiMessageBlockType.text:
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _MarkdownTextRenderer(
                text: block.text,
                baseStyle: baseStyle,
                isUser: isUser,
              ),
            );
          case _AiMessageBlockType.code:
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CopyableCodeBlock(
                text: block.text,
                language: block.language,
              ),
            );
          case _AiMessageBlockType.table:
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CopyableTableBlock(
                headers: block.headers,
                rows: block.rows,
              ),
            );
          case _AiMessageBlockType.image:
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ChatImageBlock(
                source: block.source,
                altText: block.altText,
              ),
            );
          case _AiMessageBlockType.pdf:
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PdfCardBlock(
                title: block.title,
                path: block.source,
                thumbnail: block.thumbnail,
                pages: block.pages,
              ),
            );
          case _AiMessageBlockType.timeline:
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TimelineBlock(items: block.timelineItems),
            );
          case _AiMessageBlockType.actionConfirmation:
            if (block.actionConfirmation == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActionConfirmationCard(data: block.actionConfirmation!),
            );
          case _AiMessageBlockType.chart:
            if (block.chartData == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InteractiveChartBlock(chartData: block.chartData!),
            );
          case _AiMessageBlockType.slides:
            if (block.presentationData == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InteractivePresentationDeckBlock(deck: block.presentationData!),
            );
        }
      }).toList(),
    );
  }
}

class _MarkdownTextRenderer extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final bool isUser;

  const _MarkdownTextRenderer({
    required this.text,
    required this.baseStyle,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = text.split('\n');
    final widgets = <Widget>[];

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        i++;
        continue;
      }

      // 1. Heading 1 (# Heading)
      if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            trimmed.substring(2).trim(),
            style: baseStyle.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isUser ? baseStyle.color : theme.colorScheme.primary,
            ),
          ),
        ));
        i++;
        continue;
      }

      // 2. Heading 2 (## Heading)
      if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            trimmed.substring(3).trim(),
            style: baseStyle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isUser ? baseStyle.color : theme.colorScheme.onSurface,
            ),
          ),
        ));
        i++;
        continue;
      }

      // 3. Heading 3 (### Heading or **Heading:**)
      if (trimmed.startsWith('### ') ||
          (trimmed.startsWith('**') &&
              trimmed.endsWith('**') &&
              !trimmed.contains('\n') &&
              trimmed.length <= 45)) {
        final cleanTitle = trimmed.startsWith('### ')
            ? trimmed.substring(4).trim()
            : trimmed.replaceAll('**', '').trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3.5,
                height: 14,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: isUser ? Colors.white70 : theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: Text(
                  cleanTitle,
                  style: baseStyle.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isUser ? baseStyle.color : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ));
        i++;
        continue;
      }

      // 4. Blockquote (> Note)
      if (trimmed.startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoteLines.add(lines[i].trim().replaceFirst(RegExp(r'^>\s*'), ''));
          i++;
        }
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isUser
                ? Colors.white12
                : theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: isUser ? Colors.white60 : theme.colorScheme.primary,
                width: 3.5,
              ),
            ),
          ),
          child: Text(
            quoteLines.join('\n'),
            style: baseStyle.copyWith(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: isUser
                  ? baseStyle.color
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ));
        continue;
      }

      // 5. Bullet item (- item or * item or • item or 1. item)
      final bulletMatch =
          RegExp(r'^(\s*)([-*•]|\d+[\.\)])\s+(.*)$').firstMatch(line);
      if (bulletMatch != null) {
        final indent = bulletMatch.group(1)?.length ?? 0;
        final prefix = bulletMatch.group(2) ?? '•';
        final content = bulletMatch.group(3) ?? '';
        final isNumbered = RegExp(r'^\d+[\.\)]').hasMatch(prefix);

        widgets.add(Padding(
          padding: EdgeInsets.only(
            left: indent > 0 ? (indent * 8.0) : 4,
            top: 2,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6, right: 8),
                child: isNumbered
                    ? Text(
                        prefix,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isUser
                              ? Colors.white70
                              : theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.circle,
                        size: 5,
                        color: isUser
                            ? Colors.white70
                            : theme.colorScheme.primary,
                      ),
              ),
              Expanded(
                child: _buildFormattedText(content, baseStyle, theme, isUser),
              ),
            ],
          ),
        ));
        i++;
        continue;
      }

      // 6. Regular paragraph
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _buildFormattedText(line, baseStyle, theme, isUser),
      ));
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildFormattedText(
      String text, TextStyle style, ThemeData theme, bool isUser) {
    final spans = <InlineSpan>[];
    final regex =
        RegExp(r'(`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*|\[[^\]]+\]\([^)]+\))');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: style,
        ));
      }

      final matchedStr = match.group(0)!;
      if (matchedStr.startsWith('`') && matchedStr.endsWith('`')) {
        // Inline code
        final codeText = matchedStr.substring(1, matchedStr.length - 1);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isUser
                  ? Colors.black26
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isUser
                    ? Colors.white24
                    : theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                width: 0.7,
              ),
            ),
            child: Text(
              codeText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isUser ? Colors.white : theme.colorScheme.primary,
              ),
            ),
          ),
        ));
      } else if (matchedStr.startsWith('**') && matchedStr.endsWith('**')) {
        // Bold
        spans.add(TextSpan(
          text: matchedStr.substring(2, matchedStr.length - 2),
          style: style.copyWith(
            fontWeight: FontWeight.bold,
            color: isUser ? Colors.white : theme.colorScheme.onSurface,
          ),
        ));
      } else if (matchedStr.startsWith('*') && matchedStr.endsWith('*')) {
        // Italic
        spans.add(TextSpan(
          text: matchedStr.substring(1, matchedStr.length - 1),
          style: style.copyWith(fontStyle: FontStyle.italic),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: style,
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      style: style,
    );
  }
}

enum _AiMessageBlockType { text, code, table, image, pdf, timeline, actionConfirmation, chart, slides }

class _AiSlideMetric {
  final String label;
  final String value;
  final String? target;
  final String status; // 'good', 'warning', 'critical'
  final String? change;

  const _AiSlideMetric({
    required this.label,
    required this.value,
    this.target,
    this.status = 'good',
    this.change,
  });

  factory _AiSlideMetric.fromMap(Map<String, dynamic> map) {
    return _AiSlideMetric(
      label: (map['label'] ?? map['name'] ?? map['key'])?.toString().trim() ?? 'ตัวชี้วัด',
      value: (map['value'] ?? map['val'])?.toString().trim() ?? '-',
      target: map['target']?.toString().trim(),
      status: (map['status'] ?? 'good').toString().toLowerCase().trim(),
      change: map['change']?.toString().trim(),
    );
  }
}

class _AiFishboneModel {
  final String problem;
  final List<String> man;
  final List<String> machine;
  final List<String> method;
  final List<String> material;
  final List<String> environment;

  const _AiFishboneModel({
    required this.problem,
    this.man = const [],
    this.machine = const [],
    this.method = const [],
    this.material = const [],
    this.environment = const [],
  });

  factory _AiFishboneModel.fromMap(Map<String, dynamic> map) {
    return _AiFishboneModel(
      problem: (map['problem'] ?? map['title'] ?? 'ปัญหาหลักที่ตรวจพบ')?.toString().trim() ?? '',
      man: _parseList(map['man']),
      machine: _parseList(map['machine']),
      method: _parseList(map['method']),
      material: _parseList(map['material']),
      environment: _parseList(map['environment'] ?? map['env']),
    );
  }

  static List<String> _parseList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).toList();
    }
    return [raw.toString().trim()];
  }
}

class _AiFiveWhyModel {
  final String problem;
  final List<String> whys;
  final String rootCause;
  final String? countermeasure;

  const _AiFiveWhyModel({
    required this.problem,
    required this.whys,
    required this.rootCause,
    this.countermeasure,
  });

  factory _AiFiveWhyModel.fromMap(Map<String, dynamic> map) {
    final problem = (map['problem'] ?? 'ปัญหาที่ระบุ')?.toString().trim() ?? '';
    final rawWhys = map['whys'];
    final list = <String>[];
    if (rawWhys is List) {
      for (final w in rawWhys) {
        if (w != null && w.toString().trim().isNotEmpty) {
          list.add(w.toString().trim());
        }
      }
    } else {
      for (int i = 1; i <= 5; i++) {
        final w = map['why_$i']?.toString().trim();
        if (w != null && w.isNotEmpty) list.add(w);
      }
    }

    final root = (map['root_cause'] ?? (list.isNotEmpty ? list.last : 'ไม่ระบุสาเหตุที่แท้จริง'))?.toString().trim() ?? '';
    final action = (map['countermeasure'] ?? map['preventive_action'] ?? map['action'])?.toString().trim();

    return _AiFiveWhyModel(
      problem: problem,
      whys: list,
      rootCause: root,
      countermeasure: action,
    );
  }
}

class _AiEightDStep {
  final String step;
  final String title;
  final String description;
  final String owner;
  final String status;

  const _AiEightDStep({
    required this.step,
    required this.title,
    required this.description,
    required this.owner,
    required this.status,
  });

  factory _AiEightDStep.fromMap(Map<String, dynamic> map) {
    return _AiEightDStep(
      step: (map['step'] ?? 'D')?.toString().trim() ?? 'D',
      title: (map['title'] ?? '')?.toString().trim() ?? '',
      description: (map['description'] ?? map['detail'] ?? '-')?.toString().trim() ?? '-',
      owner: (map['owner'] ?? map['responsible'] ?? '-')?.toString().trim() ?? '-',
      status: (map['status'] ?? 'Completed')?.toString().trim() ?? 'Completed',
    );
  }
}

class _AiSlideItem {
  final String type; // 'title', 'kpi', 'fishbone', 'rca_5why', 'eight_d', 'chart', 'table', 'content', 'summary'
  final String title;
  final String? subtitle;
  final String? content;
  final List<_AiSlideMetric> metrics;
  final _AiFishboneModel? fishbone;
  final _AiFiveWhyModel? fiveWhy;
  final List<_AiEightDStep> eightD;
  final _AiChartData? chartData;
  final List<String> actionItems;
  final List<String> bullets;
  final Map<String, dynamic> raw;

  const _AiSlideItem({
    required this.type,
    required this.title,
    this.subtitle,
    this.content,
    this.metrics = const [],
    this.fishbone,
    this.fiveWhy,
    this.eightD = const [],
    this.chartData,
    this.actionItems = const [],
    this.bullets = const [],
    required this.raw,
  });

  factory _AiSlideItem.fromMap(Map<String, dynamic> map) {
    final type = (map['slide_type'] ?? map['type'])?.toString().toLowerCase().trim() ?? 'content';
    final title = (map['title'] ?? 'สไลด์นำเสนอ')?.toString().trim() ?? 'สไลด์นำเสนอ';
    final subtitle = map['subtitle']?.toString().trim();
    final content = map['content']?.toString().trim();

    // Metrics
    final rawMetrics = map['metrics'] ?? map['kpis'];
    final metricsList = <_AiSlideMetric>[];
    if (rawMetrics is List) {
      for (final m in rawMetrics) {
        if (m is Map) metricsList.add(_AiSlideMetric.fromMap(m.cast<String, dynamic>()));
      }
    }

    // Fishbone
    _AiFishboneModel? fb;
    if (type == 'fishbone' || map.containsKey('fishbone_data')) {
      final fbMap = (map['fishbone_data'] ?? map) as Map;
      fb = _AiFishboneModel.fromMap(fbMap.cast<String, dynamic>());
    }

    // 5-Why
    _AiFiveWhyModel? fw;
    if (type == 'rca_5why' || type == '5why' || map.containsKey('five_why_data')) {
      final fwMap = (map['five_why_data'] ?? map) as Map;
      fw = _AiFiveWhyModel.fromMap(fwMap.cast<String, dynamic>());
    }

    // 8D
    final raw8D = map['eight_d_data'] ?? map['steps'];
    final eightDList = <_AiEightDStep>[];
    if (raw8D is List) {
      for (final st in raw8D) {
        if (st is Map) eightDList.add(_AiEightDStep.fromMap(st.cast<String, dynamic>()));
      }
    }

    // Chart
    _AiChartData? cd;
    if (type == 'chart' || map.containsKey('chart_data')) {
      final cMap = (map['chart_data'] ?? map) as Map;
      cd = _AiChartData.fromMap(cMap.cast<String, dynamic>(), '');
    }

    // Actions & bullets
    final rawActions = map['action_items'] ?? map['actions'] ?? map['items'];
    final actionsList = <String>[];
    if (rawActions is List) {
      for (final a in rawActions) {
        if (a != null && a.toString().trim().isNotEmpty) actionsList.add(a.toString().trim());
      }
    }

    final rawBullets = map['bullets'] ?? map['points'];
    final bulletsList = <String>[];
    if (rawBullets is List) {
      for (final b in rawBullets) {
        if (b != null && b.toString().trim().isNotEmpty) bulletsList.add(b.toString().trim());
      }
    }

    return _AiSlideItem(
      type: type,
      title: title,
      subtitle: subtitle,
      content: content,
      metrics: metricsList,
      fishbone: fb,
      fiveWhy: fw,
      eightD: eightDList,
      chartData: cd,
      actionItems: actionsList,
      bullets: bulletsList,
      raw: map,
    );
  }
}

class _AiPresentationDeckData {
  final String title;
  final String? subtitle;
  final String? author;
  final String theme;
  final String? pdfPath;
  final List<String> sources;
  final List<_AiSlideItem> slides;
  final String rawJson;

  const _AiPresentationDeckData({
    required this.title,
    this.subtitle,
    this.author,
    this.theme = 'blue',
    this.pdfPath,
    this.sources = const [],
    required this.slides,
    required this.rawJson,
  });

  factory _AiPresentationDeckData.fromMap(Map<String, dynamic> map, String rawJson) {
    final title = (map['title'] ?? 'สไลด์นำเสนอผลการดำเนินงาน')?.toString().trim() ?? 'สไลด์นำเสนอ';
    final subtitle = map['subtitle']?.toString().trim();
    final author = map['author']?.toString().trim();
    final theme = (map['theme'] ?? 'blue')?.toString().trim() ?? 'blue';
    final pdfPath = map['pdf_path']?.toString().trim();

    final rawSources = map['sources'] ?? map['source_references'];
    final sourcesList = <String>[];
    if (rawSources is List) {
      for (final s in rawSources) {
        if (s != null && s.toString().trim().isNotEmpty) sourcesList.add(s.toString().trim());
      }
    }

    final rawSlides = map['slides'] ?? map['deck'];
    final slidesList = <_AiSlideItem>[];
    if (rawSlides is List) {
      for (final sl in rawSlides) {
        if (sl is Map) slidesList.add(_AiSlideItem.fromMap(sl.cast<String, dynamic>()));
      }
    }

    return _AiPresentationDeckData(
      title: title,
      subtitle: subtitle,
      author: author,
      theme: theme,
      pdfPath: pdfPath,
      sources: sourcesList,
      slides: slidesList,
      rawJson: rawJson,
    );
  }
}

class _AiChartDataPoint {
  final String label;
  final double value;
  final Color? color;
  final double? secondaryValue;
  final String? group;

  const _AiChartDataPoint({
    required this.label,
    required this.value,
    this.color,
    this.secondaryValue,
    this.group,
  });

  factory _AiChartDataPoint.fromMap(Map<String, dynamic> map, int index, [List<Color>? palette]) {
    final label = (map['label'] ?? map['name'] ?? map['key'] ?? map['category'])?.toString().trim() ?? '';
    final rawVal = map['value'] ?? map['val'] ?? map['count'] ?? map['y'];
    double value = 0.0;
    if (rawVal is num) {
      value = rawVal.toDouble();
    } else if (rawVal != null) {
      value = double.tryParse(rawVal.toString().replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0.0;
    }

    Color? itemColor;
    final colorStr = map['color']?.toString().trim();
    if (colorStr != null && colorStr.isNotEmpty) {
      itemColor = _parseHexColor(colorStr);
    }
    if (itemColor == null && palette != null && palette.isNotEmpty) {
      itemColor = palette[index % palette.length];
    }

    final rawSec = map['secondary_value'] ?? map['secondary'];
    double? secVal;
    if (rawSec is num) {
      secVal = rawSec.toDouble();
    } else if (rawSec != null) {
      secVal = double.tryParse(rawSec.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
    }

    return _AiChartDataPoint(
      label: label,
      value: value,
      color: itemColor,
      secondaryValue: secVal,
      group: map['group']?.toString().trim(),
    );
  }

  static Color? _parseHexColor(String hex) {
    var str = hex.replaceAll('#', '').trim();
    if (str.length == 6) str = 'FF$str';
    final val = int.tryParse(str, radix: 16);
    return val != null ? Color(val) : null;
  }
}

class _AiChartData {
  final String chartType; // 'bar', 'pie', 'donut', 'line', 'area'
  final String title;
  final String? subtitle;
  final String? xLabel;
  final String? yLabel;
  final String unit;
  final List<_AiChartDataPoint> data;
  final String rawJson;

  const _AiChartData({
    required this.chartType,
    required this.title,
    this.subtitle,
    this.xLabel,
    this.yLabel,
    this.unit = '',
    required this.data,
    required this.rawJson,
  });

  static const List<Color> defaultPalette = [
    Color(0xFF2196F3), // Blue
    Color(0xFF4CAF50), // Green
    Color(0xFFFF9800), // Orange
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF00BCD4), // Cyan
    Color(0xFFFFC107), // Amber
    Color(0xFF607D8B), // Blue Grey
    Color(0xFF009688), // Teal
    Color(0xFFF44336), // Red
    Color(0xFF3F51B5), // Indigo
    Color(0xFF8BC34A), // Light Green
  ];

  factory _AiChartData.fromMap(Map<String, dynamic> map, String rawJson) {
    final type = (map['chart_type'] ?? map['type'])?.toString().toLowerCase().trim() ?? 'bar';
    final title = (map['title'] ?? 'กราฟแสดงผลข้อมูล')?.toString().trim() ?? 'กราฟแสดงผลข้อมูล';
    final subtitle = map['subtitle']?.toString().trim();
    final xLabel = map['x_label']?.toString().trim();
    final yLabel = map['y_label']?.toString().trim();
    final unit = map['unit']?.toString().trim() ?? '';

    final rawData = map['data'] ?? map['series'] ?? map['items'];
    final dataPoints = <_AiChartDataPoint>[];

    if (rawData is List) {
      for (int i = 0; i < rawData.length; i++) {
        final item = rawData[i];
        if (item is Map) {
          dataPoints.add(_AiChartDataPoint.fromMap(
            item.cast<String, dynamic>(),
            i,
            defaultPalette,
          ));
        }
      }
    }

    return _AiChartData(
      chartType: type,
      title: title,
      subtitle: subtitle,
      xLabel: xLabel,
      yLabel: yLabel,
      unit: unit,
      data: dataPoints,
      rawJson: rawJson,
    );
  }
}

class _AiTimelineItem {
  final String time;
  final String title;
  final String detail;
  final String type;

  const _AiTimelineItem({
    required this.time,
    required this.title,
    required this.detail,
    required this.type,
  });
}

class _AiActionConfirmationData {
  final String actionId;
  final String tool;
  final String action;
  final String title;
  final String summary;
  final List<String> options;
  final Map<String, dynamic> params;

  const _AiActionConfirmationData({
    required this.actionId,
    required this.tool,
    required this.action,
    required this.title,
    required this.summary,
    this.options = const [],
    required this.params,
  });

  factory _AiActionConfirmationData.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    final optList = <String>[];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o != null && o.toString().trim().isNotEmpty) {
          optList.add(o.toString().trim());
        }
      }
    }

    final action = map['action']?.toString() ?? 'update';
    final params = (map['params'] as Map?)?.cast<String, dynamic>() ?? {};
    if (!params.containsKey('action')) {
      params['action'] = action;
    }

    return _AiActionConfirmationData(
      actionId: map['action_id']?.toString() ?? const Uuid().v4(),
      tool: map['tool']?.toString() ?? 'manage_machines',
      action: action,
      title: map['title']?.toString() ?? 'ยืนยันการดำเนินการ',
      summary: map['summary']?.toString() ?? '',
      options: optList,
      params: params,
    );
  }
}

class _AiMessageBlock {
  final _AiMessageBlockType type;
  final String text;
  final String language;
  final List<String> headers;
  final List<List<String>> rows;
  final String source;
  final String altText;
  final String title;
  final String thumbnail;
  final int? pages;
  final List<_AiTimelineItem> timelineItems;
  final _AiActionConfirmationData? actionConfirmation;
  final _AiChartData? chartData;
  final _AiPresentationDeckData? presentationData;

  const _AiMessageBlock.text(this.text)
    : type = _AiMessageBlockType.text,
      language = '',
      headers = const [],
      rows = const [],
      source = '',
      altText = '',
      title = '',
      thumbnail = '',
      pages = null,
      timelineItems = const [],
      actionConfirmation = null,
      chartData = null,
      presentationData = null;

  const _AiMessageBlock.code(this.text, {this.language = ''})
    : type = _AiMessageBlockType.code,
      headers = const [],
      rows = const [],
      source = '',
      altText = '',
      title = '',
      thumbnail = '',
      pages = null,
      timelineItems = const [],
      actionConfirmation = null,
      chartData = null,
      presentationData = null;

  const _AiMessageBlock.table({
    required this.headers,
    required this.rows,
    required this.text,
  }) : type = _AiMessageBlockType.table,
       language = '',
       source = '',
       altText = '',
       title = '',
       thumbnail = '',
       pages = null,
       timelineItems = const [],
       actionConfirmation = null,
       chartData = null,
       presentationData = null;

  const _AiMessageBlock.image({required this.source, required this.altText})
    : type = _AiMessageBlockType.image,
      text = '',
      language = '',
      headers = const [],
      rows = const [],
      title = '',
      thumbnail = '',
      pages = null,
      timelineItems = const [],
      actionConfirmation = null,
      chartData = null,
      presentationData = null;

  const _AiMessageBlock.pdf({
    required this.title,
    required this.source,
    required this.thumbnail,
    required this.pages,
  }) : type = _AiMessageBlockType.pdf,
       text = '',
       language = '',
       headers = const [],
       rows = const [],
       altText = '',
       timelineItems = const [],
       actionConfirmation = null,
       chartData = null,
       presentationData = null;

  const _AiMessageBlock.timeline({required this.timelineItems})
    : type = _AiMessageBlockType.timeline,
      text = '',
      language = '',
      headers = const [],
      rows = const [],
      source = '',
      altText = '',
      title = '',
      thumbnail = '',
      pages = null,
      actionConfirmation = null,
      chartData = null,
      presentationData = null;

  const _AiMessageBlock.actionConfirmation(this.actionConfirmation)
    : type = _AiMessageBlockType.actionConfirmation,
      text = '',
      language = '',
      headers = const [],
      rows = const [],
      source = '',
      altText = '',
      title = '',
      thumbnail = '',
      pages = null,
      timelineItems = const [],
      chartData = null,
      presentationData = null;

  const _AiMessageBlock.chart(this.chartData)
    : type = _AiMessageBlockType.chart,
      text = '',
      language = '',
      headers = const [],
      rows = const [],
      source = '',
      altText = '',
      title = '',
      thumbnail = '',
      pages = null,
      timelineItems = const [],
      actionConfirmation = null,
      presentationData = null;

  const _AiMessageBlock.slides(this.presentationData)
    : type = _AiMessageBlockType.slides,
      text = '',
      language = '',
      headers = const [],
      rows = const [],
      source = '',
      altText = '',
      title = '',
      thumbnail = '',
      pages = null,
      timelineItems = const [],
      actionConfirmation = null,
      chartData = null;
}

class _AiMessageBlockParser {
  static final RegExp _tableSeparatorPattern = RegExp(
    r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$',
  );
  static final RegExp _markdownImagePattern = RegExp(
    r'^\s*!\[([^\]]*)\]\(([^)]+)\)\s*$',
  );
  static final RegExp _markdownImageLinkFallbackPattern = RegExp(
    r'^\s*\*?\[([^\]]+)\]\(([^)]+)\)\*?(?:\s+\*?\([^)]*\)\*?)?\s*$',
    caseSensitive: false,
  );
  static final RegExp _standaloneImageUrlPattern = RegExp(
    r'^\s*((https?:\/\/|file:\/\/\/)[^\s]+?\.(?:png|jpg|jpeg|gif|webp)(?:\?[^\s]*)?|[A-Za-z]:\\[^\n]+?\.(?:png|jpg|jpeg|gif|webp)|\\\\[^\n]+?\.(?:png|jpg|jpeg|gif|webp))\s*$',
    caseSensitive: false,
  );

  static List<_AiMessageBlock> parse(String input) {
    final normalized = input.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final blocks = <_AiMessageBlock>[];
    final textBuffer = <String>[];
    var i = 0;

    void flushText() {
      final text = textBuffer.join('\n').trim();
      if (text.isNotEmpty) {
        blocks.add(_AiMessageBlock.text(text));
      }
      textBuffer.clear();
    }

    while (i < lines.length) {
      final line = lines[i];

      if (line.trimLeft().startsWith('```')) {
        flushText();
        final language = line.trim().substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        final code = codeLines.join('\n').trimRight();
        final normalizedLanguage = language.toLowerCase();
        final specialBlock = switch (normalizedLanguage) {
          'pdfcard' => _parsePdfCard(code),
          'timeline' => _parseTimeline(code),
          'action_confirmation' || 'action_request' || 'confirmation' => _parseActionConfirmation(code),
          'chart' || 'fl_chart' || 'barchart' || 'bar_chart' || 'piechart' || 'pie_chart' || 'linechart' || 'line_chart' || 'donutchart' || 'donut_chart' || 'areachart' || 'area_chart' || 'chart_config' => _parseChart(code),
          'slides' || 'presentation' || 'slide_deck' || 'pdf_slides' || 'slides_deck' => _parseSlides(code),
          _ => null,
        };
        if (specialBlock != null) {
          blocks.add(specialBlock);
        } else {
          blocks.add(_AiMessageBlock.code(code, language: language));
        }
        if (i < lines.length) i++;
        continue;
      }

      final imageMatch = _markdownImagePattern.firstMatch(line);
      if (imageMatch != null) {
        flushText();
        blocks.add(
          _AiMessageBlock.image(
            source: imageMatch.group(2)!.trim(),
            altText: imageMatch.group(1)!.trim(),
          ),
        );
        i++;
        continue;
      }

      final imageLinkFallbackMatch = _markdownImageLinkFallbackPattern
          .firstMatch(line);
      if (imageLinkFallbackMatch != null) {
        final candidateSource = imageLinkFallbackMatch.group(2)!.trim();
        if (_AssetPreviewSupport.looksLikeImageSource(candidateSource)) {
          flushText();
          blocks.add(
            _AiMessageBlock.image(
              source: candidateSource,
              altText: imageLinkFallbackMatch.group(1)!.trim(),
            ),
          );
          i++;
          continue;
        }
      }

      final imageUrlMatch = _standaloneImageUrlPattern.firstMatch(line);
      if (imageUrlMatch != null) {
        flushText();
        blocks.add(
          _AiMessageBlock.image(
            source: imageUrlMatch.group(1)!.trim(),
            altText: '',
          ),
        );
        i++;
        continue;
      }

      final canBeTable =
          i + 1 < lines.length &&
          _looksLikeTableRow(line) &&
          _tableSeparatorPattern.hasMatch(lines[i + 1]);
      if (canBeTable) {
        flushText();
        final tableLines = <String>[line, lines[i + 1]];
        i += 2;
        while (i < lines.length && _looksLikeTableRow(lines[i])) {
          tableLines.add(lines[i]);
          i++;
        }
        final tableBlock = _parseTable(tableLines);
        if (tableBlock != null) {
          blocks.add(tableBlock);
        }
        continue;
      }

      textBuffer.add(line);
      i++;
    }

    flushText();

    // Ensure at most ONE consolidated confirmation card if no explicit block was parsed
    final hasActionConfirmation = blocks.any((b) => b.type == _AiMessageBlockType.actionConfirmation);
    if (!hasActionConfirmation) {
      final autoCard = _detectAutoActionConfirmation(input);
      if (autoCard != null) {
        blocks.add(_AiMessageBlock.actionConfirmation(autoCard));
      }
    }

    return blocks.isEmpty ? [_AiMessageBlock.text(input)] : blocks;
  }

  static bool _looksLikeTableRow(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.contains('|');
  }

  static _AiMessageBlock? _parseTable(List<String> lines) {
    if (lines.length < 2) return null;
    final headers = _splitTableRow(lines.first);
    if (headers.isEmpty) return null;

    final rows = <List<String>>[];
    for (final line in lines.skip(2)) {
      final row = _splitTableRow(line);
      if (row.isEmpty) continue;
      while (row.length < headers.length) {
        row.add('');
      }
      rows.add(row.take(headers.length).toList());
    }

    final raw = lines.join('\n');
    return _AiMessageBlock.table(headers: headers, rows: rows, text: raw);
  }

  static List<String> _splitTableRow(String line) {
    final trimmed = line.trim();
    var work = trimmed;
    if (work.startsWith('|')) work = work.substring(1);
    if (work.endsWith('|')) work = work.substring(0, work.length - 1);
    return work.split('|').map((cell) => cell.trim()).toList();
  }

  static _AiMessageBlock? _parsePdfCard(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final path =
          decoded['path']?.toString().trim() ??
          decoded['storage_path']?.toString().trim() ??
          '';
      if (path.isEmpty) return null;

      final title =
          decoded['title']?.toString().trim() ??
          decoded['display_name']?.toString().trim() ??
          _fileNameFromPath(path);
      final thumbnail =
          decoded['thumbnail']?.toString().trim() ??
          decoded['thumbnail_path']?.toString().trim() ??
          decoded['preview']?.toString().trim() ??
          decoded['preview_path']?.toString().trim() ??
          '';
      final pagesRaw = decoded['pages'] ?? decoded['page_count'];
      final pages = pagesRaw is num
          ? pagesRaw.toInt()
          : int.tryParse('$pagesRaw');

      return _AiMessageBlock.pdf(
        title: title.isEmpty ? _fileNameFromPath(path) : title,
        source: path,
        thumbnail: _AssetPreviewSupport.looksLikeImageSource(thumbnail)
            ? thumbnail
            : '',
        pages: pages,
      );
    } catch (_) {
      return null;
    }
  }

  static _AiMessageBlock? _parseTimeline(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      final items = decoded
          .whereType<Map>()
          .map((rawItem) => rawItem.cast<String, dynamic>())
          .map((item) {
            final title = item['title']?.toString().trim() ?? '';
            final detail = item['detail']?.toString().trim() ?? '';
            final time = item['time']?.toString().trim() ?? '';
            final type = item['type']?.toString().trim() ?? 'update';
            return _AiTimelineItem(
              time: time,
              title: title,
              detail: detail,
              type: type,
            );
          })
          .where(
            (item) =>
                item.title.isNotEmpty ||
                item.detail.isNotEmpty ||
                item.time.isNotEmpty,
          )
          .toList();

      if (items.isEmpty) return null;
      return _AiMessageBlock.timeline(timelineItems: items);
    } catch (_) {
      return null;
    }
  }

  static _AiMessageBlock? _parseActionConfirmation(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final data = _AiActionConfirmationData.fromMap(decoded);
      return _AiMessageBlock.actionConfirmation(data);
    } catch (_) {
      return null;
    }
  }

  static _AiMessageBlock? _parseChart(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final data = _AiChartData.fromMap(decoded, raw);
      if (data.data.isEmpty) return null;
      return _AiMessageBlock.chart(data);
    } catch (_) {
      return null;
    }
  }

  static _AiMessageBlock? _parseSlides(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final data = _AiPresentationDeckData.fromMap(decoded, raw);
      if (data.slides.isEmpty) return null;
      return _AiMessageBlock.slides(data);
    } catch (_) {
      return null;
    }
  }

  static _AiActionConfirmationData? _detectAutoActionConfirmation(String text) {
    final lines = text.split('\n');
    final options = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      final match = RegExp(r'^(?:\d+[\.\)]|[-*•])\s*\*{0,2}(.*?)\*{0,2}\s*$').firstMatch(trimmed);
      if (match != null) {
        final optText = match.group(1)?.replaceAll(RegExp(r'\*\*'), '').trim() ?? '';
        if (optText.length >= 6 &&
            !optText.startsWith('http') &&
            !optText.startsWith('|') &&
            !optText.toLowerCase().startsWith('select ') &&
            (optText.contains('แนบ') ||
                optText.contains('อัพเดท') ||
                optText.contains('อัปเดต') ||
                optText.contains('เพิ่ม') ||
                optText.contains('ลบ') ||
                optText.contains('จัดการ') ||
                optText.contains('บันทึก') ||
                optText.contains('สร้าง') ||
                optText.contains('ดำเนินการ') ||
                optText.contains('เครื่องจักร') ||
                optText.contains('วิธี'))) {
          options.add(optText);
        }
      }
    }

    final hasActionIntent = text.contains('ต้องการให้ดำเนินการใช่หรือไม่') ||
        text.contains('กรุณากดยืนยันเพื่อเริ่มดำเนินการ') ||
        text.contains('ต้องการให้บันทึก/อัปเดตลงระบบทันทีหรือไม่') ||
        text.contains('ยืนยันการบันทึกข้อมูล:');

    if (hasActionIntent && options.isNotEmpty) {
      String title = 'ยืนยันขั้นตอนดำเนินการ';
      String action = 'update';
      if (text.contains('แนบเอกสาร') || text.contains('attach') || text.contains('คู่มือ')) {
        title = 'ยืนยันการแนบเอกสาร / จัดการข้อมูลเครื่องจักร';
        action = 'attach_document';
      } else if (text.contains('ลบ') || text.contains('delete')) {
        title = 'ยืนยันการลบข้อมูล';
        action = 'delete';
      } else if (text.contains('เพิ่ม') || text.contains('insert') || text.contains('สร้าง')) {
        title = 'ยืนยันการเพิ่มข้อมูลใหม่';
        action = 'insert';
      }

      return _AiActionConfirmationData(
        actionId: const Uuid().v4(),
        tool: 'manage_machines',
        action: action,
        title: title,
        summary: options.isNotEmpty
            ? 'เลือกแนวทางที่ต้องการดำเนินการ หรือกดยืนยันเพื่อเริ่มทันที'
            : 'ต้องการให้ระบบดำเนินการตามข้อเสนอนี้หรือไม่',
        options: options,
        params: {},
      );
    }
    return null;
  }

  static String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isNotEmpty ? parts.last : path;
  }
}

class _ActionConfirmationCard extends ConsumerStatefulWidget {
  final _AiActionConfirmationData data;
  const _ActionConfirmationCard({required this.data});

  @override
  ConsumerState<_ActionConfirmationCard> createState() =>
      _ActionConfirmationCardState();
}

class _ActionConfirmationCardState
    extends ConsumerState<_ActionConfirmationCard> {
  bool _executing = false;
  bool _completed = false;
  bool _cancelled = false;
  String? _resultMessage;
  bool _showOtherInput = false;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  void _handleOptionSelected(String option) {
    setState(() {
      _completed = true;
      _resultMessage = 'เลือก: $option';
    });
    final user = ref.read(authProvider);
    ref.read(aiChatProvider.notifier).sendMessage(
      'เลือกแนวทาง: $option',
      userId: user?.userId,
    );
  }

  Future<void> _handleConfirm() async {
    if (widget.data.params.isEmpty) {
      setState(() {
        _completed = true;
        _resultMessage = 'ยืนยันดำเนินการตามที่เสนอ';
      });
      final user = ref.read(authProvider);
      ref.read(aiChatProvider.notifier).sendMessage(
        'ยืนยันดำเนินการ: ${widget.data.title}',
        userId: user?.userId,
      );
      return;
    }

    setState(() => _executing = true);
    try {
      final user = ref.read(authProvider);
      final params = Map<String, dynamic>.from(widget.data.params);
      if (!params.containsKey('action') || params['action'] == null || params['action'].toString().isEmpty) {
        params['action'] = widget.data.action;
      }
      if (user?.userId != null) {
        params['user_id'] = user!.userId;
      }

      final rawResult = await AiToolHandler.handleToolCall(
        widget.data.tool,
        params,
      );

      String message = 'ดำเนินการเรียบร้อยแล้ว';
      try {
        final decoded = jsonDecode(rawResult) as Map<String, dynamic>;
        if (decoded.containsKey('error')) {
          throw decoded['error'];
        }
        if (decoded.containsKey('message')) {
          message = decoded['message'].toString();
        }
      } catch (e) {
        if (rawResult.contains('error')) {
          throw rawResult;
        }
      }

      setState(() {
        _executing = false;
        _completed = true;
        _resultMessage = message;
      });

      if (mounted) {
        ref.invalidate(toolsProvider);
        await ref.read(aiChatProvider.notifier).addAssistantMessage(
          '✅ ดำเนินการ **${widget.data.title}** เรียบร้อยแล้วครับ\n$message',
          userId: user?.userId,
        );
      }
    } catch (e) {
      setState(() {
        _executing = false;
        _resultMessage = 'เกิดข้อผิดพลาด: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถดำเนินการได้: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleCancel() {
    setState(() {
      _cancelled = true;
    });
    final user = ref.read(authProvider);
    ref.read(aiChatProvider.notifier).addAssistantMessage(
      '❌ ยกเลิกการดำเนินการ **${widget.data.title}** เรียบร้อยแล้ว',
      userId: user?.userId,
    );
  }

  void _handleOtherSubmit() {
    final text = _otherCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _showOtherInput = false);
    final user = ref.read(authProvider);
    ref.read(aiChatProvider.notifier).sendMessage(
      'สำหรับการดำเนินการ "${widget.data.title}": $text',
      userId: user?.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAttach =
        widget.data.action.contains('attach') ||
        widget.data.tool.contains('asset');
    final isDelete =
        widget.data.action.contains('delete') ||
        widget.data.action.contains('remove');
    final isInsert =
        widget.data.action.contains('insert') ||
        widget.data.action.contains('create');

    final actionColor = isDelete
        ? Colors.red
        : isAttach
            ? Colors.indigo
            : isInsert
                ? Colors.teal
                : theme.colorScheme.primary;

    final actionLabel = isDelete
        ? 'DELETE'
        : isAttach
            ? 'ATTACH'
            : isInsert
                ? 'INSERT'
                : 'UPDATE';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _completed
              ? Colors.green.withValues(alpha: 0.5)
              : _cancelled
                  ? theme.colorScheme.outlineVariant.withValues(alpha: 0.4)
                  : actionColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isAttach
                      ? Icons.attach_file_rounded
                      : isDelete
                          ? Icons.delete_outline_rounded
                          : isInsert
                              ? Icons.add_circle_outline_rounded
                              : Icons.tune_rounded,
                  size: 16,
                  color: actionColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.data.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: actionColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: actionColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body Summary & Params & Options
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.data.summary.isNotEmpty) ...[
                  Text(
                    widget.data.summary,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Options list (Clickable alternatives)
                if (!_completed && !_cancelled && widget.data.options.isNotEmpty) ...[
                  const Text(
                    'ตัวเลือก/ขั้นตอนดำเนินการ (กดเลือกได้ทันที):',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...widget.data.options.map((opt) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.arrow_circle_right_outlined,
                          size: 14,
                          color: actionColor,
                        ),
                        label: Text(
                          opt,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.left,
                        ),
                        onPressed: _executing ? null : () => _handleOptionSelected(opt),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(
                            color: actionColor.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    ),
                  )),
                  const SizedBox(height: 8),
                ],

                if (widget.data.params.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: widget.data.params.entries
                        .where(
                          (e) =>
                              e.value != null &&
                              e.value.toString().isNotEmpty &&
                              e.key != 'action' &&
                              e.key != 'user_id',
                        )
                        .take(6)
                        .map((entry) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${entry.key}: ${entry.value}',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                ],

                // Completed state
                if (_completed) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _resultMessage ?? 'ดำเนินการเรียบร้อยแล้ว',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_cancelled) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          color: theme.colorScheme.outline,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ยกเลิกการดำเนินการแล้ว',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Action Buttons: OK, Cancel, Other
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _executing ? null : _handleConfirm,
                        icon: _executing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 15),
                        label: const Text(
                          'ยืนยัน (Confirm)',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: actionColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _executing ? null : _handleCancel,
                        icon: const Icon(Icons.close_rounded, size: 15),
                        label: const Text(
                          'ยกเลิก (Cancel)',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _executing
                            ? null
                            : () => setState(
                                () => _showOtherInput = !_showOtherInput,
                              ),
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: const Text(
                          'ระบุอื่น ๆ...',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (_showOtherInput) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _otherCtrl,
                            decoration: const InputDecoration(
                              hintText: 'พิมพ์ความต้องการเพิ่มเติม หรือรายละเอียดคำสั่ง...',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            onSubmitted: (_) => _handleOtherSubmit(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _handleOtherSubmit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          child: const Text('ส่ง', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyableCodeBlock extends StatelessWidget {
  final String text;
  final String language;

  const _CopyableCodeBlock({required this.text, required this.language});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.content_copy_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                language.isEmpty ? 'กล่องข้อความสำหรับก๊อบปี้' : language,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('คัดลอกข้อความแล้ว')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('ก๊อบปี้'),
              ),
            ],
          ),
          SelectableText(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyableTableBlock extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;

  const _CopyableTableBlock({required this.headers, required this.rows});

  String _toTsv() {
    final buffer = StringBuffer();
    buffer.writeln(headers.join('\t'));
    for (final row in rows) {
      buffer.writeln(row.join('\t'));
    }
    return buffer.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.table_chart_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'ตารางข้อมูล',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _toTsv()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('คัดลอกตารางแล้ว')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('ก๊อบปี้'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder.all(color: theme.colorScheme.outlineVariant),
              columnWidths: {
                for (var i = 0; i < headers.length; i++)
                  i: const IntrinsicColumnWidth(),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  children: headers.map((header) {
                    return Padding(
                      padding: const EdgeInsets.all(10),
                      child: SelectableText(
                        header,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                ...rows.map((row) {
                  return TableRow(
                    children: row.map((cell) {
                      return Padding(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(
                          cell,
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    }).toList(),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatImageBlock extends StatelessWidget {
  final String source;
  final String altText;

  const _ChatImageBlock({required this.source, required this.altText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = _AssetPreviewSupport.imageProvider(source);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  altText.isEmpty ? 'รูปภาพ' : altText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: source));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('คัดลอก path/url รูปแล้ว')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('ก๊อบปี้'),
              ),
            ],
          ),
          if (provider != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 280,
                  minWidth: double.infinity,
                ),
                color: Colors.black.withValues(alpha: 0.04),
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _ImageErrorState(
                      message: 'โหลดรูปไม่สำเร็จ',
                      source: source,
                    );
                  },
                ),
              ),
            )
          else
            _ImageErrorState(message: 'รูปไม่ถูกต้อง', source: source),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await _AssetOpenSupport.openWithSystemApp(
                    context,
                    source,
                    missingMessage: 'ไม่พบที่อยู่รูป',
                    openErrorPrefix: 'เปิดรูปไม่สำเร็จ',
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('เปิดรูป'),
              ),
            ],
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              source,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PdfCardBlock extends StatelessWidget {
  final String title;
  final String path;
  final String thumbnail;
  final int? pages;

  const _PdfCardBlock({
    required this.title,
    required this.path,
    required this.thumbnail,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewProvider = _AssetPreviewSupport.imageProvider(thumbnail);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.isEmpty ? 'PDF' : title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: path));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('คัดลอก path PDF แล้ว')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('ก๊อบปี้'),
              ),
            ],
          ),
          if (previewProvider != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 220,
                  minWidth: double.infinity,
                ),
                color: Colors.black.withValues(alpha: 0.04),
                child: Image(
                  image: previewProvider,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const _ImageErrorState(
                      message: 'โหลดภาพตัวอย่าง PDF ไม่สำเร็จ',
                      source: '',
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PdfInfoChip(
                icon: Icons.description_outlined,
                label: pages != null ? '$pages หน้า' : 'ไม่ทราบจำนวนหน้า',
              ),
              _PdfInfoChip(
                icon: Icons.folder_open_outlined,
                label: _AiMessageBlockParser._fileNameFromPath(path),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await _AssetOpenSupport.openWithSystemApp(
                    context,
                    path,
                    missingMessage: 'ไม่พบที่อยู่ไฟล์',
                    openErrorPrefix: 'เปิด PDF ไม่สำเร็จ',
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('เปิดไฟล์'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            path,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PdfInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  final List<_AiTimelineItem> items;

  const _TimelineBlock({required this.items});

  String _toPlainText() {
    return items
        .map((item) {
          final buffer = StringBuffer();
          if (item.time.isNotEmpty) {
            buffer.write('[${item.time}] ');
          }
          buffer.write(item.title.isEmpty ? 'เหตุการณ์' : item.title);
          if (item.detail.isNotEmpty) {
            buffer.write(' - ${item.detail}');
          }
          return buffer.toString();
        })
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.timeline_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'ไทม์ไลน์',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _toPlainText()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('คัดลอกไทม์ไลน์แล้ว')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('ก๊อบปี้'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final style = _TimelineTypeStyle.resolve(theme, item.type);
            final isLast = index == items.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, right: 10),
                      child: Text(
                        item.time.isEmpty ? '-' : item.time,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: style.dotColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 2,
                            ),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title.isEmpty ? 'เหตุการณ์' : item.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.detail.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            SelectableText(
                              item.detail,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: style.backgroundColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              style.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: style.textColor,
                                fontWeight: FontWeight.w600,
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
          }),
        ],
      ),
    );
  }
}

class _TimelineTypeStyle {
  final Color dotColor;
  final Color backgroundColor;
  final Color textColor;
  final String label;

  const _TimelineTypeStyle({
    required this.dotColor,
    required this.backgroundColor,
    required this.textColor,
    required this.label,
  });

  static _TimelineTypeStyle resolve(ThemeData theme, String rawType) {
    final type = rawType.trim().toLowerCase();
    final colorScheme = theme.colorScheme;

    switch (type) {
      case 'created':
        return _TimelineTypeStyle(
          dotColor: colorScheme.primary,
          backgroundColor: colorScheme.primaryContainer,
          textColor: colorScheme.onPrimaryContainer,
          label: 'สร้างงาน',
        );
      case 'in_progress':
        return _TimelineTypeStyle(
          dotColor: colorScheme.tertiary,
          backgroundColor: colorScheme.tertiaryContainer,
          textColor: colorScheme.onTertiaryContainer,
          label: 'กำลังดำเนินการ',
        );
      case 'completed':
        return _TimelineTypeStyle(
          dotColor: Colors.green.shade600,
          backgroundColor: Colors.green.shade50,
          textColor: Colors.green.shade900,
          label: 'เสร็จสิ้น',
        );
      case 'warning':
        return _TimelineTypeStyle(
          dotColor: Colors.orange.shade700,
          backgroundColor: Colors.orange.shade50,
          textColor: Colors.orange.shade900,
          label: 'เฝ้าระวัง',
        );
      case 'critical':
        return _TimelineTypeStyle(
          dotColor: colorScheme.error,
          backgroundColor: colorScheme.errorContainer,
          textColor: colorScheme.onErrorContainer,
          label: 'สำคัญ',
        );
      default:
        return _TimelineTypeStyle(
          dotColor: colorScheme.secondary,
          backgroundColor: colorScheme.secondaryContainer,
          textColor: colorScheme.onSecondaryContainer,
          label: 'อัปเดต',
        );
    }
  }
}

class _InteractiveChartBlock extends StatefulWidget {
  final _AiChartData chartData;

  const _InteractiveChartBlock({required this.chartData});

  @override
  State<_InteractiveChartBlock> createState() => _InteractiveChartBlockState();
}

class _InteractiveChartBlockState extends State<_InteractiveChartBlock> {
  late String _activeType;
  bool _showTable = false;
  int _touchedIndex = -1;

  @override
  void initState() {
    super.initState();
    _activeType = _normalizeType(widget.chartData.chartType);
  }

  String _normalizeType(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('pie')) return 'pie';
    if (lower.contains('donut') || lower.contains('doughnut')) return 'donut';
    if (lower.contains('line') || lower.contains('area') || lower.contains('trend')) return 'line';
    return 'bar';
  }

  double get _totalSum {
    if (widget.chartData.data.isEmpty) return 0.0;
    return widget.chartData.data.fold(0.0, (acc, item) => acc + item.value);
  }

  double get _maxValue {
    if (widget.chartData.data.isEmpty) return 0.0;
    return widget.chartData.data.map((e) => e.value).reduce(math.max);
  }

  double get _avgValue {
    if (widget.chartData.data.isEmpty) return 0.0;
    return _totalSum / widget.chartData.data.length;
  }

  String _formatNumber(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  String _generateCsvData() {
    final buffer = StringBuffer();
    buffer.writeln('ลำดับ,รายการ,ค่า,หน่วย,สัดส่วน (%)');
    final total = _totalSum;
    for (int i = 0; i < widget.chartData.data.length; i++) {
      final item = widget.chartData.data[i];
      final pct = total > 0 ? (item.value / total * 100).toStringAsFixed(1) : '0';
      buffer.writeln('${i + 1},"${item.label}",${item.value},"${widget.chartData.unit}",$pct%');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final unit = widget.chartData.unit;
    final data = widget.chartData.data;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getChartIcon(_activeType),
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.chartData.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.chartData.subtitle != null && widget.chartData.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.chartData.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Chart Type Selector
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTypeButton('bar', Icons.bar_chart_rounded, 'แท่ง', theme),
                      _buildTypeButton('pie', Icons.pie_chart_rounded, 'วงกลม', theme),
                      _buildTypeButton('donut', Icons.donut_large_rounded, 'โดนัท', theme),
                      _buildTypeButton('line', Icons.show_chart_rounded, 'เส้น', theme),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Toggle Table / Chart
                IconButton(
                  tooltip: _showTable ? 'ดูกราฟ' : 'ดูตารางข้อมูล',
                  icon: Icon(
                    _showTable ? Icons.bar_chart_rounded : Icons.table_chart_outlined,
                    size: 19,
                    color: _showTable ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => setState(() => _showTable = !_showTable),
                  style: IconButton.styleFrom(
                    backgroundColor: _showTable
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(34, 34),
                  ),
                ),
                // Copy CSV Button
                IconButton(
                  tooltip: 'คัดลอกข้อมูล CSV',
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _generateCsvData()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('คัดลอกข้อมูลตาราง CSV เรียบร้อยแล้ว'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(34, 34),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 2. Summary KPI Ribbon
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildKpiChip('ยอดรวม', '${_formatNumber(_totalSum)} $unit', theme, Colors.blue),
                _buildKpiChip('สูงสุด', '${_formatNumber(_maxValue)} $unit', theme, Colors.green),
                _buildKpiChip('ค่าเฉลี่ย', '${_formatNumber(_avgValue)} $unit', theme, Colors.orange),
                _buildKpiChip('จำนวนกลุ่ม', '${data.length} รายการ', theme, Colors.purple),
              ],
            ),
          ),

          // 3. Body View: Chart or Table
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _showTable
                ? _buildTableView(theme, unit)
                : _buildChartView(theme, unit),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton(String type, IconData icon, String tooltip, ThemeData theme) {
    final isSelected = _activeType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _activeType = type;
          _showTable = false;
        });
      },
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getChartIcon(String type) {
    switch (type) {
      case 'pie':
        return Icons.pie_chart_rounded;
      case 'donut':
        return Icons.donut_large_rounded;
      case 'line':
        return Icons.show_chart_rounded;
      default:
        return Icons.bar_chart_rounded;
    }
  }

  Widget _buildKpiChip(String label, String value, ThemeData theme, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartView(ThemeData theme, String unit) {
    final data = widget.chartData.data;
    if (data.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('ไม่มีข้อมูลสำหรับแสดงกราฟ')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 260,
          child: Padding(
            padding: const EdgeInsets.only(top: 16, right: 12),
            child: switch (_activeType) {
              'pie' => _buildPieChart(theme, false, unit),
              'donut' => _buildPieChart(theme, true, unit),
              'line' => _buildLineChart(theme, unit),
              _ => _buildBarChart(theme, unit),
            },
          ),
        ),
        const SizedBox(height: 12),
        // Legend List for Pie / Donut
        if (_activeType == 'pie' || _activeType == 'donut')
          _buildPieLegend(theme, unit),
      ],
    );
  }

  Widget _buildBarChart(ThemeData theme, String unit) {
    final data = widget.chartData.data;
    final maxVal = _maxValue;
    final maxY = maxVal > 0 ? (maxVal * 1.25) : 10.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = data[group.x.toInt()];
              final pct = _totalSum > 0 ? ' (${(item.value / _totalSum * 100).toStringAsFixed(1)}%)' : '';
              return BarTooltipItem(
                '${item.label}\n',
                TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                children: [
                  TextSpan(
                    text: '${_formatNumber(item.value)} $unit$pct',
                    style: TextStyle(
                      color: theme.colorScheme.primaryContainer,
                      fontWeight: FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          ),
          touchCallback: (FlTouchEvent event, barTouchResponse) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  barTouchResponse == null ||
                  barTouchResponse.spot == null) {
                _touchedIndex = -1;
                return;
              }
              _touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;
            });
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (val, meta) {
                if (val == meta.max || val == meta.min) return const SizedBox.shrink();
                return Text(
                  _formatNumber(val),
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                final item = data[idx];
                final shortLabel = item.label.length > 8 ? '${item.label.substring(0, 7)}…' : item.label;
                final isSelected = idx == _touchedIndex;

                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    shortLabel,
                    style: TextStyle(
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(data.length, (i) {
          final item = data[i];
          final isTouched = i == _touchedIndex;
          final barColor = item.color ?? _AiChartData.defaultPalette[i % _AiChartData.defaultPalette.length];

          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: item.value,
                color: isTouched ? barColor.withValues(alpha: 0.85) : barColor,
                width: data.length > 10 ? 14 : (data.length > 6 ? 18 : 26),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildPieChart(ThemeData theme, bool isDonut, String unit) {
    final data = widget.chartData.data;
    final total = _totalSum;

    return PieChart(
      PieChartData(
        pieTouchData: PieTouchData(
          touchCallback: (FlTouchEvent event, pieTouchResponse) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  pieTouchResponse == null ||
                  pieTouchResponse.touchedSection == null) {
                _touchedIndex = -1;
                return;
              }
              _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
            });
          },
        ),
        borderData: FlBorderData(show: false),
        sectionsSpace: 2,
        centerSpaceRadius: isDonut ? 48 : 0,
        sections: List.generate(data.length, (i) {
          final item = data[i];
          final isTouched = i == _touchedIndex;
          final radius = isTouched ? 65.0 : 54.0;
          final pct = total > 0 ? (item.value / total * 100) : 0.0;
          final color = item.color ?? _AiChartData.defaultPalette[i % _AiChartData.defaultPalette.length];

          return PieChartSectionData(
            color: color,
            value: item.value,
            title: pct >= 4.0 ? '${pct.toStringAsFixed(0)}%' : '',
            radius: radius,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(color: Colors.black45, blurRadius: 3),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPieLegend(ThemeData theme, String unit) {
    final data = widget.chartData.data;
    final total = _totalSum;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: List.generate(data.length, (i) {
          final item = data[i];
          final color = item.color ?? _AiChartData.defaultPalette[i % _AiChartData.defaultPalette.length];
          final pct = total > 0 ? (item.value / total * 100).toStringAsFixed(1) : '0';
          final isSelected = i == _touchedIndex;

          return InkWell(
            onTap: () => setState(() => _touchedIndex = (_touchedIndex == i ? -1 : i)),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${_formatNumber(item.value)} $unit - $pct%)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLineChart(ThemeData theme, String unit) {
    final data = widget.chartData.data;
    final maxVal = _maxValue;
    final maxY = maxVal > 0 ? (maxVal * 1.25) : 10.0;
    final primaryColor = theme.colorScheme.primary;

    final spots = List.generate(data.length, (i) {
      return FlSpot(i.toDouble(), data[i].value);
    });

    return LineChart(
      LineChartData(
        maxY: maxY,
        minY: 0,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final item = data[idx];
                return LineTooltipItem(
                  '${item.label}\n',
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: '${_formatNumber(spot.y)} $unit',
                      style: TextStyle(
                        color: theme.colorScheme.primaryContainer,
                        fontWeight: FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (val, meta) {
                if (val == meta.max || val == meta.min) return const SizedBox.shrink();
                return Text(
                  _formatNumber(val),
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                final item = data[idx];
                final shortLabel = item.label.length > 8 ? '${item.label.substring(0, 7)}…' : item.label;

                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    shortLabel,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: primaryColor,
            barWidth: 3.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4.5,
                  color: primaryColor,
                  strokeWidth: 2,
                  strokeColor: theme.colorScheme.surface,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: primaryColor.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableView(ThemeData theme, String unit) {
    final data = widget.chartData.data;
    final total = _totalSum;
    final maxVal = _maxValue;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            ),
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('ลำดับ', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('รายการ / หมวดหมู่', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('จำนวน / ค่า', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('สัดส่วน (%)', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('แถบสัดส่วน', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: List.generate(data.length, (i) {
              final item = data[i];
              final pct = total > 0 ? (item.value / total * 100) : 0.0;
              final color = item.color ?? _AiChartData.defaultPalette[i % _AiChartData.defaultPalette.length];
              final ratioToMax = maxVal > 0 ? (item.value / maxVal) : 0.0;

              return DataRow(
                cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  DataCell(Text('${_formatNumber(item.value)} $unit')),
                  DataCell(Text('${pct.toStringAsFixed(1)}%')),
                  DataCell(
                    SizedBox(
                      width: 100,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratioToMax.clamp(0.0, 1.0),
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _InteractivePresentationDeckBlock extends StatefulWidget {
  final _AiPresentationDeckData deck;

  const _InteractivePresentationDeckBlock({required this.deck});

  @override
  State<_InteractivePresentationDeckBlock> createState() => _InteractivePresentationDeckBlockState();
}

class _InteractivePresentationDeckBlockState extends State<_InteractivePresentationDeckBlock> {
  int _currentIndex = 0;
  bool _isExporting = false;
  bool _showSources = false;
  String? _savedPdfPath;

  @override
  void initState() {
    super.initState();
    _savedPdfPath = widget.deck.pdfPath;
  }

  Color _resolvePrimaryColor() {
    switch (widget.deck.theme.toLowerCase().trim()) {
      case 'teal':
      case 'green':
      case 'lean':
        return const Color(0xFF00796B);
      case 'purple':
      case 'enterprise':
        return const Color(0xFF5E35B1);
      case 'orange':
      case 'urgent':
      case 'rca':
        return const Color(0xFFD84315);
      case 'blue':
      default:
        return const Color(0xFF1565C0);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      String path = _savedPdfPath ?? '';
      if (path.isEmpty || !await File(path).exists()) {
        final rawSlides = widget.deck.slides.map((s) => s.raw).toList();
        path = await AiPresentationPdfService.generatePresentationPdf(
          title: widget.deck.title,
          subtitle: widget.deck.subtitle,
          author: widget.deck.author,
          themeName: widget.deck.theme,
          slides: rawSlides,
          sourceReferences: widget.deck.sources,
        );
        setState(() => _savedPdfPath = path);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ส่งออกสไลด์ PDF แนวนอนเรียบร้อย: ${p.basename(path)}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'เปิดดูไฟล์ PDF',
              onPressed: () => AiPresentationPdfService.openPdf(path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการสร้าง PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _printSlides() async {
    if (_savedPdfPath != null && await File(_savedPdfPath!).exists()) {
      await AiPresentationPdfService.printPdf(_savedPdfPath!);
    } else {
      await _exportPdf();
      if (_savedPdfPath != null && await File(_savedPdfPath!).exists()) {
        await AiPresentationPdfService.printPdf(_savedPdfPath!);
      }
    }
  }

  void _copySlideSummary() {
    final buffer = StringBuffer();
    buffer.writeln('# ${widget.deck.title}');
    if (widget.deck.subtitle != null) buffer.writeln('## ${widget.deck.subtitle}');
    buffer.writeln('');
    for (int i = 0; i < widget.deck.slides.length; i++) {
      final s = widget.deck.slides[i];
      buffer.writeln('---');
      buffer.writeln('### สไลด์ที่ ${i + 1}: ${s.title}');
      if (s.content != null && s.content!.isNotEmpty) buffer.writeln(s.content);
      if (s.metrics.isNotEmpty) {
        for (final m in s.metrics) {
          buffer.writeln('- **${m.label}**: ${m.value} (เป้าหมาย: ${m.target ?? "-"})');
        }
      }
      if (s.actionItems.isNotEmpty) {
        for (final a in s.actionItems) {
          buffer.writeln('1. $a');
        }
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('คัดลอกเนื้อหาสไลด์ทั้งหมดเรียบร้อยแล้ว'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = _resolvePrimaryColor();
    final totalSlides = widget.deck.slides.length;
    final currentSlide = totalSlides > 0 ? widget.deck.slides[_currentIndex.clamp(0, totalSlides - 1)] : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Studio Header Toolbar (NotebookLM Aesthetic)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: isDark ? 0.15 : 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    size: 20,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.deck.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'PDF แนวนอน 16:9',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.deck.subtitle != null && widget.deck.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.deck.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Action Buttons
                if (widget.deck.sources.isNotEmpty)
                  IconButton(
                    tooltip: 'แหล่งข้อมูลอ้างอิง (${widget.deck.sources.length})',
                    icon: Icon(
                      Icons.source_rounded,
                      size: 18,
                      color: _showSources ? primaryColor : theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _showSources = !_showSources),
                    style: IconButton.styleFrom(
                      backgroundColor: _showSources
                          ? primaryColor.withValues(alpha: 0.15)
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(34, 34),
                    ),
                  ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'คัดลอกสรุปสไลด์',
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  onPressed: _copySlideSummary,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(34, 34),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'พิมพ์สไลด์ (Print)',
                  icon: const Icon(Icons.print_rounded, size: 18),
                  onPressed: _printSlides,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(34, 34),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _isExporting ? null : _exportPdf,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded, size: 16),
                  label: Text(_isExporting ? 'กำลังสร้าง...' : 'ดาวน์โหลด PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // 2. Grounded Sources Drawer (NotebookLM Source Grounding)
          if (_showSources && widget.deck.sources.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hub_rounded, size: 15, color: primaryColor),
                      const SizedBox(width: 6),
                      Text(
                        '📚 แหล่งข้อมูลที่ Sub-agents นำมาสังเคราะห์ (Multi-Source Grounding):',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: widget.deck.sources.map((s) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          '• $s',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // 3. Main Slide Canvas (16:9 Responsive Display)
          Padding(
            padding: const EdgeInsets.all(16),
            child: currentSlide != null
                ? _buildSlideBody(currentSlide, theme, isDark, primaryColor)
                : const SizedBox(height: 240, child: Center(child: Text('ไม่มีสไลด์ในชุดนี้'))),
          ),

          // 4. Slide Navigation Controls
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous Slide Button
                OutlinedButton.icon(
                  onPressed: _currentIndex > 0
                      ? () => setState(() => _currentIndex--)
                      : null,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('สไลด์ก่อนหน้า'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),

                // Slide Thumbnails / Indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'สไลด์ ${_currentIndex + 1} / $totalSlides',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...List.generate(totalSlides, (idx) {
                      final isSelected = idx == _currentIndex;
                      return InkWell(
                        onTap: () => setState(() => _currentIndex = idx),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: isSelected ? 18 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryColor : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ],
                ),

                // Next Slide Button
                FilledButton.icon(
                  onPressed: _currentIndex < totalSlides - 1
                      ? () => setState(() => _currentIndex++)
                      : null,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('สไลด์ถัดไป'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlideBody(_AiSlideItem slide, ThemeData theme, bool isDark, Color primaryColor) {
    return Container(
      constraints: const BoxConstraints(minHeight: 280),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Slide Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          slide.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatSlideTypeBadge(slide.type),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Slide Specific Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: switch (slide.type) {
              'title' || 'cover' => _buildCoverSlideView(slide, theme, primaryColor),
              'kpi' => _buildKpiSlideView(slide, theme, primaryColor),
              'fishbone' => _buildFishboneSlideView(slide, theme, primaryColor),
              'rca_5why' || '5why' => _build5WhySlideView(slide, theme, primaryColor),
              'eight_d' || '8d' => _build8DSlideView(slide, theme, primaryColor),
              'chart' => _buildChartSlideView(slide, theme, primaryColor),
              'summary' => _buildSummarySlideView(slide, theme, primaryColor),
              _ => _buildGeneralSlideView(slide, theme, primaryColor),
            },
          ),
        ],
      ),
    );
  }

  String _formatSlideTypeBadge(String type) {
    switch (type) {
      case 'title':
        return 'หน้าปก (Cover)';
      case 'kpi':
        return 'KPI Dashboard';
      case 'fishbone':
        return 'Fishbone 4M1E';
      case 'rca_5why':
      case '5why':
        return '5-Why RCA';
      case 'eight_d':
      case '8d':
        return '8D Report';
      case 'chart':
        return 'สถิติกราฟ';
      case 'summary':
        return 'บทสรุป & Action';
      default:
        return 'เนื้อหา';
    }
  }

  /// 1. Cover Slide View
  Widget _buildCoverSlideView(_AiSlideItem slide, ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withValues(alpha: 0.08),
            primaryColor.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'MASAPP · EXECUTIVE PRESENTATION',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (slide.subtitle != null && slide.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              slide.subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ผู้จัดทำ: ${widget.deck.author ?? "ฝ่ายซ่อมบำรุงและวิศวกรรม"}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                DateFormat('dd/MM/yyyy').format(DateTime.now()),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 2. KPI Slide View
  Widget _buildKpiSlideView(_AiSlideItem slide, ThemeData theme, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slide.content != null && slide.content!.isNotEmpty) ...[
          Text(slide.content!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.8,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: slide.metrics.length,
          itemBuilder: (ctx, i) {
            final m = slide.metrics[i];
            Color statusColor = primaryColor;
            if (m.status == 'good' || m.status == 'pass') statusColor = Colors.green;
            if (m.status == 'warning') statusColor = Colors.orange;
            if (m.status == 'critical' || m.status == 'fail') statusColor = Colors.red;

            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    m.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        m.value,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      if (m.change != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            m.change!,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                          ),
                        ),
                    ],
                  ),
                  if (m.target != null)
                    Text(
                      'เป้าหมาย: ${m.target}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// 3. Fishbone 4M1E Slide View
  Widget _buildFishboneSlideView(_AiSlideItem slide, ThemeData theme, Color primaryColor) {
    final fb = slide.fishbone;
    if (fb == null) return const Center(child: Text('ไม่มีข้อมูลผังก้างปลา'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Problem Box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ปัญหาหลัก: ${fb.problem}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 4M1E 5 Category Boxes
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildFishboneCategoryCard('👨 Man (คน/ทักษะ)', fb.man, theme, primaryColor),
            _buildFishboneCategoryCard('⚙️ Machine (เครื่องจักร)', fb.machine, theme, primaryColor),
            _buildFishboneCategoryCard('📋 Method (ขั้นตอน)', fb.method, theme, primaryColor),
            _buildFishboneCategoryCard('📦 Material (อะไหล่/วัสดุ)', fb.material, theme, primaryColor),
            _buildFishboneCategoryCard('🌡️ Environment (สภาพแวดล้อม)', fb.environment, theme, primaryColor),
          ],
        ),
      ],
    );
  }

  Widget _buildFishboneCategoryCard(String title, List<String> items, ThemeData theme, Color primaryColor) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Text('- ไม่มีประเด็นตรวจพบ', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline))
          else
            ...items.map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                      Expanded(child: Text(it, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  /// 4. 5-Why Drill-down Slide View
  Widget _build5WhySlideView(_AiSlideItem slide, ThemeData theme, Color primaryColor) {
    final fw = slide.fiveWhy;
    if (fw == null) return const Center(child: Text('ไม่มีข้อมูล 5-Why'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '🚨 ปัญหา: ${fw.problem}',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(fw.whys.length, (idx) {
          final isLast = idx == fw.whys.length - 1;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isLast ? primaryColor.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isLast ? primaryColor : theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLast ? primaryColor : theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Why #${idx + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fw.whys[idx],
                    style: TextStyle(
                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade600),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🎯 Root Cause (สาเหตุที่แท้จริง): ${fw.rootCause}', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 13)),
              if (fw.countermeasure != null && fw.countermeasure!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('🛡️ มาตรการป้องกัน (Action): ${fw.countermeasure}', style: TextStyle(color: Colors.green.shade800, fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 5. 8D Methodology Slide View
  Widget _build8DSlideView(_AiSlideItem slide, ThemeData theme, Color primaryColor) {
    if (slide.eightD.isEmpty) return const Center(child: Text('ไม่มีข้อมูล 8D'));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(primaryColor.withValues(alpha: 0.1)),
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('ขั้นตอน', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('หัวข้อ', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('การดำเนินการ', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('ผู้รับผิดชอบ', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('สถานะ', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: slide.eightD.map((st) {
          return DataRow(cells: [
            DataCell(Text(st.step, style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(st.title, style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text(st.description)),
            DataCell(Text(st.owner)),
            DataCell(Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(st.status, style: TextStyle(fontSize: 10, color: Colors.green.shade900, fontWeight: FontWeight.bold)),
            )),
          ]);
        }).toList(),
      ),
    );
  }

  /// 6. Chart Slide View
  Widget _buildChartSlideView(_AiSlideItem slide, ThemeData theme, Color primaryColor) {
    if (slide.chartData != null) {
      return _InteractiveChartBlock(chartData: slide.chartData!);
    }
    return Text(slide.content ?? 'ไม่มีข้อมูลกราฟสำหรับสไลด์นี้');
  }

  /// 7. Summary & Action Plan View
  Widget _buildSummarySlideView(_AiSlideItem slide, ThemeData theme, Color primaryColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📌 สรุปภาพรวม (Summary):', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: primaryColor)),
                const SizedBox(height: 8),
                Text(slide.content ?? 'การดำเนินงานเป็นไปตามแผนงาน', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🎯 แผนงานขั้นตอนถัดไป (Next Actions):', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: primaryColor)),
                const SizedBox(height: 8),
                if (slide.actionItems.isEmpty)
                  const Text('- ติดตามแผนงานตามมาตรฐาน PM/AM ประจำเดือน')
                else
                  ...List.generate(slide.actionItems.length, (idx) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(slide.actionItems[idx], style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 8. General Slide View
  Widget _buildGeneralSlideView(_AiSlideItem slide, ThemeData theme, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (slide.content != null && slide.content!.isNotEmpty) ...[
          Text(slide.content!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
        ],
        if (slide.bullets.isNotEmpty)
          ...slide.bullets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: primaryColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              )),
      ],
    );
  }
}

class _AssetPreviewSupport {
  static bool _isNetworkOrFileUri(String source) {
    final lower = source.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('file:///');
  }

  static ImageProvider<Object>? imageProvider(String source) {
    final trimmed = source.trim();
    if (!looksLikeImageSource(trimmed)) return null;
    if (trimmed.toLowerCase().startsWith('file:///')) {
      return FileImage(File(Uri.parse(trimmed).toFilePath()));
    }
    if (_isNetworkOrFileUri(trimmed)) {
      return NetworkImage(trimmed);
    }
    return FileImage(File(trimmed));
  }

  static bool looksLikeImageSource(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    return RegExp(
      r'(\.png|\.jpg|\.jpeg|\.gif|\.webp|\.bmp)(\?.*)?$',
      caseSensitive: false,
    ).hasMatch(lower);
  }
}

class _AssetOpenSupport {
  static Future<void> openWithSystemApp(
    BuildContext context,
    String source, {
    required String missingMessage,
    required String openErrorPrefix,
  }) async {
    try {
      final normalizedPath = source.trim();
      if (normalizedPath.isEmpty) {
        throw Exception(missingMessage);
      }

      final result = await OpenFilex.open(normalizedPath);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถเปิดไฟล์ได้: ${result.message}'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$openErrorPrefix: $e')),
        );
      }
    }
  }
}

class _ImageErrorState extends StatelessWidget {
  final String message;
  final String source;

  const _ImageErrorState({required this.message, required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: theme.colorScheme.outline,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(message, style: theme.textTheme.bodyMedium),
            ],
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              source,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _RagDocumentsSheet extends StatefulWidget {
  final VoidCallback onRefresh;
  const _RagDocumentsSheet({required this.onRefresh});

  @override
  State<_RagDocumentsSheet> createState() => _RagDocumentsSheetState();
}

class _RagDocumentsSheetState extends State<_RagDocumentsSheet> {
  List<RagDocumentItem> _docs = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RagDocumentService.listIngestedDocuments();
      if (mounted) setState(() { _docs = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xlsx', 'xls', 'csv', 'txt', 'md'],
        dialogTitle: 'เลือกไฟล์คู่มือเครื่องจักร หรือไฟล์ตาราง Excel',
      );

      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);

      setState(() => _uploading = true);

      final res = await RagDocumentService.ingestDocument(file: file);
      if (!mounted) return;
      setState(() => _uploading = false);
      await _load();
      if (!mounted) return;
      widget.onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'นำเข้าคู่มือสำเร็จ'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการนำเข้าคู่มือ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _delete(String docId, String name) async {
    await RagDocumentService.deleteDocumentVectors(docId);
    await _load();
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: Colors.purple),
              const SizedBox(width: 8),
              Text('คลังคู่มือ & เอกสาร AI RAG', style: theme.textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(_uploading ? 'กำลังแปลง...' : 'อัปโหลดคู่มือ PDF'),
                style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'AI จะดึงเนื้อหาจากเอกสารเหล่านี้มาวิเคราะห์และอ้างอิงตอบคำถามเมื่อช่างถามเรื่องการซ่อมหรือคู่มือ',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _docs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.picture_as_pdf_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            const Text('ยังไม่มีคู่มือในระบบ RAG', style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 4),
                            const Text('กดปุ่ม "อัปโหลดคู่มือ PDF" เพื่อให้ AI ศึกษาคู่มือ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _docs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final doc = _docs[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.purple, size: 22),
                            ),
                            title: Text(doc.fileName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text('จำนวน ${doc.chunkCount} ท่อนเวกเตอร์ · ${doc.createdAt.toString().split(".").first}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                              tooltip: 'ลบออกจาก RAG',
                              onPressed: () => _delete(doc.documentId, doc.fileName),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
