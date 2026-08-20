import 'package:path/path.dart' as p;
// lib/features/ai_chat/ai_chat_screen.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/ai_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/auth/auth_provider.dart';
import 'ai_chat_provider.dart';
import '../../core/ai/rag_document_service.dart';
import 'package:file_picker/file_picker.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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



  File? _pendingAttachment;
  String? _pendingAttachmentName;
  int? _pendingAttachmentSize;
  String? _pendingAttachmentExt;

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md', 'csv', 'png', 'jpg', 'jpeg'],
        dialogTitle: 'เลือกคู่มือเครื่องจักร หรือรูปถ่ายอาการเสีย',
      );

      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      final name = p.basename(file.path);
      final size = await file.length();
      final ext = p.extension(file.path).toLowerCase().replaceAll('.', '');

      setState(() {
        _pendingAttachment = file;
        _pendingAttachmentName = name;
        _pendingAttachmentSize = size;
        _pendingAttachmentExt = ext;
      });
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

  void _clearAttachment() {
    setState(() {
      _pendingAttachment = null;
      _pendingAttachmentName = null;
      _pendingAttachmentSize = null;
      _pendingAttachmentExt = null;
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
    final attachedFile = _pendingAttachment;
    final attachedName = _pendingAttachmentName;
    final attachedExt = _pendingAttachmentExt;

    if ((text.isEmpty && attachedFile == null) || _sending) return;

    final user = ref.read(authProvider);
    setState(() {
      _sending = true;
      _pendingAttachment = null;
      _pendingAttachmentName = null;
      _pendingAttachmentSize = null;
      _pendingAttachmentExt = null;
    });
    _controller.clear();

    try {
      String finalPrompt = text;

      if (attachedFile != null) {
        if (['pdf', 'txt', 'md', 'csv'].contains(attachedExt)) {
          // Ingest document into RAG
          final res = await RagDocumentService.ingestDocument(file: attachedFile);
          final docName = res['file_name'] ?? attachedName ?? 'เอกสาร';
          if (text.isEmpty) {
            finalPrompt = '📄 [แนบเอกสาร: $docName]\nช่วยสรุปและวิเคราะห์เนื้อหาสำคัญในเอกสารนี้ให้หน่อยครับ';
          } else {
            finalPrompt = '📄 [แนบเอกสาร: $docName]\n$text';
          }
        } else {
          // Image
          if (text.isEmpty) {
            finalPrompt = '📸 [แนบรูปภาพ: $attachedName]\nช่วยวิเคราะห์อาการเสียหรือข้อมูลในภาพนี้ให้หน่อยครับ';
          } else {
            finalPrompt = '📸 [แนบรูปภาพ: $attachedName]\n$text';
          }
        }
      }

      await ref
          .read(aiChatProvider.notifier)
          .sendMessage(finalPrompt, userId: user?.userId);

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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
            icon: const Icon(Icons.menu_book_rounded),
            tooltip: 'คลังคู่มือ & เอกสาร RAG',
            onPressed: _showRagDocumentsDialog,
          ),
          if (state.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'ล้างบทสนทนา',
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
      body: !state.isConfigured
          ? _buildNotConfigured(theme)
          : Column(
              children: [
                Expanded(
                  child: state.messages.isEmpty
                      ? _buildWelcome(theme)
                      : _buildMessageList(state, theme),
                ),
                _buildQuickActions(theme),
                _buildInputBar(theme),
              ],
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

  Widget _buildQuickActions(ThemeData theme) {
    final chips = [
      ('📚 คลังคู่มือ RAG', Icons.menu_book_rounded),
      ('เครื่องที่ Breakdown', Icons.warning_amber_rounded),
      ('อะไหล่ใกล้หมด', Icons.inventory_2_outlined),
      ('งานที่ค้างอยู่', Icons.assignment_late_outlined),
      ('OEE วันนี้', Icons.analytics_outlined),
    ];

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: chips.map((c) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(c.$2, size: 16),
              label: Text(c.$1, style: const TextStyle(fontSize: 12)),
              onPressed: _sending
                  ? null
                  : () {
                      if (c.$1 == '📚 คลังคู่มือ RAG') {
                        _showRagDocumentsDialog();
                      } else {
                        _controller.text = c.$1;
                        _send();
                      }
                    },
            ),
          );
        }).toList(),
      ),
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
          if (_pendingAttachment != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  Icon(
                    _pendingAttachmentExt == 'pdf'
                        ? Icons.picture_as_pdf_rounded
                        : ['png', 'jpg', 'jpeg'].contains(_pendingAttachmentExt)
                            ? Icons.image_rounded
                            : Icons.description_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      _pendingAttachmentName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_pendingAttachmentSize != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${(_pendingAttachmentSize! / 1024).toStringAsFixed(1)} KB)',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _sending ? null : _clearAttachment,
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 18, color: Colors.grey),
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
                tooltip: 'แนบไฟล์คู่มือ PDF / รูปภาพ',
                onPressed: _sending ? null : _pickAttachment,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_sending,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: _pendingAttachment != null
                        ? 'พิมพ์คำถามเกี่ยวกับไฟล์ที่แนบไว้ แล้วกดส่ง...'
                        : 'ถามเกี่ยวกับข้อมูลในระบบ...',
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
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
              margin: const EdgeInsets.only(right: 8, top: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : message.isError
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: message.isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'กำลังคิด...',
                          style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  : _MessageContent(message: message),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  final ChatMessage message;

  const _MessageContent({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final textColor = isUser
        ? theme.colorScheme.onPrimary
        : message.isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurface;

    final blocks = _AiMessageBlockParser.parse(message.content);
    if (blocks.length == 1 && blocks.first.type == _AiMessageBlockType.text) {
      return SelectableText(
        message.content,
        style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) {
        switch (block.type) {
          case _AiMessageBlockType.text:
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText(
                block.text,
                style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
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
        }
      }).toList(),
    );
  }
}

enum _AiMessageBlockType { text, code, table, image, pdf, timeline }

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
      timelineItems = const [];

  const _AiMessageBlock.code(this.text, {this.language = ''})
    : type = _AiMessageBlockType.code,
      headers = const [],
      rows = const [],
      source = '',
      altText = '',
      title = '',
      thumbnail = '',
      pages = null,
      timelineItems = const [];

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
       timelineItems = const [];

  const _AiMessageBlock.image({required this.source, required this.altText})
    : type = _AiMessageBlockType.image,
      text = '',
      language = '',
      headers = const [],
      rows = const [],
      title = '',
      thumbnail = '',
      pages = null,
      timelineItems = const [];

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
       timelineItems = const [];

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
      pages = null;
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

  static String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isNotEmpty ? parts.last : path;
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
        allowedExtensions: ['pdf', 'txt', 'md', 'csv'],
        dialogTitle: 'เลือกคู่มือเครื่องจักร หรือเอกสารซ่อมบำรุง',
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
