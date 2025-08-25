{
  fetchFromGitHub,
  minijinja,
  python3Full,
  page,
  iptables,
}:

let
  pythonFull = python3Full.pkgs;
in
pythonFull.buildPythonApplication rec {
  pname = "intermux";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "Rishi-Bhati";
    repo = "intermux";
    tag = "v1";
    sha256 = "sha256-As3Gyhr2oFOc+XdhdbgKWbWFDwO6I1RyHaCjLDyXKPk=";
  };

  pythonPackages = with pythonFull; [
    brotli
    click
    markdown2
    markupsafe
    pyyaml
    tkinter
  ];

  propagatedBuildInputs = [
    minijinja
    page
  ]
  ++ pythonPackages;

  doCheck = false;
  format = "other";

  postPatch = ''
    substituteInPlace cli.py --replace-fail python3 ${python3Full.interpreter}
    substituteInPlace core/router.py --replace-fail '"/etc/iproute2/rt_tables"' 'os.path.join((lambda d="/etc/iproute2/rt_tables.d": (os.makedirs(d, exist_ok=True), d)[1])(), "intermux.conf")'
    substituteInPlace core/router.py --replace-fail python3 ${python3Full.interpreter}
    substituteInPlace gui/app.py --replace-fail iptables ${iptables}/bin/iptables
    substituteInPlace gui/app.py --replace-fail python3 ${python3Full.interpreter}
  '';

  installPhase =
    let
      libFolder = "$out/lib/";
    in
    ''
      runHook preInstall

      mkdir -p "${libFolder}"
      cp -r core gui cli.py "${libFolder}"

      mkdir -p $out/bin

      cat > $out/bin/intermux-gui <<EOF
      #!/usr/bin/env bash
      set -e
      export DISPLAY=''${DISPLAY:-:0}
      export XAUTHORITY=''${XAUTHORITY:-$HOME/.Xauthority}
      export XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

      ${python3Full.interpreter} "${libFolder}/gui/app.py" "\$@"
      EOF

      chmod +x $out/bin/intermux-gui

      cat > $out/bin/intermux-cli <<EOF
      #!/usr/bin/env bash
      set -e
      export DISPLAY=''${DISPLAY:-:0}
      export XAUTHORITY=''${XAUTHORITY:-$HOME/.Xauthority}
      export XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

      ${python3Full.interpreter} "${libFolder}/cli.py" "\$@"
      EOF

      chmod +x $out/bin/intermux-cli

      runHook postInstall
    '';
}
