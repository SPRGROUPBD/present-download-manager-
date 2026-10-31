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
  static const String _unityBannerPlacement = 'Banner_Android';
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
  String _activeFilter = 'All';
  DownloadItem? _selectedItem;
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
    final activeCount = _items.where((e) => e.status == DownloadStatus.downloading).length;
    final completedCount = _items.where((e) => e.status == DownloadStatus.completed).length;
    final visibleItems = _items.where((e) {
      if (_activeFilter == 'Active') return e.status == DownloadStatus.downloading;
      if (_activeFilter == 'Completed') return e.status == DownloadStatus.completed;
      return true;
    }).toList();
    final wide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Present Download Manager'),
        actions: [
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Present Download Manager',
              applicationVersion: '1.4.2',
              children: const [Text('Cross-platform file download manager.')],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'ads') {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Start.io: $_startAppAdStatus'),
                        if (_startAppAdError != null) SelectableText(_startAppAdError!),
                        const SizedBox(height: 8),
                        Text('Unity Ads: $_unityAdStatus'),
                        if (_unityAdError != null) SelectableText(_unityAdError!),
                        const SizedBox(height: 8),
                        SelectableText(_lastAdEvent),
                      ]),
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'ads', child: Text('Ad Diagnostics'))],
          ),
        ],
      ),
      body: Column(
        children: [
          // FDM-inspired dark action toolbar
          Container(
            height: 62,
            color: const Color(0xFF29364D),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF159BE8),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(54, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: _showAddDownloadDialog,
                child: const Icon(Icons.add, size: 30),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Retry failed download',
                onPressed: _busy ? null : _retryFirstFailed,
                color: Colors.white,
                icon: const Icon(Icons.play_arrow, size: 30),
              ),
              IconButton(
                tooltip: 'Pause / Cancel active download',
                onPressed: _cancelFirstActive,
                color: Colors.white,
                icon: const Icon(Icons.pause, size: 27),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'About',
                onPressed: () => showAboutDialog(context: context, applicationName: 'Present Download Manager', applicationVersion: '1.3.7'),
                color: Colors.white,
                icon: const Icon(Icons.info_outline),
              ),
            ]),
          ),
          // Download category tabs
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryTab('All (${_items.length})', 'All'),
                _buildCategoryTab('Active ($activeCount)', 'Active'),
                _buildCategoryTab('Completed ($completedCount)', 'Completed'),
                _buildCategoryTab('YouTube', 'YouTube'),
                _buildCategoryTab('Video', 'Video'),
                _buildCategoryTab('Music', 'Music'),
              ],
            ),
          ),
          Expanded(
            child: Column(children: [
              Expanded(
                flex: wide ? 6 : 5,
                child: _activeFilter == 'YouTube'
                    ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('YouTube page download is not supported. Use the platform-provided download/save option or a direct file URL.', textAlign: TextAlign.center)))
                    : Column(children: [
                        Container(
                          height: 40,
                          color: const Color(0xFFF0F2F5),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: const Row(children: [
                            SizedBox(width: 34, child: Icon(Icons.check_box_outline_blank, size: 18)),
                            Expanded(flex: 5, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                            Expanded(flex: 2, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                            Expanded(flex: 2, child: Text('Size', style: TextStyle(fontWeight: FontWeight.bold))),
                          ]),
                        ),
                        Expanded(
                          child: visibleItems.isEmpty
                              ? const Center(child: Text('কোনো ডাউনলোড নেই। + বাটনে চাপ দিয়ে URL যোগ করুন।'))
                              : ListView.separated(
                                  itemCount: visibleItems.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = visibleItems[index];
                                    return Material(
                                      color: identical(_selectedItem, item) ? const Color(0xFFE3F2FD) : Colors.transparent,
                                      child: InkWell(
                                        onTap: () => setState(() => _selectedItem = item),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                          child: Row(children: [
                                            const SizedBox(width: 34, child: Icon(Icons.insert_drive_file_outlined, color: Color(0xFF168DD1))),
                                            Expanded(flex: 5, child: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                            Expanded(
                                              flex: 2,
                                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                Text(item.status == DownloadStatus.downloading ? '${(item.progress * 100).toStringAsFixed(0)}%' : _statusText(item), style: const TextStyle(fontSize: 12)),
                                                const SizedBox(height: 4),
                                                LinearProgressIndicator(value: item.status == DownloadStatus.completed ? 1 : item.total > 0 ? item.progress : null, minHeight: 5),
                                              ]),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(flex: 2, child: Text('${_size(item.received)} / ${_size(item.total)}', style: const TextStyle(fontSize: 11))),
                                          ]),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ]),
              ),
              // FDM-style selected-file details
              Container(
                height: wide ? 205 : 175,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F2F4),
                  border: Border(top: BorderSide(color: Color(0xFFD5DAE2))),
                ),
                child: _selectedItem == null
                    ? const Center(child: Text('বিস্তারিত দেখতে তালিকা থেকে একটি ফাইল নির্বাচন করুন'))
                    : DefaultTabController(
                        length: 3,
                        child: Column(children: [
                          const TabBar(
                            tabs: [Tab(text: 'General'), Tab(text: 'Progress'), Tab(text: 'Connections')],
                            labelColor: Color(0xFF168DD1),
                            unselectedLabelColor: Colors.blueGrey,
                          ),
                          Expanded(
                            child: TabBarView(children: [
                              _buildGeneralDetails(_selectedItem!),
                              _buildProgressDetails(_selectedItem!),
                              Center(child: Text(_selectedItem!.status == DownloadStatus.downloading ? 'HTTP connection active' : 'No active connections')),
                            ]),
                          ),
                        ]),
                      ),
              ),
            ]),
          ),
          if (Platform.isAndroid && _startAppBanner != null)
            SafeArea(child: SizedBox(height: 50, child: Center(child: StartAppBanner(_startAppBanner!))))
          else if (Platform.isAndroid && _unityInitialized)
            SafeArea(
              child: SizedBox(
                height: 50,
                child: Center(
                  child: UnityBannerAd(
                    placementId: _unityBannerPlacement,
                    onLoad: (placementId) {
                      debugPrint('Unity banner loaded: $placementId');
                      if (mounted) setState(() { _unityAdStatus = 'Banner ও Interstitial প্রস্তুত'; _unityAdError = null; });
                      _recordAdEvent('Unity banner loaded: $placementId');
                    },
                    onClick: (placementId) => debugPrint('Unity banner clicked: $placementId'),
                    onShown: (placementId) => debugPrint('Unity banner shown: $placementId'),
                    onFailed: (placementId, error, message) {
                      debugPrint('Unity banner failed for $placementId: $error $message');
                      if (mounted) setState(() { _unityAdStatus = 'Banner load failed'; _unityAdError = '$error: $message'; });
                      _recordAdEvent('Unity banner failed: $placementId — $error: $message');
                    },
                  ),
                ),
              ),
            ),
          Container(
            height: 30,
            color: const Color(0xFFE8F5E9),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [Text('Active: $activeCount'), const Spacer(), Text('Completed: $completedCount')]),
          ),
        ],
      ),
    );
  }

  void _showAddDownloadDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Download'),
        content: TextField(
          controller: _urlController,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Download URL',
            hintText: 'https://example.com/file.zip',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final value = data?.text?.trim() ?? '';
              if (value.isNotEmpty) _urlController.text = value;
            },
            child: const Text('Paste'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _startDownload();
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  void _retryFirstFailed() {
    for (final item in _items) {
      if (item.status == DownloadStatus.failed || item.status == DownloadStatus.cancelled) {
        _retryDownload(item);
        return;
      }
    }
  }

  void _cancelFirstActive() {
    for (final item in _items) {
      if (item.status == DownloadStatus.downloading) {
        _cancel(item);
        return;
      }
    }
  }

  Widget _buildCategoryTab(String label, String value) {
    final selected = _activeFilter == value;
    return InkWell(
      onTap: () => setState(() => _activeFilter = value),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE3F2FD) : const Color(0xFFF0F1F3),
          border: selected ? const Border(bottom: BorderSide(color: Color(0xFF159BE8), width: 2)) : null,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(child: Text(label, style: TextStyle(
          color: selected ? const Color(0xFF126DA8) : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ))),
      ),
    );
  }

  Widget _buildGeneralDetails(DownloadItem item) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        const Icon(Icons.insert_drive_file, size: 52, color: Color(0xFF198DCE)),
        const SizedBox(width: 14),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: item.status == DownloadStatus.completed ? 1 : item.total > 0 ? item.progress : null, minHeight: 9),
            const SizedBox(height: 6),
            Text('Downloaded: ${_size(item.received)} of ${_size(item.total)}'),
            if (item.error != null) Text(item.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.red, fontSize: 11)),
          ],
        )),
      ]),
    );
  }

  Widget _buildProgressDetails(DownloadItem item) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Progress: ${(item.progress * 100).toStringAsFixed(1)}%'),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: item.status == DownloadStatus.completed ? 1 : item.total > 0 ? item.progress : null, minHeight: 10),
        const SizedBox(height: 10),
        Text('Downloaded: ${_size(item.received)}   Total: ${_size(item.total)}   Status: ${_statusText(item)}'),
      ]),
    );
  }
}
