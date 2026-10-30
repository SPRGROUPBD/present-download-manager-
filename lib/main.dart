import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:startapp_sdk/startapp.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

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
  static const String _unityGameId = '6215571';
  static const String _unityInterstitialPlacement = 'Interstitial_Android';
  final StartAppSdk _startAppSdk = StartAppSdk();
  StartAppBannerAd? _startAppBanner;
  bool _unityInitialized = false;
  bool _unityInterstitialReady = false;
  int _completedDownloadsSinceAd = 0;
  Timer? _startAppRetryTimer;
  Timer? _unityRetryTimer;
  bool _startAppBannerLoading = false;
  String _startAppAdStatus = 'বিজ্ঞাপন সংযোগ করা হচ্ছে…';
  String? _startAppAdError;
  String _unityAdStatus = 'Unity Ads চালু হচ্ছে…';
  String? _unityAdError;
  String _lastAdEvent = 'এখনো কোনো বিজ্ঞাপন ইভেন্ট পাওয়া যায়নি';

  void _recordAdEvent(String message) {
    if (!mounted) return;
    setState(() => _lastAdEvent = '${DateTime.now().toString().substring(0, 19)} — $message');
  }

  @override
  void initState() {
    super.initState();
    _initializeAds();
  }

  Future<void> _initializeAds() async {
    if (!Platform.isAndroid) return;

    await _loadStartAppBanner();

    UnityAds.init(
      gameId: _unityGameId,
      testMode: false,
      onComplete: () {
        debugPrint('Unity Ads initialized');
        _unityInitialized = true;
        if (mounted) setState(() { _unityAdStatus = 'Unity প্রস্তুত — Interstitial লোড হচ্ছে'; _unityAdError = null; });
        _recordAdEvent('Unity Ads initialized');
        _loadUnityInterstitial();
      },
      onFailed: (error, message) {
        debugPrint('Unity Ads initialization failed: $error $message');
        if (mounted) setState(() { _unityAdStatus = 'Unity initialization failed'; _unityAdError = '$error: $message'; });
        _recordAdEvent('Unity initialization failed: $error $message');
        _scheduleUnityRetry();
      },
    );
  }

  Future<void> _loadStartAppBanner() async {
    if (!Platform.isAndroid || _startAppBannerLoading || _startAppBanner != null) return;
    _startAppBannerLoading = true;
    if (mounted) setState(() { _startAppAdStatus = 'Start.io বিজ্ঞাপন লোড হচ্ছে…'; _startAppAdError = null; });
    try {
      // Explicitly disable Start.io test ads for the production release.
      // App ID is injected into AndroidManifest by the build workflow.
      await _startAppSdk.setTestAdsEnabled(false);
      debugPrint('Start.io production mode configured; requesting banner...');
      if (mounted) setState(() => _startAppAdStatus = 'Start.io: Banner request পাঠানো হচ্ছে…');
      _recordAdEvent('Start.io banner request started');
      final ad = await _startAppSdk.loadBannerAd(
        StartAppBannerType.BANNER,
        onAdImpression: () => debugPrint('Start.io banner impression received'),
        onAdClicked: () => debugPrint('Start.io banner clicked'),
      );
      if (!mounted) {
        ad.dispose();
        return;
      }
      setState(() { _startAppBanner = ad; _startAppAdStatus = 'বিজ্ঞাপন চালু আছে'; _startAppAdError = null; });
      _startAppRetryTimer?.cancel();
      debugPrint('Start.io banner loaded successfully');
      _recordAdEvent('Start.io banner loaded successfully');
    } catch (error, stackTrace) {
      final message = error.toString();
      debugPrint('Start.io production banner load failed: $message');
      try { debugPrint('Start.io SDK version: ${await _startAppSdk.getSdkVersion()}'); } catch (sdkError) { debugPrint('Start.io SDK version check failed: $sdkError'); }
      debugPrint('$stackTrace');
      if (mounted) setState(() { _startAppAdStatus = 'বিজ্ঞাপন পাওয়া যায়নি — আবার চেষ্টা করুন'; _startAppAdError = message; });
      _recordAdEvent('Start.io banner failed: $message');
      _scheduleStartAppRetry();
    } finally {
      _startAppBannerLoading = false;
    }
  }

  void _scheduleStartAppRetry() {
    if (!mounted || _startAppBanner != null) return;
    _startAppRetryTimer?.cancel();
    _startAppRetryTimer = Timer(const Duration(seconds: 30), _loadStartAppBanner);
  }

  void _scheduleUnityRetry() {
    if (!mounted || !Platform.isAndroid) return;
    _unityRetryTimer?.cancel();
    _unityRetryTimer = Timer(const Duration(seconds: 30), () {
      if (!_unityInitialized) {
        UnityAds.init(
          gameId: _unityGameId,
          testMode: false,
          onComplete: () {
            _unityInitialized = true;
            _loadUnityInterstitial();
          },
          onFailed: (error, message) {
            debugPrint('Unity Ads retry initialization failed: $error $message');
            _scheduleUnityRetry();
          },
        );
      } else {
        _loadUnityInterstitial();
      }
    });
  }

  void _loadUnityInterstitial() {
    if (!_unityInitialized || !Platform.isAndroid) return;
    UnityAds.load(
      placementId: _unityInterstitialPlacement,
      onComplete: (placementId) {
        _unityInterstitialReady = true;
        if (mounted) setState(() { _unityAdStatus = 'Interstitial প্রস্তুত'; _unityAdError = null; });
        _recordAdEvent('Unity interstitial loaded: $placementId');
        debugPrint('Unity production interstitial loaded: $placementId');
      },
      onFailed: (placementId, error, message) {
        _unityInterstitialReady = false;
        if (mounted) setState(() { _unityAdStatus = 'Interstitial load failed'; _unityAdError = '$error: $message'; });
        _recordAdEvent('Unity interstitial load failed: $error $message');
        debugPrint('Unity interstitial load failed for $placementId: $error $message');
        _scheduleUnityRetry();
      },
    );
  }

  void _maybeShowUnityInterstitial() {
    if (!Platform.isAndroid) return;
    _completedDownloadsSinceAd++;
    if (_completedDownloadsSinceAd < 3 ||
        !_unityInitialized ||
        !_unityInterstitialReady) {
      _recordAdEvent('Unity ad skipped — downloads: $_completedDownloadsSinceAd/3, initialized: $_unityInitialized, loaded: $_unityInterstitialReady');
      return;
    }
    _completedDownloadsSinceAd = 0;
    _unityInterstitialReady = false;
    UnityAds.showVideoAd(
      placementId: _unityInterstitialPlacement,
      onStart: (_) => debugPrint('Unity interstitial started'),
      onComplete: (placementId) {
        debugPrint('Unity interstitial completed: $placementId');
        _loadUnityInterstitial();
      },
      onSkipped: (placementId) {
        debugPrint('Unity interstitial skipped: $placementId');
        _loadUnityInterstitial();
      },
      onFailed: (placementId, error, message) {
        debugPrint('Unity interstitial show failed for $placementId: $error $message');
        _loadUnityInterstitial();
      },
    );
  }

  @override
  void dispose() {
    _startAppRetryTimer?.cancel();
    _unityRetryTimer?.cancel();
    _startAppBanner?.dispose();
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

  bool _isSocialVideoPage(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    return host == 'youtube.com' || host.endsWith('.youtube.com') ||
        host == 'youtu.be' || host == 'facebook.com' ||
        host.endsWith('.facebook.com') || host == 'fb.watch' ||
        host == 'tiktok.com' || host.endsWith('.tiktok.com') ||
        host == 'instagram.com' || host.endsWith('.instagram.com');
  }

  Future<Response<ResponseBody>> _requestWithRetry(
    String url,
    CancelToken? cancelToken,
  ) async {
    DioException? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await _dio.get<ResponseBody>(
          url,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
            receiveTimeout: const Duration(minutes: 0),
            sendTimeout: const Duration(seconds: 30),
            headers: {'User-Agent': 'PresentDownloadManager/1.3.5'},
          ),
        );
      } on DioException catch (e) {
        lastError = e;
        final retryable = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout;
        if (!retryable || attempt == 3 || cancelToken?.isCancelled == true) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw lastError ?? Exception('নেটওয়ার্ক সংযোগ ব্যর্থ হয়েছে।');
  }

  Future<void> _pasteUrl() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final value = data?.text?.trim() ?? '';
      if (value.isEmpty) {
        _showMessage('Clipboard-এ কোনো URL পাওয়া যায়নি। আগে লিংক Copy করুন।');
        return;
      }
      _urlController.text = value;
      _urlController.selection = TextSelection.collapsed(offset: value.length);
      _showMessage('URL পেস্ট হয়েছে। এখন Download চাপুন।');
    } catch (e) {
      _showMessage('Paste করা যায়নি: $e');
    }
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
    if (_isSocialVideoPage(uri)) {
      _showMessage('এটি YouTube/Facebook/TikTok-এর পেজ লিংক। সরাসরি ভিডিও ফাইলের MP4/WebM লিংক দিন অথবা প্ল্যাটফর্মের নিজস্ব Download/Save সুবিধা ব্যবহার করুন।');
      return;
    }
    final item = DownloadItem(url: url, fileName: _fileNameFromUrl(url));
    setState(() {
      _items.insert(0, item);
      _urlController.clear();
    });
    await _downloadItem(item);
  }

  Future<void> _retryDownload(DownloadItem item) async {
    if (_busy || item.status == DownloadStatus.downloading) return;
    setState(() {
      item.status = DownloadStatus.downloading;
      item.progress = 0;
      item.received = 0;
      item.total = 0;
      item.error = null;
      item.savedPath = null;
    });
    await _downloadItem(item);
  }

  Future<void> _downloadItem(DownloadItem item) async {
    if (_busy) return;
    _busy = true;
    item.cancelToken = CancelToken();
    if (mounted) setState(() {});
    String? path;
    try {
      final uri = Uri.parse(item.url);
      // Do not pre-resolve DNS here. Let the HTTP client use Android/Windows network DNS.
      // The previous extra lookup could fail before the actual HTTP request was attempted.
      final directory = await getApplicationDocumentsDirectory();
      final downloads = Directory('${directory.path}${Platform.pathSeparator}Downloads');
      if (!await downloads.exists()) {
        await downloads.create(recursive: true);
      }
      final safeName = item.fileName.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '_');
      path = '${downloads.path}${Platform.pathSeparator}$safeName';
      final response = await _requestWithRetry(item.url, item.cancelToken);
      final body = response.data;
      if (body == null) throw Exception('সার্ভার থেকে কোনো ডেটা পাওয়া যায়নি।');
      item.total = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      ) ?? 0;
      final file = File(path);
      final sink = file.openWrite();
      try {
        await for (final chunk in body.stream) {
          if (item.cancelToken?.isCancelled == true) break;
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
      if (item.cancelToken?.isCancelled == true) {
        if (await file.exists()) await file.delete();
        item.status = DownloadStatus.cancelled;
      } else {
        item.savedPath = path;
        item.progress = 1;
        item.status = DownloadStatus.completed;
        if (mounted) {
          _showMessage('ডাউনলোড সম্পন্ন: $safeName');
          _maybeShowUnityInterstitial();
        }
      }
    } on DioException catch (e) {
      item.status = e.type == DioExceptionType.cancel
          ? DownloadStatus.cancelled
          : DownloadStatus.failed;
      final message = e.message ?? 'নেটওয়ার্ক সংযোগ ব্যর্থ হয়েছে।';
      item.error = message.toLowerCase().contains('failed host lookup')
          ? 'DNS সমস্যা: সার্ভারের ঠিকানা পাওয়া যায়নি। Internet/DNS পরীক্ষা করে Retry চাপুন।'
          : 'সংযোগ সমস্যা: $message';
      if (path != null) {
        final partial = File(path);
        if (await partial.exists()) await partial.delete();
      }
    } catch (e) {
      item.status = item.cancelToken?.isCancelled == true
          ? DownloadStatus.cancelled
          : DownloadStatus.failed;
      item.error = e.toString().replaceFirst('Exception: ', '');
      if (path != null) {
        final partial = File(path);
        if (await partial.exists()) await partial.delete();
      }
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
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
              applicationVersion: '1.3.5',
              children: const [
                Text('HTTP/HTTPS file downloader with retry and direct video-file URL support.'),
              ],
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      bottomNavigationBar: Platform.isAndroid
          ? SafeArea(
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                width: double.infinity,
                alignment: Alignment.center,
                child: _startAppBanner != null
                    ? StartAppBanner(_startAppBanner!)
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.ads_click, size: 16),
                            const SizedBox(width: 8),
                            Flexible(child: Text(_startAppAdStatus, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center)),
                            const SizedBox(width: 8),
                            TextButton(onPressed: _startAppBannerLoading ? null : _loadStartAppBanner, child: const Text('Retry')),
                          ],
                        ),
                      ),
              ),
            )
          : null,
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _urlController,
                                keyboardType: TextInputType.url,
                                minLines: 1,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  hintText: 'https://example.com/file.zip',
                                  labelText: 'এখানে Download URL পেস্ট করুন',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.link),
                                ),
                                onSubmitted: (_) => _startDownload(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              height: 56,
                              child: OutlinedButton.icon(
                                onPressed: _pasteUrl,
                                icon: const Icon(Icons.content_paste, size: 18),
                                label: const Text('Paste'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _startDownload,
                            icon: const Icon(Icons.download),
                            label: const Text('Download Now'),
                          ),
                        ),
                        if (Platform.isAndroid) ...[
                          const SizedBox(height: 12),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            initiallyExpanded: false,
                            leading: const Icon(Icons.monitor_heart_outlined),
                            title: const Text('Ad Status / Diagnostics'),
                            subtitle: const Text('Start.io ও Unity Ads-এর অবস্থা'),
                            children: [
                              Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Start.io: $_startAppAdStatus', style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (_startAppAdError != null) SelectableText('Start.io Error: $_startAppAdError', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                                const SizedBox(height: 8),
                                Text('Unity Ads: $_unityAdStatus', style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (_unityAdError != null) SelectableText('Unity Error: $_unityAdError', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                                const SizedBox(height: 8),
                                const Text('সর্বশেষ বিজ্ঞাপন ইভেন্ট:', style: TextStyle(fontWeight: FontWeight.w600)),
                                SelectableText(_lastAdEvent, style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 8),
                                Text('Unity Interstitial: প্রতি ৩টি সফল ডাউনলোডের পর দেখানোর চেষ্টা হবে।', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ])),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        const Text(
                          'HTTP/HTTPS ফাইল এবং সরাসরি MP4/WebM/MOV ভিডিও ফাইল ডাউনলোড করুন।',
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
                                          )
                                        else if (item.status == DownloadStatus.failed ||
                                            item.status == DownloadStatus.cancelled)
                                          TextButton.icon(
                                            onPressed: _busy ? null : () => _retryDownload(item),
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('আবার চেষ্টা'),
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
