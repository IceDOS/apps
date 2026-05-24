{
  cmake,
  fetchFromGitHub,
  stdenv,
  vulkan-headers,
  vulkan-loader,
  vulkan-utility-libraries,
}:

stdenv.mkDerivation rec {
  pname = "low-latency-vulkan-layer";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "Korthos-Software";
    repo = "low_latency_layer";
    rev = "v${version}";
    hash = "sha256-mnGAH0m19wOkWEowpcPRHXQSc6HGYW+CFYxjPF2onk4=";
  };

  nativeBuildInputs = [ cmake ];

  buildInputs = [
    vulkan-headers
    vulkan-loader
    vulkan-utility-libraries
  ];
}
