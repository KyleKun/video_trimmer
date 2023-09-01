import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/src/trim_viewer/trim_editor_painter.dart';
import 'package:video_trimmer/src/trimmer.dart';
import 'package:video_trimmer/src/utils/duration_style.dart';

import '../../utils/editor_drag_type.dart';
import '../trim_area_properties.dart';
import '../trim_editor_properties.dart';
import 'fixed_thumbnail_viewer.dart';

class FixedTrimViewer extends StatefulWidget {
  /// The Trimmer instance controlling the data.
  final Trimmer trimmer;

  /// For defining the total trimmer area width
  final double viewerWidth;

  /// For defining the total trimmer area height
  final double viewerHeight;

  /// For defining the minimum length of the output video.
  final Duration minVideoLength;

  /// For defining the maximum length of the output video.
  final Duration maxVideoLength;

  /// For showing the start and the end point of the
  /// video on top of the trimmer area.
  ///
  /// By default it is set to `true`.
  final bool showDuration;

  /// For providing a `TextStyle` to the
  /// duration text.
  ///
  /// By default it is set to `TextStyle(color: Colors.white)`
  final TextStyle durationTextStyle;

  /// For specifying a style of the duration
  ///
  /// By default it is set to `DurationStyle.FORMAT_HH_MM_SS`.
  final DurationStyle durationStyle;

  /// Callback to the video start position
  ///
  /// Returns the selected video start position in `milliseconds`.
  final Function(double startValue)? onChangeStart;

  /// Callback to the video end position.
  ///
  /// Returns the selected video end position in `milliseconds`.
  final Function(double endValue)? onChangeEnd;

  /// Callback to the video playback
  /// state to know whether it is currently playing or paused.
  ///
  /// Returns a `boolean` value. If `true`, video is currently
  /// playing, otherwise paused.
  final Function(bool isPlaying)? onChangePlaybackState;

  /// Properties for customizing the trim editor.
  final TrimEditorProperties editorProperties;

  /// Properties for customizing the fixed trim area.
  final FixedTrimAreaProperties areaProperties;

  final VoidCallback onThumbnailLoadingComplete;

  /// Widget for displaying the video trimmer.
  ///
  /// This has frame wise preview of the video with a
  /// slider for selecting the part of the video to be
  /// trimmed.
  ///
  /// The required parameters are [viewerWidth] & [viewerHeight]
  ///
  /// * [viewerWidth] to define the total trimmer area width.
  ///
  ///
  /// * [viewerHeight] to define the total trimmer area height.
  ///
  ///
  /// The optional parameters are:
  ///
  /// * [maxVideoLength] for specifying the maximum length of the
  /// output video.
  ///
  ///
  /// * [showDuration] for showing the start and the end point of the
  /// video on top of the trimmer area. By default it is set to `true`.
  ///
  ///
  /// * [durationTextStyle] is for providing a `TextStyle` to the
  /// duration text. By default it is set to
  /// `TextStyle(color: Colors.white)`
  ///
  ///
  /// * [onChangeStart] is a callback to the video start position.
  ///
  ///
  /// * [onChangeEnd] is a callback to the video end position.
  ///
  ///
  /// * [onChangePlaybackState] is a callback to the video playback
  /// state to know whether it is currently playing or paused.
  ///
  ///
  /// * [editorProperties] defines properties for customizing the trim editor.
  ///
  ///
  /// * [areaProperties] defines properties for customizing the fixed trim area.
  ///
  const FixedTrimViewer({
    super.key,
    required this.trimmer,
    required this.onThumbnailLoadingComplete,
    this.viewerWidth = 50.0 * 8,
    this.viewerHeight = 50,
    this.minVideoLength = const Duration(seconds: 1),
    this.maxVideoLength = const Duration(milliseconds: 0),
    this.showDuration = true,
    this.durationTextStyle = const TextStyle(color: Colors.white),
    this.durationStyle = DurationStyle.FORMAT_HH_MM_SS,
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangePlaybackState,
    this.editorProperties = const TrimEditorProperties(),
    this.areaProperties = const FixedTrimAreaProperties(),
  });

  @override
  State<FixedTrimViewer> createState() => _FixedTrimViewerState();
}

class _FixedTrimViewerState extends State<FixedTrimViewer> with TickerProviderStateMixin {
  final _trimmerAreaKey = GlobalKey();
  File? get _videoFile => widget.trimmer.currentVideoFile;

  double _videoStartPos = 0.0;
  double _videoEndPos = 0.0;

  Offset _startPos = const Offset(0, 0);
  Offset _endPos = const Offset(0, 0);

