{
  cmake,
  fetchFromGitHub,
  gtk3,
  pkg-config,
  stdenv,
}:

stdenv.mkDerivation (final: {
  pname = "libayatana-ido";
  version = "0.10.4";
  outputs = [ "out" ];

  src = fetchFromGitHub {
    owner = "AyatanaIndicators";
    repo = "ayatana-ido";
    rev = final.version;
    sha256 = "sha256-KeErrT2umMaIVfLDr4CcQCmFrMb8/h6pNYbunuC/JtI=";
  };

  buildInputs = [
    gtk3
  ];

  nativeBuildInputs = [
    pkg-config
    cmake
  ];
})
