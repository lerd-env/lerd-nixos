{ lib, buildGoModule, buildNpmPackage, fetchFromGitHub, fetchurl }:

let
  version = "1.39.3";
  src = fetchFromGitHub {
    owner = "lerd-env"; repo = "lerd"; rev = "v${version}";
    hash = "sha256-LfXRaB1eACekpkTYD8RvpfgZt+B0fzHf37V1/OgOQ4c=";
  };

  # The UI's `paraglide-js compile` step (run as part of `npm run build`) loads
  # the inlang message-format plugin listed in project.inlang/settings.json. That
  # entry is a https://cdn.jsdelivr.net URL, which the inlang SDK fetches at build
  # time — impossible in the network-isolated Nix sandbox, leaving the dashboard's
  # i18n messages uncompiled. Vendor the plugin and rewrite the module reference to
  # its vendored path.
  # Fetch an exact release: jsDelivr's @4 tag moves with every 4.x, which
  # breaks the fixed hash.
  messageFormatPluginUrl = "https://cdn.jsdelivr.net/npm/@inlang/plugin-message-format@4/dist/index.js";
  messageFormatPlugin = fetchurl {
    url = "https://cdn.jsdelivr.net/npm/@inlang/plugin-message-format@4.6.0/dist/index.js";
    hash = "sha256-4HWYlGjFzgggrAAwBEpkWjyXmYc0ixZXuK9tcWtq1wQ=";
  };

  ui = buildNpmPackage {
    pname = "lerd-ui"; inherit version src;
    sourceRoot = "${src.name}/internal/ui/web";
    npmDepsHash = "sha256-em4eucUq4YKefBuNOtP2Eki5G7VR9G0YFcRZP/cxjjM=";
    postPatch = ''
      cp ${messageFormatPlugin} plugin-message-format.js
      substituteInPlace project.inlang/settings.json \
        --replace-fail "${messageFormatPluginUrl}" "./plugin-message-format.js"
    '';
    postBuild = ''
      grep -rq common_save src/paraglide \
        || { echo "paraglide produced no messages"; exit 1; }
    '';
    installPhase = "runHook preInstall; cp -r dist $out; runHook postInstall";
  };
in
buildGoModule {
  pname = "lerd"; inherit version src;
  vendorHash = "sha256-fZnJDZKpXgHcxwhaYAGQdDK/Fh+FWayzshyhn+ENis0=";
  subPackages = [ "cmd/lerd" ];
  tags = [ "nogui" ];
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s" "-w"
    "-X github.com/geodro/lerd/internal/version.Version=${version}"
    "-X github.com/geodro/lerd/internal/version.Commit=v${version}"
    "-X github.com/geodro/lerd/internal/version.Date=1970-01-01T00:00:00Z"
  ];
  preBuild = "cp -r ${ui} internal/ui/web/dist";
  meta = {
    description = "Herd-like local PHP development for Linux and macOS";
    homepage = "https://lerd.sh";
    license = lib.licenses.mit;
    mainProgram = "lerd";
    platforms = lib.platforms.unix;
  };
}
