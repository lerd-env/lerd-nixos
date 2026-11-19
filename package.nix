{ lib, buildGoModule, buildNpmPackage, fetchFromGitHub, fetchurl }:

let
  version = "1.39.2";
  src = fetchFromGitHub {
    owner = "lerd-env"; repo = "lerd"; rev = "v${version}";
    hash = "sha256-hqiYHK6a/R5qHby1Aa3HecrCia1y6+e7T+Y3P/iVcpM=";
  };

  # The UI's `paraglide-js compile` step (run as part of `npm run build`) loads
  # the inlang message-format plugin listed in project.inlang/settings.json. That
  # entry is a https://cdn.jsdelivr.net URL, which the inlang SDK fetches at build
  # time — impossible in the network-isolated Nix sandbox, leaving the dashboard's
  # i18n messages uncompiled. Vendor the plugin and rewrite the module reference to
  # a data: URI, which the SDK's fetch() resolves offline.
  messageFormatPluginUrl = "https://cdn.jsdelivr.net/npm/@inlang/plugin-message-format@4/dist/index.js";
  messageFormatPlugin = fetchurl {
    url = messageFormatPluginUrl;
    hash = "sha256-lIZViAHAjrsBgiPFHCBEtsPCP8KowOeJSleIKzT+tso=";
  };

  ui = buildNpmPackage {
    pname = "lerd-ui"; inherit version src;
    sourceRoot = "${src.name}/internal/ui/web";
    npmDepsHash = "sha256-em4eucUq4YKefBuNOtP2Eki5G7VR9G0YFcRZP/cxjjM=";
    postPatch = ''
      b64=$(base64 -w0 ${messageFormatPlugin})
      substituteInPlace project.inlang/settings.json \
        --replace-fail "${messageFormatPluginUrl}" "data:text/javascript;base64,$b64"
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
