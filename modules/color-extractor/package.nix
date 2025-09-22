{
  fetchFromGitHub,
  python3,
  writeShellScriptBin,
  writeText,
}:

let
  ambientExtractor = fetchFromGitHub {
    hash = "sha256-jOFG+dwNpWlS0OkLAGL4rq7MDVwW6Ntw4hSadxNq76U=";
    owner = "icedborn";
    repo = "homeassistant-ambient-extractor";
    rev = "44a87f8117ec240da2f7b5add873f3abfa533d86";
  };

  runtime = python3.withPackages (
    pythonPackages: with pythonPackages; [
      colorthief
      pillow
    ]
  );

  script =
    let
      lib = "${ambientExtractor}/custom_components/ambient_extractor";
    in
    writeText "color-extractor.py" ''
      import argparse
      import sys
      import json
      sys.path.append("${lib}")
      from color_temperature import apply_color_temperature
      from extract_color import get_file, get_color_from_image, get_color_from_file, get_cropped_image
      from extract_brightness import get_brightness

      # Parse cli arguments
      parser = argparse.ArgumentParser(description='Process some integers.')
      parser.add_argument('--accuracy', type=int, required=False)
      parser.add_argument('--brightness-mode', type=str, required=False)
      parser.add_argument('--color-count', type=int, required=False)
      parser.add_argument('--color-temp', type=int, required=False)
      parser.add_argument('--image', type=str, required=True)
      parser.add_argument('--min-brightness', type=float, required=False)
      parser.add_argument('--min-saturation', type=float, required=False)
      parser.add_argument('--static-brightness', type=int, required=False)
      parser.add_argument('--transition', type=float, required=False)
      args = parser.parse_args()

      # Set constants
      ACCURACY = args.accuracy or 1
      BRIGHTNESS_MODE = args.brightness_mode or "natural"
      COLOR_COUNT = args.color_count or 16
      COLOR_TEMP = args.color_temp or 6600
      IMAGE_PATH = args.image
      MIN_BRIGHTNESS = args.min_brightness or 0.3
      MIN_SATURATION = args.min_saturation or 0.3
      STATIC_BRIGHTNESS = args.static_brightness or False
      TRANSITION = args.transition or 0

      image = get_cropped_image(get_file(IMAGE_PATH), { "active": False })

      try:
        rgb = get_color_from_image(image, COLOR_COUNT, ACCURACY, MIN_SATURATION, MIN_BRIGHTNESS)
        rgb = apply_color_temperature(rgb, COLOR_TEMP)

        # Convert tuple of floats to int
        rgb = tuple(int(num) for num in rgb)

        if STATIC_BRIGHTNESS:
          brightness = STATIC_BRIGHTNESS
        else:
          brightness = int((get_brightness(image, BRIGHTNESS_MODE, rgb) / 255) * 100)
      except:
        rgb = (0, 0, 0)
        brightness = 0

      color = list(rgb)

      print(json.dumps({"state": json.dumps({"rgb_color": color, "brightness_pct": brightness, "transition": TRANSITION })}))
    '';
in
writeShellScriptBin "color-extractor" ''
  ${runtime}/bin/python ${script} "$@"
''