  double _startFraction = 0.0;
  double _endFraction = 1.0;

  int _videoDuration = 0;
  int _currentPosition = 0;

  double _thumbnailViewerW = 0.0;
  double _thumbnailViewerH = 0.0;

  int _numberOfThumbnails = 0;

  late double _startCircleSize;
  late double _endCircleSize;
  late double _borderRadius;

  double? minFraction;
  double? fraction;
  double? maxLengthPixels;
  double? minLengthPixels;

  FixedThumbnailViewer? thumbnailWidget;

  Animation<double>? _scrubberAnimation;
  AnimationController? _animationController;
  late Tween<double> _linearTween;

  int quickCutNumber = 1;

  /// Quick access to VideoPlayerController, only not null after [TrimmerEvent.initialized]
  /// has been emitted.
  VideoPlayerController get videoPlayerController => widget.trimmer.videoPlayerController!;

  /// Keep track of the drag type, e.g. whether the user drags the left, center or
  /// right part of the frame. Set this in [_onDragStart] when the dragging starts.
  EditorDragType _dragType = EditorDragType.left;

  /// Whether the dragging is allowed. Dragging is ignore if the user's gesture is outside
  /// of the frame, to make the UI more realistic.
  bool _allowDrag = true;
  bool _isCenterDrag = false;

