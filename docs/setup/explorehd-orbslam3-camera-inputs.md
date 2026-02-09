# exploreHD Camera Inputs for ORB_SLAM3 (`test_data/2.8.26`)

This note captures the camera information needed to run ORB_SLAM3 monocular examples on `test_data/2.8.26`.

## Source and capture context

- Camera spec source: `https://docs.dwe.ai/hardware/general-vision/exploreHD#image-sensor-specifications`
- Retrieved: 2026-02-09
- Dataset path: `test_data/2.8.26`
- Dataset image count: 210 JPG frames
- Dataset frame size: 1920x1080
- ORB_SLAM3 loader in this repo: `Examples/Monocular/mono_custom.cc`
- Timestamp behavior in loader: synthetic timestamps at fixed 30 FPS

## exploreHD camera specs relevant to ORB_SLAM3

| Spec item | Value |
|---|---|
| Image Sensor | 1/2.9" Sony Exmor CMOS |
| Sensor Color | RGB |
| Sensor Type | Rolling Shutter |
| Max Resolution | 1920x1080 |
| Max Framerate | 30 FPS (H.264/MJPEG) |
| Color Channels | 3 |
| Bits Per Channel | 8 bits |
| Compression Formats | H.264, MJPEG, YUY2 |
| Connection | USB 2.0 High Speed / UVC Compliant |
| Lens Type | Fisheye |
| Focal Length | 2.65 mm |
| Lens Aperture | f/1.9 |
| Minimum Focus Distance | 20-30 cm |
| Horizontal FOV (air) | 138 deg |
| Vertical FOV (air) | 70 deg |
| Diagonal FOV (air) | 168 deg |
| Horizontal FOV (water) | ~82 deg |

## ORB_SLAM3 mapping (what can be filled now)

| ORB_SLAM3 setting | Value to use now | Why |
|---|---|---|
| `Camera.type` | `KannalaBrandt8` | Lens is fisheye, so fisheye model is the right starting point. |
| `Camera.width` | `1920` | Matches dataset frames and max camera resolution. |
| `Camera.height` | `1080` | Matches dataset frames and max camera resolution. |
| `Camera.fps` | `30` | Matches camera max for H.264/MJPEG and current `mono_custom` timestamp assumption. |
| `Camera.RGB` | `0` | `cv::imread` loads BGR by default in `mono_custom.cc`. |
| `Camera1.cx` | `960.0` | Image center (`width / 2`). |
| `Camera1.cy` | `540.0` | Image center (`height / 2`). |
| `Camera1.fx` | `797.16` (initial guess) | From equidistant fisheye approximation using 138 deg HFOV. |
| `Camera1.fy` | `883.99` (initial guess) | From equidistant fisheye approximation using 70 deg VFOV. |
| `Camera1.k1..k4` | `0.0` initial placeholders | Real fisheye distortion terms are not published in product specs. |

## Required but missing from product specs

These values are still required for reliable tracking quality and scale consistency:

- Exact intrinsic calibration for your specific unit and lens/housing stack.
- Fisheye distortion coefficients (`Camera1.k1..k4`) from calibration.
- If captured underwater, calibration must be done underwater with the same housing/port setup.
- True per-frame timestamps (current sample loader uses synthetic 30 FPS timing).

## Starter ORB_SLAM3 settings file (monocular)

Use this as a bootstrapping profile until full calibration is available.

```yaml
%YAML:1.0

File.version: "1.0"

Camera.type: "KannalaBrandt8"

Camera1.fx: 797.16
Camera1.fy: 883.99
Camera1.cx: 960.0
Camera1.cy: 540.0

Camera1.k1: 0.0
Camera1.k2: 0.0
Camera1.k3: 0.0
Camera1.k4: 0.0

Camera.width: 1920
Camera.height: 1080

Camera.fps: 30
Camera.RGB: 0

ORBextractor.nFeatures: 2000
ORBextractor.scaleFactor: 1.2
ORBextractor.nLevels: 8
ORBextractor.iniThFAST: 20
ORBextractor.minThFAST: 7

Viewer.KeyFrameSize: 0.05
Viewer.KeyFrameLineWidth: 1.0
Viewer.GraphLineWidth: 0.9
Viewer.PointSize: 2.0
Viewer.CameraSize: 0.08
Viewer.CameraLineWidth: 3.0
Viewer.ViewpointX: 0.0
Viewer.ViewpointY: -0.7
Viewer.ViewpointZ: -1.8
Viewer.ViewpointF: 500.0
```

## Run command pattern

```bash
./Examples/Monocular/mono_custom ./Vocabulary/ORBvoc.txt <settings.yaml> ./test_data/2.8.26
```

## Notes

- The public rendered table for "Image Sensor Specifications" may show blank cells, but values are present in the page source payload.
- The FOV numbers are not pinhole-consistent (expected for fisheye), so calibration is needed to replace the initial guesses above.
