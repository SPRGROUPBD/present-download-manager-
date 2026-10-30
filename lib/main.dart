import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const PresentDownloadManagerApp());

class PresentDownloadManagerApp extends StatelessWidget {
  const PresentDownloadManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Present Download Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769AA)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF64B5F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const DownloadHomePage(),
    );
  }
}

enum DownloadStatus { downloading, completed, failed, cancelled }

class DownloadItem {
  DownloadItem({required this.url, required this.fileName});
  final String url;
  final String fileName;
  double progress = 0;
  int received = 0;
  int total = 0;
  DownloadStatus status = DownloadStatus.downloading;
  String? savedPath;
  String? error;
  CancelToken? cancelToken;
}

class DownloadHomePage extends StatefulWidget {
  const DownloadHomePage({super.key});

  @override
  State<DownloadHomePage> createState() => _DownloadHomePageState();
}

class _DownloadHomePageState extends State<DownloadHomePage> {
  final _urlController = TextEditingController();
  final _dio = Dio();
  final List<DownloadItem> _items = [];
  bool _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    for (final item in _items) {
      item.cancelToken?.cancel('Application closed');
    }
    super.dispose();
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    if (segment.isNotEmpty && segment.contains('.')) {
      return Uri.decodeComponent(segment);
    }
    return 'download_${DateTime.now().millisecondsSinceEpoch}.bin';
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _showMessage('একটি সঠিক HTTP/HTTPS ডাউনলোড লিংক দিন।');
      return;
    }

    final item = DownloadItem(url: url, fileName: _fileNameFromUrl(url))
      ..cancelToken = CancelToken();
    setState(() {
      _items.insert(0, item);
      _busy = true;
      _urlController.clear();
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloads = Directory('${directory.path}${Platform.pathSeparator}Downloads');
      if (!await downloads.exists()) {
        await downloads.create(recursive: true);
      }
      final safeName = item.fileName.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '_');
      final path = '${downloads.path}${Platform.pathSeparator}$safeName';
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: item.cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 0),
        ),
      );
      final body = response.data;
      if (body == null) throw Exception('সার্ভার থেকে কোনো ডেটা পাওয়া যায়নি।');
      item.total = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
      final file = File(path);
      final sink = file.openWrite();
      try {
        await for (final chunk in body.stream) {
          sink.add(chunk);
          item.received += chunk.length;
          if (mounted) {
            setState(() {
              item.progress = item.total > 0
                  ? (item.received / item.total).clamp(0.0, 1.0)
                  : 0;
            });
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      item.savedPath = path;
      item.progress = 1;
      item.status = DownloadStatus.completed;
      if (mounted) _showMessage('ডাউনলোড সম্পন্ন: $safeName');
    } on DioException catch (e) {
      item.status = e.type == DioExceptionType.cancel
          ? DownloadStatus.cancelled
          : DownloadStatus.failed;
      item.error = e.message;
    } catch (e) {
      item.status = DownloadStatus.failed;
      item.error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) setState(() {});
  }

  void _cancel(DownloadItem item) {
    item.cancelToken?.cancel('Cancelled by user');
    setState(() => item.status = DownloadStatus.cancelled);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusText(DownloadItem item) {
    switch (item.status) {
      case DownloadStatus.downloading: return 'ডাউনলোড হচ্ছে';
      case DownloadStatus.completed: return 'সম্পন্ন';
      case DownloadStatus.failed: return 'ব্যর্থ';
      case DownloadStatus.cancelled: return 'বাতিল';
    }
  }

  String _size(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Present Download Manager'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'About',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Present Download Manager',
              applicationVersion: '1.2.0',
              children: const [
                Text('Cross-platform HTTP/HTTPS download manager starter.'),
              ],
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('নতুন ডাউনলোড', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            hintText: 'https://example.com/file.zip',
                            labelText: 'Download URL',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link),
                          ),
                          onSubmitted: (_) => _startDownload(),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _busy ? null : _startDownload,
                          icon: const Icon(Icons.download),
                          label: const Text('ডাউনলোড শুরু করুন'),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'এই সংস্করণে HTTP/HTTPS ফাইল ডাউনলোডের প্রাথমিক সুবিধা রয়েছে।',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('ডাউনলোড তালিকা', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    Text('${_items.length} টি'),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('এখনো কোনো ডাউনলোড নেই।'))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.insert_drive_file_outlined),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                        Text(_statusText(item)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(value: item.total > 0 ? item.progress : null),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(child: Text('${_size(item.received)} / ${_size(item.total)}')),
                                        if (item.status == DownloadStatus.downloading)
                                          TextButton.icon(
                                            onPressed: () => _cancel(item),
                                            icon: const Icon(Icons.close),
                                            label: const Text('বাতিল'),
                                          ),
                                      ],
                                    ),
                                    if (item.savedPath != null)
                                      SelectableText('সংরক্ষিত: ${item.savedPath}', style: const TextStyle(fontSize: 11)),
                                    if (item.error != null)
                                      Text(item.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