  @override
  void initState() {
    super.initState();
    _startCircleSize = widget.editorProperties.circleSize;
    _endCircleSize = widget.editorProperties.circleSize;
    _borderRadius = widget.editorProperties.borderRadius;
    _thumbnailViewerH = widget.viewerHeight;
    log('thumbnailViewerW: $_thumbnailViewerW');
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final renderBox = _trimmerAreaKey.currentContext?.findRenderObject() as RenderBox?;
      final trimmerActualWidth = renderBox?.size.width;
      log('RENDER BOX: $trimmerActualWidth');
      if (trimmerActualWidth == null) return;
      _thumbnailViewerW = trimmerActualWidth;
      _initializeVideoController();
      videoPlayerController.seekTo(const Duration(milliseconds: 0));
      _numberOfThumbnails = trimmerActualWidth ~/ _thumbnailViewerH;
      log('numberOfThumbnails: $_numberOfThumbnails');
      log('thumbnailViewerW: $_thumbnailViewerW');
      setState(() {
        _thumbnailViewerW = _numberOfThumbnails * _thumbnailViewerH;

        final FixedThumbnailViewer thumbnailWidget = FixedThumbnailViewer(
          videoFile: _videoFile!,
          videoDuration: _videoDuration,
          fit: widget.areaProperties.thumbnailFit,
          thumbnailHeight: _thumbnailViewerH,
          numberOfThumbnails: _numberOfThumbnails,
          quality: widget.areaProperties.thumbnailQuality,
          onThumbnailLoadingComplete: widget.onThumbnailLoadingComplete,
        );
        this.thumbnailWidget = thumbnailWidget;
        Duration totalDuration = videoPlayerController.value.duration;

        if (totalDuration.inMilliseconds <= 1500) {
          maxLengthPixels = _thumbnailViewerW;
          minLengthPixels = _thumbnailViewerW;
        } else if (widget.maxVideoLength > const Duration(milliseconds: 0) &&
            widget.maxVideoLength < totalDuration) {
          minFraction = widget.minVideoLength.inMilliseconds / totalDuration.inMilliseconds;
          fraction = widget.maxVideoLength.inMilliseconds / totalDuration.inMilliseconds;
          minLengthPixels = _thumbnailViewerW * minFraction!;
          maxLengthPixels = _thumbnailViewerW * fraction!;
        } else {
          minFraction = widget.minVideoLength.inMilliseconds / totalDuration.inMilliseconds;
          maxLengthPixels = _thumbnailViewerW;
          minLengthPixels = _thumbnailViewerW * minFraction!;
        }

        _videoEndPos =
            fraction != null ? _videoDuration.toDouble() * fraction! : _videoDuration.toDouble();

        widget.onChangeEnd!(_videoEndPos);

        _endPos = Offset(
          maxLengthPixels != null ? maxLengthPixels! : _thumbnailViewerW,
          _thumbnailViewerH,
        );

        // Defining the tween points
        _linearTween = Tween(begin: _startPos.dx, end: _endPos.dx);
        _animationController = AnimationController(
          vsync: this,
          duration: Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt()),
        );

        _scrubberAnimation = _linearTween.animate(_animationController!)
          ..addListener(() {
            setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _animationController!.stop();
            }
          });
      });
    });
  }

  Future<void> _initializeVideoController() async {
    if (_videoFile != null) {
      videoPlayerController.addListener(() {
        final bool isPlaying = videoPlayerController.value.isPlaying;

        if (isPlaying) {
          widget.onChangePlaybackState!(true);
          setState(() {
            _currentPosition = videoPlayerController.value.position.inMilliseconds;

            if (_currentPosition > _videoEndPos.toInt()) {
              videoPlayerController.pause();
              widget.onChangePlaybackState!(false);
              _animationController!.stop();
            } else {
              if (!_animationController!.isAnimating) {
                if (videoPlayerController.value.isBuffering) {
                  return;
                }
                widget.onChangePlaybackState!(true);
                _animationController!.forward();
              }
            }
          });
        } else {
          if (videoPlayerController.value.isInitialized) {
            if (_animationController != null) {
              if ((_scrubberAnimation?.value ?? 0).toInt() == (_endPos.dx).toInt()) {
                _animationController!.reset();
              }
              _animationController!.stop();
              widget.onChangePlaybackState!(false);
            }
          }
        }
      });

      videoPlayerController.setVolume(1.0);
      _videoDuration = videoPlayerController.value.duration.inMilliseconds;
      quickCutNumber = (_videoDuration ~/ 1000).clamp(1, 10);
    }
  }

  /// Called when the user starts dragging the frame, on either side on the whole frame.
  /// Determine which [EditorDragType] is used.
  void _onDragStart(DragStartDetails details) {
    debugPrint("_onDragStart");
    debugPrint('StartPos: ${_startPos.dx}');
    debugPrint('EndPos: ${_endPos.dx}');

    final tapDx = details.localPosition.dx;
    debugPrint('TapDx: $tapDx');

    final sideTapSize = widget.editorProperties.sideTapSize;
    debugPrint('SideTapSize: $sideTapSize');

    final startDifference = (tapDx * 0.92) - _startPos.dx;
    final endDifference = (tapDx * 0.92) - _endPos.dx;
    debugPrint('StartDiff: $startDifference');
    debugPrint('EndDiff: $endDifference');

    // Left range
    final startIsWithinLeftRange = startDifference.abs() <= sideTapSize;
    final endIsWithinLeftRange = endDifference.abs() <= sideTapSize;

    // Right range
    final startIsWithinRightRange =
        tapDx >= _startPos.dx && tapDx <= _startPos.dx + sideTapSize * 1.75;
    final endIsWithinRightRange = tapDx >= _endPos.dx && tapDx <= _endPos.dx + sideTapSize * 1.75;

    // Determine which part is dragged
    if (startIsWithinLeftRange || startIsWithinRightRange) {
      _dragType = EditorDragType.left;
      _allowDrag = true;
      _isCenterDrag = false;
    } else if (endIsWithinLeftRange || endIsWithinRightRange) {
      _dragType = EditorDragType.right;
      _allowDrag = true;
      _isCenterDrag = false;
    } else {
      _dragType = EditorDragType.center;
      _allowDrag = true;
      _isCenterDrag = true;
    }
  }

  /// Called during dragging, only executed if [_allowDrag] was set to true in
  /// [_onDragStart].
  /// Makes sure the limits are respected.
  void _onDragUpdate(DragUpdateDetails details) {
    if (!_allowDrag) return;

    final double newStartPos = _startPos.dx + details.delta.dx;
    final double newEndPos = _endPos.dx + details.delta.dx;

    if (_dragType == EditorDragType.left) {
      _startCircleSize = widget.editorProperties.circleSizeOnDrag;
      if ((_endPos.dx - newStartPos >= minLengthPixels!) &&
          (newStartPos >= 0) &&
          (newStartPos <= _endPos.dx) &&
          !(_endPos.dx - _startPos.dx - details.delta.dx > maxLengthPixels!)) {
        _startPos += details.delta;
        _onStartDragged();
      }
    } else if (_dragType == EditorDragType.center) {
      _startCircleSize = widget.editorProperties.circleSizeOnDrag;
      _endCircleSize = widget.editorProperties.circleSizeOnDrag;
      if ((newStartPos >= 0) && (newEndPos <= _thumbnailViewerW)) {
        _startPos += details.delta;
        _endPos += details.delta;
        _onStartDragged();
        _onEndDragged();
      }
    } else {
      _endCircleSize = widget.editorProperties.circleSizeOnDrag;
      if ((newEndPos - _startPos.dx >= minLengthPixels!) &&
          (newEndPos <= _thumbnailViewerW) &&
          (newEndPos >= _startPos.dx) &&
          !(_endPos.dx - _startPos.dx + details.delta.dx > maxLengthPixels!)) {
        _endPos += details.delta;
        _onEndDragged();
      }
    }
    setState(() {});
  }

  void _onStartDragged() {
    _startFraction = (_startPos.dx / _thumbnailViewerW);
    _videoStartPos = _videoDuration * _startFraction;
    widget.onChangeStart!(_videoStartPos);
    _linearTween.begin = _startPos.dx;
    _animationController!.duration =
        Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
    _animationController!.reset();
  }

  void _onEndDragged() {
    _endFraction = _endPos.dx / _thumbnailViewerW;
    _videoEndPos = _videoDuration * _endFraction;
    widget.onChangeEnd!(_videoEndPos);
    _linearTween.end = _endPos.dx;
    _animationController!.duration =
        Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
    _animationController!.reset();
  }

  /// Drag gesture ended, update UI accordingly.
  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _startCircleSize = widget.editorProperties.circleSize;
      _endCircleSize = widget.editorProperties.circleSize;
      if (_dragType == EditorDragType.right) {
        videoPlayerController.seekTo(Duration(milliseconds: _videoEndPos.toInt()));
      } else {
        videoPlayerController.seekTo(Duration(milliseconds: _videoStartPos.toInt()));
      }
    });
  }

  @override
  void dispose() {
    videoPlayerController.pause();
    widget.onChangePlaybackState!(false);
    if (_videoFile != null) {
      videoPlayerController.setVolume(0.0);
      videoPlayerController.dispose();
      widget.onChangePlaybackState!(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          widget.showDuration
              ? SizedBox(
                  width: _thumbnailViewerW,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: <Widget>[
                        Text(
                          Duration(milliseconds: _videoEndPos.toInt() - _videoStartPos.toInt())
                              .format(widget.durationStyle),
                          style: widget.durationTextStyle,
                        ),
                      ],
                    ),
                  ),
                )
              : Container(),
          CustomPaint(
            foregroundPainter: TrimEditorPainter(
              startPos: _startPos,
              endPos: _endPos,
              scrubberAnimationDx: _scrubberAnimation?.value ?? 0,
              startCircleSize: _startCircleSize,
              endCircleSize: _endCircleSize,
              borderRadius: _borderRadius,
              borderWidth: widget.editorProperties.borderWidth,
              scrubberWidth: widget.editorProperties.scrubberWidth,
              circlePaintColor: widget.editorProperties.circlePaintColor,
              borderPaintColor: widget.editorProperties.borderPaintColor,
              scrubberPaintColor: widget.editorProperties.scrubberPaintColor,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.areaProperties.borderRadius),
              child: Container(
                key: _trimmerAreaKey,
                color: Colors.grey[900],
                height: _thumbnailViewerH,
                width: _thumbnailViewerW == 0.0 ? widget.viewerWidth : _thumbnailViewerW,
                child: thumbnailWidget ?? Container(),
              ),
            ),
          ),

          /// Quick Cut Buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (int i = 1; i < quickCutNumber + 1; i++)
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: TextButton.icon(
                      style: ButtonStyle(
                        foregroundColor: MaterialStateProperty.all<Color>(
                          widget.editorProperties.quickCutForegroundColor,
                        ),
                        backgroundColor: MaterialStateProperty.all<Color>(
                          widget.editorProperties.quickCutBackgroundColor,
                        ),
                        overlayColor: MaterialStateProperty.all<Color>(
                          widget.editorProperties.quickCutForegroundColor.withOpacity(0.25),
                        ),
                        shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(35.0),
                          ),
                        ),
                      ),
                      icon: Icon(
                        widget.editorProperties.quickCutIcon,
                        size: widget.editorProperties.quickCutIconSize,
                      ),
                      onPressed: () {
                        _startPos = const Offset(0, 0);
                        _startFraction = 0.0;
                        _videoStartPos = 0.0;
                        _currentPosition = 0;
                        _linearTween.begin = _startPos.dx;

                        widget.onChangeStart!(_videoStartPos);
                        videoPlayerController.seekTo(const Duration(milliseconds: 0));

                        _endFraction = (i * 1000) / _videoDuration;
                        _videoEndPos = _videoDuration * _endFraction;
                        _endPos = Offset((_endFraction * _thumbnailViewerW), _thumbnailViewerH);
                        _linearTween.end = _endPos.dx;
                        widget.onChangeEnd!(_videoEndPos);

                        _animationController!.duration =
                            Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
                        _animationController!.reset();
                      },
                      label: Text(
                        i.toString(),
                        style: TextStyle(color: widget.editorProperties.quickCutTextColor),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
