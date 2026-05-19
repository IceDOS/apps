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
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "Korthos-Software";
    repo = "low_latency_layer";
    rev = "v${version}";
    hash = "sha256-YYQpLC3yCvqbArhqeWkZ8rRhVT69qz31SHr5dxXc0zM=";
  };

  nativeBuildInputs = [ cmake ];

  buildInputs = [
    vulkan-headers
    vulkan-loader
    vulkan-utility-libraries
  ];
}
