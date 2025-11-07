// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:camerawesome/camerawesome_plugin.dart' as camerawesome;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shimmer/shimmer.dart';

import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_bloc.dart';
import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_event.dart';
import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_state.dart';

class LensSelectorPage extends StatefulWidget {
  const LensSelectorPage({super.key});

  @override
  State<LensSelectorPage> createState() => _LensSelectorPageState();
}

class _LensSelectorPageState extends State<LensSelectorPage>
    with SingleTickerProviderStateMixin {
  final bool _useIosHardware = Platform.isIOS;
  CameraDescription? _camera;
  CameraController? _configuredController;
  bool _isConfiguringLens = false;

  late final AnimationController _animCtl;

  List<_LensOption> _lensOptions = const [];
  _LensOption? _selectedLens;

  bool _flashSupported = false;
  FlashMode _currentFlashMode = FlashMode.off;
  camerawesome.FlashMode _iosFlashMode = camerawesome.FlashMode.auto;

  camerawesome.PhotoCameraState? _iosPhotoState;
  bool _isLoadingIosSensors = false;
  bool _isCapturingIosPhoto = false;
  String? _lastPhotoPath;

  @override
  void initState() {
    super.initState();
    _animCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (_useIosHardware) {
      _loadIosSensors();
    } else {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_useIosHardware) return;
    final cameras = await availableCameras();
    _camera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    context.read<PlateCameraCaptureBloc>().add(InitializeCamera(_camera!));
  }

  Future<void> _loadIosSensors() async {
    setState(() {
      _isLoadingIosSensors = true;
      _flashSupported = true;
    });

    try {
      final available = await camerawesome.CamerawesomePlugin.getSensors();
      final sensors = <camerawesome.SensorTypeDevice>[];
      if (available.ultraWideAngle != null) {
        sensors.add(available.ultraWideAngle!);
      }
      if (available.wideAngle != null) {
        sensors.add(available.wideAngle!);
      }
      if (available.telephoto != null) {
        sensors.add(available.telephoto!);
      }

      sensors.sort(
        (a, b) => _iosLensOrder(a.sensorType).compareTo(
          _iosLensOrder(b.sensorType),
        ),
      );

      final options = sensors
          .map(
            (sensor) => _LensOption(
              _iosLensLabel(sensor.sensorType),
              _iosZoomForSensor(sensor.sensorType),
              iosSensor: sensor,
            ),
          )
          .toList();

      _lensOptions = options;
      if (options.isNotEmpty) {
        _selectedLens = options.firstWhere(
          (opt) => opt.label == '1x',
          orElse: () => options.first,
        );
      } else {
        _selectedLens = null;
      }

      setState(() {
        _isLoadingIosSensors = false;
        _flashSupported = options.isNotEmpty;
      });

      await _applyIosLensSelection();
      await _ensureIosFlashMode();
    } catch (e, st) {
      debugPrint('⚠️ [LensSelector] gagal memuat lensa iOS: $e\n$st');
      if (!mounted) return;
      setState(() {
        _lensOptions = const [];
        _selectedLens = null;
        _isLoadingIosSensors = false;
        _flashSupported = false;
      });
    }
  }

  Future<String> _buildPhotoPath() async {
    final directory = await getTemporaryDirectory();
    final filePath = p.join(
      directory.path,
      'lens_capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    _lastPhotoPath = filePath;
    return filePath;
  }

  camerawesome.Sensor _sensorFromDevice(
    camerawesome.SensorTypeDevice device,
  ) {
    final sensor = camerawesome.Sensor.type(device.sensorType);
    sensor.position = camerawesome.SensorPosition.back;
    sensor.deviceId = device.uid;
    return sensor;
  }

  String _iosLensLabel(camerawesome.SensorType type) {
    switch (type) {
      case camerawesome.SensorType.ultraWideAngle:
        return '0.5x';
      case camerawesome.SensorType.telephoto:
        return '3x';
      case camerawesome.SensorType.wideAngle:
        return '1x';
      default:
        return type.name;
    }
  }

  double _iosZoomForSensor(camerawesome.SensorType type) {
    switch (type) {
      case camerawesome.SensorType.ultraWideAngle:
        return 0.5;
      case camerawesome.SensorType.telephoto:
        return 3.0;
      default:
        return 1.0;
    }
  }

  int _iosLensOrder(camerawesome.SensorType type) {
    switch (type) {
      case camerawesome.SensorType.ultraWideAngle:
        return 0;
      case camerawesome.SensorType.wideAngle:
        return 1;
      case camerawesome.SensorType.telephoto:
        return 2;
      default:
        return 3;
    }
  }

  Future<void> _applyIosLensSelection() async {
    if (!_useIosHardware) return;
    final photoState = _iosPhotoState;
    final target = _selectedLens?.iosSensor;
    if (photoState == null || target == null) return;

    await photoState.setSensorConfig(
      camerawesome.SensorConfig.single(
        sensor: _sensorFromDevice(target),
        flashMode: _iosFlashMode,
        aspectRatio: camerawesome.CameraAspectRatios.ratio_4_3,
      ),
    );

    final bloc = context.read<PlateCameraCaptureBloc>();
    bloc.add(InitializeCamera(_camera!));
  }

  @override
  void dispose() {
    context.read<PlateCameraCaptureBloc>().add(DisposeCamera());
    _animCtl.dispose();
    super.dispose();
  }

  Future<void> _configureController(CameraController controller) async {
    if (!controller.value.isInitialized || _isConfiguringLens) return;
    if (identical(_configuredController, controller)) return;

    _isConfiguringLens = true;
    _configuredController = controller;

    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();

      final options = <_LensOption>[];
      if (minZoom <= 0.6) {
        options.add(const _LensOption('0.5x', 0.5));
      }

      final standardZoom = _clampZoom(1.0, minZoom, maxZoom);
      options.add(_LensOption('1x', standardZoom));

      if (maxZoom >= 2.0) {
        final teleZoom = maxZoom >= 2.8 ? 3.0 : maxZoom;
        final label = teleZoom >= 2.8 ? '3x' : '${teleZoom.toStringAsFixed(1)}x';
        options.add(_LensOption(label, teleZoom));
      }

      _lensOptions = options;

      final match = _matchExistingSelection(options);
      final targetZoom = _clampZoom(match.zoom, minZoom, maxZoom);

      try {
        await controller.setZoomLevel(targetZoom);
      } catch (_) {}

      final actualZoom = controller.value.zoomLevel;
      _selectedLens = _matchSelectionByZoom(options, actualZoom) ?? match;

      _flashSupported = await _ensureFlash(controller);
    } finally {
      if (mounted) {
        setState(() {});
      }
      _isConfiguringLens = false;
    }
  }

  Future<bool> _ensureFlash(CameraController controller) async {
    _currentFlashMode = FlashMode.off;
    try {
      await controller.setFlashMode(_currentFlashMode);
      return true;
    } on CameraException {
      return false;
    }
  }

  _LensOption _matchExistingSelection(List<_LensOption> options) {
    if (_selectedLens != null) {
      final existing = _matchSelectionByZoom(options, _selectedLens!.zoom);
      if (existing != null) {
        return existing;
      }
    }

    final standard = options.firstWhere(
      (opt) => opt.label == '1x',
      orElse: () => options.first,
    );
    return standard;
  }

  _LensOption? _matchSelectionByZoom(
    List<_LensOption> options,
    double zoom,
  ) {
    const epsilon = 0.05;
    for (final option in options) {
      if ((option.zoom - zoom).abs() <= epsilon) {
        return option;
      }
    }
    return null;
  }

  double _clampZoom(double value, double minZoom, double maxZoom) {
    if (value < minZoom) return minZoom;
    if (value > maxZoom) return maxZoom;
    return value;
  }

  Future<void> _selectLens(_LensOption option) async {
    final controller = context.read<PlateCameraCaptureBloc>().state.controller;
    if (controller == null) return;
    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final zoom = _clampZoom(option.zoom, minZoom, maxZoom);
      await controller.setZoomLevel(zoom);
      if (!mounted) return;
      setState(() {
        _selectedLens = option;
      });
    } catch (_) {}
  }

  Future<void> _toggleFlash() async {
    if (!_flashSupported) return;
    final controller = context.read<PlateCameraCaptureBloc>().state.controller;
    if (controller == null) return;

    FlashMode nextMode;
    switch (_currentFlashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.torch;
        break;
      default:
        nextMode = FlashMode.off;
        break;
    }

    try {
      await controller.setFlashMode(nextMode);
      if (!mounted) return;
      setState(() {
        _currentFlashMode = nextMode;
      });
    } on CameraException {
      if (!mounted) return;
      setState(() {
        _currentFlashMode = FlashMode.off;
        _flashSupported = false;
      });
    }
  }

  IconData _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on_rounded;
    }
  }

  String _lensSummary() {
    if (_lensOptions.isEmpty) return '-';
    return _lensOptions.map((opt) => opt.label).join(' • ');
  }

  Future<void> _ensureIosFlashMode() async {
    if (!_useIosHardware) return;
    final photoState = _iosPhotoState;
    if (photoState == null) return;

    try {
      await photoState.setFlashMode(_iosFlashMode);
      if (!_flashSupported && mounted) {
        setState(() {
          _flashSupported = true;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [LensSelector] flash iOS tidak tersedia: $e');
      if (mounted) {
        setState(() {
          _flashSupported = false;
          _iosFlashMode = camerawesome.FlashMode.off;
        });
      }
    }
  }

  @override
  void dispose() {
    if (!_useIosHardware) {
      context.read<PlateCameraCaptureBloc>().add(DisposeCamera());
    }
    _animCtl.dispose();
    super.dispose();
  }

  Future<void> _configureController(CameraController controller) async {
    if (_useIosHardware) return;
    if (!controller.value.isInitialized || _isConfiguringLens) return;
    if (identical(_configuredController, controller)) return;

    _isConfiguringLens = true;
    _configuredController = controller;

    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();

      final options = <_LensOption>[];
      if (minZoom <= 0.6) {
        options.add(_LensOption('0.5x', 0.5));
      }

      final standardZoom = _clampZoom(1.0, minZoom, maxZoom);
      options.add(_LensOption('1x', standardZoom));

      if (maxZoom >= 2.0) {
        final teleZoom = maxZoom >= 2.8 ? 3.0 : maxZoom;
        final label = teleZoom >= 2.8 ? '3x' : '${teleZoom.toStringAsFixed(1)}x';
        options.add(_LensOption(label, teleZoom));
      }

      _lensOptions = options;

      final match = _matchExistingSelection(options);
      final targetZoom = _clampZoom(match.zoom, minZoom, maxZoom);

      try {
        await controller.setZoomLevel(targetZoom);
      } catch (_) {}

      final actualZoom = controller.value.zoomLevel;
      _selectedLens = _matchSelectionByZoom(options, actualZoom) ?? match;

      _flashSupported = await _ensureFlash(controller);
    } finally {
      if (mounted) {
        setState(() {});
      }
      _isConfiguringLens = false;
    }
  }

  Future<bool> _ensureFlash(CameraController controller) async {
    _currentFlashMode = FlashMode.off;
    try {
      await controller.setFlashMode(_currentFlashMode);
      return true;
    } on CameraException {
      return false;
    }
  }

  _LensOption _matchExistingSelection(List<_LensOption> options) {
    if (_selectedLens != null) {
      final existing = _matchSelectionByZoom(options, _selectedLens!.zoom);
      if (existing != null) {
        return existing;
      }
    }

    final standard = options.firstWhere(
      (opt) => opt.label == '1x',
      orElse: () => options.first,
    );
    return standard;
  }

  _LensOption? _matchSelectionByZoom(
    List<_LensOption> options,
    double zoom,
  ) {
    const epsilon = 0.05;
    for (final option in options) {
      if ((option.zoom - zoom).abs() <= epsilon) {
        return option;
      }
    }
    return null;
  }

  double _clampZoom(double value, double minZoom, double maxZoom) {
    if (value < minZoom) return minZoom;
    if (value > maxZoom) return maxZoom;
    return value;
  }

  Future<void> _selectLens(_LensOption option) async {
    if (_useIosHardware) {
      if (_selectedLens == option) return;
      setState(() {
        _selectedLens = option;
      });
      await _applyIosLensSelection();
      return;
    }

    final controller = context.read<PlateCameraCaptureBloc>().state.controller;
    if (controller == null) return;
    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final zoom = _clampZoom(option.zoom, minZoom, maxZoom);
      await controller.setZoomLevel(zoom);
      if (!mounted) return;
      setState(() {
        _selectedLens = option;
      });
    } catch (_) {}
  }

  Future<void> _captureIosPhoto() async {
    if (!_useIosHardware || _iosPhotoState == null) return;
    if (_isCapturingIosPhoto) return;

    setState(() {
      _isCapturingIosPhoto = true;
    });

    try {
      _lastPhotoPath = null;
      await _iosPhotoState!.takePhoto();
      final path = _lastPhotoPath;
      if (path == null) {
        throw Exception('Gagal menyimpan foto');
      }

      final file = File(path);
      if (!await file.exists()) {
        throw Exception('File foto tidak ditemukan');
      }

      final bytes = await file.readAsBytes();
      context.read<PlateCameraCaptureBloc>().add(ProcessExternalPhoto(bytes));

      try {
        await file.delete();
      } catch (_) {}
    } catch (e, st) {
      debugPrint('❌ Gagal mengambil foto iOS: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil foto: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingIosPhoto = false;
        });
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (!_flashSupported) return;

    if (_useIosHardware) {
      final photoState = _iosPhotoState;
      if (photoState == null) return;

      camerawesome.FlashMode nextMode;
      switch (_iosFlashMode) {
        case camerawesome.FlashMode.off:
          nextMode = camerawesome.FlashMode.auto;
          break;
        case camerawesome.FlashMode.auto:
          nextMode = camerawesome.FlashMode.torch;
          break;
        default:
          nextMode = camerawesome.FlashMode.off;
          break;
      }

      try {
        await photoState.setFlashMode(nextMode);
        if (!mounted) return;
        setState(() {
          _iosFlashMode = nextMode;
        });
      } catch (e) {
        debugPrint('⚠️ [LensSelector] gagal mengubah flash iOS: $e');
        if (!mounted) return;
        setState(() {
          _iosFlashMode = camerawesome.FlashMode.off;
          _flashSupported = false;
        });
      }
      return;
    }

    final controller = context.read<PlateCameraCaptureBloc>().state.controller;
    if (controller == null) return;

    FlashMode nextMode;
    switch (_currentFlashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.torch;
        break;
      default:
        nextMode = FlashMode.off;
        break;
    }

    try {
      await controller.setFlashMode(nextMode);
      if (!mounted) return;
      setState(() {
        _currentFlashMode = nextMode;
      });
    } on CameraException {
      if (!mounted) return;
      setState(() {
        _currentFlashMode = FlashMode.off;
        _flashSupported = false;
      });
    }
  }

  IconData _flashIconData() {
    if (_useIosHardware) {
      switch (_iosFlashMode) {
        case camerawesome.FlashMode.off:
          return Icons.flash_off_rounded;
        case camerawesome.FlashMode.auto:
          return Icons.flash_auto_rounded;
        case camerawesome.FlashMode.always:
        case camerawesome.FlashMode.torch:
          return Icons.flash_on_rounded;
        default:
          return Icons.flash_off_rounded;
      }
    }

    switch (_currentFlashMode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on_rounded;
    }
  }

  String _lensSummary() {
    if (_lensOptions.isEmpty) return '-';
    return _lensOptions.map((opt) => opt.label).join(' • ');
  }

  Widget _buildPreview(PlateCameraCaptureState state) {
    final preview = state.preview;
    if (preview != null) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: Center(
          key: ValueKey(preview),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  preview,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
                if (state.isProcessing)
                  AnimatedBuilder(
                    animation: _animCtl..forward(),
                    builder: (_, __) => BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 10 * _animCtl.value,
                        sigmaY: 10 * _animCtl.value,
                      ),
                      child: Shimmer.fromColors(
                        baseColor: Colors.tealAccent.withOpacity(0.25),
                        highlightColor: Colors.white.withOpacity(0.1),
                        child: Container(
                          color: Colors.black.withOpacity(0.25),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildLivePreview(state);
  }

  Widget _buildLivePreview(PlateCameraCaptureState state) {
    if (_useIosHardware) {
      return _buildIosCameraCore();
    }

    final controller = state.controller;
    if (controller != null && controller.value.isInitialized) {
      return CameraPreview(controller);
    }

    return const Center(
      child: CircularProgressIndicator(color: Colors.tealAccent),
    );
  }

  Widget _buildIosCameraCore() {
    if (_isLoadingIosSensors) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.tealAccent),
      );
    }

    final selected = _selectedLens?.iosSensor;
    if (selected == null) {
      return const Center(
        child: Text(
          'Tidak ada lensa belakang yang tersedia',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: camerawesome.CameraAwesomeBuilder.custom(
        key: ValueKey('${selected.uid}_${_iosFlashMode.name}'),
        sensorConfig: camerawesome.SensorConfig.single(
          sensor: _sensorFromDevice(selected),
          flashMode: _iosFlashMode,
          aspectRatio: camerawesome.CameraAspectRatios.ratio_4_3,
        ),
        saveConfig: camerawesome.SaveConfig.photo(
          pathBuilder: _buildPhotoPath,
        ),
        builder: (
          cameraContext,
          cameraState,
          previewSize,
          previewRect,
        ) {
          return cameraState.when(
            onPhotoMode: (photoState) {
              if (_iosPhotoState != photoState) {
                _iosPhotoState = photoState;
                Future.microtask(() async {
                  await _applyIosLensSelection();
                  await _ensureIosFlashMode();
                });
              }

              return camerawesome.AwesomeCameraPreview(
                state: photoState,
                alignment: Alignment.center,
                padding: EdgeInsets.zero,
              );
            },
            orElse: (_) => const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlateCameraCaptureBloc, PlateCameraCaptureState>(
      listener: (context, state) async {
        final controller = state.controller;
        if (!_useIosHardware && controller != null && controller.value.isInitialized) {
          await _configureController(controller);
        }

        if (!_useIosHardware && controller == null) {
          _configuredController = null;
          _lensOptions = const [];
          _selectedLens = null;
          if (mounted) setState(() {});
        }

        if (!state.isProcessing &&
            state.lastText != null &&
            state.preview != null) {
          await _showResult(context, state.lastText!);
          if (!_useIosHardware && _camera != null) {
            context.read<PlateCameraCaptureBloc>().add(ResetCamera(_camera!));
          }
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: const Color(0xFF0B1220),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Multi-Lens Capture'),
            centerTitle: true,
            actions: [
              if (_flashSupported)
                IconButton(
                  icon: Icon(_flashIconData()),
                  tooltip: 'Ubah mode flash',
                  onPressed: state.isProcessing ? null : _toggleFlash,
                ),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: _buildPreview(state)),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lensa tersedia',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _lensSummary(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (state.isProcessing)
                  Positioned(
                    bottom: 120,
                    left: 50,
                    right: 50,
                    child: LinearProgressIndicator(
                      value: state.progress,
                      color: Colors.tealAccent,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                if (state.message != null)
                  Positioned(
                    bottom: 170,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        state.message!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_lensOptions.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Wrap(
                            spacing: 12,
                            children: _lensOptions
                                .map(
                                  (option) => ChoiceChip(
                                    label: Text(option.label),
                                    selected: _selectedLens == option,
                                    onSelected: state.isProcessing
                                        ? null
                                        : (_) => _selectLens(option),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      if (_lensOptions.isEmpty && _useIosHardware)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(
                            _isLoadingIosSensors
                                ? 'Memindai lensa...' : 'Lensa iOS tidak tersedia',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: Text(
                          state.isProcessing
                              ? 'Memproses...'
                              : _isCapturingIosPhoto
                                  ? 'Mengambil foto...'
                                  : 'Ambil Foto',
                        ),
                        onPressed: state.isProcessing
                            ? null
                            : _useIosHardware
                                ? (_iosPhotoState == null || _isCapturingIosPhoto)
                                    ? null
                                    : _captureIosPhoto
                                : state.isReady
                                    ? () => context
                                        .read<PlateCameraCaptureBloc>()
                                        .add(CapturePhoto())
                                    : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent.withOpacity(0.3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showResult(BuildContext context, String text) async {
    final outerContext = context;
    final normalized = text.trim();
    final canSave =
        normalized.isNotEmpty &&
        normalized.toLowerCase() != 'tidak terbaca' &&
        normalized.toLowerCase() != 'error';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final box = Hive.box('plates');
        final existing = List<String>.from(box.get('data', defaultValue: []));
        final alreadySaved = existing.contains(normalized);

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Center(
                child: Text(
                  'Plat Terbaca',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  normalized,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: Text(
                        alreadySaved ? 'Sudah Tersimpan' : 'Simpan',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSave && !alreadySaved
                            ? Colors.green
                            : Colors.white12,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: (!canSave || alreadySaved)
                          ? null
                          : () async {
                              existing.add(normalized);
                              await box.put('data', existing);
                              if (mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(outerContext).showSnackBar(
                                  SnackBar(
                                    content: Text('Plat $normalized disimpan'),
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      label: const Text(
                        'Tutup',
                        style: TextStyle(color: Colors.white70),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LensOption {
  final String label;
  final double zoom;
  final camerawesome.SensorTypeDevice? iosSensor;

  const _LensOption(this.label, this.zoom, {this.iosSensor});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _LensOption) return false;
    final sameZoom = (other.zoom - zoom).abs() < 0.01;
    final sameSensor = other.iosSensor?.uid == iosSensor?.uid;
    return other.label == label && sameZoom && sameSensor;
  }

  @override
  int get hashCode => Object.hash(label, zoom.toStringAsFixed(2), iosSensor?.uid);
}
