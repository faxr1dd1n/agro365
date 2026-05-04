import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Agro365 uchun asosiy ranglar.
class Agro365Colors {
  Agro365Colors._();

  static const Color brandGreen = Color(0xFF1B4332);
  static const Color brandRed = Color(0xFFE53935);
  static const Color splashBackground = Colors.white;
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Status bar rangini o'rnatamiz
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agro365',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Agro365Colors.brandGreen),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
    _runSplashSequence();
  }

  Future<void> _runSplashSequence() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const WebViewPage()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Agro365Colors.splashBackground,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _fadeAnimation.value,
                child: child,
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.asset(
              'assets/logo/agro365.jpg',
              width: 250,
              height: 250,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _showSplashUntilFirstPage = true;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    // Platform-specific parameters
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        limitsNavigationsToAppBoundDomains: false,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    // Controller ni URL yuklamasdan init qilamiz
    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted || !_showSplashUntilFirstPage) return;
            setState(() {
              _showSplashUntilFirstPage = false;
            });
          },
        ),
      );

    // Platform-specific setup
    if (Platform.isAndroid) {
      if (_controller.platform is AndroidWebViewController) {
        final androidController =
            _controller.platform as AndroidWebViewController;
        await androidController.setMediaPlaybackRequiresUserGesture(false);
        await androidController.setGeolocationEnabled(true);
        androidController.setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (GeolocationPermissionsRequestParams params) async {
            final status = await Permission.locationWhenInUse.request();
            return GeolocationPermissionsResponse(
              allow: status.isGranted,
              retain: false,
            );
          },
          onHidePrompt: () {},
        );
      }
      // Setup file handler for Android only
      _setupFileHandler();
    }

    await _controller.loadRequest(Uri.parse('https://agro-365.uz/ru'));
  }

  void _setupFileHandler() {
    _controller.addJavaScriptChannel(
      'FileUpload',
      onMessageReceived: (JavaScriptMessage message) async {
        await _handleFileUpload();
      },
    );

    // Inject JavaScript to intercept file inputs
    Future.delayed(const Duration(milliseconds: 1000), () {
      _controller.runJavaScript('''
      (function() {
          console.log('🔴 File upload interceptor loaded');

          // Function to prevent default file input
          function preventFileInput(input) {
            input.addEventListener('click', function(e) {
              console.log('📁 File input click prevented!');
              e.preventDefault();
              e.stopPropagation();
              e.stopImmediatePropagation();
              window.FileUpload.postMessage('upload');
              return false;
            }, { capture: true, passive: false });

            // Also prevent focus
            input.addEventListener('focus', function(e) {
              console.log('📁 File input focus prevented!');
              e.preventDefault();
              input.blur();
              window.FileUpload.postMessage('upload');
            }, { capture: true });
          }

          // Block existing file inputs
          var existingInputs = document.querySelectorAll('input[type="file"]');
          console.log('Found ' + existingInputs.length + ' file inputs');
          existingInputs.forEach(preventFileInput);

          // Intercept ALL clicks globally (highest priority)
          document.addEventListener('click', function(e) {
            var target = e.target;

            // Check if click is on or near file input
            if (target.tagName === 'INPUT' && target.type === 'file') {
              console.log('🚫 Direct file input click blocked!');
              e.preventDefault();
              e.stopPropagation();
              e.stopImmediatePropagation();
              window.FileUpload.postMessage('upload');
              return false;
            }

            // Check parent elements for file input
            var parent = target;
            for (var i = 0; i < 5; i++) {
              if (!parent) break;
              var fileInput = parent.querySelector('input[type="file"]');
              if (fileInput) {
                console.log('🚫 File input found in parent, blocking click!');
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                window.FileUpload.postMessage('upload');
                return false;
              }
              parent = parent.parentElement;
            }
          }, true); // Use capture phase

          // Watch for new file inputs
          var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
              mutation.addedNodes.forEach(function(node) {
                if (node.nodeType === 1) { // Element node
                  if (node.tagName === 'INPUT' && node.type === 'file') {
                    console.log('🆕 New file input detected and blocked');
                    preventFileInput(node);
                  }
                  // Check children
                  var inputs = node.querySelectorAll && node.querySelectorAll('input[type="file"]');
                  if (inputs) {
                    inputs.forEach(preventFileInput);
                  }
                }
              });
            });
          });

          observer.observe(document.body, {
            childList: true,
            subtree: true
          });

          console.log('✅ File upload interceptor ready');
      })();
    ''');
    });
  }

  Future<void> _handleFileUpload() async {
    debugPrint('🔴 File upload button pressed!');

    // Faqat Android uchun - source tanlash
    final source = await _showImageSourcePicker();
    if (source == null) {
      debugPrint('User cancelled source selection');
      return;
    }

    // Android uchun - faqat camera permission kerak
    final cameraStatus = await Permission.camera.status;
    debugPrint('📸 Camera: $cameraStatus');

    // Agar camera tanlanmagan bo'lsa (gallery) - permission kerak emas
    if (source == ImageSource.gallery) {
      debugPrint('📷 Gallery selected - no permission needed');
      try {
        final XFile? pickedFile = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );

        if (pickedFile != null) {
          await _uploadFileToWebView(pickedFile.path);
        }
      } catch (e) {
        debugPrint('❌ Error picking image: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rasm tanlashda xatolik: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    // Camera uchun permission tekshirish
    if (cameraStatus.isGranted) {
      debugPrint('✅ Camera permission OK');
      try {
        final XFile? pickedFile = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );

        if (pickedFile != null) {
          await _uploadFileToWebView(pickedFile.path);
        }
      } catch (e) {
        debugPrint('❌ Error picking image: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rasm tanlashda xatolik: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    // Agar permanently denied bo'lsa
    if (cameraStatus.isPermanentlyDenied) {
      debugPrint('🚫 Camera permanently denied - showing settings');
      if (mounted) {
        _showPermissionDialog();
      }
      return;
    }

    // Camera permission so'raymiz
    debugPrint('⏳ Requesting camera permission...');
    final newCameraStatus = await Permission.camera.request();
    debugPrint('📋 Camera result: $newCameraStatus');

    if (newCameraStatus.isGranted) {
      debugPrint('✅ Camera granted! Opening camera');
      try {
        final XFile? pickedFile = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );

        if (pickedFile != null) {
          await _uploadFileToWebView(pickedFile.path);
        }
      } catch (e) {
        debugPrint('❌ Error: $e');
      }
    } else if (newCameraStatus.isPermanentlyDenied) {
      debugPrint('❌ Permanently denied - showing settings');
      if (mounted) {
        _showPermissionDialog();
      }
    } else {
      debugPrint('❌ Camera permission denied by user');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Ruxsat kerak',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Rasm yuklash uchun kamera va galereya ruxsati kerak. Iltimos, sozlamalarda ruxsat bering.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Bekor qilish',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Agro365Colors.brandGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Sozlamalar'),
            ),
          ],
        );
      },
    );
  }

  Future<ImageSource?> _showImageSourcePicker() async {
    return await showModalBottomSheet<ImageSource>(
      backgroundColor: Colors.white,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'Rasm tanlash',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Agro365Colors.brandGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Agro365Colors.brandGreen,
                    ),
                  ),
                  title: const Text(
                    'Kamera',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text('Yangi rasm oling'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Agro365Colors.brandGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.photo_library,
                      color: Agro365Colors.brandGreen,
                    ),
                  ),
                  title: const Text(
                    'Galereya',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text('Mavjud rasmdan tanlang'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _uploadFileToWebView(String filePath) async {
    // Convert file to base64 and inject to webpage (iOS only)
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final fileName = filePath.split('/').last;

    // Inject the file data to the webpage's file input
    await _controller.runJavaScript('''
      (function() {
        var fileInput = document.querySelector('input[type="file"]');
        if (fileInput) {
          // Create a data transfer object
          var dataTransfer = new DataTransfer();
          
          // Convert base64 to blob
          var byteString = atob('$base64Image');
          var ab = new ArrayBuffer(byteString.length);
          var ia = new Uint8Array(ab);
          for (var i = 0; i < byteString.length; i++) {
            ia[i] = byteString.charCodeAt(i);
          }
          var blob = new Blob([ab], { type: 'image/jpeg' });
          
          // Create file from blob
          var file = new File([blob], '$fileName', { type: 'image/jpeg' });
          dataTransfer.items.add(file);
          
          // Set files to input
          fileInput.files = dataTransfer.files;
          
          // Trigger change event
          var event = new Event('change', { bubbles: true });
          fileInput.dispatchEvent(event);
        }
      })();
    ''');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rasm yuklandi!'),
          backgroundColor: Agro365Colors.brandGreen,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_showSplashUntilFirstPage)
              Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/logo/agro365.jpg',
                    width: 250,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
